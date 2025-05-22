#!/usr/bin/env bash
#set -euo pipefail



APP_TITLE="Скрипт индивидуальной синхронизации"
APP_NAME=$(basename "$0")
APP_PATH=$(dirname "$0")
VERSION="1.4.0-alfa (2025-05-22)"
LAST_CHANGES="\
v1.3.0 (2025-04-21): Добавлена команда автоматического создания удалённого репозитория командой CLOUD_UP_INIT
v1.3.1 (2025-04-22): Добавлено дефолтное наполнение файла excludes
v1.3.2 (2025-05-08): Добавлена команда LOG для показа логов работы скрипта
v1.3.3 (2025-05-17): Добавлен параметр SHOW_DEST показывает облачные пути
v1.4.0 (2025-05-22): Рефакторинг и массовые проверки.
"

DIR_SYNC=".sync"                            # папка параметров синхронизации
FILE_EXCLUDES="${DIR_SYNC}/excludes"        # Файл исключений для rsync
FILE_DEST="${DIR_SYNC}/dest"                # файл, в котором записан адрес удаленного каталога
DIR_TEMP="${DIR_SYNC}/tmp"                  # Временная папка для работы этого скрипта

LOG_PREFIX="SYNC_1: "                       # Используется для префикса в системном логе
LOG_FILE="${DIR_SYNC}/log_sync"             # Используется только для логирования того, что делает rsync
LOG_COUNT_ROWS="20"                         # Количество строк по умолчанию при просмотре логов

USER_PREFIX="USER_"                         # Префикс для формирования имени хоста
MY_NAME="${USER_PREFIX}$(hostname)"         # Имя этого хоста вида USER_<hostname>

FILE_SYNC_ALL_LIST="sync_all.list"          # Имя файла для скрипта массовой синхронизации. 
                                            # В него добавляется строка при создании репозитория.
SSH_PORT="21235"                            # Порт для доступа по протоколу ssh

# типы обращения к серверу. Они по разному копируют файлы
SYNC_TYPE_SERVICE="SYNC_SERVICE"            # для копирования служебных данных
SYNC_TYPE_DATA="SYNC_DATA"                  # для копирования пользовательских данных
COLOR_STATUS="\e[0;36m"                     # Терминальный цвет для вывода переменной статуса
COLOR_USAGE="\e[1;32m"                      # Терминальный цвет для вывода переменной статуса
COLOR_OFF="\e[0m"                           # Терминальный цвет для сброса цвета



LINE_TOP_="╔═══════════════════════════════════════════════════════════════════════════════╗"
LINE_FREE="║                                                                               ║"
MSG_TO_UP="║                          Отправка на сервер...⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ║"
MSG__DIV_="╟╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╢" 
MSG_TO_DN="║                          Загрузка с сервера...⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ║"
LINE_BOT_="╚═══════════════════════════════════════════════════════════════════════════════╝"

#
# Список поддерживаемых команд
#
# Внутренние команды
SHOW_VERSION="VERSION"
SHOW_USAGE="USAGE"
SHOW_HELP="HELP"
# Параметры командной строки
SHOW_LOG="LOG"                              # Показать логи
SHOW_DEST="SHOW_DEST"                       # Показывает dest-строку
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

DIR_LOCAL_DEFAULT="."                       # Локальная папка, назначаемая если не указана явно
CMD_DEFAULT="${SYNC_CMD_REGULAR}"           # Команда синхнронизации, если не указана явно

# Значения по умолчанию
DIR_LOCAL="$DIR_LOCAL_DEFAULT"              # Папка для синхронизации
CMD_USER="$CMD_DEFAULT"                     # Пользовательская команда синхронизации
CMD_CLOUD="${SYNC_CMD_REGULAR}"             # Серверная команда синхронизации


