#!/usr/bin/env bash
set -euo pipefail
trap 'logger -p error -t "SYNC_WATHER" "[$(date)] Ошибка в строке $LINENO: команда \"$BASH_COMMAND\""' ERR

VERSION="0.2-alfa (2025-07-10)"
LAST_CHANGES="\
v0.2.0 (2025-07-10): Базовый функционал
"

APP_TITLE="Слушатель изменений и автосинхронизатор"
APP_NAME=$(basename "$0")                                   # Полное имя скрипта, включая расширение
APP_PATH=$(cd "$(dirname "$0")" && pwd)                     # Путь размещения исполняемого скрипта
FILE_NAME="${APP_NAME%.*}"                                  # Убираем расширение (если есть), например ".sh"
# shellcheck disable=SC2034
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")                 # Полное имя [вложенного] скрипта, включая расширение
# shellcheck disable=SC2034
SCRIPT_PATH=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)   # Путь размещения [вложенного] скрипта

CONFIG_DIRNAME="sync"
CONFIG_PATH="${XDG_CONFIG_HOME:-${HOME}/.config}/${CONFIG_DIRNAME}"
CONFIG_FILE="${CONFIG_PATH}/${FILE_NAME}.conf"              # Конфиг-файл
LIST_FILE="${CONFIG_PATH}/${FILE_NAME}.list"                # Файл со списком папаок для мониторинга

DRY_RUN=0                                                   # Режим имитации, без фактического выполнения синхронизации
VERBOSE=0                                                   # Подробный вывод всякой фигни


