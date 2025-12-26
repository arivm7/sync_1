#!/usr/bin/env bash
set -euo pipefail
trap 'logger -p error -t "SYNC_WATHER" "[$(date)] Ошибка в строке $LINENO: команда \"$BASH_COMMAND\""' ERR

##
##  Project     : sync_1
##  Description : Слушатель изменений для синхронизации.
##                Часть пакета индивидуальной синхронизации sync_1.
##  File        : sync_1.sh
##  Author      : Ariv <ariv@meta.ua> | https://github.com/arivm7
##  Org         : RI-Network, Kiev, UK
##  License     : GPL v3
##    
##  Copyright (C) 2004-2025 Ariv <ariv@meta.ua> | https://github.com/arivm7 | RI-Network, Kiev, UK
##



VERSION="0.4.0-alfa (2025-12-26)"
COPYRIGHT="Copyright (C) 2004-2025 Ariv <ariv@meta.ua> | https://github.com/arivm7 | RI-Network, Kiev, UK"
LAST_CHANGES="\
v0.4.0 (2025-12-26): Добавлена предварительная синхронизация и возможность включени/отключения предварительной синхронизации через конфиг или чреез параметр
v0.3.0 (2025-10-27): Исправлена передача команды в синхронизатор: передаётся не папка, где произошло событие, а корневая папка для синхронизации. Это устранило ошибку прекращения работы скрипта при удалении локальной папки, что ранее вызывало ошибку в синхронизаторе 'Папка не найдена'.
v0.2.2 (2025-08-25): Добавлено полное описание работы скрипта
v0.2.1 (2025-08-05): Исправление механизма передачи параметров с sync_1
v0.2.0 (2025-07-10): Базовый функционал
"



APP_TITLE="Слушатель изменений и автосинхронизатор"
APP_NAME=$(basename "$0")                                   # Полное имя скрипта, включая расширение
APP_PATH=$(cd "$(dirname "$0")" && pwd)                     # Путь размещения исполняемого скрипта
FILE_NAME="${APP_NAME%.*}"                                  # Убираем расширение (если есть)
# shellcheck disable=SC2034
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")                 # Полное имя [вложенного] скрипта, включая расширение
# shellcheck disable=SC2034
SCRIPT_PATH=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)   # Путь размещения [вложенного] скрипта

CONFIG_DIRNAME="sync"
CONFIG_PATH="${XDG_CONFIG_HOME:-${HOME}/.config}/${CONFIG_DIRNAME}"
CONFIG_FILE="${CONFIG_PATH}/${FILE_NAME}.conf"              # Конфиг-файл
LIST_FILE="${CONFIG_PATH}/${FILE_NAME}.list"                # Файл со списком папок для мониторинга

#
# Список поддерживаемых команд
#
# shellcheck disable=SC2034
{
    SHOW_LOG="LOG"                              # Показать логи
    SHOW_DEST="SHOW_DEST"                       # Показывает dest-строку
    SHOW_TEST="TEST"                            # Только проверить структуру
    SHOW_CLOUD_STAT="SHOW_CLOUD_STAT"           # Показывает статус сервера
    SHOW_CLOUD_CMD="SHOW_CLOUD_CMD"             # Показывает команду сервера
    SYNC_CMD_REGULAR="REGULAR"
    SYNC_CMD_UP="UP"
    SYNC_CMD_DL="DL"
    SYNC_CMD_UP_INIT="UP_INIT"
    SYNC_CMD_DL_INIT="DL_INIT"
    SYNC_CMD_PAUSE="PAUSE"
    SYNC_CMD_UP_EDIT="UP_EDIT"
    SYNC_CMD_UNPAUSE="UNPAUSE"
    SYNC_CMD_CLOUD_UP_INIT="CLOUD_UP_INIT"      # Создаёт sync-репозиторий из текущей папки. 
    SYNC_CMD_CLOUD_DL_INIT="CLOUD_DL_INIT"      # Загружает sync-репозиторий с сервера в текущую папку. Близко к DL_INIT
}



##
##  [CONFIG START] ============================================================================
##  Начало секции конфига
##