# Начальный список файла excludes для исключений rsync
EXCLUDES="\
*.kate-swp
*.swp
.git
.Trash*
.idea
.sync/*
.~lock.*
venv
venv/*
__pycache__
Temporary
"



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
    "${SYNC_CMD_CLOUD_UP_INIT}"
    "${SYNC_CMD_CLOUD_DL_INIT}"
    # Показывают
    "${SHOW_LOG}"
    "${SHOW_DEST}"
)



# Список команд, требующих наличия папки .sync
REQUIRING_SYNC_COMMANDS=(
    "${SYNC_CMD_REGULAR}"
    "${SYNC_CMD_UP}"
    "${SYNC_CMD_DL}"
    "${SYNC_CMD_UP_INIT}"
    "${SYNC_CMD_DL_INIT}"
    "${SYNC_CMD_PAUSE}"
    "${SYNC_CMD_UP_EDIT}"
    "${SYNC_CMD_UNPAUSE}"
    "${SHOW_DEST}"
)



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



print_version()
{
    echo "Version: ${VERSION}"
    echo "Скрипт: ${APP_NAME}"
    echo "Папка размещения: ${APP_PATH}"
    echo ""
    echo "Последние изменения:"
    echo "${LAST_CHANGES}"
}



print_help()
{
cat << EOF
${APP_TITLE}
Версия ${VERSION} | Host ${MY_NAME}
Использование:
    ${APP_NAME}  [<локальная_папка>] [ $(str=$(IFS="|"; echo "${VALID_COMMANDS[*]:0:5}"); echo "${str//|/ | }";) ]
                                   [ $(str=$(IFS="|"; echo "${VALID_COMMANDS[*]:5:5}"); echo "${str//|/ | }";) ]
                                   [ $(str=$(IFS="|"; echo "${VALID_COMMANDS[*]:10}");  echo "${str//|/ | }";) ]
                                   По умолчанию: ${SYNC_CMD_REGULAR}

    ${SYNC_CMD_REGULAR} -- действие по умолчанию.
               Запись данных на сервер (${SYNC_CMD_UP}) и скачивание данных с сервера (${SYNC_CMD_DL})
               без удаления расхождений. По сути, это двусторонее совмещение данных на сервере 
               и на локальном компьютере, с заменой старых файлов на новые по метке времени.
    ${SYNC_CMD_UP}      -- Запись данных на сервер без удаления. Переписываются старые.
    ${SYNC_CMD_DL}      -- Чтение данных с сервера без удаления. Переписываются старые.
    ${SYNC_CMD_DL_INIT} -- Загрузка данных с сервера на локальный хост 
               с полным удалением расхождений на локальном хосте.
    $SYNC_CMD_UP_INIT -- Запись данных с локального хоста на сервер 
               с полным удалением расхождений на сервере, и установка для всех хостов 
               статуса ${SYNC_CMD_DL_INIT} для обязательной загрузки изменений.
    ${SYNC_CMD_PAUSE}   -- Обмен данными не происходит. Режим используется для изменений данных 
               на сервере. Никакая команда с сервера ничего не скачивает. 
               Изменение в структуре файлов можно проводить прямо на сервере (поскольку доступ 
               по ssh у вас есть), или в локальной папке у вас на компе, после чего можно отправить 
               изменения на сервер командой ${SYNC_CMD_UP_EDIT}, которая, собственно, 
               только для этого и предназначена.
    ${SYNC_CMD_UP_EDIT} -- Отправляет данные на сервер с удалением расхождений на стороне сервера.
               Работает только если статус сервера ${SYNC_CMD_PAUSE}. 
               Работает как ${SYNC_CMD_UP_INIT} только НЕ изменяет статус синхронизации для клиентов.
    ${SYNC_CMD_UNPAUSE} -- Обмен данными не происходит.
               Для всех хостов устанавливается статус ${SYNC_CMD_DL_INIT} 

    ${SHOW_DEST} -- Показать строку "dest" (из файла "${FILE_DEST}").
               Это адрес размещения папки на облачном сервере. Обычно вида "user@host/путь/папка".
    ${SHOW_LOG} <количество_строк>
               Показыват указанное количество строк из лог-файла. По умолчанию количество = ${LOG_COUNT_ROWS}

    ${APP_NAME} ${SYNC_CMD_CLOUD_UP_INIT} <user@host/путь/удалённая_папка>
               -- Создаёт sync-репозиторий из текущей папки.
               <удалённая_папка> -- папка на сервере, которая будет облачным хранилищем
               Обычно вида "user@host/путь/папка" (без слэша "/" в конце!)
               Локальная_папка используется текущая "."
               Действия:
               1. Создаёт в <локальной_папке> папку "${DIR_SYNC}"
                  Создаёт файл "${FILE_EXCLUDES}" (Файл исключений для rsync)
                  Создаёт файл "${FILE_DEST}" внутрь которого записывает облачный адрес
                  Создаёт файл "${DIR_SYNC}/${MY_NAME}" внутрь которого записывает статус "${SYNC_CMD_REGULAR}"
               2. Копируем "<локальную_папку>/${DIR_SYNC}" на сервер в папку <удалённая_папка>/
               3. Выполняет обычную синхронизацию [${SYNC_CMD_REGULAR}] для записи данных на сервер.

Разумеется, классика:
    --usage   | -u    Показать краткое использование
    --help    | -h    Показать эту подсказку
    --version | -v    Показать версию
EOF
}



#
# Подсказка по использованию
#
print_usage() {
    local str1 str2 str3 str4
    str1=$(IFS="|"; echo "${VALID_COMMANDS[*]:0:5}"); str1="${str1//|/ | }";
    str2=$(IFS="|"; echo "${VALID_COMMANDS[*]:5:3}"); str2="${str2//|/ | }";
    str3=$(IFS="|"; echo "${VALID_COMMANDS[*]:8:2}"); str3="${str3//|/ | }";
    str4=$(IFS="|"; echo "${VALID_COMMANDS[*]:10}" ); str4="${str4//|/ | }";
cat<< EOF
${APP_TITLE}
Использование: ${APP_NAME} [папка | число_строк | cloud_path] [команда]
  [папка]         — путь к локальной папке (по умолчанию: .)
  [число_строк]   — только для команды ${SHOW_LOG} (по умолчанию: ${LOG_COUNT_ROWS})
  [cloud_path]    — путь вида user@host:/path/to/cloud_folder (только для ${SYNC_CMD_CLOUD_UP_INIT})
  [команда]       — одна из: [ ${str1} ]
                             [ ${str2} ]
                             [ ${str3} ]
                             [ ${str4} ]
                             По умолчанию: ${SYNC_CMD_REGULAR}
  --usage   | -u  — Показать краткое использование
  --help    | -h  — Показать эту подсказку
  --version | -v  — Показать версию
EOF
}




#
# Проверяет доступ к хосту, наличие папки cloud_dir и доступность записи в папку cloud_dir
# Строка вида user@host:/path/to/parent/cloud_dir
#
check_cloud_dir() {
    local cloud_url="${1:?check_cloud_dir: укажите путь вида user@host:/path/to/cloud_dir}"
    local user_host="${cloud_url%%:*}"
    local remote_path="${cloud_url#*:}"

    # Проверка корректности user@host
    if [[ ! "$user_host" =~ ^[^@]+@[^@]+$ ]] || [ -z "$remote_path" ]; then
        echo "Ошибка: неверный формат cloud_dir: $cloud_url"
        return 1
    fi

    local test_file
    test_file=".check_cloud_dir_$(date +%s%N)_$$.tmp"

    # Обёртка для ssh
    ssh_exec() {
        ssh -p "${SSH_PORT:?SSH_PORT не задана}" -o BatchMode=yes "${user_host}" "$@"
    }

    # Сначала проверяем доступ на запись
    if ssh_exec "touch \"${remote_path}/${test_file}\" && rm -f \"${remote_path}/${test_file}\"" 2>/dev/null; then
        # echo "Папка ${remote_path} на хосте ${user_host} доступна для записи"
        return 0
    fi

    echo "Ошибка: нет доступа на запись в [${user_host}:${remote_path}]"

    # Проверяем доступность хоста (ssh)
    if ssh_exec "true" >/dev/null 2>&1; then
        echo "Доступ к хосту ${user_host} есть"
    else
        echo "Нет доступа к хосту ${user_host}"
    fi

    # Проверяем наличие папки
    if ssh_exec "test -d '${remote_path}'"; then
        echo "Папка ${remote_path} существует на хосте ${user_host}"
    else
        echo "Папка ${remote_path} НЕ существует на хосте ${user_host}"
    fi

    return 1
}



# 
# Проверяем Доступ к серверной папке на правильность перед созданием там новой облачной папки
# Разбираем путь на родительскую папку и конечную папку (dirname и basename).
# Проверяем, что родительская папка существует (test -d).
# Проверяем, что конечная папка НЕ существует (test -e — есть ли такой файл/папка).
# Если конечная папка существует — возвращаем ошибку.
# Если всё ок — возвращаем 0.
# 
validate_cloud_up_init() {
    local remote_spec="${1:?validate_cloud_up_init: укажите путь вида user@host:/path/to/new_dir}"

    # Разбор user@host и пути
    local remote_user_host="${remote_spec%%:*}"
    local remote_full_path="${remote_spec#*:}"

    # пример регулярки для двух папок в пути
    # if [[ "$remote_spec" =~ ^[a-zA-Z0-9._-]+@[a-zA-Z0-9._-]+:/.+/.+$ ]]; then
    #     local remote_user_host="${remote_spec%%:*}"
    #     local remote_full_path="${remote_spec#*:}"
    #     local remote_parent_path
    #     remote_parent_path=$(dirname "$remote_full_path")

    # Проверка формата user@host
    if [[ ! "$remote_user_host" =~ ^[a-zA-Z0-9._-]+@[a-zA-Z0-9._-]+$ ]]; then
        echo "Ошибка: неверный формат user@host в '$remote_spec'"
        return 1
    fi

    # Проверка абсолютного пути
    if [[ -z "$remote_full_path" || "$remote_full_path" != /* ]]; then
        echo "Ошибка: путь должен быть абсолютным и начинаться с /"
        return 1
    fi

    local remote_parent_path
    remote_parent_path=$(dirname "$remote_full_path")

    # Проверка существования родительской директории
    if ! check_cloud_dir "${remote_user_host}:${remote_parent_path}" >/dev/null; then
        echo "Ошибка: родительская папка '$remote_parent_path' недоступна или не существует на сервере '$remote_user_host'."
        return 1
    fi

    # Проверка, что целевая папка не существует
    if ssh -p "${SSH_PORT}" "$remote_user_host" "test -e '$remote_full_path'" 2>/dev/null; then
        echo "Ошибка: конечная папка '$remote_full_path' уже существует на сервере '$remote_user_host'."
        return 1
    fi

    return 0
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



#
# Начинает с текущего значения переменной DIR_LOCAL.
# Проверяет, есть ли в этой папке подкаталог .sync.
# Если нет — поднимается на уровень выше и повторяет.
# Проверка не доходит до корневой папки.
# Если на каком-то уровне .sync найден — обновляет DIR_LOCAL и завершает.
# Если .sync так и не найден — сообщает об ошибке и завершает с кодом 1.
#
find_sync_dir() {
    local current
    current="$(get_abs_path "$DIR_LOCAL")" # Это действие уже было сделано в парсинге параметров. Тут на всякий случай.
    while [[ "$current" != "/" ]]; do
        if [[ -d "$current/${DIR_SYNC}" ]]; then
            DIR_LOCAL="$current"
            return 0
        fi
        current=$(dirname "$current")
    done
    exit_with_msg "Ошибка: не удалось найти папку '${DIR_SYNC}' ни в '${DIR_LOCAL}', ни выше по дереву."
}



#
#  парсинг входных параметров
#
parse_args() {

    # Если ничего не передано, то выйти с ошибкой и подсказкой.
    if [ $# -lt 1 ]; then
        exit_with_msg "Вы не указали что именно Вы хотите сделать." 2
    fi

    local DIR_LOCAL_SET=0

    for arg in "$@"; do
        # Проверка на наличие posix команд-параметров --help|-h|--version|-v|--usage|-u
        case "$arg" in
            -h|--help)
                CMD_USER="${SHOW_HELP}"
                return 0
                ;;
            --usage|-u)
                CMD_USER="${SHOW_USAGE}"
                return 0
                ;;
            -v|--version)
                CMD_USER="${SHOW_VERSION}"
                return 0
                ;;
        esac
        # Проверка на правильность пользовательской команды
        for cmd_true in "${VALID_COMMANDS[@]}"; do
            if [[ "$arg" == "${cmd_true}" ]]; then
                CMD_USER="$arg"
                continue 2
            fi
        done
        # Првоерка чтобы пользовательская папка была указана один раз
        if [[ $DIR_LOCAL_SET -eq 0 ]]; then
            DIR_LOCAL="$arg"
            DIR_LOCAL_SET=1
        else
            exit_with_msg "Ошибка: неизвестный параметр '$arg'" 2
        fi
    done

    # Проверка команды LOG
    if [[ "$CMD_USER" == "${SHOW_LOG}" ]]; then
        if [[ $DIR_LOCAL_SET -eq 1 ]]; then
            if [[ "${DIR_LOCAL}" =~ ^[0-9]+$ ]]; then
                LOG_COUNT_ROWS="${DIR_LOCAL}"
                DIR_LOCAL="${DIR_LOCAL_DEFAULT}"
            else
                exit_with_msg "Ошибка: для команды LOG можно указать число строк, а не путь к папке." 2
            fi
        fi

    # Проверка команды CLOUD_UP_INIT
    elif [[ "$CMD_USER" == "${SYNC_CMD_CLOUD_UP_INIT}" ]]; then
        if [[ $DIR_LOCAL_SET -eq 0 ]]; then
            exit_with_msg "Ошибка: необходимо указать путь для загрузки в облако (user@host:/путь/к/новая_папка)" 2
        fi

        DIR_CLOUD="${DIR_LOCAL}"
        DIR_LOCAL="."

        if ! validate_cloud_up_init "${DIR_CLOUD}"; then
            exit_with_msg "Ошибка: ${DIR_CLOUD} не прошла валидацию." 1
        fi
    fi

    # Проверка существования локальной папки (в любом случае)
    if [[ ! -d "${DIR_LOCAL}" ]]; then
        if [[ -f "${DIR_LOCAL}" ]]; then
            exit_with_msg "Ошибка: '${DIR_LOCAL}' является файлом, а не папкой." 2
        else
            exit_with_msg "Ошибка: папка '${DIR_LOCAL}' не найдена." 2
        fi
    fi

    # вернуть полный путь, даже для ссылок
    DIR_LOCAL="$(get_abs_path "$DIR_LOCAL")"
}



#
#  CMD_TRANSFER_SERV и CMD_TRANSFER_DATA должны инициализироваться 
#  только после parse_args(), поскольку именно там
#  инициализируется переменная DIR_LOCAL
# 
init_transfer_commands() {
    #  Команда для копирования служебных данных
    CMD_TRANSFER_SERV=(rsync 
        -c -htprl --inplace -W
        --rsh="ssh -p ${SSH_PORT}"
    )

    # CMD_TRANSFER_SERV="rsync \
    #         -c -htprl --inplace -W"

    #  Команда для копирования пользовательских данных
    CMD_TRANSFER_DATA=(rsync
        --log-file="${DIR_LOCAL}/${LOG_FILE}"
        --include="${FILE_EXCLUDES}" 
        --include="${FILE_DEST}" 
        --exclude-from="${DIR_LOCAL}/${FILE_EXCLUDES}" 
        -azhtpErl --progress -u 
        --exclude="${DIR_SYNC}/*" 
        --exclude="${LOG_FILE}"
        --rsh="ssh -p ${SSH_PORT}"
    )

    # CMD_TRANSFER_DATA="rsync \
    #     --log-file=\"${DIR_LOCAL}/${LOG_FILE}\" \
    #     --include=\"${FILE_EXCLUDES}\" \
    #     --include=\"${FILE_DEST}\" \
    #     --exclude-from=\"${DIR_LOCAL}/${FILE_EXCLUDES}\" \
    #     -azhtpErl --progress -u \
    #     --exclude=\"${DIR_SYNC}/*\" \
    #     --exclude=\"${LOG_FILE}\""
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
    local LOCAL="${1:?dl LOCAL не передана или пуста. Это программная ошибка скрипта.}"
    local DEST="${2:?dl DEST не передана или пуста. Это программная ошибка скрипта.}"
    local TYPE_TRANSFER="${3:-${SYNC_TYPE_DATA}}"
    if [ "${TYPE_TRANSFER}" != "${SYNC_TYPE_SERVICE}" ] && [ "${TYPE_TRANSFER}" != "${SYNC_TYPE_DATA}" ]; then
        exit_with_msg "DL: Недопустимый тип копирования: [${TYPE_TRANSFER}]. Допустимы: '${SYNC_TYPE_SERVICE}' | '${SYNC_TYPE_DATA}'" 1
    fi

    logger -p info "${LOG_PREFIX} ACT DL START: [${LOCAL}] -> [${DEST}]"

    if [ "${TYPE_TRANSFER}" = "${SYNC_TYPE_SERVICE}" ]; then
        # echo "Сервисное копирование"
        "${CMD_TRANSFER_SERV[@]}" "${LOCAL}" "${DEST}"
    else
        # echo "Копирование данных"
        "${CMD_TRANSFER_DATA[@]}" "${LOCAL}" "${DEST}"
    fi
    logger -p info "${LOG_PREFIX} ACT DL END: [$LOCAL] -> [$DEST]"
}



#
# Копирование пользовательский данных (с учетом исключений) в папку назначения 
# с удалением расхождений в папке назначения
# Использование:
# dl <LOCAL> <DEST>
#    LOCAL -- Путь папки-источника
#    DEST -- Путь папки-назначения
#
dl_init()
{
    local LOCAL="${1:?dl_init LOCAL не передана или пуста. Это программная ошибка скрипта.}"
    local DEST="${2:?dl_init DEST не передана или пуста. Это программная ошибка скрипта.}"

    logger -p info "${LOG_PREFIX} ACT DL_INIT START: [$LOCAL] -> [$DEST]"

    "${CMD_TRANSFER_DATA[@]}" --delete "${LOCAL}" "${DEST}"
        
    logger -p info "${LOG_PREFIX} ACT DL_INIT END: [$LOCAL] -> [$DEST]"
}



##
## sync_regular LOCAL DEST
## Копирование данных на удаленный сервер без удаления
## Копирование данных с удаленного хоста на локальный без удаления
##
sync_regular()
{
    local LOCAL="${1:?sync_regular LOCAL не передана или пуста. Это программная ошибка скрипта.}"
    local DEST="${2:?sync_regular DEST не передана или пуста. Это программная ошибка скрипта.}"
    echo   "$MSG_TO_UP"
    dl "$LOCAL" "$DEST" "${SYNC_TYPE_DATA}" || exit_with_msg  "sync_regular: Ошибка при выполнении dl \"$LOCAL\" \"$DEST\" \"${SYNC_TYPE_DATA}\"" 1

    echo   "${MSG__DIV_}"
    echo   "${MSG_TO_DN}"
    dl "$DEST"  "$LOCAL" "${SYNC_TYPE_DATA}" || exit_with_msg "sync_regular: Ошибка при выполнении dl \"$DEST\" \"$LOCAL\" \"${SYNC_TYPE_DATA}\"" 1
}



#
# В локальной папке создает папку .sync
# и в ней создаст файл имени этого хоста .sync/USER_<hostname>
# для последующей регистрации на удаленном хосте
#
init_local()
{
    local STATUS="${1:?init_local CMD не передана или пуста. Это программная ошибка скрипта.}"
    echo "INIT_LOCAL: Создание файла ${DIR_LOCAL}/${DIR_SYNC}/${MY_NAME}"
    touch "${DIR_LOCAL}/${DIR_SYNC}/${MY_NAME}" || exit_with_msg "init_local(${STATUS}): По какой-то причине не удалось создать/обновить файл \"${DIR_LOCAL}/${DIR_SYNC}/${MY_NAME}\"" 1
    echo "${STATUS}"  > "${DIR_LOCAL}/${DIR_SYNC}/${MY_NAME}"
}



#
# В папку $DIR_CLOUD/.sync записывается $MY_NAME -- имя этого компьютера в виде USER_<hostname>
#
init_dest()
{
    echo "INIT_DEST: Запись имени компьютера в ${DIR_CLOUD}/${DIR_SYNC}/${MY_NAME}"
    # Проверка существования директории ${DIR_CLOUD}/${DIR_SYNC} перед попыткой записать в нее файл.
    mkdir "${DIR_LOCAL}/${DIR_TEMP}/${DIR_SYNC}" || exit_with_msg "init_dest: Не удалось создать папку \"${DIR_LOCAL}/${DIR_TEMP}/${DIR_SYNC}\"" 1
    dl    "${DIR_LOCAL}/${DIR_TEMP}/${DIR_SYNC}" "${DIR_CLOUD}/"                       "${SYNC_TYPE_SERVICE}" || exit_with_msg "init_dest: Ошибка при выполнении dl \"${DIR_LOCAL}/${DIR_TEMP}/${DIR_SYNC}\" \"${DIR_CLOUD}/\" \"${SYNC_TYPE_SERVICE}\"" 1
    rmdir "${DIR_LOCAL}/${DIR_TEMP}/${DIR_SYNC}" || exit_with_msg "init_dest: Не удалось удалить папку \"${DIR_LOCAL}/${DIR_TEMP}/${DIR_SYNC}\"" 1
    dl    "${DIR_LOCAL}/${DIR_SYNC}/${MY_NAME}"  "${DIR_CLOUD}/${DIR_SYNC}/${MY_NAME}" "${SYNC_TYPE_SERVICE}" || exit_with_msg "init_dest: Ошибка при выполнении dl \"${DIR_LOCAL}/${DIR_SYNC}/${MY_NAME}\" \"${DIR_CLOUD}/${DIR_SYNC}/${MY_NAME}\" \"${SYNC_TYPE_SERVICE}\"" 1
}



#
# Просто удаляет и создаёт папку для временных файлов
#
init_temp() {
    local temp_dir
    # Если DIR_LOCAL или DIR_TEMP пуста или неопределена, shell выводит сообщение об ошибке и завершает выполнение скрипта.
    temp_dir="${DIR_LOCAL:?DIR_LOCAL не определена или пуста. Это программная ошибка скрипта.}/${DIR_TEMP:?DIR_TEMP не определена или пуста. Это программная ошибка скрипта.}"
    rm -rf "${temp_dir}" 2>/dev/null
    # mkdir -p нельзя использовать, поскольку DIR_LOCAL должна быть обязательно. 
    # Если по какой-то причине её нет, то это критическая ошибка скрипта.
    mkdir "${temp_dir}" || { echo "Ошибка создания директории ${temp_dir}: $?";  exit 1; }
}



#
# Устанавливает на сервере статус синхронизации для этого хоста
# Статус синхронизации записывается внутрь файла с названием этого хоста
#
set_status_my()
{
    local STATUS="${1:?}"
    printf "Установка статуса синхронизации в [${COLOR_STATUS}%s${COLOR_OFF}]... " "${STATUS}"
    echo "${STATUS}" > "${DIR_LOCAL}/${DIR_SYNC}/${MY_NAME}"
    touch "${DIR_LOCAL}/${DIR_SYNC}/${MY_NAME}"
    dl "${DIR_LOCAL}/${DIR_SYNC}/${MY_NAME}" "${DIR_CLOUD}/${DIR_SYNC}/${MY_NAME}" "${SYNC_TYPE_SERVICE}" || exit_with_msg  "set_status_my: Ошибка при выполнении dl \"${DIR_LOCAL}/${DIR_SYNC}/${MY_NAME}\" \"${DIR_CLOUD}/${DIR_SYNC}/${MY_NAME}\" \"${SYNC_TYPE_SERVICE}\"" 1
    echo " Выполнено."
}



#
# set_status_all <STATUS_ALL> [<STATUS_MY>]
#
set_status_all()
{
    local STATUS
    local STATUS_ALL="${1:?}"
    local STATUS_MY="${2:-$1}"
    local filename
    
    echo -e "Установка для всех статуса синхронизации в \"${COLOR_STATUS}${STATUS_ALL}${COLOR_OFF}\" (для меня в \"${COLOR_STATUS}${STATUS_MY}${COLOR_OFF}\")"
    init_temp
    # Считываем вайлы всех пользователей зарегистрированных на сервере
    dl "${DIR_CLOUD}/${DIR_SYNC}/${USER_PREFIX}*"  "${DIR_LOCAL}/${DIR_TEMP}/" "${SYNC_TYPE_SERVICE}" || exit_with_msg  "set_status_all: Ошибка при выполнении dl \"${DIR_CLOUD}/${DIR_SYNC}/${USER_PREFIX}*\"  \"${DIR_LOCAL}/${DIR_TEMP}/\" \"${SYNC_TYPE_SERVICE}\"" 1
    
    for F in "${DIR_LOCAL}/${DIR_TEMP}/${USER_PREFIX}"*; do
        if [ ! -f "$F" ]; then
            # не файл
            exit_with_msg   "Файл $F имеет неизвестный тип, не обрабатывается.\n" \
                            "Этого не долно быть, поскольку все файлы в папку '${DIR_LOCAL}/${DIR_TEMP}/'\n" \
                            "копировались с сервера по шаблону '${DIR_CLOUD}/${DIR_SYNC}/${USER_PREFIX}*'.\n\n" \
                            "Нужно проверить папку на сервере и локальную папку на предмет директорий, ссылок и прав доступа.\n\n" \
                            "Поскольку такого не должно быть, то считаем ошибку критической.\n" \
                            1;
        fi
        filename="${F##*/}"
            # ${F##*/} - это синтаксис параметрного расширения в bash, который используется для удаления самого длинного префикса, совпадающего с шаблоном */.
            # В данном случае, ${F##*/} удаляет путь к файлу и оставляет только имя файла.
            # Например, если $F равен /path/to/file.txt, то ${F##*/} будет равно file.txt.
            # Этот синтаксис используется для того, чтобы получить только имя файла, без пути к нему.
            # Вот разбивка синтаксиса:
            # ${parameter##word} - это синтаксис параметрного расширения, который удаляет самый длинный префикс, совпадающий с шаблоном word.
            # ## - это оператор удаления самого длинного префикса.
            # */ - это шаблон, который совпадает с любым путем к файлу.
            # Итак, ${F##*/} - это способ получить только имя файла, без пути к нему, используя параметрное расширение в bash.
        STATUS=$([ "${filename}" = "${MY_NAME}" ] && echo "${STATUS_MY}" || echo "${STATUS_ALL}")
        echo -e "set status ${COLOR_STATUS}${STATUS}${COLOR_OFF} for ${COLOR_STATUS}${filename}${COLOR_OFF}"
        echo    "${STATUS}" > "$F"
        dl "$F" "${DIR_CLOUD}/${DIR_SYNC}/${filename}" "${SYNC_TYPE_SERVICE}" || exit_with_msg  "set_status_all: Ошибка при выполнении dl \"$F\" \"${DIR_CLOUD}/${DIR_SYNC}/${filename}\" \"${SYNC_TYPE_SERVICE}\"" 1
    done
    # dl "${DIR_LOCAL}/${DIR_TEMP}/${USER_PREFIX}*" "${DIR_CLOUD}/${DIR_SYNC}/" "${SYNC_TYPE_SERVICE}"
    init_temp
}



