#!/usr/bin/env bash
set -e
set -u
set -o pipefail


VERSION="1.2.7 (2025-05-08)"
LAST_CHANGES="\
v1.2.6 (2025-04-25): Рефакторинг run_one_dir()
v1.2.7 (2025-05-08): Добавлен параметр LOG для показа логов работы скрипта
"

APP_NAME=$(basename "$0")
APP_PATH=$(dirname "$0")

SYNC_ALL_LIST_FILE="sync_all.list"  # Конфиг-файл со списком папок для синхронизации
SYNC1="${HOME}/bin/sync_1.sh"       # скрипт синхронизатор
WAIT_END=5                          # seconds для просмотря результатв синхронизации
LOG_PREFIX="SYNC_ALL: "             # Используется для префикса в системном логе
LOG_COUNT_ROWS="20"                 # Количество строк по умолчанию при просмотре логов

# Переходим в папку, где находится скрипт, чтобы правильно видеть конфиг-файл
SCRIPT_PATH=$(realpath "$0")
SCRIPT_DIR=$(dirname "${SCRIPT_PATH}")
cd "${SCRIPT_DIR}" || { 
    ERR="По какой-то причине переход в папку размещения скрипла [${SCRIPT_DIR}] не удался."
    logger -p info "${LOG_PREFIX} ERR: ${ERR}"
    echo "${ERR}" ; 
    exit 1; 
} 



# Поддерживаемые пользовательские комманды
SHOW_LOG="LOG"
SYNC_STATUS_UP="UP"
SYNC_STATUS_DL="DL"
SYNC_STATUS_REGULAR="REGULAR"
SYNC_STATUS_UP_INIT="UP_INIT"
SYNC_STATUS_DL_INIT="DL_INIT"
SYNC_STATUS_PAUSE="PAUSE"
SYNC_STATUS_UP_EDIT="UP_EDIT"
SYNC_STATUS_UNPAUSE="UNPAUSE"



print_help()
{
    echo "" 
    echo "Скрипт: ${APP_NAME} Версия: ${VERSION}"
    echo "Папка размещения: \"${APP_PATH}\""
    echo "" 
    echo "Скрипт массовой синхронизации списка папок." 
    echo "Вспомогательный скрипт из комплекта персональной синхронизации sync_1." 
    echo "Подробности о работе см. основной скрипт \"sync_1.sh --help\"" 
    echo "" 
    echo "Список файлов для синхронизации берётся из файла ${SYNC_ALL_LIST_FILE}" 
    echo "в котором просто перечислены папки для синхронизации " 
    echo "и не обязательное текстовое сообщение-баннер для оформления лога синхронизации." 
    echo ""
    echo "Использование:"
    echo "    ${APP_NAME} [${SYNC_STATUS_REGULAR}|${SYNC_STATUS_UP}|${SYNC_STATUS_DL}|${SYNC_STATUS_UP_INIT}|${SYNC_STATUS_DL_INIT}|${SYNC_STATUS_PAUSE}|${SYNC_STATUS_UP_EDIT}|${SYNC_STATUS_UNPAUSE}] "
    echo "    "
    echo "    ${SYNC_STATUS_REGULAR} -- действие по умолчанию. Указывать не обязательно."
    echo "               Запись данных на сервер (${SYNC_STATUS_UP}) и скачивание данных с сервера (${SYNC_STATUS_DL}) "
    echo "               без удаления расхождений."
    echo "    ${SYNC_STATUS_UP}      -- Запись данных на сервер без удаления."
    echo "    ${SYNC_STATUS_DL}      -- Чтение данных с сервера без удаления."
    echo "    ${SYNC_STATUS_DL_INIT} -- Загрузка данных с сервера на локальный хост "
    echo "               с *удалением* расхождений на локальном хосте."
    echo "    $SYNC_STATUS_UP_INIT -- Запись данных с локального хоста на сервер "
    echo "               с *удалением* расхождений на сервере, и установка для всех хостов "
    echo "               статуса ${SYNC_STATUS_DL_INIT} для обязательной загрузки изменений."
    echo "    ${SYNC_STATUS_PAUSE}   -- Обмен данными не происходит. "
    echo "               Режим для изменений данных на самом сервере. "
    echo "               Никаая комманда с серера ничего не скачивает. "
    echo "               Для изменения файлов на сервере в этом режиме используется комманда ${SYNC_STATUS_UP_EDIT}. "
    echo "    ${SYNC_STATUS_UP_EDIT} -- Отправляет данные на сервер с удалением расхождений на стороне сервера."
    echo "               Работает только если статус сервера ${SYNC_STATUS_PAUSE}. "
    echo "               Работает как ${SYNC_STATUS_UP_INIT} только НЕ изменяет статус синхронизации для клиентов."
    echo "    ${SYNC_STATUS_UNPAUSE} -- Обмен данными не происходит. "
    echo "               Для всех хостов устанавливается статус ${SYNC_STATUS_DL_INIT} "
    echo ""
    echo "    ${APP_NAME} ${SHOW_LOG} <количество_строк>"
    echo "               Показыват указанное количство строк из лог-файла. По умолчанию количечтво = ${LOG_COUNT_ROWS}"
    echo ""
    echo "Последние изменения"
    echo "${LAST_CHANGES}"
    echo ""
}



print_version()
{
    echo "Скрипт       : ${APP_NAME}"
    echo "Версия       : ${VERSION}"
    echo "Путь скрипта : \"${APP_PATH}\""
    echo "Последние изменения"
    echo "${LAST_CHANGES}"
    echo ""
}



