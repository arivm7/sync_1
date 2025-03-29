#!/bin/sh



VERSION="1.2.3 (2025-03-25)"

APP_NAME=$(basename "$0")

SYNC_FOLDER=".sync"                        # папка параметров синхронизации
SYNC_EXCLUDES="${SYNC_FOLDER}/excludes"    # Файл исключений для rsync
SYNC_DEST_FILE="${SYNC_FOLDER}/dest"       # файл, в котором записан адрес удаленного каталога
MY_NAME=$(hostname)
LOG_FILE="${SYNC_FOLDER}/log_sync"
TEMP="${SYNC_FOLDER}/tmp"



#
# Список команд
#
SYNC_STATUS_REGULAR="REGULAR"
SYNC_STATUS_UP="UP"
SYNC_STATUS_DL="DL"
SYNC_STATUS_UP_INIT="UP_INIT"
SYNC_STATUS_DL_INIT="DL_INIT"
SYNC_STATUS_PAUSE="PAUSE"
SYNC_STATUS_UP_EDIT="UP_EDIT"
SYNC_STATUS_UNPAUSE="UNPAUSE"



#
# папка синхронизации
#
SYNC_LOCAL="$1"

#
# Команда синхронизации
#
CMD="$2"


# типы обращения к серверу. 
# По разному копируют файлы
SYNC_TYPE_SERVICE="SYNC_SERVICE"    # для копирования служебных данных
SYNC_TYPE_DATA="SYNC_DATA"          # для копирования пользовательских данных



LINE__TOP="╔═══════════════════════════════════════════════════════════════════════════════╗"
LINE_FREE="║%79s║\n"
MSG_TO_UP="║                          Отправка на сервер...⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ║"
MSG__DIV_="╟╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╢"
MSG_TO_DN="║                          Загрузка с сервера...⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ║"
LINE_DOWN="╚═══════════════════════════════════════════════════════════════════════════════╝"



#
# Проверка, если первым аргументом указана не папка а команда,
# то папка берётся текущая
# или ищется выше по дереву каталогов
#
if      [ "=$1=" = "=${SYNC_STATUS_REGULAR}=" ] \
     || [ "=$1=" = "=${SYNC_STATUS_UP}=" ] \
     || [ "=$1=" = "=${SYNC_STATUS_DL}=" ] \
     || [ "=$1=" = "=${SYNC_STATUS_UP_INIT}=" ] \
     || [ "=$1=" = "=${SYNC_STATUS_DL_INIT}=" ] \
     || [ "=$1=" = "=${SYNC_STATUS_PAUSE}=" ] \
     || [ "=$1=" = "=${SYNC_STATUS_UP_EDIT}=" ] \
     || [ "=$1=" = "=${SYNC_STATUS_UNPAUSE}=" ]; then


    CMD="$1"
    echo   ${LINE__TOP}
    echo   ${LINE_FREE}
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
                echo   ${LINE_FREE}
                echo   ${LINE_DOWN}
                exit 1
            else
                printf "║ Переходим выше %-62s ║\n" " "
                cd ..
            fi
        fi
    done
    echo   ${LINE_FREE}
    echo   ${MSG__DIV_}
    echo   ${LINE_FREE}
    printf "║ Папка синхронизации     : %-51s ║\n" "${SYNC_LOCAL}"
    printf "║ Параметры синхронизации : %-51s ║\n" "${SYNC_FOLDER}"
    printf "║ Команда пользователя    : %-51s ║\n" "${CMD}"
    echo   ${LINE_FREE}
    echo   ${LINE_DOWN}
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
    echo "Скрипт синхронизации папки с копией на сервере | Версия ${VERSION}"
    # shellcheck disable=SC2028
    echo "Использование:\n\
    ${APP_NAME} <локальная_папка> [${SYNC_STATUS_REGULAR}|${SYNC_STATUS_UP}|${SYNC_STATUS_DL}|${SYNC_STATUS_UP_INIT}|${SYNC_STATUS_DL_INIT}|${SYNC_STATUS_PAUSE}|${SYNC_STATUS_UP_EDIT}|${SYNC_STATUS_UNPAUSE}] \n\
    \n\
    ${SYNC_STATUS_REGULAR} -- действие по умолчанию. \n\
               Запись данных на сервер (${SYNC_STATUS_UP}) и скачивание данных с сервера (${SYNC_STATUS_DL}) \n\
               без удаления расхождений.\n\
    ${SYNC_STATUS_UP}      -- Запись данных на сервер без удаления.\n\
    ${SYNC_STATUS_DL}      -- Чтение данных с сервера без удаления.\n\
    ${SYNC_STATUS_DL_INIT} -- Загрузка данных с сервера на локальный хост \n\
               с удалением расхождений на локальном хосте.\n\
    $SYNC_STATUS_UP_INIT -- Запись данных с локального хоста на сервер \n\
               с удалением расхождений на сервере, и установка для всех хостов \n\
               статуса ${SYNC_STATUS_DL_INIT} для обязательной загрузки изменений.\n\
    ${SYNC_STATUS_PAUSE}   -- Обмен данными не происходит. \n\
               Режим для изменений данных на самом сервере. \n\
               Никаая комманда с серера ничего не скачивает. \n\
               Для изменения файлов на сервере в этом режиме используется комманда ${SYNC_STATUS_UP_EDIT}. \n\
    ${SYNC_STATUS_UP_EDIT} -- Отправляет данные на сервер с удалением расхождений на стороне сервера.\n\
               Работает только если статус сервера ${SYNC_STATUS_PAUSE}. \n\
               Работает как ${SYNC_STATUS_UP_INIT} только НЕ изменяет статус синхронизации для клиентов.\n\
    ${SYNC_STATUS_UNPAUSE} -- Обмен данными не происходит. \n\
               Для всех хостов устанавливается статус ${SYNC_STATUS_DL_INIT} \n\
    "
}