#
# Проверка, заполнение и обновление путей и переменных
#       DIR_SYNC        # папка параметров синхронизации
#       MY_NAME         # Переменная означающа имя устройства, проверяем наличие локального файла
#       FILE_DEST       # файл, в котором записан адрес удаленного каталога
#       DIR_CLOUD       # Переменная содержащая удалённый адрес
#       CMD_CLOUD       # Команда синхронизации с сервера
#       FILE_EXCLUDES   # Файл исключений для rsync
#
update_sync_variables()
{
    #
    #  "Проверка служебной папки синхронизатора \"${DIR_LOCAL}/${DIR_SYNC}\"..."
    #

    # DIR_SYNC                  # папка параметров синхронизации
    if [ ! -d "${DIR_LOCAL}/${DIR_SYNC}" ]; then
        exit_with_msg   "╔═══════════════════════════════════════════════════════════════════════════════╗\n"\
                        "║                                                                               ║\n"\
                        "║      ОЩИБКА: Служебной папки синхронизатора нет.                              ║\n"\
                        "║              Возможно, вы указали не верную папку для синхронизации           ║\n"\
                        "║                                                                               ║\n"\
                        "$(printf "║      В папке для синхронизации нужно создать папку:        %-15s    ║\n" "${DIR_SYNC}")"\
                        "$(printf "║      файл, в котором записан адрес удаленного каталога:    %-15s    ║\n" "${FILE_DEST}")"\
                        "$(printf "║      файл со списком шаблонов исключений из синхронизации: %-15s    ║\n" "${FILE_EXCLUDES}")"\
                        "║                                                                               ║\n"\
                        "║              ЭТО КРИТИЧЕСКАЯ ОШИБКА.                                          ║\n"\
                        "║                                                                               ║\n"\
                        "╚═══════════════════════════════════════════════════════════════════════════════╝"\
                        1
    fi

    # FILE_DEST                 # файл, в котором записан адрес удаленного каталога
    if [ ! -f "${DIR_LOCAL}/${FILE_DEST}" ]; then
        exit_with_msg   "╔═══════════════════════════════════════════════════════════════════════════════╗\n"\
                        "║                                                                               ║\n"\
                        "$(printf "║      ОЩИБКА: Нет файла %-24s,                              ║\n" "[ ${FILE_DEST} ]")"\
                        "║              в котором записана строка с адресом удаленного каталога          ║\n"\
                        "║              адрес вида: 'user@host:/cloud/path/dir'                          ║\n"\
                        "║                                                                               ║\n"\
                        "║              ЭТО КРИТИЧЕСКАЯ ОШИБКА.                                          ║\n"\
                        "║                                                                               ║\n"\
                        "╚═══════════════════════════════════════════════════════════════════════════════╝\n"\
                        1
    fi

    # DIR_CLOUD                 # Переменная содержащая удалённый адрес
    read -r DIR_CLOUD <"${DIR_LOCAL}/${FILE_DEST}"
    if ! check_cloud_dir "${DIR_CLOUD}"; then
        exit_with_msg   "╔═══════════════════════════════════════════════════════════════════════════════╗\n"\
                        "║                                                                               ║\n"\
              "$(printf "║    Облачная папка: %-46s             ║\n" "[ ${FILE_DEST} ]")"\
                        "║            ОЩИБКА: Доступа к облачной папке нет.                              ║\n"\
                        "║            Проверьте адрес и права.                                           ║\n"\
                        "║                                                                               ║\n"\
                        "║            ЭТО КРИТИЧЕСКАЯ ОШИБКА.                                            ║\n"\
                        "║                                                                               ║\n"\
                        "╚═══════════════════════════════════════════════════════════════════════════════╝\n"\
                        1
    fi

    # CMD_CLOUD                 # Команда синхронизации с сервера
    init_temp
    dl  "${DIR_CLOUD}/${DIR_SYNC}/${MY_NAME}" \
        "${DIR_LOCAL}/${DIR_TEMP}/" \
        "${SYNC_TYPE_SERVICE}"

    if [ ! -f "${DIR_LOCAL}/${DIR_TEMP}/${MY_NAME}" ]; then
        echo "Файла ${DIR_LOCAL}/${DIR_TEMP}/${MY_NAME} нет"
        echo "Предположительно его нет на удаленном хосте"
        echo "Регистрируем компьютер на удаленном хосте"
        init_local "${SYNC_CMD_DL_INIT}"
        init_dest
        exit_with_msg   "╔═══════════════════════════════════════════════════════════════════════════════╗\n"\
                        "║                                                                               ║\n"\
                        "║                      Запустите синхронизацию ещё раз                          ║\n"\
                        "║                                                                               ║\n"\
                        "╚═══════════════════════════════════════════════════════════════════════════════╝"\
                        1;
    else
        CMD_CLOUD=$(cat "${DIR_LOCAL}/${DIR_TEMP}/${MY_NAME}")
        if [ -f "${DIR_LOCAL}/${DIR_TEMP}/${MY_NAME}" ]; then
            rm "${DIR_LOCAL}/${DIR_TEMP}/${MY_NAME}" || exit_with_msg "update_sync_variables: Не удалось удалить \"${DIR_LOCAL}/${DIR_TEMP}/${MY_NAME}\"" 1;
        fi
    fi

    # FILE_EXCLUDES             # Файл исключений для rsync
    if [ ! -f "${DIR_LOCAL}/${FILE_EXCLUDES}" ]; then
        echo -e         "╔═══════════════════════════════════════════════════════════════════════════════╗\n"\
                        "║                                                                               ║\n"\
              "$(printf "║      ОЩИБКА: Нет файла %-14s,                                        ║\n" "[ ${FILE_EXCLUDES} ]")"\
                        "║              в котором записаны исключения для rsync.                         ║\n"\
                        "║              Создаём вефолтный.                                               ║\n"\
                        "║                                                                               ║\n"\
                        "╚═══════════════════════════════════════════════════════════════════════════════╝\n";
        touch "${DIR_LOCAL}/${FILE_EXCLUDES}" || exit_with_msg "По какой-то причине не удалось создать файл '${DIR_LOCAL}/${FILE_EXCLUDES}'. Проверьте доступы." 1
        echo "${EXCLUDES}">"${DIR_LOCAL}/${FILE_EXCLUDES}" || exit_with_msg "Очень странно..." 1
    fi
}



