#!/usr/bin/env bash
set -euo pipefail
trap 'logger -p error -t "SYNC_ALL" "[$(date)] Ошибка в строке $LINENO: команда \"$BASH_COMMAND\""' ERR



# Определение: запуск из cron или вручную
# [[ ! -t 0 && ! -t 1 ]] проверяет, не подключены ли stdin и stdout к терминалу.
# Если оба не подключены — почти наверняка это cron, systemd, или другой фоновый запуск.
IS_CRON=false
if [[ ! -t 0 && ! -t 1 ]]; then
    IS_CRON=true
fi



APP_TITLE="Скрипт массовой сихронизации. Часть пакета персональной синхронизации sync_1"
VERSION="1.7.0 (2025-07-10)"
LAST_CHANGES="\
v1.2.6 (2025-04-25): Рефакторинг run_one_dir()
v1.2.7 (2025-05-08): Добавлен параметр LOG для показа логов работы скрипта
v1.3.0 (2025-05-17): Добавлен параметр SHOW_DEST показывает облачные пути
v1.3.1 (2025-05-23): Починка того, что сломалось после рефактринга sync_1
v1.3.2 (2025-06-02): Перенос конфигов в системную пользовательскую папаку конфигов
v1.4.0 (2025-06-12): Добавлена команда TEST, которая проверяет и показывает состояние синхронизатора
v1.6.0 (2025-06-27): Добавлен конфиг и команда редактирования конфига --edit-conf|-e
v1.7.0 (2025-07-10): Добавлена поддержка команды SHOW_CLOUD_CMD
"



APP_PATH=$(cd "$(dirname "$0")" && pwd)                     # Путь размещения исполняемого скрипта
APP_NAME=$(basename "$0")                                   # Полное имя скрипта, включая расширение
# shellcheck disable=SC2034
FILE_NAME="${APP_NAME%.*}"                                  # Убираем расширение (если есть), например ".sh"
# shellcheck disable=SC2034
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")                 # Полное имя [вложенного] скрипта, включая расширение
# shellcheck disable=SC2034
SCRIPT_PATH=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)   # Путь размещения [вложенного] скрипта

CONFIG_DIRNAME="sync"
CONFIG_PATH="${XDG_CONFIG_HOME:-${HOME}/.config}/${CONFIG_DIRNAME}"
CONFIG_FILE="${CONFIG_PATH}/${FILE_NAME}.conf"
SYNC_ALL_LIST_FILE="${CONFIG_PATH}/${FILE_NAME}.list"       # Список папок для синхронизации

VERB_MODE=$([[ "$IS_CRON" == false ]] && echo true || echo false) # Подробный вывод всех действий. Если false -- то "тихий режим"



##
##  ============================================================================
##  [CONFIG START] Начало секции конфига
##

##
##  Конфиг для скрипта sync_all. 
##  Из пакета индивидуальной синхронизации sync_1.
##  VERSION 1.0.0 (2025-06-26)
##

#
#  Допустимо использование переменных типа ${HOME}
#

SYNC1="sync_1.sh"                   # скрипт синхронизатор

LOG_PREFIX="SYNC_ALL"               # Используется для префикса в системном логе
LOG_COUNT_ROWS=40                   # Количество строк по умолчанию при просмотре логов
WAIT_END=5                          # seconds для просмотря результатв синхронизации

COLOR_USAGE="\e[1;32m"              # Терминальный цвет для вывода переменной статуса
COLOR_ERROR="\e[0;31m"              # Терминальный цвет для вывода ошибок
COLOR_INFO="\e[0;34m"               # Терминальный цвет для вывода информации (об ошибке или причине выхода)
COLOR_FILENAME="\e[1;36m"         # Терминальный цвет для вывода имён файлов
COLOR_OFF="\e[0m"                   # Терминальный цвет для сброса цвета