##
##  Конфиг для скрипта Слушателя изменений и синхронизатора. 
##  VERSION 0.4.0-alfa (2025-12-26)
##
##  APP_PATH                                # Путь размещения исполняемого скрипта
##

LOG_PREFIX="SYNC_ALL"                       # Используется для префикса в системном логе
APP_S1="${APP_PATH}/sync_1.sh"              # Программа-синхронизатор

APP_INOTIFYWAIT="/usr/bin/inotifywait"      # мониторинг файловых событий
APP_INOTIFYWAIT_PKG="inotify-tools"         # пакет, из которого устанавливать

APP_AWK="/usr/bin/awk"                      # потоковый текстовый процессор
APP_AWK_PKG="gawk"                          # пакет, из которого устанавливать

PRE_SYNC=1                                  # Предварительная синхронизация перед запуском слушателя изменений
WAIT_CHANGES=60                             # Время ожидния перед выполнением команды синхронизации

DRY_RUN=0                                   # Режим имитации, без фактического выполнения синхронизации
VERBOSE=0                                   # Подробный вывод всякой фигни

#
# Шаблоны файлов, которые не должны вызывать синхронизацию
#
IGNORE_PATTERNS=(
    '^\.sync_'          # файлы, начинающиеся на .sync_
    '\.swp$'            # swap-файлы
    '\.tmp$'            # временные
    '\.bak$'            # резервные
    '\.zim-new~$'       # Временный файл zim
    '(^|/)\.sync/'      # любые файлы в папке .sync (в любом месте пути)
    '\.~lock\.'         # Файлы блокировок офисных пакетов
    '.git/index.lock'   # Файд git блокировки
)

#
#  Цвета для консольных сообщений
#
COLOR_FILENAME="\e[1;36m"                   # Для вывода имён файлов и путей
COLOR_STATUS="\033[0;36m"                   # Терминальный цвет для вывода переменной статуса
COLOR_USAGE="\033[1;34m"                    # Терминальный цвет для вывода подсказки по использованию
COLOR_INFO="\033[0;34m"                     # Терминальный цвет для вывода информации (об ошибке или причине выхода)
COLOR_OK="\033[0;32m"                       # Терминальный цвет для вывода Ok-сообщения
COLOR_ERROR="\033[0;31m"                    # Терминальный цвет для вывода ошибок
COLOR_OFF="\033[0m"                         # Сброс цвета

#
# Программа-редактор для редактирования конфиг-файла и файла-списка папок для контроля
# (без пробелов в пути/и/названии)
EDITOR="nano"



##
##  Конец секции конфига
##  [CONFIG END] ----------------------------------------------------------------------------
##



#
# Обязательные зависимости в виде ассоциаливного массива
# [программа]=пакет
# где "программа" -- собственно сама исполняемая програма
#     "пакет"     -- пакет внутри которого находится эта программа 
#                    для установки в систму
declare -A DEPENDENCIES_REQUIRED=(
    ["${APP_INOTIFYWAIT}"]="${APP_INOTIFYWAIT_PKG}"
    ["${APP_AWK}"]="${APP_AWK_PKG}"
    ## ["${APP_ENVSUBST}"]="${APP_ENVSUBST_PKG}"
)



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
# Функция возвращает (печатает) абсолютный путь для заданной папки
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



#
#  Записывает в конфиг файл фрагмент этого же скрипта между строками, содержащими [КОНФИГ СТАРТ] и [КОНФИГ ЕНД] 
#  Используемые глобальные переменные:
#       $0
#       $CONFIG_PATH
#       $CONFIG_FILE
#       $APP_AWK
#       $DRY_RUN
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
    # Переопределение переменных из конфиг-файла
    # Если конфиг-файла нет, то создаём его
    # load_config()
    #
    if [ -f "${CONFIG_FILE}" ]; then
        # shellcheck source="${CONFIG_PATH}/${FILE_NAME}.conf"
        # shellcheck disable=SC1091
        source "${CONFIG_FILE}"
    else
        save_config_file
    fi
}



