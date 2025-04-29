#!/bin/sh



VERSION="1.3.1-beta (2025-04-22)"
LAST_CHANGES="\
v1.3.1 2025-04-22: Дабавлено дефолтное наполнние файла excludes при автосоздании репозитория командой CLOUD_UP_INIT
v1.3.0 2025-04-21: Дабавлена Комманда автоматического создания удалённого репозитория командой CLOUD_UP_INIT
"

APP_NAME=$(basename "$0")
APP_PATH=$(dirname "$0")

SYNC_FOLDER=".sync"                        # папка параметров синхронизации
SYNC_EXCLUDES="${SYNC_FOLDER}/excludes"    # Файл исключений для rsync
SYNC_DEST_FILE="${SYNC_FOLDER}/dest"       # файл, в котором записан адрес удаленного каталога
TEMP="${SYNC_FOLDER}/tmp"

LOG_FILE="${SYNC_FOLDER}/log_sync"         # Используется только для логирования того, что делает rsync
LOG_PREFIX="SYNC_1: "                      # Используется для префикса в системном логе

USER_PREFIX="USER_"
MY_NAME="${USER_PREFIX}$(hostname)"        # Имя этого хоста вида USER_<hostname>

SYNC_ALL_LIST_FILE="sync_all.list"

# Начальный список файла excludes для исключений rsync
EXCLUDES="\
*.kate-swp
*.swp
.git
_.git
.Trash*
.idea
.sync/*
.~lock.*
venv
venv/*
__pycache__
"



#
# Список команд
#
SYNC_CMD_REGULAR="REGULAR"
SYNC_CMD_UP="UP"
SYNC_CMD_DL="DL"
SYNC_CMD_UP_INIT="UP_INIT"
SYNC_CMD_DL_INIT="DL_INIT"
SYNC_CMD_PAUSE="PAUSE"
SYNC_CMD_UP_EDIT="UP_EDIT"
SYNC_CMD_UNPAUSE="UNPAUSE"
SYNC_CMD_CLOUD_UP_INIT="CLOUD_UP_INIT" # Создаёт sync-репозиторий из текущей папки. 
SYNC_CMD_CLOUD_DL_INIT="CLOUD_DL_INIT" # Загружает sync-репозиторий с сервера в текущую папку. Близко к DL_INIT

# типы обращения к серверу. 
# По разному копируют файлы
SYNC_TYPE_SERVICE="SYNC_SERVICE"    # для копирования служебных данных
SYNC_TYPE_DATA="SYNC_DATA"          # для копирования пользовательских данных

#
# папка синхронизации
#
SYNC_LOCAL="$1"

#
# Команда синхронизации
#
CMD="$2"



LINE_TOP_="╔═══════════════════════════════════════════════════════════════════════════════╗"
LINE_FREE="║                                                                               ║"
MSG_TO_UP="║                          Отправка на сервер...⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ║"
MSG__DIV_="╟╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╢"
MSG_TO_DN="║                          Загрузка с сервера...⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ║"
LINE_BOT_="╚═══════════════════════════════════════════════════════════════════════════════╝"



#
# Проверка, если первым аргументом указана не папка а команда,
# то папка берётся текущая
# или ищется выше по дереву каталогов
#
if      [ "=$1=" = "=${SYNC_CMD_REGULAR}=" ] \
     || [ "=$1=" = "=${SYNC_CMD_UP}=" ] \
     || [ "=$1=" = "=${SYNC_CMD_DL}=" ] \
     || [ "=$1=" = "=${SYNC_CMD_UP_INIT}=" ] \
     || [ "=$1=" = "=${SYNC_CMD_DL_INIT}=" ] \
     || [ "=$1=" = "=${SYNC_CMD_PAUSE}=" ] \
     || [ "=$1=" = "=${SYNC_CMD_UP_EDIT}=" ] \
     || [ "=$1=" = "=${SYNC_CMD_UNPAUSE}=" ]; then


    CMD="$1"
    echo   "${LINE_TOP_}"
    echo   "${LINE_FREE}"
    printf "║ Команда для текущей папки : %-49s ║\n" "${CMD}"

    ok=0
    while [ $ok -eq 0 ]
    do
        P=$(pwd)
        printf "║ Текущая папка: %-62s ║\n" "[${P}]"
        if [ -d "${SYNC_FOLDER}" ]; then
            printf "║ Папка %-78s ║\n" "[${SYNC_FOLDER}] найдена."
            SYNC_LOCAL="$P"
            ok=1
        else
            printf "║ %-85s ║\n" "Папки [${SYNC_FOLDER}] нет."
            if [ "$P" = "/" ]; then
                echo   "║ Корневая папка. Папка ${SYNC_FOLDER} не найдена."
                echo   "║ Синхронизация не возможна."
                echo   "║ Прекращение работы."
                echo   "${LINE_FREE}"
                echo   "${LINE_BOT_}"
                exit 1
            else
                printf "║ Переходим выше %-62s ║\n" " "
                cd ..
            fi
        fi
    done
    echo   "${LINE_FREE}"
    echo   "${MSG__DIV_}"
    echo   "${LINE_FREE}"
    printf "║ Папка синхронизации     : %-51s ║\n" "${SYNC_LOCAL}"
    printf "║ Параметры синхронизации : %-51s ║\n" "${SYNC_FOLDER}"
    printf "║ Команда пользователя    : %-51s ║\n" "${CMD}"
    echo   "${LINE_FREE}"
    echo   "${LINE_BOT_}"
fi



#
# Проверка, если первым аргументом указан SYNC_CMD_CLOUD_*,
# то ...
#
if  [ "=$1=" = "=${SYNC_CMD_CLOUD_UP_INIT}=" ]; then


    if [ "=$3=" = "==" ]; then
        echo "Не указан удалённый (облачный) путь для сохранения локальной папаки"
        echo "см ${APP_NAME} --help"
        echo ""
        exit 2; # 2 — Неправильный синтаксис. Обычно возникает, когда команда была вызвана с неправильными аргументами.
    fi

    if [ "=$2=" = "==" ]; then
        echo "Не указана локальная папака для сохранения на сервере"
        echo "см ${APP_NAME} --help"
        echo ""
        exit 2; # 2 — Неправильный синтаксис. Обычно возникает, когда команда была вызвана с неправильными аргументами.
    fi

    SYNC_LOCAL="$2"

    if [ -d "${SYNC_LOCAL}/${SYNC_FOLDER}" ]; then
        echo "Папка синхронизатора [${SYNC_LOCAL}/${SYNC_FOLDER}] -- есть."
        echo "Ничего не делаем."
        exit 0;
    fi
fi



# CMD_TRANSFER_SERV="rsync -e='ssh -p 21235' -azhtpErul --progress"
CMD_TRANSFER_SERV="rsync \
        -c -htprl --inplace -W"

CMD_TRANSFER_DATA="rsync \
        --log-file=${SYNC_LOCAL}/${LOG_FILE} \
        --include=${SYNC_EXCLUDES} \
        --include=${SYNC_DEST_FILE} \
        --exclude-from=${SYNC_LOCAL}/${SYNC_EXCLUDES} \
        -azhtpErl --progress -u \
        --exclude=${SYNC_FOLDER}/* \
        --exclude=${LOG_FILE}"



sync_help()
{
    echo "Скрипт индивидуальной синхронизации"
    echo "Версия ${VERSION} | Host ${MY_NAME}"
    echo ""
    # shellcheck disable=SC2059
    printf "Использование:\n\
    ${APP_NAME} [<локальная_папка>] [${SYNC_CMD_REGULAR}|${SYNC_CMD_UP}|${SYNC_CMD_DL}|${SYNC_CMD_UP_INIT}|${SYNC_CMD_DL_INIT}|${SYNC_CMD_PAUSE}|${SYNC_CMD_UP_EDIT}|${SYNC_CMD_UNPAUSE}] \n\
    \n\
    ${SYNC_CMD_REGULAR} -- действие по умолчанию. \n\
               Запись данных на сервер (${SYNC_CMD_UP}) и скачивание данных с сервера (${SYNC_CMD_DL}) \n\
               без удаления расхождений.\n\
    ${SYNC_CMD_UP}      -- Запись данных на сервер без удаления.\n\
    ${SYNC_CMD_DL}      -- Чтение данных с сервера без удаления.\n\
    ${SYNC_CMD_DL_INIT} -- Загрузка данных с сервера на локальный хост \n\
               с удалением расхождений на локальном хосте.\n\
    $SYNC_CMD_UP_INIT -- Запись данных с локального хоста на сервер \n\
               с удалением расхождений на сервере, и установка для всех хостов \n\
               статуса ${SYNC_CMD_DL_INIT} для обязательной загрузки изменений.\n\
    ${SYNC_CMD_PAUSE}   -- Обмен данными не происходит. \n\
               Режим для изменений данных на сервере. Никакая комманда с серера ничего не скачивает. \n\
               Для изменения файлов на сервере в этом режиме используется комманда ${SYNC_CMD_UP_EDIT}. \n\
    ${SYNC_CMD_UP_EDIT} -- Отправляет данные на сервер с удалением расхождений на стороне сервера.\n\
               Работает только если статус сервера ${SYNC_CMD_PAUSE}. \n\
               Работает как ${SYNC_CMD_UP_INIT} только НЕ изменяет статус синхронизации для клиентов.\n\
    ${SYNC_CMD_UNPAUSE} -- Обмен данными не происходит. \n\
               Для всех хостов устанавливается статус ${SYNC_CMD_DL_INIT} \n\n\

    ${APP_NAME} ${SYNC_CMD_CLOUD_UP_INIT} <локальная_папка> <удалённая_папка> \n\
               -- Создаёт sync-репозиторий из указанной папки.\n\
               <локальная_папка> -- полный или относительный путь к папке, или \".\"\n\
               <удалённая_папка> -- папка на сервере, которая будет облачным хранилищем\n\
               Обычно вида \"user@host/путь/папка\" (без \"/\" в конце)\n\
               Действия:
               1. Создаёт в <локальной_папке> папку ${SYNC_FOLDER}\n\
                  Создаёт файл ${SYNC_EXCLUDES} (Файл исключений для rsync)\n\
                  Создаёт файл ${SYNC_DEST_FILE} внутрь которого записывает облачный адрес\n\
                  Создаёт файл ${SYNC_FOLDER}/${MY_NAME} внутрь которого записывает статус ${SYNC_CMD_REGULAR}\n\
               2. Копируем <локальную_папку>/${SYNC_FOLDER} на сервер в папку <удалённая_папка>/\n\
               3. Выполняет обычную синхронизацию [${SYNC_CMD_REGULAR}] для записи данных на сервер.\n\n\

    ## Пока не реализовано
    ${APP_NAME} ${SYNC_CMD_CLOUD_DL_INIT} <локальная_папка> <удалённая_папка> \n\
               Загружает sync-репозиторий с сервера в текущую папку. \n\
               Создаёт локальную структуру папки ${SYNC_FOLDER}\n\
               и выполняет ${SYNC_CMD_DL_INIT}\n\n"
}



#
# Использование:
# dl <LOCAL> <DEST> <TYPE_TRANSFER>
#    LOCAL -- Путь папки-источника
#    DEST -- Путь папки-назначения
#    TYPE_TRANSFER -- тип копирования ${SYNC_TYPE_SERVICE} | ${SYNC_TYPE_DATA}
#       ${SYNC_TYPE_SERVICE} -- для копирования служебных данных (без исключений)
#       ${SYNC_TYPE_DATA} -- для копирования пользовательских данных (с исключениями) (по умолчанию)
#
dl()
{
    LOCAL="$1"
    DEST="$2"
    TYPE_TRANSFER="$3"

    logger -p info "${LOG_PREFIX} ACT DL START: [$LOCAL] -> [$DEST]"

    if [ "${TYPE_TRANSFER}" = "${SYNC_TYPE_SERVICE}" ]; then
        echo "Сервисное копирование"
        EXEC=${CMD_TRANSFER_SERV}
    else
        echo "Копирование данных"
        EXEC=${CMD_TRANSFER_DATA}
    fi
    # echo "[${EXEC} --rsh='ssh -p 21235' \"${LOCAL}\" \"${DEST}\"]"
    ${EXEC} --rsh='ssh -p 21235' "${LOCAL}" "${DEST}"
    logger -p info "${LOG_PREFIX} ACT DL END: [$LOCAL] -> [$DEST]"
}



#
# Копирование пользовательский данных (с учетом исключений) в папку назначения 
# с удалением расхождений в папке назначения
#
dl_init()
{
    LOCAL="$1"
    DEST="$2"

    logger -p info "${LOG_PREFIX} ACT DL_INIT START: [$LOCAL] -> [$DEST]"

    ${CMD_TRANSFER_DATA} \
        --delete \
        --log-file="${SYNC_LOCAL}/${LOG_FILE}" \
        --rsh='ssh -p 21235' \
        "$LOCAL" \
        "$DEST"
        
    logger -p info "${LOG_PREFIX} ACT DL_INIT END: [$LOCAL] -> [$DEST]"
}



##
## usage:
## sync_regular LOCAL DEST
## Копирование данных на удаленный сервер без удаления
## Копирование данных с удаленного хоста на локальный без удаления
##
sync_regular()
{
    LOCAL="$1"
    DEST="$2"
    echo   "$MSG_TO_UP"
    dl "$LOCAL" "$DEST" "${SYNC_TYPE_DATA}"
    echo   "${MSG__DIV_}"
    echo   "${MSG_TO_DN}"
    dl "$DEST"  "$LOCAL" "${SYNC_TYPE_DATA}"
}



#
# В локальной папке создает папку .sync
# и в ней создаст файл имени этого хоста .sync/USER_<hostname>
# для последующей регистрации на удаленном хосте
#
init_local()
{
    STATUS="$1"
    echo "INIT_LOCAL: Создание файла ${SYNC_LOCAL}/${SYNC_FOLDER}/${MY_NAME}"
    echo "${STATUS}"  > "${SYNC_LOCAL}/${SYNC_FOLDER}/${MY_NAME}"
}



#
# Создание папки DEST/.sync
# В папку DEST/.sync записывается имя этого компьютера в виде USER_<hostname>
#
init_dest()
{
    echo "INIT_DEST: Запись имени компьютера в ${SYNC_DEST}/${SYNC_FOLDER}/${MY_NAME}"
    mkdir "${SYNC_LOCAL}/${TEMP}/${SYNC_FOLDER}"
    dl    "${SYNC_LOCAL}/${TEMP}/${SYNC_FOLDER}"         "${SYNC_DEST}/"                     "${SYNC_TYPE_SERVICE}"
    rmdir "${SYNC_LOCAL}/${TEMP}/${SYNC_FOLDER}"
    dl    "${SYNC_LOCAL}/${SYNC_FOLDER}/${MY_NAME}" "${SYNC_DEST}/${SYNC_FOLDER}/${MY_NAME}" "${SYNC_TYPE_SERVICE}"
}



#
# Просто удаляет и создаёт папаку для временных файлов
#
init_temp()
{
    # echo "Инициализация папки временных файлов"
    if ! [ "=${SYNC_LOCAL}=" = "==" ]; then
        if ! [ "=${TEMP}=" = "==" ]; then
            # shellcheck disable=SC2115 # проверка сделана двумя строками выше
            rm -R "${SYNC_LOCAL}/${TEMP}"
            mkdir "${SYNC_LOCAL}/${TEMP}"
            # ls -R1 "${SYNC_LOCAL}/${TEMP}/"
            # echo "-END-"
        else
            printf "Папка TEMP [%s] не установлена.\n\n" \
                 "Это критическая ошибка." "${TEMP}"
            exit 1
        fi
    else
        printf "Папка SYNC_LOCAL [%s] не установлена.\n\n" \
             "Это критическая ошибка." "${SYNC_LOCAL}"
        exit 1
    fi
}



#
# Устанавливает на сервере статус синхронизации для этого хоста
# Статус синхронизации записывается внутрь файла с названием этого хоста
#
set_status_my()
{
    STATUS=$1
    echo "Установка статуса синхронизации в \"${STATUS}\""
    echo "${STATUS}" > "${SYNC_LOCAL}/${SYNC_FOLDER}/${MY_NAME}"
    touch "${SYNC_LOCAL}/${SYNC_FOLDER}/${MY_NAME}"
    dl "${SYNC_LOCAL}/${SYNC_FOLDER}/${MY_NAME}" "${SYNC_DEST}/${SYNC_FOLDER}/${MY_NAME}" "${SYNC_TYPE_SERVICE}"
    echo "-END-"
}



#
# set_status_all <STATUS_ALL> [<STATUS_MY>]
#
set_status_all()
{
    STATUS_ALL="$1"
    
    if [ "=$2=" = "==" ]; then
        STATUS_MY="$1"
    else
        STATUS_MY="$2"
    fi
    
    echo "Установка для всех статуса синхронизации в \"${STATUS_ALL}\" (\"${STATUS_MY}\")"
    init_temp
    dl "${SYNC_DEST}/${SYNC_FOLDER}/${USER_PREFIX}*"  "${SYNC_LOCAL}/${TEMP}/" "${SYNC_TYPE_SERVICE}"
    # ls -1 "${SYNC_LOCAL}/${TEMP}/"
    # echo "----"
    # shellcheck disable=SC2045
    for F in $(ls -1 "${SYNC_LOCAL}/${TEMP}/" 2>/dev/null); do
        if [ "$F" = "${MY_NAME}" ]; then
            STATUS="${STATUS_MY}"
        else
            STATUS="${STATUS_ALL}"
        fi
        echo "$F set status to ${STATUS}"
        echo "${STATUS}" > "${SYNC_LOCAL}/${TEMP}/$F"
        # echo "[dl \"${SYNC_LOCAL}/${TEMP}/$F\" \"${SYNC_DEST}/${SYNC_FOLDER}/$F\" \"${SYNC_TYPE_SERVICE}\"]"
        dl "${SYNC_LOCAL}/${TEMP}/$F" "${SYNC_DEST}/${SYNC_FOLDER}/$F" "${SYNC_TYPE_SERVICE}"
    done
    # dl "${SYNC_LOCAL}/${TEMP}/${USER_PREFIX}*" "${SYNC_DEST}/${SYNC_FOLDER}/" "${SYNC_TYPE_SERVICE}"
    init_temp
}



#
#
# sync_lib.sh END
# # ================================================================================
#
#



if [ "=$1=" = "==" ] || [ "$1" = "--help" ] || [ "$2" = "--help" ] || [ "$1" = "-h" ] || [ "$2" = "-h" ] || [ "$1" = "-H" ] || [ "$2" = "-H" ]; then

    sync_help
    exit 0

fi



if [ "=$1=" = "=-v=" ] || [ "$1" = "--version" ] || [ "$1" = "-V" ] || [ "$1" = "--VERSION" ]; then

    echo "Version: ${VERSION}"
    echo "Скрипт: ${APP_NAME}"
    echo "Папка размещения: ${APP_PATH}"
    echo ""
    echo "Последние изменения:"
    echo "${LAST_CHANGES}"
    exit 0;

fi



logger -p info "${LOG_PREFIX} BEG: $(date)"
logger -p info "${LOG_PREFIX} VER: ${VERSION}"
logger -p info "${LOG_PREFIX} CMD: $0 $1 $2 $3 $4 $5 $6 $7 $8 $9"



#
# Создание репозитория на сервере из указанной локальной папки
#
if  [ "=$1=" = "=${SYNC_CMD_CLOUD_UP_INIT}=" ]; then

    REMOTE_PATH=$(dirname "$3")
    REMOTE_FOLDER=$(basename "$3")
    SYNC_DEST="${REMOTE_PATH}/${REMOTE_FOLDER}"
    {
        PREV_DIR=$(pwd)
        cd "${SYNC_LOCAL}" || { echo "Не удалось перейти в папаку [${SYNC_LOCAL}]"; exit 1; }
        SYNC_LOCAL=$(pwd)
        LOCAL_PATH=$(dirname "${SYNC_LOCAL}")
        LOCAL_FOLDER=$(basename "${SYNC_LOCAL}")
        cd "${PREV_DIR}" || { echo "Не удалось перейти в папаку [${PREV_DIR}]"; exit 1; }
    }

    echo   "${LINE_TOP_}"
    echo   "${LINE_FREE}"
    printf "║             Комманда : %-54s ║\n" "${SYNC_CMD_CLOUD_UP_INIT}"
    printf "║      Локальная папка : %-54s ║\n" "${SYNC_LOCAL}"
    printf "║         Путь к папке : %-54s ║\n" "${LOCAL_PATH}"
    printf "║           Сама папка : %-54s ║\n" "${LOCAL_FOLDER}"
    printf "║ Облачные папки         %-54s ║\n" " "
    printf "║  Путь к папке (SYNC) : %-54s ║\n" "${REMOTE_PATH}"
    printf "║           Сама папка : %-54s ║\n" "${REMOTE_FOLDER}"
    echo   "${LINE_FREE}"
    echo   "${LINE_BOT_}"

    echo     "Создание папки синхронизатора ${SYNC_LOCAL}/${SYNC_FOLDER}"
    mkdir -p "${SYNC_LOCAL}/${SYNC_FOLDER}" || { echo "Не удалось создать папку синхронизатора [${SYNC_LOCAL}/${SYNC_FOLDER}]"; exit 1; }
    printf   "Создание файла [%s]" "${MY_NAME}"
    echo     "${SYNC_CMD_REGULAR}" > "${SYNC_LOCAL}/${SYNC_FOLDER}/${MY_NAME}"
    printf   ", [%s]" "${SYNC_DEST_FILE}"
    echo     "${REMOTE_PATH}/${REMOTE_FOLDER}" > "${SYNC_LOCAL}/${SYNC_DEST_FILE}"
    printf   ", [%s]" "${SYNC_EXCLUDES}"
    echo     "${EXCLUDES}" > "${SYNC_LOCAL}/${SYNC_EXCLUDES}"
    printf   ". Ок\n"

    echo "Создаём в папке tmp копию того, что нужно отправить на сервер"
    mkdir -p "${SYNC_LOCAL}/${TEMP}/${REMOTE_FOLDER}/${SYNC_FOLDER}" || { echo "Не удалось создать папку [${SYNC_LOCAL}/${TEMP}/${REMOTE_FOLDER}/${SYNC_FOLDER}]"; exit 1; }
    # shellcheck disable=SC2059
    printf   "Копируем [${REMOTE_FOLDER}/${SYNC_FOLDER}/${MY_NAME}]"
    cp       "${SYNC_LOCAL}/${SYNC_FOLDER}/${MY_NAME}" "${SYNC_LOCAL}/${TEMP}/${REMOTE_FOLDER}/${SYNC_FOLDER}/"
    # shellcheck disable=SC2059
    printf   ", [${REMOTE_FOLDER}/${SYNC_DEST_FILE}]"
    cp       "${SYNC_LOCAL}/${SYNC_DEST_FILE}"         "${SYNC_LOCAL}/${TEMP}/${REMOTE_FOLDER}/${SYNC_FOLDER}/"
    # shellcheck disable=SC2059
    printf   ", [${REMOTE_FOLDER}/${SYNC_EXCLUDES}]"
    cp       "${SYNC_LOCAL}/${SYNC_EXCLUDES}"          "${SYNC_LOCAL}/${TEMP}/${REMOTE_FOLDER}/${SYNC_FOLDER}/"
    printf   ". Ок\n"

    echo     "Копируем локальную временную папку [${REMOTE_FOLDER}]"
    echo     "На сервер в папаку                 [${REMOTE_PATH}]"
    dl "${SYNC_LOCAL}/${TEMP}/${REMOTE_FOLDER}" "${REMOTE_PATH}" "${SYNC_TYPE_SERVICE}"
    init_temp

    echo     "Добавляем папаку в список массовой синхронизации [${SYNC_ALL_LIST_FILE}]..."
    if [ -f "${APP_PATH}/${SYNC_ALL_LIST_FILE}" ]; then

        if ( grep -q "${SYNC_LOCAL}" "${APP_PATH}/${SYNC_ALL_LIST_FILE}" ); 
        then 
            echo "В файле [${APP_PATH}/${SYNC_ALL_LIST_FILE}] строка [${SYNC_LOCAL}] есть."; 
            echo "Ничего не делаем."; 
        else 
            echo "В файле [${APP_PATH}/${SYNC_ALL_LIST_FILE}] НЕТ строки [${SYNC_LOCAL}]."; 
            printf "Добавляем..."; 
            {
                echo ""
                echo "#"
                echo "# Добавлено $(date)"
                echo "# пользователем ${USER}"
                echo "# коммандой ${SYNC_CMD_CLOUD_UP_INIT}"
                echo "#"
                echo "\"${SYNC_LOCAL}\" \"$(basename "${SYNC_LOCAL}")\""
            }  >> "${APP_PATH}/${SYNC_ALL_LIST_FILE}"
            printf "...Ok.\n"; 
        fi
    else
        echo "Файла [${SYNC_ALL_LIST_FILE}] нет."
    fi

    echo   "${LINE_TOP_}"
    echo   "${LINE_FREE}"
         # "║                                                                               ║"
    printf "║     Проверьте, пожалуста, файл исключений для синхронизации.                  ║\n" 
    printf "║     Исправьте его для ваших потребностей.                                     ║\n" 
    printf "║     За тем, выполните комманду синхронизации для отправки данных на сервер    ║\n" 
    echo   "${LINE_FREE}"
    printf "║     Файл исключений         : [%-45s] ║\n" "${SYNC_LOCAL}/${SYNC_EXCLUDES}"
    echo   "${LINE_FREE}"
    printf "║     Выполните синхронизацию : [%-45s] ║\n" "${APP_NAME} ."
    echo   "${LINE_FREE}"
    echo   "${LINE_BOT_}"

    # echo     "Проводим обычную синхронихацию [${SYNC_CMD_REGULAR}]"
    # sync_regular "${SYNC_LOCAL}/" "${SYNC_DEST}/"

    exit 0;
fi



if [ ! -d "${SYNC_LOCAL}" ]; then

    echo "Папки нет: ${SYNC_LOCAL}"
    exit 1

fi



echo "Проверка служебной папки синхронизатора \"${SYNC_LOCAL}/${SYNC_FOLDER}\"..."
if [ -d "${SYNC_LOCAL}/${SYNC_FOLDER}" ]; then

    echo "Служебная папка синхронизатора есть"

else

    echo   "╔═══════════════════════════════════════════════════════════════════════════════╗"
    echo   "║                                                                               ║"
    echo   "║      ОЩИБКА: Служебной папки синхронизатора нет.                              ║"
    echo   "║              Возможно, вы указали не верную папку для синхронизации           ║"
    echo   "║                                                                               ║"
    printf "║      В папке для синхронизации нужно создать папку:        %-15s    ║\n" "${SYNC_FOLDER}"
    printf "║      файл, в котором записан адрес удаленного каталога:    %-15s    ║\n" "${SYNC_DEST_FILE}"
    printf "║      файл со списком шаблонов исключений из синхронизации: %-15s    ║\n" "${SYNC_EXCLUDES}"
    echo   "║                                                                               ║"
    echo   "║              ЭТО КРИТИЧЕСКАЯ ОШИБКА.                                          ║"
    echo   "║                                                                               ║"
    echo   "╚═══════════════════════════════════════════════════════════════════════════════╝"
    
    exit 1

fi

if [ -f "${SYNC_LOCAL}/${SYNC_DEST_FILE}" ]; then

    read -r SYNC_DEST <"${SYNC_LOCAL}/${SYNC_DEST_FILE}"

else

    echo   "╔═══════════════════════════════════════════════════════════════════════════════╗"
    echo   "║                                                                               ║"
    printf "║      ОЩИБКА: Нет файла %-14s,                                        ║\n" "[ ${SYNC_DEST_FILE} ]"
    echo   "║              в котором записана строка с адресом удаленного каталога          ║"
    echo   "║              Возможно, вы указали не верную папку для синхронизации           ║"
    echo   "║                                                                               ║"
    echo   "║              ЭТО КРИТИЧЕСКАЯ ОШИБКА.                                          ║"
    echo   "║                                                                               ║"
    echo   "╚═══════════════════════════════════════════════════════════════════════════════╝"
    exit 1

fi

echo   "╔═══════════╤═══════════════════════════════════════════════════════════════════╗"
printf "║ MY:       │ %-64s  ║\n" "${MY_NAME}"
printf "║ LOCAL:    │ %-64s  ║\n" "${SYNC_LOCAL}"
printf "║ DEST:     │ %-64s  ║\n" "${SYNC_DEST}"
printf "║ LOG (opt) │ %-64s  ║\n" "${LOG_FILE}"
printf "║ EXCLUDES: │ %-64s  ║\n" "${SYNC_EXCLUDES}"
printf "║ TEMP:     │ %-64s  ║\n" "${TEMP}"
echo   "╚═══════════╧═══════════════════════════════════════════════════════════════════╝"



#  INIT START
if [ ! -f "${SYNC_LOCAL}/${SYNC_FOLDER}/${MY_NAME}" ]; then

    echo "Файла ${SYNC_LOCAL}/${SYNC_FOLDER}/${MY_NAME} нет"
    init_local "${SYNC_CMD_DL_INIT}"
    init_dest

fi
#  /INIT START END



echo "Считывание статуса синхронизации"
init_temp
dl  "${SYNC_DEST}/${SYNC_FOLDER}/${MY_NAME}" \
    "${SYNC_LOCAL}/${TEMP}/" \
    "${SYNC_TYPE_SERVICE}"

if [ ! -f "${SYNC_LOCAL}/${TEMP}/${MY_NAME}" ]; then

    echo "Файла ${SYNC_LOCAL}/${TEMP}/${MY_NAME} нет"
    echo "Предположительно его нет на удаленном хосте"
    echo "Регистрируем компьютер на удаленном хосте"
    init_local "${SYNC_CMD_DL_INIT}"
    init_dest
    echo   "╔═══════════════════════════════════════════════════════════════════════════════╗"
    echo   "║                                                                               ║"
    printf "║                      Запустите синхронизацию ещё раз                          ║\n"
    echo   "║                                                                               ║"
    echo   "╚═══════════════════════════════════════════════════════════════════════════════╝"

    exit 1

    # Повторный запуск. Нужно проверять как это работает.
    # $0 $1
    # exit 1

else

    echo "Скачали файл статуса сервера"
    cat "${SYNC_LOCAL}/${TEMP}/${MY_NAME}"
    echo "----------------------------"
    SYNC_STATUS=$(cat "${SYNC_LOCAL}/${TEMP}/${MY_NAME}")
    if [ -f "${SYNC_LOCAL}/${TEMP}/${MY_NAME}" ]; then
        rm "${SYNC_LOCAL}/${TEMP}/${MY_NAME}"
    fi

fi

## ╟╌─╢

TITLE=$(printf "%-30s" "${SYNC_LOCAL}" | sed 's/ /═/g')

        printf "╔═════════════════%s════════════════════════════════╗\n" "${TITLE}"
       #printf "║                 %-30s                                ║\n" ${SYNC_LOCAL}
       #echo   "╟───────────────────────────────────────────────────────────────────────────────╢"
        echo   "║                                                                               ║"
        printf "║                 Статус сервера: %-10s                                    ║\n" "${SYNC_STATUS}"
        printf "║                 Команда хоста:  %-10s                                    ║\n" "${CMD}"
        echo   "║                                                                               ║"
        echo   "${MSG__DIV_}"

if [ "${CMD}" = "${SYNC_CMD_DL}" ]; then

        echo   "║                                                                               ║"
        echo   "║                 Загрузка данных на хост, без удаления                         ║"
        echo   "║                                                                               ║"
        echo   "╚═══════════════════════════════════════════════════════════════════════════════╝"
        printf "╔═════════════════%s════════════════════════════════╗\n" "${TITLE}"
        echo   "║                                                                               ║"
        echo   "║                 ПЕРЕДАЧА ДАННЫХ                                               ║"
        echo   "║                                                                               ║"
        echo   "${MSG__DIV_}"
        echo   "${MSG_TO_DN}"
        dl "${SYNC_DEST}/" "${SYNC_LOCAL}/"
        echo   "╚═══════════════════════════════════════════════════════════════════════════════╝"


elif [ "${CMD}" = "${SYNC_CMD_UP}" ]; then

    if [ "${SYNC_STATUS}" = "${SYNC_CMD_REGULAR}" ]; then

        echo   "║                                                                               ║"
        echo   "║                 Отправка данных на сервер без удаления                        ║"
        echo   "║                                                                               ║"
        echo   "╚═══════════════════════════════════════════════════════════════════════════════╝"
        printf "╔═════════════════%s════════════════════════════════╗\n" "${TITLE}"
        echo   "║                                                                               ║"
        echo   "║                 ПЕРЕДАЧА ДАННЫХ                                               ║"
        echo   "║                                                                               ║"
        echo   "${MSG__DIV_}"
        echo   "${MSG_TO_UP}"
        dl "${SYNC_LOCAL}/" "${SYNC_DEST}/"
        echo   "╚═══════════════════════════════════════════════════════════════════════════════╝"

    else

        echo   "║                                                                               ║"
        echo   "║                 Отправка данных разрешена только                              ║"
        printf "║                 со статусом %-10s                                        ║\n" ${SYNC_CMD_REGULAR}
        echo   "║                                                                               ║"
        echo   "║                 ДЕЙСТВИЙ НЕТ                                                  ║"
        echo   "║                                                                               ║"
        echo   "╚═══════════════════════════════════════════════════════════════════════════════╝"

    fi

elif [ "${CMD}" = "${SYNC_CMD_DL_INIT}" ]; then

        echo   "║                                                                               ║"
        echo   "║                 ЗАГРУЗКА папок с сервера на хост                              ║"
        echo   "║                 с УДАЛЕНИЕМ локальных расхождений                             ║"
        echo   "║                                                                               ║"
        echo   "╚═══════════════════════════════════════════════════════════════════════════════╝"
        printf "╔═════════════════%s════════════════════════════════╗\n" "${TITLE}"
        echo   "║                                                                               ║"
        echo   "║                 ПЕРЕДАЧА ДАННЫХ                                               ║"
        echo   "║                                                                               ║"
        echo   "${MSG__DIV_}"
        echo   "${MSG_TO_DN}"
        dl_init "${SYNC_DEST}/" "${SYNC_LOCAL}/"
        echo   "╚═══════════════════════════════════════════════════════════════════════════════╝"


elif [ "${CMD}" = "${SYNC_CMD_UP_INIT}" ]; then
    if [ "${SYNC_STATUS}" = "${SYNC_CMD_REGULAR}" ]; then

        echo   "║                                                                               ║"
        echo   "║                 Отправка данных на сервер С УДАЛЕНИЕМ                         ║"
        echo   "║                                                                               ║"
        printf "║                 Для ВСЕХ хостов установка статуса сервера %-10s          ║\n" ${SYNC_CMD_DL_INIT}
        printf "║                 Для ЭТОГО хоста установка статуса сервера %-10s          ║\n" ${SYNC_CMD_REGULAR}
        echo   "║                                                                               ║"
        echo   "╚═══════════════════════════════════════════════════════════════════════════════╝"
        printf "╔═════════════════%s════════════════════════════════╗\n" "${TITLE}"
        echo   "║                                                                               ║"
        echo   "║                 ПЕРЕДАЧА ДАННЫХ                                               ║"
        echo   "║                                                                               ║"
        echo   "${MSG__DIV_}"
        echo   "${MSG_TO_UP}"
        dl_init   "${SYNC_LOCAL}/" "${SYNC_DEST}/"
        echo   "╚═══════════════════════════════════════════════════════════════════════════════╝"
        set_status_all "${SYNC_CMD_DL_INIT}" "${SYNC_CMD_REGULAR}"

    else

        echo   "║                                                                               ║"
        echo   "║                 Отправка данных С УДАЛЕНИЕМ разрешена только                  ║"
        printf "║                 со статусом %-10s                                        ║\n" ${SYNC_CMD_REGULAR}
        echo   "║                                                                               ║"
        echo   "║                 ДЕЙСТВИЙ НЕТ                                                  ║"
        echo   "║                                                                               ║"
        echo   "╚═══════════════════════════════════════════════════════════════════════════════╝"

    fi


elif [ "${CMD}" = "${SYNC_CMD_UP_EDIT}" ]; then
    if [ "${SYNC_STATUS}" = "${SYNC_CMD_PAUSE}" ]; then

        echo   "║                                                                               ║"
        echo   "║                 Сервер в состоянии ПАУЗЫ для редактирования наполнения.       ║"
        echo   "║                 Отправка корректирующих данных на сервер С УДАЛЕНИЕМ          ║"
        echo   "║                                                                               ║"
        printf "║                 Статус хостов НЕ МЕНЯЕТСЯ                                     ║\n"
        echo   "║                                                                               ║"
        echo   "╚═══════════════════════════════════════════════════════════════════════════════╝"
        printf "╔═════════════════%s════════════════════════════════╗\n" "${TITLE}"
        echo   "║                                                                               ║"
        echo   "║                 ПЕРЕДАЧА ДАННЫХ                                               ║"
        echo   "║                                                                               ║"
        echo   "${MSG__DIV_}"
        echo   "${MSG_TO_UP}"
        dl_init   "${SYNC_LOCAL}/" "${SYNC_DEST}/"
        echo   "${MSG__DIV_}"
        printf "║                 Статус хостов НЕ МЕНЯЕТСЯ                                     ║\n"
        echo   "╚═══════════════════════════════════════════════════════════════════════════════╝"

    else

        echo   "║                                                                               ║"
        echo   "║                 Отправка данных С УДАЛЕНИЕМ разрешена только                  ║"
        printf "║                 со статусом %-10s                                        ║\n" ${SYNC_CMD_PAUSE}
        echo   "║                                                                               ║"
        echo   "║                 ДЕЙСТВИЙ НЕТ                                                  ║"
        echo   "║                                                                               ║"
        echo   "╚═══════════════════════════════════════════════════════════════════════════════╝"

    fi


elif [ "${CMD}" = "${SYNC_CMD_REGULAR}" ] || [ "${CMD}" = "" ]; then
    if [ "${SYNC_STATUS}" = "${SYNC_CMD_DL_INIT}" ]; then

        echo   "║                                                                               ║"
        echo   "║                 Выполняем требование сервера:                                 ║"
        echo   "║                              ЗАГРУЗКА папок с сервера на хост                 ║"
        echo   "║                             с УДАЛЕНИЕМ локальных расхождений                 ║"
        echo   "║                                                                               ║"
        echo   "╚═══════════════════════════════════════════════════════════════════════════════╝"
        printf "╔═════════════════%s════════════════════════════════╗\n" "${TITLE}"
        echo   "║                                                                               ║"
        echo   "║                 ПЕРЕДАЧА ДАННЫХ                                               ║"
        echo   "║                                                                               ║"
        echo   "${MSG__DIV_}"
        echo   "${MSG_TO_DN}"
        dl_init "${SYNC_DEST}/" "${SYNC_LOCAL}/"
        echo   "╚═══════════════════════════════════════════════════════════════════════════════╝"
        set_status_my "${SYNC_CMD_REGULAR}"

    elif [ "${SYNC_STATUS}" = "${SYNC_CMD_PAUSE}" ]; then

        printf "╔═════════════════%s════════════════════════════════╗\n" "${TITLE}"
        echo   "║                                                                               ║"
        echo   "║                  СТАТУС СЕРВЕРА: [ПАУЗА]. Ничего не делаем.                   ║"
        echo   "║                                                                               ║"
        echo   "╚═══════════════════════════════════════════════════════════════════════════════╝"
        
    elif [ "${SYNC_STATUS}" = "${SYNC_CMD_REGULAR}" ]; then

        echo   "║                                                                               ║"
        echo   "║                 Обычная осторожная синхронизация:                             ║"
        echo   "║                          1. Выгрузка с хоста на сервер без удаления           ║"
        echo   "║                          2. Загрузка с сервера на хост без удаления           ║"
        echo   "║                                                                               ║"
        echo   "╚═══════════════════════════════════════════════════════════════════════════════╝"
        printf "╔═════════════════%s════════════════════════════════╗\n" "${TITLE}"
        echo   "║                                                                               ║"
        echo   "║                 ПЕРЕДАЧА ДАННЫХ                                               ║"
        echo   "║                                                                               ║"
        echo   "${MSG__DIV_}"
        sync_regular "${SYNC_LOCAL}/" "${SYNC_DEST}/"
        echo   "╚═══════════════════════════════════════════════════════════════════════════════╝"

    else

        printf "╔═════════════════%s════════════════════════════════╗\n" "${TITLE}"
        echo   "║                                                                               ║"
        echo   "║                 ДОПИЛИТЬ ОБРАБОТКУ СИТУАЦИИ:                                  ║"
        echo   "║                                                                               ║"
        printf "║                 '%10s' -- '%-10s'                                  ║\n" "${CMD}" "${SYNC_STATUS}"
        echo   "║                                                                               ║"
        echo   "╚═══════════════════════════════════════════════════════════════════════════════╝"

    fi

elif [ "${CMD}" = "${SYNC_CMD_PAUSE}" ]; then

        echo   "║                                                                               ║"
        echo   "║               Постановка на ПАУЗУ                                             ║"
        echo   "║               для ручных работ на сервере.                                    ║"
        echo   "║               Автоматическая синхронизация для всех хостов ОТКЛЮЧЕНА          ║"
        printf "║               Для снятия с паузы выполните с командой %-10s             ║\n" "${SYNC_CMD_UNPAUSE}"
        echo   "║                                                                               ║"
        echo   "╚═══════════════════════════════════════════════════════════════════════════════╝"
        set_status_all "${SYNC_CMD_PAUSE}"

elif [ "${CMD}" = "${SYNC_CMD_UNPAUSE}" ]; then

        echo   "║                                                                               ║"
        echo   "║               Снятие с ПАУЗЫ                                                  ║"
        echo   "║               (по завершению работ на сервере).                               ║"
        echo   "║               Автоматическая синхронизация для всех хостов                    ║"
        printf "║               установлена в режим %-10s -- обязательная загрузка         ║\n" "${SYNC_CMD_DL_INIT}"
        echo   "║                                                                               ║"
        echo   "╚═══════════════════════════════════════════════════════════════════════════════╝"
        set_status_all "${SYNC_CMD_DL_INIT}"

else

    echo    "Не известная команда пользователя ${CMD}."
    echo    "см ${APP_NAME} --help"
    echo    ""
    sync_help
    exit 2; # 2 — Неправильный синтаксис. Обычно возникает, когда команда была вызвана с неправильными аргументами.

fi

logger -p info "${LOG_PREFIX} END: $(date)"