# Программа-редактор для редактирования конфиг-файла и списка папаок для копирования
# (без пробелов в пути/и/названии)
EDITOR="nano"


APP_AWK="/usr/bin/awk"
# VERB_MODE=1                               # Режим подробного вывода. # Не реализован
DRY_RUN=0                                   # Только посчитать. Без файловых операций

##
##  [CONFIG END] Конец секции конфига
##  ----------------------------------------------------------------------------
##


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
        source "${CONFIG_FILE}"
    else
        save_config_file
    fi
}



# Поддерживаемые пользовательские комманды
SYNC_CMD_REGULAR="REGULAR"
SYNC_CMD_UP="UP"
SYNC_CMD_DL="DL"
SYNC_CMD_UP_INIT="UP_INIT"
SYNC_CMD_DL_INIT="DL_INIT"
SYNC_CMD_PAUSE="PAUSE"
SYNC_CMD_UP_EDIT="UP_EDIT"
SYNC_CMD_UNPAUSE="UNPAUSE"
SHOW_LOG="LOG"                      # Показывает последние строки системного лога
SHOW_DEST="SHOW_DEST"               # Показывает dest-строку
SHOW_TEST="TEST"                    # Только проверить структуру
SHOW_CLOUD_CMD="SHOW_CLOUD_CMD"     # Показывает команду сервера