#
#  Проверка обязательных зависимостей
#
check_dependencies_required() {
  local missing=()

  for cmd in "${!DEPENDENCIES_REQUIRED[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done

  if [ "${#missing[@]}" -eq 0 ]; then
    echo -e "[${COLOR_OK}OK${COLOR_OFF}] Все обязательные зависимости установлены."
    return 0
  else
    echo -e "[${COLOR_ERROR}ERROR${COLOR_OFF}] Обязательные зависимости не найдены:"
    for cmd in "${missing[@]}"; do
      local pkg="${DEPENDENCIES_REQUIRED[$cmd]}"
      echo -e "${COLOR_STATUS}  - $cmd (пакет: ${pkg:-неизвестен})${COLOR_OFF}"
    done
    return 1
  fi
}



print_help()
{
echo -e "$(cat <<EOF
${APP_NAME}
${COLOR_USAGE}${APP_TITLE}${COLOR_OFF}
Скрипт предназначен для автоматического отслеживания изменений в указанных папках
и автоматической синхронизации этих изменений с сервером с помощью sync_1.sh.

Полный справочник по использованию.

ВАЖНО: 
Хост, на котором вы запускаете этот скрипт, считаетмя "главным" в вашей распределённой системе синхронизации. 
То есть, все изменения, которые происходят в указанных папках на этом хосте,
будут автоматически отправляться на сервер при помощи sync_1.sh.

Поэтому, перед запуском скрипта нужно убедиться, что все папки синхронизированы с сервером,
чтобы избежать конфликтов и потери данных. Этот механизм по умолчанию включен, его можно отключить в конфиге или через параметр ${COLOR_USAGE}--presync${COLOR_OFF}.

Как это работает:

Читает из файла (${COLOR_FILENAME}$(basename "${LIST_FILE}")${COLOR_OFF}) список папок. 
Для этих папок устанавливается слушатель изменений ${COLOR_FILENAME}$(basename "${APP_INOTIFYWAIT}")${COLOR_OFF}.
Когда происходит изменение, то запускается синхронизатор (${COLOR_FILENAME}$(basename "${APP_S1}")${COLOR_OFF}), 
только не в дефолтном режиме, а в режиме отправки данных на сервер.

Поскольку Вы запустили этот скрипт, то Вы хотите, чтобы все изменения 
(создание, удаление, переименование, изменение файлов)
автоматически отправлялись на сервер. И эти изменения считаются основными.

По этому, вместо ${COLOR_STATUS}${SYNC_CMD_REGULAR}${COLOR_OFF} выполняется ${COLOR_STATUS}${SYNC_CMD_CLOUD_UP_INIT}${COLOR_OFF}
Если сервер в статусе ${COLOR_STATUS}${SYNC_CMD_PAUSE}${COLOR_OFF}, то синхронизируется командой ${COLOR_STATUS}${SYNC_CMD_UP_EDIT}${COLOR_OFF}

В конфиге есть параметры:

${COLOR_USAGE}WAIT_CHANGES${COLOR_OFF} -- это время ожидния перед выполнением команды синхронизации, 
чтобы не дёргать синхронизатор каждуюу секунду, учитывая что синхронизация 
сама по себе занимает несколько секунд, то есть смысл собрать какое-то 
количество изменений и синхронизировать их вместе.

Массив ${COLOR_USAGE}IGNORE_PATTERNS${COLOR_OFF} -- включает шаблоны файлов и папок 
на которые inotifywait не должен реагировать (.git-файлы, файлы блокировок, временные файлы).

${COLOR_INFO}Использование:${COLOR_OFF}
    ${APP_NAME} [опции]

${COLOR_INFO}Опции:${COLOR_OFF}
    ${COLOR_USAGE}--edit-conf, -ec${COLOR_OFF}  Открыть конфигурационный файл в редакторе
    ${COLOR_USAGE}--edit-list, -el${COLOR_OFF}  Открыть список папок для наблюдения в редакторе
    ${COLOR_USAGE}--dry-run, -n${COLOR_OFF}     Только инициализировать конфиг, без выполнения действий
    ${COLOR_USAGE}--verbose, -v${COLOR_OFF}     Подробный вывод
    ${COLOR_USAGE}--presync 1|0${COLOR_OFF}
    ${COLOR_USAGE}--presync=1|0${COLOR_OFF}     Выполнить предварительную синхронизацию перед запуском слушателя изменений
                      По умолчанию: ${COLOR_USAGE}1${COLOR_OFF} (выполнить)
                      Значение ${COLOR_USAGE}0${COLOR_OFF} отключает предварительную синхронизацию
    ${COLOR_USAGE}--help, -h${COLOR_OFF}        Показать это сообщение
    ${COLOR_USAGE}--usage, -u${COLOR_OFF}       Краткая справка
    ${COLOR_USAGE}--version, -V${COLOR_OFF}     Версия скрипта

${COLOR_INFO}Примечание:${COLOR_OFF}
    Файл со списком папок ${COLOR_FILENAME}$(basename "${LIST_FILE}")${COLOR_OFF} должен содержать пути, одна строка — один путь.
    Допускаются переменные окружения (например, \$HOME), 
    но ${COLOR_ERROR}запрещена${COLOR_OFF} подстановка команд: ${COLOR_USAGE}\`...\`${COLOR_OFF} и ${COLOR_USAGE}\$()${COLOR_OFF}.

${COLOR_INFO}Используемые компоненты:${COLOR_OFF}
    Файл конфигурации ............... : ${COLOR_FILENAME}${CONFIG_FILE}${COLOR_OFF}
    Файл со списком для слежения .... : ${COLOR_FILENAME}${LIST_FILE}${COLOR_OFF}

${COLOR_INFO}переопределяются в конфиге:${COLOR_OFF}
    Синхронизатор ................... : ${COLOR_FILENAME}${APP_S1}${COLOR_OFF}
    Слушатель файловых событий ...... : ${COLOR_FILENAME}${APP_INOTIFYWAIT}${COLOR_OFF}
    Языковой сканер, нужен только для 
    формирования конфиг-файла ....... : ${COLOR_FILENAME}${APP_AWK}${COLOR_OFF}

${COPYRIGHT}

EOF
)";
}



print_usage()
{
    echo -e "Использование: ${COLOR_USAGE}${APP_NAME} [опции]${COLOR_OFF}"
    echo -e "    Подробнее: ${COLOR_USAGE}${APP_NAME} --help${COLOR_OFF}"
}



print_version()
{
    echo -e "${COLOR_STATUS}${APP_NAME}${COLOR_OFF} — ${APP_TITLE}"
    echo -e "${COLOR_INFO}Версия:${COLOR_OFF} ${VERSION}"
    echo -e "${LAST_CHANGES}"
}



parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -ec|--edit-conf)
                echo "Редактирование конфига: ${CONFIG_FILE}"
                exec ${EDITOR} "${CONFIG_FILE}"
                exit 0;
                ;;
            -el|--edit-list)
                echo "Редактирование списка: ${LIST_FILE}"
                exec "${EDITOR}" "${LIST_FILE}"
                exit 0;
                ;;
            -n|--dry-run)
                DRY_RUN=1
                ;;
            -v|--verbose)
                VERBOSE=1
                ;;
            --presync=*)
                PRE_SYNC="${1#*=}"
                ;;
            --presync)
                shift
                [[ $# -gt 0 ]] || exit_with_msg "Отсутствует значение для --presync" 2
                PRE_SYNC="$1"
                ;;
            -h|--help)
                print_help
                exit 0
                ;;
            -u|--usage)
                print_usage
                exit 0
                ;;
            -V|--version)
                print_version
                exit 0
                ;;
            *)
                exit_with_msg "Неизвестный параметр: ${COLOR_USAGE}$1${COLOR_OFF}" 2
                ;;
        esac
        shift
    done

    # Валидация PRESYNC (один раз, централизованно)
    if [[ -n ${PRE_SYNC+x} ]]; then
        case "${PRE_SYNC}" in
            0|1) ;;
            *)
                exit_with_msg "Недопустимое значение --presync=${PRE_SYNC} (ожидается 0 или 1)" 2
                ;;
        esac
    fi

}



#
# Массив путей для мониторинга
#
WATCH_DIRS=()



#
# Чтение списка папаок для мониторинга
#
read_watch_folders()
{
    local line;

    # Проверка наличия конфигурационного файла
    [[ -f "${LIST_FILE}" ]] || {
        exit_with_msg "Файл списка ${LIST_FILE} не найден" 1
    }

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Удалить ведущие и хвостовые пробелы
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        # Пропуск пустых строк и комментариев (с ведущими пробелами)
        [[ -z "$line" || "${line:0:1}" == "#" ]] && continue

        # Запретить подстановку команд: $(...) или `...`
        if [[ "$line" == *'$'* && ( "$line" == *'('* || "$line" == *')'* || "$line" == *'\`'* ) ]]; then
            exit_with_msg "ИНЪЕКЦИЯ: Подстановка команды в строке: ${COLOR_FILENAME}${line}${COLOR_OFF}" 1
        fi

        # Безопасная подстановка переменных окружения
        line=$(echo "$line" | envsubst)

        # Удалить внешние кавычки, если они есть
        line="${line%\"}"
        line="${line#\"}"

        # Проверка на существование директории
        if [[ ! -d "$line" ]]; then
            exit_with_msg "Несуществующая папка: ${COLOR_FILENAME}${line}${COLOR_OFF}\n\
            Исправьте список папок синхронизации ${COLOR_FILENAME}${LIST_FILE}${COLOR_OFF}." 1
        fi

        # Добавление пути в массив
        WATCH_DIRS+=("$line")
    done < "${LIST_FILE}"

    # Проверка, что есть что мониторить
    if [[ ${#WATCH_DIRS[@]} -eq 0 ]]; then
        exit_with_msg "Нет папок для наблюдения. Проверьте файл-список ${COLOR_FILENAME}${LIST_FILE}${COLOR_OFF}." 1
    else
        echo -e "Считано папок: ${COLOR_INFO}${#WATCH_DIRS[@]}${COLOR_OFF}"
    fi
}



#
#
#
#  ======================================== MAIN ========================================
#
#
#



read_config_file

[[ ${VERBOSE} -eq 1 ]] && {
    echo -e "[${COLOR_INFO}ii${COLOR_OFF}] Конфиг: '${COLOR_FILENAME}${CONFIG_FILE}${COLOR_OFF}'";
    echo -e "[${COLOR_INFO}ii${COLOR_OFF}] Список: '${COLOR_FILENAME}${LIST_FILE}${COLOR_OFF}'";
    echo -e "[${COLOR_INFO}ii${COLOR_OFF}] sync_1: '${COLOR_FILENAME}${APP_S1}${COLOR_OFF}'";
}

parse_args "$@"

check_dependencies_required

read_watch_folders

# Предварительная синхронизация
if [[ ${PRE_SYNC} -eq 1 ]]; then
    echo -e "${COLOR_INFO}===> Выполняется предварительная синхронизация...${COLOR_OFF}"
    for dir in "${WATCH_DIRS[@]}"; do
        echo -e "${COLOR_INFO}===> Синхронизация папки: ${COLOR_FILENAME}${dir}${COLOR_OFF}${COLOR_USAGE}...${COLOR_OFF}"
        if [[ ${VERBOSE} -eq 1 ]]; then
            "${APP_S1}" "${dir}" "${SYNC_CMD_REGULAR}" --verbose
        else
            "${APP_S1}" "${dir}" "${SYNC_CMD_REGULAR}"
        fi
    done
    echo -e "${COLOR_INFO}===> Предварительная синхронизация завершена.${COLOR_OFF}"
else
    echo -e "${COLOR_INFO}===> Предварительная синхронизация отключена.${COLOR_OFF}"
fi

# Отображение наблюдаемых директорий
echo -e "${COLOR_INFO}===> Мониторинг следующих папок:${COLOR_OFF}"
for dir in "${WATCH_DIRS[@]}"; do
    cloud_stat="$("${APP_S1}" "${dir}" "${SHOW_CLOUD_STAT}")" || { exit_with_msg "Ошибка получения данных с сервера" 1; }
    cloud_cmd="$("${APP_S1}" "${dir}" "${SHOW_CLOUD_CMD}")" || { exit_with_msg "Ошибка получения данных с сервера" 1; }
    printf "     ${COLOR_FILENAME}%-30s${COLOR_OFF} | CLOUD STAT: ${COLOR_STATUS}%-8s${COLOR_OFF} | CLOUD CMD: ${COLOR_STATUS}%-8s${COLOR_OFF} |\n" "$dir" "${cloud_stat}" "${cloud_cmd}"
done
echo -e "${COLOR_INFO}===> Ctrl+C для выхода${COLOR_OFF}"



##
##  ========================================  Главный цикл  ========================================
##
inotifywait -r -m -e modify,create,delete,move --format '%w|%e|%f' "${WATCH_DIRS[@]}" | while IFS='|' read -r path action file; do
    
    # ⛔️ Игнорируем внутренние/временные/служебные файлы
    for pattern in "${IGNORE_PATTERNS[@]}"; do
        if [[ "${path}${file}" =~ $pattern ]]; then
            [[ ${VERBOSE} -eq 1 ]] && echo -e "$(date '+%H:%M:%S') ⛔️ ${COLOR_INFO}Пропущен по шаблону '${pattern}': ${COLOR_FILENAME}${path}${file}${COLOR_OFF}";
            continue 2
        fi
    done

    echo -e "\n🟡 Обнаружено изменение"
    echo -e "${COLOR_USAGE}$(date +'%F %T')${COLOR_OFF} | ${COLOR_INFO}${action}${COLOR_OFF} → ${COLOR_FILENAME}${path}${file}${COLOR_OFF}"

    # Абсолютный путь к папке, где произошло событие
    local_event_dir=$(get_abs_path "$path")

        # Найти родительскую папку из WATCH_DIRS, которая содержит событие
    parent_sync_dir=""
    for watch_dir in "${WATCH_DIRS[@]}"; do
        abs_watch_dir=$(get_abs_path "${watch_dir}")
        if [[ "${local_event_dir}" == "${abs_watch_dir}"* ]]; then
            parent_sync_dir="$abs_watch_dir"
            break
        fi
    done

    # Если не найдено соответствие — предупреждение и пропуск
    if [[ -z "$parent_sync_dir" ]]; then
        echo -e "${COLOR_ERROR}⚠️  Не удалось определить корневую папку синхронизации для:${COLOR_OFF} ${COLOR_FILENAME}${local_event_dir}${COLOR_OFF}"
        continue
    fi

    cloud_stat="$("${APP_S1}" "${parent_sync_dir}" "${SHOW_CLOUD_STAT}")" || { exit_with_msg "Ошибка получения статуса сервера для папки '${path}'" 1; }
    cloud_cmd="$("${APP_S1}" "${parent_sync_dir}" "${SHOW_CLOUD_CMD}")" || { exit_with_msg "Ошибка получения команды сервера для папки '${path}'" 1; }
    # echo -e "CMD_CLOUD: ${cloud_cmd}"

    case "${cloud_stat}" in
        "${SYNC_CMD_REGULAR}")
            cmd=("${APP_S1}" "${parent_sync_dir}" "${SYNC_CMD_UP_INIT}")
            ;;
        "${SYNC_CMD_PAUSE}")
            cmd=("${APP_S1}" "${parent_sync_dir}" "${SYNC_CMD_UP_EDIT}")
            ;;
        *)
            cmd=()
            ;;
    esac


    if ((${#cmd[@]})); then
        # П оказать какая команда выполнится
        echo -e "RUN: ${COLOR_INFO}${cmd[*]}${COLOR_OFF}"
        # Подождать перед тем, как грузить файлы
        echo -e "Через ${COLOR_INFO}${WAIT_CHANGES} сек${COLOR_OFF} будет выполнена синхронизация..."
        sleep "${WAIT_CHANGES}"

        {   # СИНХРОНИЗИРУЕМ
            trap '' SIGINT  # Выключить ловлю Ctrl+C
            "${cmd[@]}"
            trap - SIGINT   # Восстановить ловлю Ctrl+C
        }
    else
        printf "     ${COLOR_FILENAME}%-30s${COLOR_OFF} | CLOUD STAT: ${COLOR_STATUS}%s${COLOR_OFF} | CLOUD CMD: ${COLOR_STATUS}%s${COLOR_OFF}\n" \
                "$parent_sync_dir" "${cloud_stat}" "${cloud_cmd}"
    fi

    echo -e "==== End UP [ ${COLOR_INFO}Ctrl+C${COLOR_OFF} to stop ] ===="
done

