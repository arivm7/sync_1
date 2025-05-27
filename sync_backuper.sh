#!/usr/bin/env bash
set -euo pipefail

# Определение: запуск из cron или вручную
# [[ ! -t 0 && ! -t 1 ]] проверяет, не подключены ли stdin и stdout к терминалу.
# Если оба не подключены — почти наверняка это cron, systemd, или другой фоновый запуск.
IS_CRON=false
if [[ ! -t 0 && ! -t 1 ]]; then
    IS_CRON=true
fi



APP_TITLE="Скрипт автобакапа с ротацией архивов. Из пакета индивидуальной синхронизации sync_1."
APP_NAME=$(basename "$0")                       # Полное имя скрипта, включая расширение
APP_PATH=$(cd "$(dirname "$0")" && pwd)         # Путь размещения исполняемого скрипта
FILE_NAME="${APP_NAME%.*}"                      # Убираем расширение (если есть), например ".sh"
# shellcheck disable=SC2034
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")     # Полное имя [вложенного] скрипта, включая расширение
SCRIPT_PATH=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) # Путь размещения [вложенного] скрипта
VERSION="1.0.0-alfa (2025-05-25)"
LAST_CHANGES="\
v1.0.0 (2025-05-25): Базовый функционал
"



#
#  --------------------------------- Конфиг ----------------------------------------
#

# LIST_FILE="$SCRIPT_PATH/sync_all.list"        # Списко для бакапа из конфига для sync_all.sh
LIST_FILE="$SCRIPT_PATH/$FILE_NAME.list"        # Списко для бакапа из конфига для этого скрипта. 
                                                # Лучше так, поскольку не все папки из sync_all.list нужно бакапить
# BACKUP_DIR="$SCRIPT_PATH/backups"             # Папка назначения бакапов там же где скрипт
BACKUP_DIR="${HOME}/Backups/syncBackups"        # Папка назначения бакапов указанная прямо

#
#  ============================== Конец конфига ====================================
#

LOG_PREFIX="SYNC_BACKUPER: "        # Используется для префикса в системном логе
COLOR_USAGE="\e[1;32m"              # Терминальный цвет для вывода переменной статуса
COLOR_ERROR="\e[0;31m"              # Терминальный цвет для вывода ошибок
COLOR_OFF="\e[0m"                   # Терминальный цвет для сброса цвета
BUFFER_PERCENT=10                   # Запас свободного места (%) от размера папки
DRY_RUN=0                           # Только посчитать
# VERB_MODE=1                       # Режим подробного вывода. # Пока Не реализован

# Зависимости обязательные
DEPENDENCIES_REQUIRED="tar du df awk gzip"
# Зависимости рекомендованные
DEPENDENCIES_OPTIONAL="pv realpath readlink"


print_usage() {
cat <<EOF
${APP_TITLE}
Версия: ${VERSION}
Использование: $APP_NAME [опции]

Опции:
  --dry-run, -n    Выполнить только расчёт (размеры, свободное место), без создания архивов
  --help, -h       Показать эту справку
  --usage, -u      Показать эту справку

Конфигурация:
  - Список папок для архивации берётся из файла: $LIST_FILE
  - Архивы сохраняются в папке: $BACKUP_DIR

ВАЖНО:
При добавлении скрипта в crontab нужно добавить в cron-скрипт переменные окружения, 
               которые нужны этому скрипту, и которые отсутсвуют при выполнении скрипта 
               не в пользовательском окружении: cron, systemd, или другой фоновый запуск.
               примерно так:

               PATH=/usr/local/bin:/usr/bin:/bin:${HOME}/bin:${HOME}/.local/bin
               HOME=${HOME}
               USER=${USER}
               SHELL=/bin/bash
               1  1  *  *  6    ${HOME}/bin/sync_backuper.sh

               для контроля исполнения скрипта можно добавить логирование работы самого скрипта:
               1  1  *  *  6    ${HOME}/bin/sync_backuper.sh >> ${HOME}/sync_backuper_cron.log 2>&1

Путь скрипта: "${APP_PATH}"
Последние изменения:
${LAST_CHANGES}
EOF
}



#
# Вывод строки и выход из скрипта
# $1 -- сообщение
# $2 -- код ошибки. По умолчанию "1"
#
exit_with_msg() {
    local msg="${1:?exit_with_msg строка не передана или пуста. Смотреть вызывающую функцию.}"
    local num="${2:-1}"
    logger -p error "${LOG_PREFIX} ERR: ${msg}"
    if [ "$num" -eq 2 ]; then
        msg="${msg}\nПодсказка по использованию: ${COLOR_USAGE}${APP_NAME} --usage|-u${COLOR_OFF}"
    fi
    echo -e "${msg}"
    exit "$num"
}