# Список допустимых команд
VALID_COMMANDS=(
    # Синхронизируют
    "${SYNC_CMD_REGULAR}"
    "${SYNC_CMD_UP}"
    "${SYNC_CMD_DL}"
    "${SYNC_CMD_UP_INIT}"
    "${SYNC_CMD_DL_INIT}"
    "${SYNC_CMD_PAUSE}"
    "${SYNC_CMD_UP_EDIT}"
    "${SYNC_CMD_UNPAUSE}"
    # Показывают
    "${SHOW_LOG}"
    "${SHOW_DEST}"
    "${SHOW_TEST}"
    "${SHOW_CLOUD_CMD}"
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
#  Полная справка по скрипту
#
print_help()
{
cat << EOF
${APP_TITLE}
Скрипт: ${APP_NAME} Версия: ${VERSION}
Папка размещения: "${APP_PATH}"

Скрипт массовой синхронизации списка папок.
Вспомогательный скрипт из комплекта персональной синхронизации sync_1.
Подробности о работе см. основной скрипт "sync_1.sh --help"

Список файлов для синхронизации берётся из файла ${SYNC_ALL_LIST_FILE}
в котором просто перечислены папки для синхронизации 
и не обязательное текстовое сообщение-баннер для оформления лога синхронизации.

Использование:
    ${APP_NAME}  [ $(str=$(IFS="|"; echo "${VALID_COMMANDS[*]:0:5}"); echo "${str//|/ | }";) ]
                 [ $(str=$(IFS="|"; echo "${VALID_COMMANDS[*]:5:3}"); echo "${str//|/ | }";) ]
                 [ $(str=$(IFS="|"; echo "${VALID_COMMANDS[*]:8}");  echo "${str//|/ | }";) ]
                 По умолчанию: ${SYNC_CMD_REGULAR}

    ${SYNC_CMD_REGULAR}   -- действие по умолчанию. Указывать не обязательно.
                 Запись данных на сервер (${SYNC_CMD_UP}) и скачивание данных с сервера (${SYNC_CMD_DL}) 
                 без удаления расхождений.
                 
    ${SYNC_CMD_UP}        -- Запись данных на сервер без удаления.

    ${SYNC_CMD_DL}        -- Чтение данных с сервера без удаления.

    ${SYNC_CMD_DL_INIT}   -- Загрузка данных с сервера на локальный хост 
                 с *удалением* расхождений на локальном хосте.

    $SYNC_CMD_UP_INIT   -- Запись данных с локального хоста на сервер 
                 с *удалением* расхождений на сервере, и установка для всех хостов 
                 статуса ${SYNC_CMD_DL_INIT} для обязательной загрузки изменений.

    ${SYNC_CMD_PAUSE}     -- Обмен данными не происходит. 
                 Режим для изменений данных на самом сервере. 
                 Никаая комманда с серера ничего не скачивает. 
                 Для изменения файлов на сервере в этом режиме используется комманда ${SYNC_CMD_UP_EDIT}. 

    ${SYNC_CMD_UP_EDIT}   -- Отправляет данные на сервер с удалением расхождений на стороне сервера.
                 Работает только если статус сервера ${SYNC_CMD_PAUSE}. 
                 Работает как ${SYNC_CMD_UP_INIT} только НЕ изменяет статус синхронизации для клиентов.

    ${SYNC_CMD_UNPAUSE}   -- Обмен данными не происходит. 
                 Для всех хостов устанавливается статус ${SYNC_CMD_DL_INIT} 

    ${SHOW_DEST} -- Обмен данными не происходит. 
                 Показать строку dest -- адрес папки на сервере. 

    ${SHOW_CLOUD_CMD} -- Обмен данными не происходит. 
                 Показать статус команд сервера для всех папок
                 
    ${SHOW_TEST}      -- Тестирует настройки синхронизатора.
                 Обмен данными не происходит. 
                 Только проверяет и показывает локальную струткуру 
                 и проверяет доступ к папке на сервере. 

    ${SHOW_LOG} [<количество_строк>]
                 Показыват указанное количство строк из лог-файла. 
                 По умолчанию количеcтво = ${LOG_COUNT_ROWS}

    --help    | -h      Это описание
    --usage   | -u      Краткая справка по использованию
    --version | -v      Версия скрипта
    --edit-conf         Редактирование конфига
    --edit-list         Редактирование списка для синхронизации

ВАЖНО:
При добавлении скрипта в crontab нужно добавить в cron-скрипт переменные окружения, 
               которые нужны этому скрипту, и которые отсутсвуют при выполнении скрипта 
               не в пользовательском окружении: cron, systemd, или другой фоновый запуск.
               примерно так:

               USER=${USER}
               HOME=${HOME}
               PATH=/usr/local/bin:/usr/bin:/bin:${HOME}/bin:${HOME}/.local/bin
               SHELL=/bin/bash
               BASH_ENV=${HOME}/.bashrc

               1  *  *  *  *    ${HOME}/bin/sync_all.sh

               для контроля исполнения скрипта можно добавить логирование работы самого скрипта:
               1  *  *  *  *    ${HOME}/bin/sync_all.sh >> ${HOME}/sync_all_cron.log 2>&1

Последние изменения
${LAST_CHANGES}
EOF
}



#
#  Кратная справка по использованию
#
print_usage()
{
cat << EOF
${APP_TITLE}
Использование:
    ${APP_NAME}  [ $(str=$(IFS="|"; echo "${VALID_COMMANDS[*]:0:5}"); echo "${str//|/ | }";) ]
                 [ $(str=$(IFS="|"; echo "${VALID_COMMANDS[*]:5:3}"); echo "${str//|/ | }";) ]
                 [ $(str=$(IFS="|"; echo "${VALID_COMMANDS[*]:8}");  echo "${str//|/ | }";) ]
                 По умолчанию: ${SYNC_CMD_REGULAR}
                 [ --help | -h | --usage | -u | --version | -v ]
                 [ --edit-conf | --edit-list ]
                 [ ${SHOW_LOG} <количество_строк> ]
EOF
}



#
#  Вывод версии скрипта
#
print_version()
{
    echo "${APP_TITLE}"
    echo "Скрипт       : ${APP_NAME}"
    echo "Версия       : ${VERSION}"
    echo "Путь скрипта : \"${APP_PATH}\""
    echo "Последние изменения"
    echo "${LAST_CHANGES}"
    echo ""
}



#
#  Вывод последних сообщений этого скрипта из системного лога
#
print_log() {
    local count="${1:-${LOG_COUNT_ROWS}}"
    # journalctl -p info --since "2 days ago" | grep -- "$LOG_PREFIX" || true | tail -n "$count"
    # journalctl -t "${LOG_PREFIX}" --since "2 days ago" || true | tail -n "$count"
    journalctl -t "${LOG_PREFIX}" -n "$count"

}



#
# Запуск синхронизации для указанной папки.
# С предварительной проверкой наличия самой папки, 
# и наличия в ней папки синхронизатора .sync
# с проверкой наличия подпапки `.sync` и файлов dest/excludes
#
run_one_dir() {
    local dir="${1:?Папка синхронизации не указана}"
    local sync_dir="$dir/.sync"
    local dest_file="$sync_dir/dest"
    local excludes_file="$sync_dir/excludes"

    [[ -f "$dest_file" ]] || { echo "Нет файла [$dest_file]"; return 1; }
    [[ -f "$excludes_file" ]] || { echo "Нет файла [$excludes_file]"; return 1; }

    if [[ -z "${USER_CMD:-}" ]]; then
        "$SYNC1" "$dir" < /dev/null
    else
        "$SYNC1" "$dir" "$USER_CMD" < /dev/null
    fi
}



#
#  Предварительная информация перед запуском синхронизации 
#  для визуального разделения результатов команд синхронизации.
#  Информационный баннер перез запуском синхронизации
#
run_banner() {
    local folder="${1:?}"
    local banner="${2:-$folder}"

    if [[ "$VERB_MODE" == true ]]; then
        printf "\n\n\n\n"
        echo "$banner"
        command -v figlet &>/dev/null && figlet -k "$banner" -f big
    fi

    run_one_dir "$folder"
}



#
#  Возвращает пары folder + banner для синхронизации
#
parse_sync_list() {
    local file="$1"
    [[ -f "$file" ]] || {
        echo "Файл $file не найден"
        return 1
    }

    while IFS= read -r line_raw || [[ -n "$line_raw" ]]; do
        [[ -z "$line_raw" || "$line_raw" =~ ^[[:space:]]*# ]] && continue

        eval "set -- $line_raw"  # корректно обрабатывает кавычки
        echo "$1|${2:-$1}"
    done < "$file"
}



#
#  Вывод информационного баннера и таймера завершения скрипта
#
#     📌 Способы перемещения курсора:
#     Escape-код	Описание
#     \033[A	вверх на 1 строку
#     \033[B	вниз на 1 строку
#     \033[C	вправо на 1 символ
#     \033[D	влево на 1 символ
#     \033[F	в начало предыдущей строки (эквивалент \033[A\r)
#
wait_end() {
    local seconds="${1:-${WAIT_END}}"
    local first=true
    while (( seconds >= 0 )); do
        if ! $first; then
            printf "\033[F\033[F\033[F\033[F\033[F\033[F"
        else
            first=false
        fi
        echo    "╔═══════════════════════════════════════════════════════════════════════════════╗"
        echo    "║                                                                               ║"
        echo    "║                     Все выполнено. Окно можно закрыть.                        ║"
        printf  "║                     Автоматическое закрытие через [\e[0;31m%2d\e[0m] сек.                   ║\n" "${seconds}"
        echo    "║                                                                               ║"
        echo    "╚═══════════════════════════════════════════════════════════════════════════════╝"
        # printf "\rОкно можно закрыть. Автоматическое завершение через %2d сек..." "$seconds"
        sleep 1
        ((seconds--))
    done
}



#
#
#
# =================================== MAIN ====================================
#
#
#



read_config_file



# #   DEBUG
# {
#     echo "=== Крон запуск: $(date) ==="
#     echo "UID: $(id -u), USER: ${USER:?}, HOME: ${HOME:?}"
#     echo "PATH: ${PATH:?}"
#     echo "PWD: $(pwd)"
#     echo "SYNC_ALL_LIST_FILE: ${SYNC_ALL_LIST_FILE:?}"
#     # echo "Содержимое sync_all.list:"
#     # cat "$SYNC_ALL_LIST_FILE"
# } >> ${HOME:?}/sync_all_debug.log 2>&1



case "${1:-}" in
  -h|--help)
    print_help
    exit 0
    ;;
  -u|--usage)
    print_usage
    exit 0
    ;;
  -v|--version)
    print_version
    exit 0
    ;;
  --edit-conf)
    echo "Редактирование конфига: ${CONFIG_FILE}"
    exec "${EDITOR}" "${CONFIG_FILE}"
    exit 0
    ;;
  --edit-list)
    echo "Редактирование списка: ${SYNC_ALL_LIST_FILE}"
    exec "${EDITOR}" "${SYNC_ALL_LIST_FILE}"
    exit 0
    ;;