#
#  Создаёт локальную папку .sync и инициализирует её
#  Создаёт на сервере указанную папку и инициализирует её
#  Добавляет локальную папку в конфиг скрипта массовой синхронизации
#
do_cloud_up_init()
{
    local CLOUD_PATH CLOUD_FOLDER 
    local LOCAL_PATH LOCAL_FOLDER
    local PREV_DIR
    CLOUD_PATH=$(dirname "$DIR_CLOUD")
    CLOUD_FOLDER=$(basename "$DIR_CLOUD")
    {
        PREV_DIR=$(pwd)
        cd "${DIR_LOCAL}" || { exit_with_msg "Не удалось перейти в папку [${DIR_LOCAL}]" 1; }
        DIR_LOCAL=$(pwd)
        LOCAL_PATH=$(dirname "${DIR_LOCAL}")
        LOCAL_FOLDER=$(basename "${DIR_LOCAL}")
        cd "${PREV_DIR}" || { exit_with_msg "Не удалось перейти в папку [${PREV_DIR}]" 1; }
    }

    echo   "${LINE_TOP_}"
    echo   "${LINE_FREE}"
    printf "║              Команда : %-54s ║\n" "${CMD_USER}"
    printf "║      Локальная папка : %-54s ║\n" "${DIR_LOCAL}"
    printf "║         Путь к папке : %-54s ║\n" "${LOCAL_PATH}"
    printf "║           Сама папка : %-54s ║\n" "${LOCAL_FOLDER}"
    printf "║ Облачные папки         %-54s ║\n" " "
    printf "║  Путь к папке (SYNC) : %-54s ║\n" "${CLOUD_PATH}"
    printf "║           Сама папка : %-54s ║\n" "${CLOUD_FOLDER}"
    echo   "${LINE_FREE}"
    echo   "${LINE_BOT_}"

    echo     "Создание папки синхронизатора ${DIR_LOCAL}/${DIR_SYNC}"
    mkdir -p "${DIR_LOCAL}/${DIR_SYNC}" || { exit_with_msg "Не удалось создать папку синхронизатора [${DIR_LOCAL}/${DIR_SYNC}]" 1; }
    printf   "Создание файла [%s]" "${MY_NAME}"
    echo     "${SYNC_CMD_REGULAR}" > "${DIR_LOCAL}/${DIR_SYNC}/${MY_NAME}"
    printf   ", [%s]" "${FILE_DEST}"
    echo     "${CLOUD_PATH}/${CLOUD_FOLDER}" > "${DIR_LOCAL}/${FILE_DEST}"
    printf   ", [%s]" "${FILE_EXCLUDES}"
    echo     "${EXCLUDES}" > "${DIR_LOCAL}/${FILE_EXCLUDES}"
    printf   ". Ок\n"

    echo "Создаём в папке tmp копию того, что нужно отправить на сервер"
    mkdir -p "${DIR_LOCAL}/${DIR_TEMP}/${CLOUD_FOLDER}/${DIR_SYNC}" || { exit_with_msg "Не удалось создать папку [${DIR_LOCAL}/${DIR_TEMP}/${CLOUD_FOLDER}/${DIR_SYNC}]" 1; }
    printf   "Копируем %s" "[${CLOUD_FOLDER}/${DIR_SYNC}/${MY_NAME}]"
    cp       "${DIR_LOCAL}/${DIR_SYNC}/${MY_NAME}" "${DIR_LOCAL}/${DIR_TEMP}/${CLOUD_FOLDER}/${DIR_SYNC}/" || { exit_with_msg "Ошибка при копировании файла [1] [${MY_NAME}]" 1; }
    printf   ", %s" "[${CLOUD_FOLDER}/${FILE_DEST}]"
    cp       "${DIR_LOCAL}/${FILE_DEST}"           "${DIR_LOCAL}/${DIR_TEMP}/${CLOUD_FOLDER}/${DIR_SYNC}/" || { exit_with_msg "Ошибка при копировании файла [2] [${FILE_DEST}]" 1; }
    printf   ", %s" "[${CLOUD_FOLDER}/${FILE_EXCLUDES}]"
    cp       "${DIR_LOCAL}/${FILE_EXCLUDES}"       "${DIR_LOCAL}/${DIR_TEMP}/${CLOUD_FOLDER}/${DIR_SYNC}/" || { exit_with_msg "Ошибка при копировании файла [3] [${FILE_EXCLUDES}]" 1; }
    printf   ". Ок\n"

    echo     "Копируем локальную временную папку [${DIR_TEMP}/${CLOUD_FOLDER}]"
    echo     "На сервер в папку                  [${CLOUD_PATH}]"
    dl "${DIR_LOCAL}/${DIR_TEMP}/${CLOUD_FOLDER}" "${CLOUD_PATH}" "${SYNC_TYPE_SERVICE}" || { exit_with_msg  "do_cloud_up_init: Ошибка при выполнении dl '${DIR_LOCAL}/${DIR_TEMP}/${CLOUD_FOLDER}' '${CLOUD_PATH}' '${SYNC_TYPE_SERVICE}'" 1; }
    init_temp

    echo     "Добавляем папку в список массовой синхронизации [${FILE_SYNC_ALL_LIST}]..."
    if [ -f "${APP_PATH}/${FILE_SYNC_ALL_LIST}" ]; then
        if [ -w "${APP_PATH}/${FILE_SYNC_ALL_LIST}" ]; then # Есть права на запись
            if ( grep -q "${DIR_LOCAL}" "${APP_PATH}/${FILE_SYNC_ALL_LIST}" ); 
            then 
                echo "В файле [${APP_PATH}/${FILE_SYNC_ALL_LIST}] строка [${DIR_LOCAL}] есть."; 
                echo "Ничего не делаем."; 
            else 
                echo "В файле [${APP_PATH}/${FILE_SYNC_ALL_LIST}] НЕТ строки [${DIR_LOCAL}]."; 
                printf "Добавляем..."; 
                {
                    echo ""
                    echo "#"
                    echo "# Добавлено $(date)"
                    echo "# пользователем ${USER}"
                    echo "# командой ${SYNC_CMD_CLOUD_UP_INIT}"
                    echo "#"
                    echo "\"${DIR_LOCAL}\" \"$(basename "${DIR_LOCAL}")\""
                }  >> "${APP_PATH}/${FILE_SYNC_ALL_LIST}"
                printf "...Ok.\n"; 
            fi
        else
            echo "Нет прав на запись в [${APP_PATH}/${FILE_SYNC_ALL_LIST}]"
            echo "Проверьте права доступа и добавьте строку в ручную."
        fi
    else
        echo "Файла [${FILE_SYNC_ALL_LIST}] нет."
    fi

    echo   "${LINE_TOP_}"
    echo   "${LINE_FREE}"
    printf "║     Проверьте, пожалуйста, файл исключений для синхронизации.                 ║\n" 
    printf "║     Исправьте его для ваших потребностей.                                     ║\n" 
    printf "║     За тем, выполните команду синхронизации для отправки данных на сервер     ║\n" 
    echo   "${LINE_FREE}"
    printf "║     Файл исключений         : [%-45s] ║\n" "${DIR_LOCAL}/${FILE_EXCLUDES}"
    echo   "${LINE_FREE}"
    printf "║     Выполните синхронизацию : [%-45s] ║\n" "${APP_NAME} ."
    echo   "${LINE_FREE}"
    echo   "${LINE_BOT_}"

    # echo     "Проводим обычную синхронихацию [${SYNC_CMD_REGULAR}]"
    # sync_regular "${DIR_LOCAL}/" "${DIR_CLOUD}/"

    exit 0;

}