#
# Использование:
# dl <LOCAL> <DEST> <LOG> <TYPE_TRANSFER>
#    LOCAL -- Путь папки-источника
#    DEST -- Путь папки-назначения
#    LOG -- адрес лог-файла
#    TYPE_TRANSFER -- тип копирования ${SYNC_TYPE_SERVICE} | ${SYNC_TYPE_DATA}
#       ${SYNC_TYPE_SERVICE} -- для копирования служебных данных (без исключений)
#       ${SYNC_TYPE_DATA} -- для копирования пользовательских данных (с исключениями)
#
dl()
{
    LOCAL="$1"
    DEST="$2"
    LOG="$3"
    TYPE_TRANSFER="$4"

    {
        echo "|---"
        echo "|--- $LOCAL -> $DEST"
        echo "|---"
    } >> "$LOG"

    if [ "${TYPE_TRANSFER}" = "${SYNC_TYPE_SERVICE}" ]; then
        echo "Сервисное копирование"
        EXEC=${CMD_TRANSFER_SERV}
    else
        echo "Копирование данных"
        EXEC=${CMD_TRANSFER_DATA}
    fi
    # echo "[$EXEC --rsh='ssh -p 21235' \"$LOCAL\" \"$DEST\"]"
    $EXEC --rsh='ssh -p 21235' "$LOCAL" "$DEST"
    echo "|-END-" >> "$LOG"
}



#
# Копирование пользовательский данных (с учетом исключений) в папку назначения 
# с удалением расхождений в папке назначения
#
dl_init()
{
    LOCAL="$1"
    DEST="$2"
    LOG="$3"

    {
        echo "|---"
        echo "|--- $LOCAL -->> $DEST"
        echo "|---"
    } >> "$LOG"

    ${CMD_TRANSFER_DATA} \
        --delete \
        --log-file="$LOG" \
        --rsh='ssh -p 21235' \
        "$LOCAL" \
        "$DEST"
        
    echo "|-END-" >>"$LOG"
}



##
## usage:
## sync_regular LOCAL DEST LOG_FILE
## Копирование данных на удаленный сервер без удаления
## Копирование данных с удаленного хоста на локальный без удаления
##
sync_regular()
{
    LOCAL="$1"
    DEST="$2"
    LOG="$3"
    echo   "$MSG_TO_UP"
    dl "$LOCAL" "$DEST"  "$LOG" "${SYNC_TYPE_DATA}"
    echo   "${MSG__DIV_}"
    echo   "${MSG_TO_DN}"
    dl "$DEST"  "$LOCAL" "$LOG" "${SYNC_TYPE_DATA}"
}



#
# В локальной папке создает папку .sync
# и в ней создаст файл имени этого хоста .sync/USER_<hostname>
# для последующей регистрации на удаленном хосте
#
init_local()
{
    STATUS="$1"
    echo "INIT_LOCAL: Создание файла ${SYNC_LOCAL}/${SYNC_FOLDER}/USER_${MY_NAME}"
    echo "${STATUS}"  > "${SYNC_LOCAL}/${SYNC_FOLDER}/USER_${MY_NAME}"
}



