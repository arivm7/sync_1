#!/usr/bin/env bash
set -euo pipefail



# Определение: запуск из cron или вручную
# [[ ! -t 0 && ! -t 1 ]] проверяет, не подключены ли stdin и stdout к терминалу.
# Если оба не подключены — почти наверняка это cron, systemd, или другой фоновый запуск.
IS_CRON=false
if [[ ! -t 0 && ! -t 1 ]]; then
    # shellcheck disable=SC2034
    IS_CRON=true
fi



APP_TITLE="Скрипт автобакапа с ротацией архивов. Из пакета индивидуальной синхронизации sync_1."
COPYRIGHT="(c) 2004-2025 RI-Network, tech support."         # Авторские права
APP_NAME=$(basename "$0")                                   # Полное имя скрипта, включая расширение
APP_PATH=$(cd "$(dirname "$0")" && pwd)                     # Путь размещения исполняемого скрипта
FILE_NAME="${APP_NAME%.*}"                                  # Убираем расширение (если есть), например ".sh"
# shellcheck disable=SC2034
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")                 # Полное имя [вложенного] скрипта, включая расширение
# shellcheck disable=SC2034
SCRIPT_PATH=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)   # Путь размещения [вложенного] скрипта
VERSION="1.1.0-alfa (2025-06-02)"
LAST_CHANGES="\
v1.0.0 (2025-05-25): Базовый функционал
v1.1.0 (2025-06-02): Перенос конфигов скрипта в системную папку домашних конфигов.
"


DIR_SYNC=".sync"                                # папка параметров синхронизации
FILE_EXCLUDES="${DIR_SYNC}/excludes"            # Файл исключений для rsync
FILE_DEST="${DIR_SYNC}/dest"                    # файл, в котором записан адрес удаленного каталога

CONFIG_DIRNAME="sync"
CONFIG_PATH="${XDG_CONFIG_HOME:-${HOME}/.config}/${CONFIG_DIRNAME:+${CONFIG_DIRNAME}}"
# CONFIG_FILE="${XDG_CONFIG_HOME:-${HOME}/.config}/${CONFIG_DIRNAME:+${CONFIG_DIRNAME}/}${FILE_NAME}.conf"
CONFIG_FILE="${CONFIG_PATH}/${FILE_NAME}.conf"



##
##  ============================================================================
##  [CONFIG START] Начало секции конфига
##

##
##  Конфиг для скрипта автобакапа с ротацией архивов. 
##  Из пакета индивидуальной синхронизации sync_1.
##  VERSION 1.0.0 (2025-05-25)
##

#
#  Допустимо использование переменных типа ${HOME}
#

# Список для бакапа из конфига для этого скрипта. 
# Лучше отдельный файл с папками, поскольку не все 
# папки из sync_all.list нужно бакапить
# LIST_FILE="$SCRIPT_PATH/sync_all.list"        # Списко для бакапа из конфига для sync_all.sh
# LIST_FILE="$SCRIPT_PATH/$FILE_NAME.list"      # Списко для бакапа из конфига для этого скрипта. 
LIST_FILE="${CONFIG_PATH}/${FILE_NAME}.list"    # Списко для бакапа из системного конфига для этого скрипта. 

BACKUP_DIR="${HOME}/Backups/syncBackups"        # Папка размещения бакапов

LOG_PREFIX="SYNC_BACKUPER: "                    # Используется для префикса в системном логе
COLOR_USAGE="\e[1;32m"                          # Терминальный цвет для вывода переменной статуса
COLOR_ERROR="\e[0;31m"                          # Терминальный цвет для вывода ошибок
COLOR_INFO="\e[0;34m"                           # Терминальный цвет для вывода информации (об ошибке или причине выхода)
COLOR_FILENAME="\e[1;36m"                       # Терминальный цвет для вывода имён файлов
COLOR_OFF="\e[0m"                               # Терминальный цвет для сброса цвета
BUFFER_PERCENT=10                               # Запас свободного места (%) от размера папки
VERB_MODE=1                                     # Режим подробного вывода
DRY_RUN=0                                       # Только посчитать. Без файловых операций

# Программа-редактор для редактирования конфиг-файла и списка папаок для копирования
# (без пробелов в пути/и/названии)
EDITOR="nano"

APP_AWK="/usr/bin/awk"

##
##  [CONFIG END] Конец секции конфига
##  ----------------------------------------------------------------------------
##



# Зависимости обязательные
DEPENDENCIES_REQUIRED="tar du df awk gzip ${EDITOR}"

# Зависимости рекомендованные. 
DEPENDENCIES_OPTIONAL="pv realpath readlink"



#
#  Записывает в конфиг файл фрагмент этого же скрипта между строками, содержащими [КОНФИГ СТАРТ] и [КОНФИГ ЕНД] 
#  Используемые глобальные переменные 0 и CONFIG_FILE
#
save_config_file()
{
    mkdir -p "${CONFIG_PATH}"
    echo  -e "Инициализация конфиг-файла '${COLOR_FILENAME}${CONFIG_FILE}${COLOR_OFF}'"
    if ! command -v "${APP_AWK}" >/dev/null 2>&1; then
        exit_with_msg "Нет приложения ${COLOR_FILENAME}${APP_AWK}${COLOR_OFF}." 1
    fi
    # Извлечь фрагмент между [КОНФИГ СТАРТ] и [КОНФИГ ЕНД] из самого скрипта
    [[ $DRY_RUN -eq 0 ]] && "${APP_AWK}" '/\[\s*CONFIG START\s*\]/,/\[\s*CONFIG END\s*\]/' "$0" > "${CONFIG_FILE}"
}