esac



#
# Пользовательская комманда из списка выше
# Используется для того, чтоыб всем папкам передать определеннуб команду
# например:
# sync_all.sh UP_INIT -- для полного обновления всех файлов на сервере с локального компьютера 
#                        и обновления файлов на всех подключенных к синхронизауии компьютерах
# РИСК: если злоумышленник удалит файлы на локальном компьюбтере и выполнит эту комманду, 
#       то файлы удаляться на всех клинтских компьютерах при следующей синхронизации. 
#       Хотя, так-же функционируют все системы синхронизации.
# 
USER_CMD="${1:-}"



# Переходим в папку, где находится конфиг, чтобы правильно видеть конфиг-файл
cd "${CONFIG_PATH}" || { 
    exit_with_msg "По какой-то причине переход в папку размещения скрипла [${CONFIG_PATH}] не удался." 1;
} 



case "$USER_CMD" in
    "$SHOW_LOG") print_log "${2:-}"; exit 0 ;;

    #  Если нужно вывести только dest-строки, то использовать "тихий" режим
    "${SHOW_DEST}"|"${SHOW_CLOUD_CMD}"|"${SHOW_TEST}") VERB_MODE=false ;;

    ""|\
    "$SYNC_CMD_REGULAR"|"$SYNC_CMD_UP"|"$SYNC_CMD_DL"|\
    "$SYNC_CMD_UP_INIT"|"$SYNC_CMD_DL_INIT"|\
    "$SYNC_CMD_PAUSE"|"$SYNC_CMD_UP_EDIT"|"$SYNC_CMD_UNPAUSE") : ;;  # допустимые команды

    *)
        exit_with_msg "Неверная команда: [$USER_CMD]" 2;
        ;;