#
# Создание папки DEST/.sync
# В папку DEST/.sync записывается имя этого компьютера в виде USER_<hostname>
#
init_dest()
{
    echo "INIT_DEST: Запись имени компьютера в ${SYNC_DEST}/${SYNC_FOLDER}/USER_${MY_NAME}"
    mkdir "${SYNC_LOCAL}/${TEMP}/${SYNC_FOLDER}"
    dl    "${SYNC_LOCAL}/${TEMP}/${SYNC_FOLDER}"         "${SYNC_DEST}/"                               "${SYNC_LOCAL}/${LOG_FILE}" "${SYNC_TYPE_SERVICE}"
    rmdir "${SYNC_LOCAL}/${TEMP}/${SYNC_FOLDER}"
    dl    "${SYNC_LOCAL}/${SYNC_FOLDER}/USER_${MY_NAME}" "${SYNC_DEST}/${SYNC_FOLDER}/USER_${MY_NAME}" "${SYNC_LOCAL}/${LOG_FILE}" "${SYNC_TYPE_SERVICE}"
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
            exit 10
        fi
    else
        printf "Папка SYNC_LOCAL [%s] не установлена.\n\n" \
             "Это критическая ошибка." "${SYNC_LOCAL}"
        exit 10
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
    echo "${STATUS}" > "${SYNC_LOCAL}/${SYNC_FOLDER}/USER_${MY_NAME}"
    touch "${SYNC_LOCAL}/${SYNC_FOLDER}/USER_${MY_NAME}"
    dl "${SYNC_LOCAL}/${SYNC_FOLDER}/USER_${MY_NAME}" "${SYNC_DEST}/${SYNC_FOLDER}/USER_${MY_NAME}" "${SYNC_LOCAL}/${LOG_FILE}" "${SYNC_TYPE_SERVICE}"
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
    dl "${SYNC_DEST}/${SYNC_FOLDER}/USER_*"  "${SYNC_LOCAL}/${TEMP}/" "${SYNC_LOCAL}/${LOG_FILE}" "${SYNC_TYPE_SERVICE}"
    # ls -1 "${SYNC_LOCAL}/${TEMP}/"
    # echo "----"
    # shellcheck disable=SC2045
    for F in $(ls -1 "${SYNC_LOCAL}/${TEMP}/" 2>/dev/null); do
        if [ "$F" = "USER_${MY_NAME}" ]; then
            STATUS="${STATUS_MY}"
        else
            STATUS="${STATUS_ALL}"
        fi
        echo "$F set status to ${STATUS}"
        echo "${STATUS}" > "${SYNC_LOCAL}/${TEMP}/$F"
        # echo "[dl \"${SYNC_LOCAL}/${TEMP}/$F\" \"${SYNC_DEST}/${SYNC_FOLDER}/$F\" \"${SYNC_LOCAL}/${LOG_FILE}\" \"${SYNC_TYPE_SERVICE}\"]"
        dl "${SYNC_LOCAL}/${TEMP}/$F" "${SYNC_DEST}/${SYNC_FOLDER}/$F" "${SYNC_LOCAL}/${LOG_FILE}" "${SYNC_TYPE_SERVICE}"
    done
    # dl "${SYNC_LOCAL}/${TEMP}/USER_*" "${SYNC_DEST}/${SYNC_FOLDER}/" "${SYNC_LOCAL}/${LOG_FILE}" "${SYNC_TYPE_SERVICE}"
    init_temp
}



#
# sync_lib.sh END
# # ================================================================================
#



if [ "=$1=" = "==" ] || [ "$1" = "--help" ] || [ "$2" = "--help" ] || [ "$1" = "-h" ] || [ "$2" = "-h" ] || [ "$1" = "-H" ] || [ "$2" = "-H" ]; then

    sync_help
    exit 0

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
    printf "║      ОЩИБКА: Нет файла [ %-10s ],                                        ║\n" "${SYNC_DEST_FILE}"
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
printf "║ LOG:      │ %-64s  ║\n" "${LOG_FILE}"
printf "║ EXCLUDES: │ %-64s  ║\n" "${SYNC_EXCLUDES}"
printf "║ TEMP:     │ %-64s  ║\n" "${TEMP}"
echo   "╚═══════════╧═══════════════════════════════════════════════════════════════════╝"