#
# Список поддерживаемых команд
#
# shellcheck disable=SC2034
{
    SHOW_LOG="LOG"                              # Показать логи
    SHOW_DEST="SHOW_DEST"                       # Показывает dest-строку
    SHOW_TEST="TEST"                            # Только проверить структуру
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
##  ============================================================================
##  [CONFIG START] Начало секции конфига
##

##
##  Конфиг для скрипта Слушателя изменений и синхронизатора. 
##  VERSION 0.2-alfa (2025-07-10)
##
##  APP_PATH                                # Путь размещения исполняемого скрипта
##

LOG_PREFIX="SYNC_ALL"                       # Используется для префикса в системном логе
APP_S1="${APP_PATH}/sync_1.sh"              # Программа-синхронизатор

APP_INOTIFYWAIT="/usr/bin/inotifywait"
APP_INOTIFYWAIT_PKG="inotify-tools"

APP_AWK="/usr/bin/awk"
APP_AWK_PKG="gawk"

APP_ENVSUBST="/usr/bin/envsubst"
APP_ENVSUBST_PKG="gettext"

SLEEP_WAIT=1                                # Время ожидния перед выполнением команды синхронизации



#
# Шаблоны файлов, которые не должны вызывать синхронизацию
#
IGNORE_PATTERNS=(
    '^\.sync_'             # файлы, начинающиеся на .sync_
    '\.swp$'               # swap-файлы
    '\.tmp$'               # временные
    '\.bak$'               # резервные
    '(^|/)\.sync/'         # любые файлы в папке .sync (в любом месте пути)
)



#
#  Цвета для консольных сообщений
#
COLOR_FILENAME="\e[1;36m"                   # Для вывода имён файлов и путей
COLOR_STATUS="\033[0;36m"                   # Терминальный цвет для вывода переменной статуса
COLOR_USAGE="\033[1;34m"                    # Терминальный цвет для вывода переменной статуса
COLOR_INFO="\033[0;34m"                     # Терминальный цвет для вывода информации (об ошибке или причине выхода)
COLOR_OK="\033[0;32m"                       # Терминальный цвет для вывода Ok-сообщения
COLOR_ERROR="\033[0;31m"                    # Терминальный цвет для вывода ошибок
COLOR_OFF="\033[0m"                         # Сброс цвета

#
# Программа-редактор для редактирования конфиг-файла и файла-списка папок для контроля
# (без пробелов в пути/и/названии)
EDITOR="nano"



##
##  [CONFIG END] Конец секции конфига
##  ----------------------------------------------------------------------------
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
    ["${APP_ENVSUBST}"]="${APP_ENVSUBST_PKG}"
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
Полный справочник по использованию.

${COLOR_INFO}Использование:${COLOR_OFF}
    ${APP_NAME} [опции]

${COLOR_INFO}Опции:${COLOR_OFF}
    ${COLOR_STATUS}--edit-conf${COLOR_OFF}       Открыть конфигурационный файл в редакторе
    ${COLOR_STATUS}--edit-list${COLOR_OFF}       Открыть список папок для наблюдения в редакторе
    ${COLOR_STATUS}--dry-run, -n${COLOR_OFF}     Только инициализировать конфиг, без выполнения действий
    ${COLOR_STATUS}--help, -h${COLOR_OFF}        Показать это сообщение
    ${COLOR_STATUS}--usage, -u${COLOR_OFF}       Краткая справка
    ${COLOR_STATUS}--version, -v${COLOR_OFF}     Версия скрипта

${COLOR_INFO}Примечание:${COLOR_OFF}
    Файл со списком папок должен содержать пути (одна строка — один путь).
    Допускаются переменные окружения (например, \$HOME), но запрещена подстановка команд: \`...\` и \$().
EOF
)";
}


print_usage()
{
    echo -e "${COLOR_USAGE}Использование:${COLOR_OFF} ${APP_NAME} [опции]"
    echo -e "  Подробнее: ${APP_NAME} --help"
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
            --edit-conf)
                echo "Редактирование конфига: ${CONFIG_FILE}"
                exec ${EDITOR} "${CONFIG_FILE}"
                exit 0;
                ;;
            --edit-list)
                echo "Редактирование списка: ${LIST_FILE}"
                exec "${EDITOR}" "${LIST_FILE}"
                exit 0;
                ;;
            --dry-run|-n)
                DRY_RUN=1
                ;;
            --verbose|-V)
                VERBOSE=1
                ;;
            --help|-h)
                print_help
                exit 0
                ;;
            --usage|-u)
                print_usage
                exit 0
                ;;
            --version|-v)
                print_version
                exit 0
                ;;
            *)
                exit_with_msg "Неизвестный параметр: $1" 2
                ;;
        esac
        shift
    done
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
        exit_with_msg "Файл конфигурации ${LIST_FILE} не найден" 1
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
            exit_with_msg "Несуществующая папка: ${COLOR_FILENAME}${line}${COLOR_OFF}" 1
        fi

        # Добавление пути в массив
        WATCH_DIRS+=("$line")
    done < "${LIST_FILE}"

    # Проверка, что есть что мониторить
    if [[ ${#WATCH_DIRS[@]} -eq 0 ]]; then
        exit_with_msg "Нет папок для наблюдения. Проверьте конфигурацию." 1
    else
        echo -e "Считано папок: ${COLOR_INFO}${#WATCH_DIRS[@]}${COLOR_OFF}"
    fi
}



#
#
#
#  =================================== MAIN ===================================
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



# Отображение наблюдаемых директорий
echo -e "${COLOR_USAGE}===> Мониторинг следующих папок:${COLOR_OFF}"
for dir in "${WATCH_DIRS[@]}"; do
    cmd="${APP_S1} ${dir} ${SHOW_CLOUD_CMD}"
    cloud_cmd="$(${cmd})" || { exit_with_msg "Ошибка получения данных с сервера" 1; }
    printf "     ${COLOR_FILENAME}%-30s${COLOR_OFF} | CLOUD CMD: ${COLOR_STATUS}%s${COLOR_OFF}\n" "$dir" "${cloud_cmd}"
done
echo -e "${COLOR_USAGE}===> Ctrl+C для выхода${COLOR_OFF}"



# Главный цикл
inotifywait -r -m -e modify,create,delete,move --format '%w|%e|%f' "${WATCH_DIRS[@]}" | while IFS='|' read -r path action file; do
    
    # ⛔️ Игнорируем внутренние/временные/служебные файлы
    for pattern in "${IGNORE_PATTERNS[@]}"; do
        if [[ "${path}${file}" =~ $pattern ]]; then
            [[ ${VERBOSE} -eq 1 ]] && echo -e "⛔️ ${COLOR_INFO}Пропущен по шаблону '${pattern}': ${COLOR_FILENAME}${path}${file}${COLOR_OFF}";
            continue 2
        fi
    done

    echo -e "\n🟡 Обнаружено изменение"
    echo -e "${COLOR_USAGE}$(date +'%F %T')${COLOR_OFF} | ${COLOR_INFO}${action}${COLOR_OFF} → ${COLOR_FILENAME}${path}${file}${COLOR_OFF}"

    cmd="${APP_S1} ${path} ${SHOW_CLOUD_CMD}"
    cloud_cmd="$(${cmd})" || { exit_with_msg "Ошибка получения данных с сервера" 1; }
    echo -e "CMD_CLOUD: ${cloud_cmd}"
    case "${cloud_cmd}" in
        "${SYNC_CMD_REGULAR}")
            cmd="${APP_S1} ${path} ${SYNC_CMD_UP}"
            ;;
        "${SYNC_CMD_PAUSE}")
            cmd="${APP_S1} ${path} ${SYNC_CMD_UP_EDIT}"
            ;;
        *)
            cmd="${APP_S1} ${path}"
            ;;
    esac
    echo "RUN: eval ${cmd}"
    # Подождать перед тем, ка грузить файлы
    sleep "${SLEEP_WAIT}"
    {   # СИНХРОНИЗИРУЕМ
        trap '' SIGINT  # Выключить ловлю Ctrl+C
        eval "$cmd"
        trap - SIGINT   # Восстановить ловлю Ctrl+C
    }
    echo -e "==== End UP [ Ctrl+C to stop ] ===="
done