#
#  Чтение конфигурационного файла.
#  Если его нет, то создание.
#
read_config_file()
{
    #
    # Перепределение переменных из конфиг-файла
    # Если конфиг-файла нет, то создаём его
    # load_config
    #
    if [ -f "${CONFIG_FILE}" ]; then
        # shellcheck source="${XDG_CONFIG_HOME:-${HOME}/.config}/${CONFIG_DIRNAME}}/${FILE_NAME}.conf"
        # shellcheck source="${CONFIG_PATH}/${FILE_NAME}.conf"
        source "${CONFIG_FILE}"
    else
        save_config_file
    fi
}



print_usage() {
cat <<EOF
${APP_TITLE}
Версия: ${VERSION}
Использование: $APP_NAME [опции]

Опции:
  --dry-run, -n     Выполнить только расчёт (размеры, свободное место), без создания архивов
  --help, -h        Показать эту справку
  --usage, -u       Показать эту справку
  --edit-conf, -c   Редактирование конфига
  --edit-list, -l   Редактирование списка для бакапа

Конфигурация:
  - Список папок для архивации берётся из файла: $LIST_FILE
  - Архивы сохраняются в папке: $BACKUP_DIR

ВАЖНО:  При добавлении скрипта в crontab нужно добавить в cron-скрипт переменные окружения, 
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

${COPYRIGHT}

EOF
}



update_config_var() {
    local key="${1:?}"
    local value="${2:?}"

    if grep -q "^$key=" "$CONFIG_FILE"; then
        sed -i "s|^$key=.*|$key=\"$value\"|" "$CONFIG_FILE"
    else
        echo "$key=$value" >> "$CONFIG_FILE"
    fi
}



#
#  Обёртка для logger -p info
#
log_info() {
    logger -p info -t "${LOG_PREFIX}" "$*"
}



#
#  Обёртка для logger -p error
#
log_error() {
    logger -p error -t "${LOG_PREFIX}" "$*"
}



#
# Вывод строки и выход из скрипта
# $1 -- сообщение
# $2 -- код ошибки. По умолчанию "1"
#
exit_with_msg() {
    local msg="${1:?Строка не передана или пуста. Смотреть вызывающую функцию.}"
    local num="${2:-1}"
    case "${num}" in
    1)
        log_error "ERR: ${msg}"
        msg="[${COLOR_ERROR}Ошибка${COLOR_OFF}] ${msg}"
        ;;
    2)
        log_error "ERR: ${msg}"
        msg="[${COLOR_ERROR}Ошибка${COLOR_OFF}] ${msg}"
        msg="${msg}\nПодсказка по использованию: ${COLOR_USAGE}${APP_NAME} --usage|-u${COLOR_OFF}"
        ;;
    0)
        log_info "OK: ${msg}"
        msg="[${COLOR_OK}Ok${COLOR_OFF}] ${msg}"
        ;;
    *)
        log_info "${msg}"
        msg="[${COLOR_INFO}i${COLOR_OFF}] ${msg}"
        ;;
    esac
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
            --edit-conf|-c)
                echo "Редактирование конфига: ${CONFIG_FILE}"
                exec ${EDITOR} "${CONFIG_FILE}"
                exit 0;
                ;;
            --edit-list|-l)
                echo "Редактирование списка: ${LIST_FILE}"
                exec "${EDITOR}" "${LIST_FILE}"
                exit 0;
                ;;
            --dry-run|-n)
                DRY_RUN=1
                shift
                ;;
            --version|-v|--help|-h|--usage|-u)
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

    local file_excludes="${DIR}/${FILE_EXCLUDES}"
    local TAR

    if [[ -f "${file_excludes}" ]]; then
        TAR=(tar 
            --add-file="${DIR}/${FILE_EXCLUDES}"
            --add-file="${DIR}/${FILE_DEST}"
            --exclude-from="${file_excludes}"
        )
    else
        TAR=(tar 
        )
    fi

    if [[ -z "$DIR_SIZE" ]]; then
        DIR_SIZE=$(du -sb "$DIR" | cut -f1)
    fi

    if command -v pv >/dev/null 2>&1; then
        # Архивируем с прогрессом
        # shellcheck disable=SC2086
        if "${TAR[@]}" -cf - -C "$(dirname "$DIR")" "$(basename "$DIR")" | pv -s "$DIR_SIZE" | gzip > "$BACKUP_NAME"; then
            echo "    ✅ Архив создан: $BACKUP_DIR/$BACKUP_NAME"
        else
            echo "    ❌ Ошибка при создании архива $BACKUP_NAME"
        fi
    else
        # Архивируем без прогресса
        # shellcheck disable=SC2086
        if "${TAR[@]}" -czvf "$BACKUP_NAME" -C "$(dirname "$DIR")" "$(basename "$DIR")"; then
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
    read_config_file
    [[ $VERB_MODE -eq 1 ]] && {
        echo -e "Конфиг: '${COLOR_FILENAME}${CONFIG_FILE}${COLOR_OFF}'"
        echo -e "Список: '${COLOR_FILENAME}${LIST_FILE}${COLOR_OFF}'"
    }
    parse_args "$@"
    check_dependencies
    
    if [[ ! -f "${LIST_FILE}" ]]; then
        exit_with_msg "❌ Файл со списком путей не найден: ${LIST_FILE}" 1
    fi

    mkdir -p "${BACKUP_DIR}"

    cd "${BACKUP_DIR}" || {
        echo "❌ Не удалось перейти в каталог ${BACKUP_DIR}"
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