#
#  Печат заголовка перед выполнение команды
#
do_sync_print_header()
{
        echo   "${TITLE}"
       #echo   "╟───────────────────────────────────────────────────────────────────────────────╢"
        echo   "$LINE_FREE"
        printf "║                 Статус сервера: %-10s                                    ║\n" "${CMD_CLOUD}"
        printf "║                 Команда хоста : %-10s                                    ║\n" "${CMD_USER}"
        echo   "$LINE_FREE"
        echo   "${MSG__DIV_}"
        echo   "$LINE_FREE"

}



#
#  Выполнение команды
#  SYNC_CMD_DL
#
do_sync_dl()
{
    {   # Баннер
        do_sync_print_header
        echo   "║                 Загрузка данных с сервера на хост, без удаления               ║"
        echo   "${LINE_FREE}"
        echo   "║                 ПЕРЕДАЧА ДАННЫХ                                               ║"
        echo   "${LINE_FREE}"
        echo   "${MSG__DIV_}"
        echo   "${MSG_TO_DN}"
    }

    dl "${DIR_CLOUD}/" "${DIR_LOCAL}/"

    {   # Баннер
        echo   "${LINE_BOT_}"
    }
}


#
#  Выполнение команды
#  SYNC_CMD_UP
#
do_sync_up()
{
    {   # Баннер
        do_sync_print_header
        echo   "║                 Отправка данных c хоста на сервер без удаления                ║"
        echo   "${LINE_FREE}"
        echo   "║                 ПЕРЕДАЧА ДАННЫХ                                               ║"
        echo   "${LINE_FREE}"
        echo   "${MSG__DIV_}"
        echo   "${MSG_TO_UP}"
    }

    dl "${DIR_LOCAL}/" "${DIR_CLOUD}/"

    {   # Баннер
        echo   "${LINE_BOT_}"
    }
}



