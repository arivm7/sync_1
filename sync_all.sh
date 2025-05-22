#!/usr/bin/env bash
set -euo pipefail



APP_TITLE="Скрипт массовой сихронизации. Часть пакета персональной синхронизации sync_1"
VERSION="1.3.1 (2025-05-23)"
LAST_CHANGES="\
v1.2.6 (2025-04-25): Рефакторинг run_one_dir()
v1.2.7 (2025-05-08): Добавлен параметр LOG для показа логов работы скрипта
v1.3.0 (2025-05-17): Добавлен параметр SHOW_DEST показывает облачные пути
v1.3.1 (2025-05-23): Починка того, что сломалось после рефактринга sync_1
"

APP_NAME=$(basename "$0")
APP_PATH=$(dirname "$0")

SYNC_ALL_LIST_FILE="sync_all.list"  # Конфиг-файл со списком папок для синхронизации
SYNC1="sync_1.sh"                   # скрипт синхронизатор

LOG_PREFIX="SYNC_ALL: "             # Используется для префикса в системном логе
LOG_COUNT_ROWS="20"                 # Количество строк по умолчанию при просмотре логов
VERB_MODE=true                      # Подробный вывод всех действий. Если false -- то "тихий режим"
WAIT_END=5                          # seconds для просмотря результатв синхронизации



# Поддерживаемые пользовательские комманды
SHOW_LOG="LOG"
SHOW_DEST="SHOW_DEST"                   # Показывает dest-строку
SYNC_CMD_REGULAR="REGULAR"
SYNC_CMD_UP="UP"
SYNC_CMD_DL="DL"
SYNC_CMD_UP_INIT="UP_INIT"
SYNC_CMD_DL_INIT="DL_INIT"
SYNC_CMD_PAUSE="PAUSE"
SYNC_CMD_UP_EDIT="UP_EDIT"
SYNC_CMD_UNPAUSE="UNPAUSE"



log_info() {
    logger -p info "${LOG_PREFIX} $*"
}



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
    ${APP_NAME} [${SYNC_CMD_REGULAR}|${SYNC_CMD_UP}|${SYNC_CMD_DL}|${SYNC_CMD_UP_INIT}|${SYNC_CMD_DL_INIT}|${SYNC_CMD_PAUSE}|${SYNC_CMD_UP_EDIT}|${SYNC_CMD_UNPAUSE}|${SHOW_DEST}] 

    ${SYNC_CMD_REGULAR} -- действие по умолчанию. Указывать не обязательно.
               Запись данных на сервер (${SYNC_CMD_UP}) и скачивание данных с сервера (${SYNC_CMD_DL}) 
               без удаления расхождений.
    ${SYNC_CMD_UP}      -- Запись данных на сервер без удаления.
    ${SYNC_CMD_DL}      -- Чтение данных с сервера без удаления.
    ${SYNC_CMD_DL_INIT} -- Загрузка данных с сервера на локальный хост 
               с *удалением* расхождений на локальном хосте.
    $SYNC_CMD_UP_INIT -- Запись данных с локального хоста на сервер 
               с *удалением* расхождений на сервере, и установка для всех хостов 
               статуса ${SYNC_CMD_DL_INIT} для обязательной загрузки изменений.
    ${SYNC_CMD_PAUSE}   -- Обмен данными не происходит. 
               Режим для изменений данных на самом сервере. 
               Никаая комманда с серера ничего не скачивает. 
               Для изменения файлов на сервере в этом режиме используется комманда ${SYNC_CMD_UP_EDIT}. 
    ${SYNC_CMD_UP_EDIT} -- Отправляет данные на сервер с удалением расхождений на стороне сервера.
               Работает только если статус сервера ${SYNC_CMD_PAUSE}. 
               Работает как ${SYNC_CMD_UP_INIT} только НЕ изменяет статус синхронизации для клиентов.
    ${SYNC_CMD_UNPAUSE} -- Обмен данными не происходит. 
               Для всех хостов устанавливается статус ${SYNC_CMD_DL_INIT} 
    ${SHOW_DEST} -- Обмен данными не происходит. 
               Показать строку dest -- адрес папки на сервере. 

    ${APP_NAME} ${SHOW_LOG} <количество_строк>
               Показыват указанное количство строк из лог-файла. По умолчанию количечтво = ${LOG_COUNT_ROWS}