#  INIT START
if [ ! -f "${SYNC_LOCAL}/${SYNC_FOLDER}/USER_${MY_NAME}" ]; then

    echo "Файла ${SYNC_LOCAL}/${SYNC_FOLDER}/USER_${MY_NAME} нет"
    init_local "${SYNC_STATUS_DL_INIT}"
    init_dest

fi
#  /INIT START END



echo "Считывание статуса синхронизации"
init_temp
dl  "${SYNC_DEST}/${SYNC_FOLDER}/USER_${MY_NAME}" \
    "${SYNC_LOCAL}/${TEMP}/" \
    "${SYNC_LOCAL}/${LOG_FILE}" \
    "${SYNC_TYPE_SERVICE}"

if [ ! -f "${SYNC_LOCAL}/${TEMP}/USER_${MY_NAME}" ]; then

    echo "Файла ${SYNC_LOCAL}/${TEMP}/USER_${MY_NAME} нет"
    echo "Предположительно его нет на удаленном хосте"
    echo "Регистрируем компьютер на удаленном хосте"
    init_local "${SYNC_STATUS_DL_INIT}"
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
    cat "${SYNC_LOCAL}/${TEMP}/USER_${MY_NAME}"
    echo "----------------------------"
    SYNC_STATUS=$(cat "${SYNC_LOCAL}/${TEMP}/USER_${MY_NAME}")
    if [ -f "${SYNC_LOCAL}/${TEMP}/USER_${MY_NAME}" ]; then
        rm "${SYNC_LOCAL}/${TEMP}/USER_${MY_NAME}"
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

if [ "${CMD}" = "${SYNC_STATUS_DL}" ]; then

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
        dl "${SYNC_DEST}/" "${SYNC_LOCAL}/" "${SYNC_LOCAL}/${LOG_FILE}"
        echo   "╚═══════════════════════════════════════════════════════════════════════════════╝"


elif [ "${CMD}" = "${SYNC_STATUS_UP}" ]; then

    if [ "${SYNC_STATUS}" = "${SYNC_STATUS_REGULAR}" ]; then

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
        dl "${SYNC_LOCAL}/" "${SYNC_DEST}/" "${SYNC_LOCAL}/${LOG_FILE}"
        echo   "╚═══════════════════════════════════════════════════════════════════════════════╝"

    else

        echo   "║                                                                               ║"
        echo   "║                 Отправка данных разрешена только                              ║"
        printf "║                 со статусом %-10s                                        ║\n" ${SYNC_STATUS_REGULAR}
        echo   "║                                                                               ║"
        echo   "║                 ДЕЙСТВИЙ НЕТ                                                  ║"
        echo   "║                                                                               ║"
        echo   "╚═══════════════════════════════════════════════════════════════════════════════╝"

    fi

elif [ "${CMD}" = "${SYNC_STATUS_DL_INIT}" ]; then

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
        dl_init "${SYNC_DEST}/" "${SYNC_LOCAL}/" "${SYNC_LOCAL}/${LOG_FILE}"
        echo   "╚═══════════════════════════════════════════════════════════════════════════════╝"


elif [ "${CMD}" = "${SYNC_STATUS_UP_INIT}" ]; then
    if [ "${SYNC_STATUS}" = "${SYNC_STATUS_REGULAR}" ]; then

        echo   "║                                                                               ║"
        echo   "║                 Отправка данных на сервер С УДАЛЕНИЕМ                         ║"
        echo   "║                                                                               ║"
        printf "║                 Для ВСЕХ хостов установка статуса сервера %-10s          ║\n" ${SYNC_STATUS_DL_INIT}
        printf "║                 Для ЭТОГО хоста установка статуса сервера %-10s          ║\n" ${SYNC_STATUS_REGULAR}
        echo   "║                                                                               ║"
        echo   "╚═══════════════════════════════════════════════════════════════════════════════╝"
        printf "╔═════════════════%s════════════════════════════════╗\n" "${TITLE}"
        echo   "║                                                                               ║"
        echo   "║                 ПЕРЕДАЧА ДАННЫХ                                               ║"
        echo   "║                                                                               ║"
        echo   "${MSG__DIV_}"
        echo   "${MSG_TO_UP}"
        dl_init   "${SYNC_LOCAL}/" "${SYNC_DEST}/" "${SYNC_LOCAL}/${LOG_FILE}"
        echo   "╚═══════════════════════════════════════════════════════════════════════════════╝"
        set_status_all "${SYNC_STATUS_DL_INIT}" "${SYNC_STATUS_REGULAR}"

    else

        echo   "║                                                                               ║"
        echo   "║                 Отправка данных С УДАЛЕНИЕМ разрешена только                  ║"
        printf "║                 со статусом %-10s                                        ║\n" ${SYNC_STATUS_REGULAR}
        echo   "║                                                                               ║"
        echo   "║                 ДЕЙСТВИЙ НЕТ                                                  ║"
        echo   "║                                                                               ║"
        echo   "╚═══════════════════════════════════════════════════════════════════════════════╝"

    fi