#
#  Выполнение команды
#  SYNC_CMD_REGULAR
#
do_sync_regular()
{
    {   # Баннер
        do_sync_print_header
        echo   "║                 Обычная осторожная синхронизация:                             ║"
        echo   "║                          1. Выгрузка с хоста на сервер без удаления           ║"
        echo   "║                          2. Загрузка с сервера на хост без удаления           ║"
        echo   "${LINE_FREE}"
        echo   "║                 ПЕРЕДАЧА ДАННЫХ                                               ║"
        echo   "${LINE_FREE}"
        echo   "${MSG__DIV_}"
    }

    sync_regular "${DIR_LOCAL}/" "${DIR_CLOUD}/"

    {   # Баннер
        echo   "${LINE_BOT_}"
    }
}



#
#  Выполнение команды
#  SYNC_CMD_DL_INIT
#
do_sync_dl_init()
{
    MSG="${1:-}"
    {   # Баннер
        do_sync_print_header
        [[ -n "$MSG" ]] && \
        printf "║                 %-50s            ║\n" "${MSG}"
        echo   "║                 ЗАГРУЗКА папок с сервера на хост                              ║"
        echo   "║                 с УДАЛЕНИЕМ локальных расхождений                             ║"
        echo   "${LINE_FREE}"
        echo   "║                 ПЕРЕДАЧА ДАННЫХ                                               ║"
        echo   "${LINE_FREE}"
        echo   "${MSG__DIV_}"
        echo   "${MSG_TO_DN}"
    }

    dl_init "${DIR_CLOUD}/" "${DIR_LOCAL}/"
    set_status_my "${SYNC_CMD_REGULAR}"

    {   # Баннер
        echo   "${LINE_BOT_}"
    }
}