#
# Функция возвращает абсолютный путь для заданной папки
#
get_abs_path() {
    local dir="${1:?}"
    # realpath может отсутствовать, используем readlink -f, или fallback
    if command -v realpath >/dev/null 2>&1; then
        realpath "$dir"
    elif command -v readlink >/dev/null 2>&1; then
        readlink -f "$dir"
    else
        # Простейший fallback, если нет realpath/readlink -f
        (cd "$dir" 2>/dev/null && pwd) || exit_with_msg "Не удалось перейти в папку [$dir] (Возможно её нет)."
    fi
}



parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run|-n)
                DRY_RUN=1
                shift
                ;;
            --help|-h|--usage|-u)
                print_usage
                exit 0
                ;;
            *)
                exit_with_msg "Неизвестный параметр: $1" 2
                ;;
        esac
    done
}



check_dependencies() {

    for cmd in $DEPENDENCIES_REQUIRED; do
        if ! command -v "$cmd" &>/dev/null; then
            exit_with_msg "Ошибка: команда '$cmd' не найдена. Установите её, пожалуйста." 1
        fi
    done

    for cmd in $DEPENDENCIES_OPTIONAL; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "ℹ️ Предупреждение: команда '$cmd' не найдена. Некоторые функции будут недоступны."
        fi
    done
}



get_free_space() {
    # Получить свободное место на диске для BACKUP_DIR (в байтах)
    df -P --block-size=1 "$BACKUP_DIR" | tail -1 | awk '{print $4}'
}



### Ротация архивов
rotate_archives() {
    local BACKUP_NAME="$1"  # имя архива, например myfolder.tar.gz
    [[ -f "${BACKUP_NAME}.02" ]] && rm -f "${BACKUP_NAME}.02"
    [[ -f "${BACKUP_NAME}.01" ]] && mv    "${BACKUP_NAME}.01" "${BACKUP_NAME}.02"
    [[ -f "${BACKUP_NAME}"    ]] && mv    "${BACKUP_NAME}"    "${BACKUP_NAME}.01"
}



### Архивирование одной папки
create_archive() {
    local DIR="${1:?}"
    local BACKUP_NAME="${2:?}"
    local DIR_SIZE="${3:-}"

    if [[ -z "$DIR_SIZE" ]]; then
        DIR_SIZE=$(du -sb "$DIR" | cut -f1)
    fi

    if command -v pv >/dev/null 2>&1; then
        # Архивируем с прогрессом
        if tar -cf - -C "$(dirname "$DIR")" "$(basename "$DIR")" | pv -s "$DIR_SIZE" | gzip > "$BACKUP_NAME"; then
            echo "    ✅ Архив создан: $BACKUP_DIR/$BACKUP_NAME"
        else
            echo "    ❌ Ошибка при создании архива $BACKUP_NAME"
        fi
    else
        # Архивируем без прогресса
        if tar -czvf "$BACKUP_NAME" -C "$(dirname "$DIR")" "$(basename "$DIR")"; then
            echo "    ✅ Архив создан: $BACKUP_DIR/$BACKUP_NAME"
        else
            echo "    ❌ Ошибка при создании архива $BACKUP_NAME"
        fi
    fi  
}


get_dir_size() {
    local dir="${1:?get_dir_size: не указана папка}"
    local output size status

    # Выполняем du и перехватываем stderr
    output=$(du -sb "$dir" 2>&1)
    status=$?

    if [ $status -ne 0 ]; then
        echo -e "${COLOR_ERROR}Ошибка при определении размера папки [$dir]: $output${COLOR_OFF}" >&2
        return 1
    fi

    # Извлекаем размер (первое поле)
    size=$(echo "$output" | cut -f1)
    echo "$size"
    return 0
}