Последние изменения
${LAST_CHANGES}
EOF
}



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



print_log() {
    local count="${1:-$LOG_COUNT_ROWS}"
    journalctl -p info --since today | grep -- "$LOG_PREFIX" || true | tail -n "$count"
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
# Предварительная информация перед запуском синхронизации 
# для визуального разделения результатов команд синхронизации.
# Информационный баннер перез запуском синхронизации
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



# Возвращает пары folder + banner для синхронизации
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
#
#
# ========== ПАРСИНГ АРГУМЕНТОВ ==========
#
#
#



[[ "${1:-}" =~ ^-h|--help$ ]] && { print_help; exit 0; }

[[ "${1:-}" =~ ^-v|--version$ ]] && { print_version; exit 0; }

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



# Переходим в папку, где находится скрипт, чтобы правильно видеть конфиг-файл
SCRIPT_DIR=$(dirname "$(realpath "$0")")
cd "${SCRIPT_DIR}" || { 
    ERR="По какой-то причине переход в папку размещения скрипла [${SCRIPT_DIR}] не удался."
    logger -p info "${LOG_PREFIX} ERR: ${ERR}"
    echo "${ERR}" ; 
    exit 1; 
} 



case "$USER_CMD" in
    "$SHOW_LOG") print_log "${2:-}"; exit 0 ;;

    #  Если нужно вывести только dest-строки, то использовать "тихий" режим
    "$SHOW_DEST") VERB_MODE=false ;;

    ""|"$SYNC_CMD_REGULAR"|"$SYNC_CMD_UP"|"$SYNC_CMD_DL"|"$SYNC_CMD_UP_INIT"|"$SYNC_CMD_DL_INIT"|"$SYNC_CMD_PAUSE"|"$SYNC_CMD_UP_EDIT"|"$SYNC_CMD_UNPAUSE") ;;  # допустимые команды

    *)
        log_info "Неверная команда: [$USER_CMD]"
        echo "Неверная команда: [$USER_CMD]"
        exit 2
        ;;
esac


log_info "BEG: $(date)"
log_info "VER: $VERSION"
# ${*@Q} — цитирует каждый аргумент как Bash-литерал (например, --opt="some val" → '--opt=some val'), безопасно для логов.
log_info "CMD: $0 ${*@Q}"
[[ "$VERB_MODE" == true ]] && echo "$APP_NAME VERSION $VERSION"


# ========== ОСНОВНОЙ ЦИКЛ ОБРАБОТКИ ФАЙЛОВ ==========


[[ -f "$SYNC_ALL_LIST_FILE" ]] || {
    echo "Файл $SYNC_ALL_LIST_FILE не найден"
    exit 1
}


##  =================================================  ##
##                                                     ##
##  Собственно, тут перебор синхронизируемых папок     ##
##                                                     ##

while IFS="|" read -r folder banner; do
    run_banner "$folder" "$banner"
done < <(parse_sync_list "$SYNC_ALL_LIST_FILE")

##                                                     ##
##  конец списка синхронизации                         ##
##                                                     ##
##  =================================================  ##



logger -p info "${LOG_PREFIX} END: $(date)"
[[ "$VERB_MODE" == true ]] && {
    echo    "╔═══════════════════════════════════════════════════════════════════════════════╗"
    echo    "║                                                                               ║"
    echo    "║                     Все выполнено. Окно можно закрыть.                        ║"
    echo    "║                     Автоматическое закрытие через [${WAIT_END}] сек.                    ║"
    echo    "║                                                                               ║"
    echo    "╚═══════════════════════════════════════════════════════════════════════════════╝"
    sleep ${WAIT_END}
};