#
#  Выполнение команды
#  SYNC_CMD_UP_INIT
#
do_sync_up_init()
{
    {   # Баннер
        do_sync_print_header
        echo   "║                 Отправка данных на сервер С УДАЛЕНИЕМ                         ║"
        echo   "║                                                                               ║"
        printf "║                 Для ВСЕХ хостов установка статуса сервера %-10s          ║\n" "${SYNC_CMD_DL_INIT}"
        printf "║                 Для ЭТОГО хоста установка статуса сервера %-10s          ║\n" "${SYNC_CMD_REGULAR}"
        echo   "${LINE_FREE}"
        echo   "║                 ПЕРЕДАЧА ДАННЫХ                                               ║"
        echo   "${LINE_FREE}"
        echo   "${MSG__DIV_}"
        echo   "${MSG_TO_UP}"
    }

    dl_init   "${DIR_LOCAL}/" "${DIR_CLOUD}/"
    set_status_all "${SYNC_CMD_DL_INIT}" "${SYNC_CMD_REGULAR}"

    {   # Баннер
        echo   "${LINE_BOT_}"
    }
}



#
#  Выполнение команды
#  SYNC_CMD_UP_EDIT
#
do_sync_up_edit()
{
    {   # Баннер
        do_sync_print_header
        echo   "║                 Сервер в состоянии ПАУЗЫ для редактирования наполнения.       ║"
        echo   "║                 Отправка корректирующих данных на сервер С УДАЛЕНИЕМ          ║"
        echo   "${LINE_FREE}"
        echo   "║                 Статус хостов НЕ МЕНЯЕТСЯ                                     ║"
        echo   "${LINE_FREE}"
        echo   "║                 ПЕРЕДАЧА ДАННЫХ                                               ║"
        echo   "${MSG__DIV_}"
        echo   "${MSG_TO_UP}"
    }

    dl_init   "${DIR_LOCAL}/" "${DIR_CLOUD}/"

    {   # Баннер
        echo   "${MSG__DIV_}"
        echo   "║                 Статус хостов НЕ МЕНЯЕТСЯ                                     ║"
        echo   "${LINE_BOT_}"
    }
}



#
#  Выполнение команды
#  SYNC_CMD_PAUSE
#
do_sync_pause()
{
    {   # Баннер
        do_sync_print_header
        echo   "║               Постановка на ПАУЗУ                                             ║"
        echo   "║               для ручных работ на сервере.                                    ║"
        printf "║               Статус всех хостов устанавливается в    %-10s              ║\n" "${SYNC_CMD_PAUSE}"
        echo   "║               Автоматическая синхронизация для всех хостов ОТКЛЮЧЕНА          ║"
        printf "║               Данные на сервере изменяются командой   %-10s              ║\n" "${SYNC_CMD_UP_EDIT}"
        printf "║               Для снятия с паузы выполните с командой %-10s              ║\n" "${SYNC_CMD_UNPAUSE}"
        echo   "${LINE_FREE}"
        echo   "${MSG__DIV_}"
    }

    set_status_all "${SYNC_CMD_PAUSE}"

    {   # Баннер
        echo   "${LINE_BOT_}"
    }
}



#
#  Выполнение команды
#  SYNC_CMD_UNPAUSE
#
do_sync_unpause()
{
    {   # Баннер
        do_sync_print_header
        echo   "║               Снятие с ПАУЗЫ                                                  ║"
        echo   "║               (по завершению работ на сервере).                               ║"
        echo   "║               Автоматическая синхронизация для всех хостов                    ║"
        printf "║               установлена в режим %-10s -- обязательная загрузка         ║\n" "${SYNC_CMD_DL_INIT}"
        echo   "║               Данные не передаются                                            ║"
        echo   "${LINE_FREE}"
        echo   "${MSG__DIV_}"
    }

    set_status_all "${SYNC_CMD_DL_INIT}"

    {   # Баннер
        echo   "${LINE_BOT_}"
    }
}



#
#
#
# =================================== MAIN ====================================
#
#
#



#
# Сканирование параметров командной строки
# Папка синхронизации
# Команда синхронизации
# 
parse_args "$@"



#
# Если CMD_USER в списке команд требующих синхронизацию, то вызываем find_sync_dir
#
for cmd_sync in "${REQUIRING_SYNC_COMMANDS[@]}"; do
    if [[ "$CMD_USER" == "${cmd_sync}" ]]; then
        find_sync_dir
        break
    fi
done



#
#  CMD_TRANSFER_SERV и CMD_TRANSFER_DATA должны инициализироваться 
#  только после parse_args(), поскольку именно там
#  инициализируется переменная DIR_LOCAL
# 
init_transfer_commands



#
# Обработка простых команд
#
case "$CMD_USER" in
    "${SHOW_HELP}")
        print_help
        exit 0
        ;;
    "${SHOW_USAGE}")
        print_usage
        exit 0
        ;;
    "${SHOW_VERSION}")
        print_version
        exit 0;
        ;;
    "${SYNC_CMD_CLOUD_UP_INIT}")
        # Создание репозитория на сервере из указанной локальной папки
        do_cloud_up_init
        # exit 0;
        ;;
    "${SYNC_CMD_CLOUD_DL_INIT}")
        # Создание локального репозитория из копии на сервере
        echo "Пока не реализовано."
        exit 0;
        ;;
    "${SHOW_LOG}")
        journalctl -p info --since today | grep "$LOG_PREFIX" | tail -n "${LOG_COUNT_ROWS}"
        exit 0
        ;;
    "${SHOW_DEST}")
        #  Показать строку dest
        read -r DIR_CLOUD <"${DIR_LOCAL}/${FILE_DEST}" || exit_with_msg "Ошибка чтения \"${DIR_LOCAL}/${FILE_DEST}\"" 1
        echo "${DIR_CLOUD}"
        exit 0;
        ;;