process_folder() {
    local DIR="${1:?}"
    local FREE_SPACE="${2:?}"
    local BANNER="${3:-}"

    if [[ ! -d "$DIR" ]]; then
        echo "⚠️  Путь не существует, пропущен: $DIR"
        return 1
    fi

    local BASENAME
    BASENAME=$(basename "$DIR")
    local BACKUP_NAME="${BASENAME}.tar.gz"

    local DIR_SIZE
    # DIR_SIZE=$(du -sb "$DIR" | cut -f1)
    DIR_SIZE=$(get_dir_size "$DIR") || {
        local err="Не удалось получить размер папки [$DIR]."
        if (( DRY_RUN == 1 )); then
            echo "  ⏸️ Режим dry-run — архивирование пропущено."
            echo "     $err"
            return 0
        else
            exit_with_msg "$err"
        fi
    } 

    local BUFFER_SIZE=$(( DIR_SIZE * BUFFER_PERCENT / 100 ))
    local NEEDED_SPACE=$(( DIR_SIZE + BUFFER_SIZE ))

    echo "Папка: $DIR"
    [[ -n "$BANNER" ]] && echo "  Метка: $BANNER"
    echo "  Фактический размер: $DIR_SIZE байт (~$((DIR_SIZE / 1024 / 1024)) МБ | ~$((DIR_SIZE / 1024 / 1024 / 1024)) Гб )"
    echo "  Рекомендуемый запас: $BUFFER_SIZE байт (~$((BUFFER_SIZE / 1024 / 1024)) МБ | ~$((BUFFER_SIZE / 1024 / 1024 / 1024)) Гб)"
    echo "  Рекомендуемый размер для операции: $NEEDED_SPACE байт (~$((NEEDED_SPACE / 1024 / 1024)) МБ | ~$((NEEDED_SPACE / 1024 / 1024 / 1024)) Гб)"

    if (( FREE_SPACE < NEEDED_SPACE )); then
        echo "  ❌ Недостаточно свободного места, архивирование пропущено."
        echo
        return 1
    fi

    # Считаем размер для итогов, даже если dry-run
    TOTAL_SIZE=$(( TOTAL_SIZE + DIR_SIZE ))
    TOTAL_NEEDED=$(( TOTAL_NEEDED + NEEDED_SPACE ))

    if (( DRY_RUN == 1 )); then
        echo "  ⏸️ Режим dry-run — архивирование пропущено."
        echo
        return 0
    fi

    echo "  📁 Обработка → $BACKUP_NAME"

    if [[ -f "$BACKUP_NAME" ]]; then
        echo "    🔁 Ротация архивов..."
        rotate_archives "$BACKUP_NAME"
    fi

    echo "    📦 Создание архива..."
    create_archive "$DIR" "$BACKUP_NAME" "$DIR_SIZE"
}



main() {
    parse_args "$@"
    check_dependencies

    if [[ ! -f "$LIST_FILE" ]]; then
        exit_with_msg "❌ Файл со списком путей не найден: $LIST_FILE" 1
    fi

    mkdir -p "$BACKUP_DIR"

    cd "$BACKUP_DIR" || {
        echo "❌ Не удалось перейти в каталог $BACKUP_DIR"
        if (( DRY_RUN == 0 )); then
            exit_with_msg "❌ Это критическая ошибка при реальном запуске, завершаем." 1
        else
            echo "ℹ️ Режим dry-run — продолжаем без перехода."
        fi
    }

    TOTAL_SIZE=0
    TOTAL_NEEDED=0

    echo "=============================================="

    while IFS= read -r LINE || [[ -n "$LINE" ]]; do
        # Удаляем пробелы по краям
        LINE=$(echo "$LINE" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # Пропускаем пустые строки и комментарии
        [[ -z "$LINE" || "$LINE" =~ ^# ]] && continue

        # Разбираем строку на аргументы, учитывая кавычки
        # Используем массив и встроенный парсер bash
        if ! eval "ARGS=($LINE)"; then
            echo "⚠️  Ошибка разбора строки: $LINE"
            continue
        fi
        DIR=$(get_abs_path "${ARGS[0]}")
        BANNER="${ARGS[1]:-}"

        local FREE_SPACE
        FREE_SPACE=$(get_free_space)

        echo "----------------------------------------------"
        echo "Свободное место в папке назначения: $FREE_SPACE байт (~$((FREE_SPACE / 1024 / 1024)) МБ | ~$((FREE_SPACE / 1024 / 1024 / 1024)) Гб)"

        process_folder "$DIR" "$FREE_SPACE" "$BANNER"
    done < "$LIST_FILE"

    echo "=============================================="
    echo "Итого суммарный фактический размер папок: $TOTAL_SIZE байт (~$((TOTAL_SIZE / 1024 / 1024 / 1024)) ГБ)"
    echo "Итого рекомендуемый размер свободного места: $TOTAL_NEEDED байт (~$((TOTAL_NEEDED / 1024 / 1024 / 1024)) ГБ)"
}



main "$@"