print_log()
{
    if  [ "$#" -ge 1 ] ;
    then
        local LOG_COUNT="$1"
    else
        local LOG_COUNT="${LOG_COUNT_ROWS}"
    fi
    journalctl -p info --since today | grep "$LOG_PREFIX" | tail -n "${LOG_COUNT}"
}



if  [ "$#" -ge 1 ] && { [ "$1" = "--help" ] || [ "$1" = "-h" ] || [ "$1" = "-H" ]; } then
    print_help
    exit 0
fi



if  [ "$#" -ge 1 ] && { [ "$1" = "--version" ] || [ "$1" = "-v" ] || [ "$1" = "-V" ]; } then
    print_version
    exit 0
fi



if  [ "$#" -ge 1 ] && [ "=$1=" = "=${SHOW_LOG}=" ] ;
then
    if  [ "$#" -ge 2 ] ;
    then
        print_log "$2"
    else
        print_log
    fi
    exit 0
fi



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
USER_CMD=""

if  [ "$#" -ge 1 ];
then
    USER_CMD="$1"
    if  [ ! "=$1=" = "=${SHOW_LOG}="            ] && \
        [ ! "=$1=" = "=${SYNC_STATUS_UP}="      ] && \
        [ ! "=$1=" = "=${SYNC_STATUS_DL}="      ] && \
        [ ! "=$1=" = "=${SYNC_STATUS_REGULAR}=" ] && \
        [ ! "=$1=" = "=${SYNC_STATUS_UP_INIT}=" ] && \
        [ ! "=$1=" = "=${SYNC_STATUS_DL_INIT}=" ] && \
        [ ! "=$1=" = "=${SYNC_STATUS_PAUSE}="   ] && \
        [ ! "=$1=" = "=${SYNC_STATUS_UP_EDIT}=" ] && \
        [ ! "=$1=" = "=${SYNC_STATUS_UNPAUSE}=" ];
    then
        ERR="${LOG_PREFIX} ERROR: Пользовательская комманда ${USER_CMD} не верна."
        logger -p info "${ERR}"
        echo "${ERR}"
        exit 2;
    fi
fi



#
# Запуск синхронизации для указанной папакм.
# С предварительной проверкой наличия самой папаки, 
# и наличия в ней папки синхронизатора
#
run_one_dir()
{
    if  [ "$#" -ge 1 ];
    then
        # $1 -- папка для синхронизации
        local P="$1"
        # shellcheck disable=SC2059
        printf "[${P}/.sync/dest] -- Проверка наличия файла... "
        if [ -f "${P}/.sync/dest" ]; then
            echo "Есть."
            # shellcheck disable=SC2059
            printf "[${P}/.sync/excludes] -- Проверка наличия файла... "
            if [ -f "${P}/.sync/excludes" ]; then
                echo "Есть."
                echo "Стартуем..."
                $SYNC1 "${P}" "${USER_CMD}"
                echo "...закончили"
            else
                echo "Нет файла"
                echo "см.: sync_1.sh --help"
            fi
        else
            echo "Нет файла."
            echo "см.: sync_1.sh --help"
        fi
    else
        local ERR="[run_one_dir()] Не указана папка синхронизации"
        echo "$ERR"
        logger -p info "${LOG_PREFIX} $ERR"
        exit 1;
    fi
}



#
# Предварительная информация перед запуском синхронизации 
# для визуального разделения результатов команд синхронизации.
# Информационный баннер перез запуском синхронизации
#
run_banner()
{
    if  [ "$#" -ge 1 ];
    then
        # $1 -- Папка синхронизации
        local FOLDER=$1
        # $2 -- Строка-баннер для красивого отображени на экране
        local BANNER=$2

        printf "\n\n\n\n"

        if [ "#$BANNER#" == "##" ]; then
            local BANNER="${FOLDER}"
        fi
        echo   "${BANNER}"
        figlet -k "${BANNER}" -f "big"
        run_one_dir "${FOLDER}"
    else
        local ERR="[run_banner()] Не указана папка синхронизации"
        echo "$ERR"
        logger -p info "${LOG_PREFIX} $ERR"
        exit 1;
    fi
}



logger -p info "${LOG_PREFIX} BEG: $(date)"
logger -p info "${LOG_PREFIX} VER: ${VERSION}"
if  [ "$#" -ge 1 ]; then
logger -p info "${LOG_PREFIX} CMD: $0 $1 $2 $3 $4 $5 $6 $7 $8 $9"
fi

echo "${APP_NAME} VERSION ${VERSION}"



##  ==================================================
##                                                   =
##  Собственно, тут перебор синхронизируемых папок   =
##                                                   =

while read -r line_raw; 
do
    # Проверяем, есть ли комментарий в строке
    if ! [[ $line_raw == *"#"* ]]; then
        # Если комментария нет, то
        # Используем eval для обработки кавычек
        eval "set -- $line_raw"
        if [ "$#" -ge 1 ]; then
            # Если параметр есть, то запускаем
            run_banner "$1" "$2"
        fi
    fi
done < ${SYNC_ALL_LIST_FILE}

##                                                   =
##  конец списка синхронизации                       =
##                                                   =
##  ==================================================



echo "===================="
echo "Все выполнено. Окно можно закрыть."
echo "Автоматическое закрытие через [${WAIT_END}] сек."
logger -p info "${LOG_PREFIX} END: $(date)"
echo "===================="
sleep ${WAIT_END}