esac



update_sync_variables



#
#   Дальше обрабатывается то, что нужно синхронизировать
#


TITLE=$(printf "%-50s" "${DIR_LOCAL}" | sed 's/ /═/g')
TITLE=$(printf "╔═════════════════%s════════════╗\n" "${TITLE}")

echo   "╔═════════════╤═════════════════════════════════════════════════════════════════╗"
printf "║  CMD CLOUD  │  ${COLOR_STATUS}%-58s${COLOR_OFF}  √  ║\n" "${CMD_CLOUD}"
printf "║  CMD LOCAL  │  ${COLOR_STATUS}%-58s${COLOR_OFF}  √  ║\n" "${CMD_USER}"
printf "║  MY:        │  %-58s  √  ║\n" "${MY_NAME}"
printf "║  DIR CLOUD  │  %-58s  √  ║\n" "${DIR_CLOUD}"
printf "║  DIR LOCAL  │  %-58s  √  ║\n" "${DIR_LOCAL}"
printf "║  EXCLUDES:  │  %-58s  √  ║\n" "${FILE_EXCLUDES}"
printf "║  TEMP:      │  %-58s  √  ║\n" "${DIR_TEMP}"
printf "║  LOG (opt)  │  %-58s     ║\n" "${LOG_FILE}"
echo   "╚═════════════╧═════════════════════════════════════════════════════════════════╝"



logger -p info "${LOG_PREFIX} BEG: $(date)"
logger -p info "${LOG_PREFIX} VER: ${VERSION}"
logger -p info "${LOG_PREFIX} CMD: $0 $1 $2 $3 $4 $5 $6 $7 $8 $9"



#                  Таблица действий 
#           в зависимости от статуса сервера
#
# SERVER CMD          USER CMD            ACTION
#
# SYNC_CMD_REGULAR    SYNC_CMD_REGULAR    REGULAR
# SYNC_CMD_REGULAR    SYNC_CMD_UP         UP
# SYNC_CMD_REGULAR    SYNC_CMD_DL         DL
# SYNC_CMD_REGULAR    SYNC_CMD_UP_INIT    UP_INIT
# SYNC_CMD_REGULAR    SYNC_CMD_DL_INIT    DL_INIT
# SYNC_CMD_REGULAR    SYNC_CMD_PAUSE      PAUSE
# SYNC_CMD_REGULAR    SYNC_CMD_UP_EDIT    -
# SYNC_CMD_REGULAR    SYNC_CMD_UNPAUSE    -
#
# SYNC_CMD_DL_INIT    SYNC_CMD_REGULAR    DL_INIT
# SYNC_CMD_DL_INIT    SYNC_CMD_UP         -
# SYNC_CMD_DL_INIT    SYNC_CMD_DL         DL_INIT
# SYNC_CMD_DL_INIT    SYNC_CMD_UP_INIT    -
# SYNC_CMD_DL_INIT    SYNC_CMD_DL_INIT    DL_INIT
# SYNC_CMD_DL_INIT    SYNC_CMD_PAUSE      -
# SYNC_CMD_DL_INIT    SYNC_CMD_UP_EDIT    -
# SYNC_CMD_DL_INIT    SYNC_CMD_UNPAUSE    -
#
# SYNC_CMD_PAUSE      SYNC_CMD_REGULAR    -
# SYNC_CMD_PAUSE      SYNC_CMD_UP         -
# SYNC_CMD_PAUSE      SYNC_CMD_DL         -
# SYNC_CMD_PAUSE      SYNC_CMD_UP_INIT    -
# SYNC_CMD_PAUSE      SYNC_CMD_DL_INIT    -
# SYNC_CMD_PAUSE      SYNC_CMD_PAUSE      -
# SYNC_CMD_PAUSE      SYNC_CMD_UP_EDIT    SYNC_CMD_UP_EDIT
# SYNC_CMD_PAUSE      SYNC_CMD_UNPAUSE    SYNC_CMD_UNPAUSE



case "${CMD_CLOUD}" in
    "${SYNC_CMD_REGULAR}")
        case "${CMD_USER}" in
            "${SYNC_CMD_REGULAR}")
                do_sync_regular
                ;;
            "${SYNC_CMD_UP}"|"${SYNC_CMD_UP_INIT}")
                do_sync_up
                ;;
            "${SYNC_CMD_DL}")
                do_sync_dl
                ;;
            "${SYNC_CMD_UP_INIT}")
                do_sync_up_init
                ;;
            "${SYNC_CMD_DL_INIT}")
                do_sync_dl_init
                ;;
            "${SYNC_CMD_PAUSE}")
                do_sync_pause
                ;;
            "${SYNC_CMD_UP_EDIT}"|"${SYNC_CMD_UNPAUSE}")
                exit_with_msg "Эти команды можно отправлять только если сервер в статусе [${SYNC_CMD_PAUSE}]" 2
                ;;
            *)
                exit_with_msg "Необработанная ситуация: USER: [${CMD_USER}] | CLOUD: [${CMD_CLOUD}]\nОбратитесь к разработчикам." 1
                ;;
        esac
        ;;

    "${SYNC_CMD_DL_INIT}")
        case "${CMD_USER}" in
            "${SYNC_CMD_REGULAR}"|"${SYNC_CMD_DL}"|"${SYNC_CMD_DL_INIT}")
                do_sync_dl_init "ТРЕБОВАНИЕ СЕРВЕРА:"
                ;;
            "${SYNC_CMD_UP}"|"${SYNC_CMD_UP_INIT}"|"${SYNC_CMD_PAUSE}"|"${SYNC_CMD_UP_EDIT}"|"${SYNC_CMD_UNPAUSE}")
                echo -e "При статусе сервера ${SYNC_CMD_DL_INIT} отправка данных на сервер запрещена.\nСперва нужно скачать данные.\nДейстий нет."
                ;;
            *)
                exit_with_msg "Необработанная ситуация: CLOUD: [${CMD_CLOUD}] и USER: [${CMD_USER}]\nОбратитесь к разработчикам." 1
                ;;
        esac
        ;;

    "${SYNC_CMD_PAUSE}")
        case "${CMD_USER}" in
            "${SYNC_CMD_REGULAR}"|"${SYNC_CMD_UP}"|"${SYNC_CMD_DL}"|"${SYNC_CMD_UP_INIT}"|"${SYNC_CMD_DL_INIT}"|"${SYNC_CMD_PAUSE}")
                echo -e "При статусе сервера ${SYNC_CMD_PAUSE} обмен данными запрещён."
                echo -e "Доступны команды редактирования данных ${SYNC_CMD_UP_EDIT}"
                echo -e "и снятия с паузы ${SYNC_CMD_UNPAUSE}.\nДейстий нет."
                ;;
            "${SYNC_CMD_UP_EDIT}")
                do_sync_up_edit
                ;;
            "${SYNC_CMD_UNPAUSE}")
                do_sync_unpause
                ;;
            *)
                exit_with_msg "Необработанная ситуация: CLOUD: [${CMD_CLOUD}] и USER: [${CMD_USER}]\nОбратитесь к разработчикам." 1
                ;;
        esac
        ;;

    *)
        exit_with_msg "Необработанная ситуация: CLOUD: [${CMD_CLOUD}]\nОбратитесь к разработчикам." 1
        ;;
esac



logger -p info "${LOG_PREFIX} END: $(date)"