elif [ "${CMD}" = "${SYNC_STATUS_UP_EDIT}" ]; then
    if [ "${SYNC_STATUS}" = "${SYNC_STATUS_PAUSE}" ]; then

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
        dl_init   "${SYNC_LOCAL}/" "${SYNC_DEST}/" "${SYNC_LOCAL}/${LOG_FILE}"
        echo   "${MSG__DIV_}"
        printf "║                 Статус хостов НЕ МЕНЯЕТСЯ                                     ║\n"
        echo   "╚═══════════════════════════════════════════════════════════════════════════════╝"

    else

        echo   "║                                                                               ║"
        echo   "║                 Отправка данных С УДАЛЕНИЕМ разрешена только                  ║"
        printf "║                 со статусом %-10s                                        ║\n" ${SYNC_STATUS_PAUSE}
        echo   "║                                                                               ║"
        echo   "║                 ДЕЙСТВИЙ НЕТ                                                  ║"
        echo   "║                                                                               ║"
        echo   "╚═══════════════════════════════════════════════════════════════════════════════╝"

    fi


elif [ "${CMD}" = "${SYNC_STATUS_REGULAR}" ] || [ "${CMD}" = "" ]; then
    if [ "${SYNC_STATUS}" = "${SYNC_STATUS_DL_INIT}" ]; then

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
        dl_init "${SYNC_DEST}/" "${SYNC_LOCAL}/" "${SYNC_LOCAL}/${LOG_FILE}"
        echo   "╚═══════════════════════════════════════════════════════════════════════════════╝"
        set_status_my "${SYNC_STATUS_REGULAR}"

    elif [ "${SYNC_STATUS}" = "${SYNC_STATUS_PAUSE}" ]; then

        printf "╔═════════════════%s════════════════════════════════╗\n" "${TITLE}"
        echo   "║                                                                               ║"
        echo   "║                  СТАТУС СЕРВЕРА: [ПАУЗА]. Ничего не делаем.                   ║"
        echo   "║                                                                               ║"
        echo   "╚═══════════════════════════════════════════════════════════════════════════════╝"
        
    elif [ "${SYNC_STATUS}" = "${SYNC_STATUS_REGULAR}" ]; then

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
        sync_regular "${SYNC_LOCAL}/" "${SYNC_DEST}/" "${SYNC_LOCAL}/${LOG_FILE}"
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

elif [ "${CMD}" = "${SYNC_STATUS_PAUSE}" ]; then

        echo   "║                                                                               ║"
        echo   "║               Постановка на ПАУЗУ                                             ║"
        echo   "║               для ручных работ на сервере.                                    ║"
        echo   "║               Автоматическая синхронизация для всех хостов ОТКЛЮЧЕНА          ║"
        printf "║               Для снятия с паузы выполните с командой %-10s             ║\n" "${SYNC_STATUS_UNPAUSE}"
        echo   "║                                                                               ║"
        echo   "╚═══════════════════════════════════════════════════════════════════════════════╝"
        set_status_all "${SYNC_STATUS_PAUSE}"

elif [ "${CMD}" = "${SYNC_STATUS_UNPAUSE}" ]; then

        echo   "║                                                                               ║"
        echo   "║               Снятие с ПАУЗЫ                                                  ║"
        echo   "║               (по завершению работ на сервере).                               ║"
        echo   "║               Автоматическая синхронизация для всех хостов                    ║"
        printf "║               установлена в режим %-10s -- обязательная загрузка         ║\n" "${SYNC_STATUS_DL_INIT}"
        echo   "║                                                                               ║"
        echo   "╚═══════════════════════════════════════════════════════════════════════════════╝"
        set_status_all "${SYNC_STATUS_DL_INIT}"

else

    echo    "Не известная команда пользователя ${CMD}. см $0 --help"
    sync_help
    exit 1

fi