esac



log_info "BEG: $(date)"
log_info "VER: $VERSION"
# ${*@Q} — цитирует каждый аргумент как Bash-литерал (например, --opt="some val" → '--opt=some val'), безопасно для логов.
log_info "CMD: $0 ${*@Q}"
[[ "$VERB_MODE" == true ]] && echo "$APP_NAME VERSION $VERSION"


# ========== ОСНОВНОЙ ЦИКЛ ОБРАБОТКИ ФАЙЛОВ ==========



[[ -f "$SYNC_ALL_LIST_FILE" ]] || {
    exit_with_msg "Файл $SYNC_ALL_LIST_FILE не найден" 1;
}


##  =================================================  ##
##                                                     ##
##  Собственно, тут перебор синхронизируемых папок     ##
##                                                     ##

while IFS="|" read -r folder banner; do
    if ! run_banner "$folder" "$banner"; then
        err="Ошибка обработки папки: $folder"
        echo     "$err" >&2
        log_info "ERR: $err"
    fi
done < <(parse_sync_list "$SYNC_ALL_LIST_FILE")

##                                                     ##
##  конец списка синхронизации                         ##
##                                                     ##
##  =================================================  ##



log_info "END: $(date)"
${VERB_MODE} && wait_end "${WAIT_END}"
