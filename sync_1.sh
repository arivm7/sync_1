#!/usr/bin/env bash
# set -euo pipefail
# trap 'logger -p error -t "SYNC_1" "[$(date)] Ошибка в строке $LINENO: команда \"$BASH_COMMAND\""' ERR

##
##  Project     : sync_1
##  Description : Основной скрипт синхронизатор.
##                Часть пакета индивидуальной синхронизации sync_1.
##  File        : sync_1.sh
##  Author      : Ariv <ariv@meta.ua> | https://github.com/arivm7
##  Org         : RI-Network, Kiev, UK
##  License     : GPL v3
##    
##  Copyright (C) 2004-2025 Ariv <ariv@meta.ua> | https://github.com/arivm7 | RI-Network, Kiev, UK
##



VERSION="1.8.0 (2025-10-01)"
COPYRIGHT="Copyright (C) 2004-2025 Ariv <ariv@meta.ua> | https://github.com/arivm7 | RI-Network, Kiev, UK"
LAST_CHANGES="\
v1.8.0 (2025-10-01): Добавлен механизм статуса сервера (установка, чтение, ветвление работы)
v1.7.0 (2025-07-10): Добавлена команда SHOW_CLOUD_CMD, которая проверяет и показывает команду сервера
v1.6.0 (2025-06-27): Добавлен конфиг и команда редактирования конфига --edit-conf|-e
v1.5.0 (2025-06-12): Добавлена команда TEST, которая проверяет и показывает состояние синхронизатора
v1.4.1 (2025-05-26): Исправление ошибок диспетчеризации команд
v1.4.0 (2025-05-22): Рефакторинг и массовые проверки.
v1.3.3 (2025-05-17): Добавлен параметр SHOW_DEST показывает облачные пути
v1.3.2 (2025-05-08): Добавлена команда LOG для показа логов работы скрипта
v1.3.1 (2025-04-22): Добавлено дефолтное наполнение файла excludes
v1.3.0 (2025-04-21): Добавлена команда автоматического создания удалённого репозитория командой CLOUD_UP_INIT
"



APP_TITLE="Скрипт индивидуальной синхронизации"
APP_NAME=$(basename "$0")                                   # Полное имя скрипта, включая расширение
APP_PATH=$(cd "$(dirname "$0")" && pwd)                     # Путь размещения исполняемого скрипта
FILE_NAME="${APP_NAME%.*}"                                  # Убираем расширение (если есть), например ".sh"
# shellcheck disable=SC2034
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")                 # Полное имя [вложенного] скрипта, включая расширение
# shellcheck disable=SC2034
SCRIPT_PATH=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)   # Путь размещения [вложенного] скрипта

CONFIG_DIRNAME="sync"
CONFIG_PATH="${XDG_CONFIG_HOME:-${HOME}/.config}/${CONFIG_DIRNAME:+${CONFIG_DIRNAME}}"
CONFIG_FILE="${CONFIG_PATH}/${FILE_NAME}.conf"

DIR_SYNC=".sync"                            # папка параметров синхронизации
FILE_EXCLUDES="${DIR_SYNC}/excludes"        # Файл исключений для rsync
FILE_DEST="${DIR_SYNC}/dest"                # файл, в котором записан адрес удаленного каталога
DIR_TEMP="${DIR_SYNC}/tmp"                  # Временная папка для работы этого скрипта
LOG_FILE="${DIR_SYNC}/log_sync"             # Используется только для логирования того, что делает rsync

USER_PREFIX="USER_"                         # Префикс для формирования имени хоста
MY_NAME="${USER_PREFIX}$(hostname)"         # Имя этого хоста вида USER_<hostname>

DIR_CLOUD=                                  # Сетевой путь вида [user@]host:/path
DIR_LOCAL=                                  # Локальная папка для синхронизации



#
# типы обращения к серверу. 
# Они по разному копируют файлы
#
SYNC_TYPE_SERVICE="SYNC_SERVICE"            # для копирования служебных данных
SYNC_TYPE_DATA="SYNC_DATA"                  # для копирования пользовательских данных



##
##  [CONFIG START] =============================================================
##  Начало секции, перекрываемой из конфиг-файла
##

##
##  Конфиг для скрипта sync_1. 
##  Из пакета индивидуальной синхронизации sync_1.
##  VERSION 1.0.0 (2025-06-26)
##

#
#  Допустимо использование переменных типа ${HOME}
#

LOG_PREFIX="SYNC_1"                         # Используется для префикса в системном логе
SSH_PORT="22"                               # Порт для доступа по протоколу ssh
LOG_COUNT_ROWS="40"                         # Количество строк по умолчанию при просмотре логов

FILE_SYNC_ALL_LIST="sync_all.list"          # Имя файла для скрипта массовой синхронизации. 
                                            # В него добавляется строка при создании репозитория.

# Начальный список файла excludes для исключений rsync
# Если файла excludes нет, то он создаётся и заполняется этими данными
EXCLUDES="\
*.kate-swp
*.swp
.git
.Trash*
.idea
.sync
.sync/*
.~lock.*
venv
venv/*
__pycache__
Temporary
"

COLOR_FILENAME="\e[1;36m"                   # Терминальный цвет для вывода имён файлов
COLOR_STATUS="\e[0;36m"                     # Терминальный цвет для вывода переменной статуса
COLOR_USAGE="\e[1;32m"                      # Терминальный цвет для вывода подсказок по использованию
COLOR_INFO="\e[0;34m"                       # Терминальный цвет для вывода информации
COLOR_CODE="\e[1;36m"                       # Терминальный цвет для вывода примеров кода
COLOR_OK="\033[0;32m"                       # Терминальный цвет для вывода Ok-сообщения
COLOR_ERROR="\e[0;31m"                      # Терминальный цвет для вывода ошибок
COLOR_OFF="\e[0m"                           # Терминальный цвет для сброса цвета

# Программа-редактор для редактирования конфиг-файла
# (без пробелов в пути/и/названии)
EDITOR="nano"

APP_AWK="/usr/bin/awk"

DRY_RUN=0                                   # Только посчитать. Без файловых операций


##
##  Конец секции, перекрываемой из конфиг-файла
##  [CONFIG END] ---------------------------------------------------------------
##



# Определение: запуск из cron или вручную
# [[ ! -t 0 && ! -t 1 ]] проверяет, не подключены ли stdin и stdout к терминалу.
# Если оба не подключены — почти наверняка это cron, systemd, или другой фоновый запуск.
IS_CRON=false
if [[ ! -t 0 && ! -t 1 ]]; then
    IS_CRON=true
fi
VERB_MODE=$(! ${IS_CRON})                   # Подробный вывод всех действий. Если false -- то "тихий режим"



#
# Список поддерживаемых команд
#
# Параметры командной строки
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
    "${SHOW_TEST}"
    "${SHOW_CLOUD_STAT}"
    "${SHOW_CLOUD_CMD}"
)



#
# Список допустимых статусов сервера
#
VALID_CLOUD_STATS=(
    "${SYNC_CMD_REGULAR}"
    "${SYNC_CMD_PAUSE}"
)



#
# Список допустимых серверных команд для клиента
#
VALID_CLOUD_COMMANDS=(
    "${SYNC_CMD_REGULAR}"
    "${SYNC_CMD_DL_INIT}"
    "${SYNC_CMD_PAUSE}"
)



#
# Список команд, требующих наличия папки .sync
#
COMMANDS_REQUIRING_SYNC=(
    "${SYNC_CMD_REGULAR}"
    "${SYNC_CMD_UP}"
    "${SYNC_CMD_DL}"
    "${SYNC_CMD_UP_INIT}"
    "${SYNC_CMD_DL_INIT}"
    "${SYNC_CMD_PAUSE}"
    "${SYNC_CMD_UP_EDIT}"
    "${SYNC_CMD_UNPAUSE}"
    "${SHOW_DEST}"
    "${SHOW_TEST}"
    "${SHOW_CLOUD_CMD}"
)



# Значения по умолчанию
DIR_LOCAL_DEFAULT="."                       # Локальная папка, назначаемая если не указана явно
DIR_LOCAL="${DIR_LOCAL_DEFAULT}"            # Локальная папка для синхронизации
CMD_USER="${SYNC_CMD_REGULAR}"              # Пользовательская команда синхронизации
CMD_CLOUD="${SYNC_CMD_REGULAR}"             # Серверная команда синхронизации

CLOUD_STAT_FILE="${DIR_SYNC}/status"        # Файл на сервере в коором находится глобальный статус сервера
CLOUD_STAT="${SYNC_CMD_REGULAR}"            # Дефолтный Статус сервера
CLOUD_STAT_CHECK="-"                        # Для отметки, что статус сервера прочитан и валиден



#
# Блок начальной инициализации переменных закончен
# -----------------------------------------------------------------------------
#



LINE_TOP_="╔═══════════════════════════════════════════════════════════════════════════════╗"
LINE_FREE="║                                                                               ║"
  #echo   "╟───────────────────────────────────────────────────────────────────────────────╢"
MSG_TO_UP="║                          Отправка на сервер...⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ⮭ ║"
MSG__DIV_="╟╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╢" 
MSG_TO_DN="║                          Загрузка с сервера...⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ⮯ ║"
LINE_BOT_="╚═══════════════════════════════════════════════════════════════════════════════╝"



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
#  Записывает в конфиг файл фрагмент этого же скрипта между строками, содержащими [КОНФИГ СТАРТ] и [КОНФИГ ЕНД] 
#  Используемые глобальные переменные $0 и $CONFIG_FILE
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
        # shellcheck disable=SC1091
        source "${CONFIG_FILE}"
    else
        save_config_file
    fi
}



print_version()
{
echo -e "$(cat << EOF
Version: ${VERSION}
Скрипт: ${APP_NAME}
Папка размещения: ${APP_PATH}

Последние изменения:
${LAST_CHANGES}

${COPYRIGHT}
EOF
)"
}



print_help()
{
echo -e "$(cat << EOF
${APP_TITLE}
Версия ${VERSION} | Host ${MY_NAME}
Использование:
    ${COLOR_USAGE}${APP_NAME}${COLOR_OFF}  [<локальная_папка>] [ $(str=$(IFS="|"; echo "${VALID_COMMANDS[*]:0:5}"); echo "${str//|/ | }";) ]
                                   [ $(str=$(IFS="|"; echo "${VALID_COMMANDS[*]:5:5}"); echo "${str//|/ | }";) ]
                                   [ $(str=$(IFS="|"; echo "${VALID_COMMANDS[*]:10}");  echo "${str//|/ | }";) ]
                                   По умолчанию: ${SYNC_CMD_REGULAR}

    ${COLOR_USAGE}${SYNC_CMD_REGULAR}${COLOR_OFF} -- действие по умолчанию.
                Запись данных на сервер (${SYNC_CMD_UP}) и скачивание данных с сервера (${SYNC_CMD_DL})
                без удаления расхождений. По сути, это двусторонее совмещение данных на сервере 
                и на локальном компьютере, с заменой старых файлов на новые по метке времени.

    ${COLOR_USAGE}${SYNC_CMD_UP}${COLOR_OFF}      -- Запись данных на сервер без удаления. Переписываются старые.

    ${COLOR_USAGE}${SYNC_CMD_DL}${COLOR_OFF}      -- Чтение данных с сервера без удаления. Переписываются старые.

    ${COLOR_USAGE}${SYNC_CMD_DL_INIT}${COLOR_OFF} -- Загрузка данных с сервера на локальный хост 
                   с полным удалением расхождений на локальном хосте.

    ${COLOR_USAGE}${SYNC_CMD_UP_INIT}${COLOR_OFF} -- Запись данных с локального хоста на сервер 
                с полным удалением расхождений на сервере, и установка для всех хостов 
                статуса ${SYNC_CMD_DL_INIT} для обязательной загрузки изменений.

    ${COLOR_USAGE}${SYNC_CMD_PAUSE}${COLOR_OFF}   -- Обмен данными не происходит. Режим используется для изменений данных 
                на сервере. Никакая команда с сервера ничего не скачивает. 
                Изменение в структуре файлов можно проводить прямо на сервере (поскольку доступ 
                по ssh у вас есть), или в локальной папке у вас на компе, после чего можно отправить 
                изменения на сервер командой ${COLOR_USAGE}${SYNC_CMD_UP_EDIT}${COLOR_OFF}, которая, собственно, 
                только для этого и предназначена.

    ${COLOR_USAGE}${SYNC_CMD_UP_EDIT}${COLOR_OFF} -- Отправляет данные на сервер с удалением расхождений на стороне сервера.
                Работает только если статус сервера ${COLOR_USAGE}${SYNC_CMD_PAUSE}${COLOR_OFF}. 
                Работает как ${COLOR_USAGE}${SYNC_CMD_UP_INIT}${COLOR_OFF} только НЕ изменяет статус синхронизации для клиентов.

    ${COLOR_USAGE}${SYNC_CMD_UNPAUSE}${COLOR_OFF} -- Обмен данными не происходит.
                Для всех хостов устанавливается статус ${COLOR_USAGE}${SYNC_CMD_DL_INIT}${COLOR_OFF} для обязательной загрузки изменений.
                Используется для выхода из режима ${COLOR_USAGE}${SYNC_CMD_PAUSE}${COLOR_OFF}.

    ${COLOR_USAGE}${SHOW_DEST}${COLOR_OFF} -- Показать строку из файла '${FILE_DEST}'.
                   Это адрес размещения папки на облачном сервере. Обычно вида 'user@host:/путь/папка'.

    ${COLOR_USAGE}${SHOW_CLOUD_STAT}${COLOR_OFF} -- Показать статус сервера для этой папки.
                Это значение из файла '${CLOUD_STAT_FILE}' на сервере.
                Возможные значения: ${VALID_CLOUD_STATS[*]} 
                Если файл отсутствует, то считается что статус сервера '${SYNC_CMD_REGULAR}'
                Если статус сервера '${SYNC_CMD_PAUSE}', то обмен данными не происходит.

    ${COLOR_USAGE}${SHOW_CLOUD_CMD}${COLOR_OFF} -- Показать команду сервера для этой папки

    Немного про статусы и команды сервера:
        Статус сервера -- показывает общую команду для всех клиентов, не зависимо от клиентских 
        команд, в том числе и для новых клиентов, для которых команда сервера не определена.
        
        Команда сервера -- показывает для конкретного клиента, что он должен сделать. 
        Для разных клиентов эти команды могут отличаться.

        К примеру: Если вы отправили команду ${SYNC_CMD_UP_INIT}, то всем клиентам
        будет установлена команда ${SYNC_CMD_DL_INIT}. 
        Когда клиент в следующий раз синхронизируется, он увидит команду ${SYNC_CMD_DL_INIT}. 
        После выполнения этой команды на сервере для этого клиента будет установлен статус '${SYNC_CMD_REGULAR}',
        а для всех остальных клиентов статус останется '${SYNC_CMD_DL_INIT}'.

        Возможные статусы сервера: ${VALID_CLOUD_STATS[*]} 
        Возможные команды сервера: ${VALID_CLOUD_COMMANDS[*]} 

        Если статус сервера '${SYNC_CMD_PAUSE}', то обмен данными не происходит.
        В этом режиме можно только отправлять данные на сервер командой '${SYNC_CMD_UP_EDIT}',
        или менять команду сервера на '${SYNC_CMD_UNPAUSE}', которая при следующей синхронизации
        установит всем клиентам статус '${SYNC_CMD_DL_INIT}' для обязательной загрузки изменений.

    ${COLOR_USAGE}${SHOW_TEST}${COLOR_OFF}    -- Тестирует настройки синхронизатора.
                Обмен данными не происходит. 
                Только проверяет и показывает локальную структуру 
                и проверяет доступ к папке на сервере. 

    ${COLOR_USAGE}${SHOW_LOG}${COLOR_OFF} [<количество_строк>]
                Показывает указанное количество строк из лог-файла. По умолчанию количество = ${LOG_COUNT_ROWS}

    ${COLOR_USAGE}${SYNC_CMD_CLOUD_UP_INIT}${COLOR_OFF} <user@host:/путь/облачная_папка>
                -- Создаёт sync-репозиторий из текущей папки.
                <удалённая_папка> -- папка на сервере, которая будет облачным хранилищем
                Обычно вида 'user@host:/путь/папка' (без слэша "/" в конце!)
                Локальная_папка используется текущая '.'
                Действия:
                1. Создаёт в <локальной_папке> папку '${DIR_SYNC}'
                    Создаёт файл '${FILE_EXCLUDES}' (Файл исключений для rsync)
                    Создаёт файл '${FILE_DEST}' внутрь которого записывает облачный адрес
                    Создаёт файл '${DIR_SYNC}/${MY_NAME}' внутрь которого записывает статус '${SYNC_CMD_REGULAR}'
                2. Копируем '<локальную_папку>/${DIR_SYNC}' на сервер в папку <удалённая_папка>/
                3. Выполняет обычную синхронизацию [${SYNC_CMD_REGULAR}] для записи данных на сервер.

${COLOR_INFO}Разумеется, классика:${COLOR_OFF} 

    Все команды можно использовать в связке с указанием локальной папки.
    Например: ${COLOR_USAGE}${APP_NAME} /home/user/Документы ${SYNC_CMD_UP}${COLOR_OFF}
         или: ${COLOR_USAGE}${APP_NAME} /home/user/Документы${COLOR_OFF}
         или: ${COLOR_USAGE}${APP_NAME} .${COLOR_OFF}
         или: ${COLOR_USAGE}${APP_NAME} ${SYNC_CMD_REGULAR}${COLOR_OFF}
    Если папка не указана, то используется текущая папка (по умолчанию: '${DIR_LOCAL_DEFAULT}').

    ${COLOR_USAGE}--usage${COLOR_OFF}     | ${COLOR_USAGE}-u${COLOR_OFF}    Показать краткое использование
    ${COLOR_USAGE}--help${COLOR_OFF}      | ${COLOR_USAGE}-h${COLOR_OFF}    Показать эту подсказку
    ${COLOR_USAGE}--version${COLOR_OFF}   | ${COLOR_USAGE}-v${COLOR_OFF}    Показать версию
    ${COLOR_USAGE}--edit-conf${COLOR_OFF} | ${COLOR_USAGE}-e${COLOR_OFF}    Редактирование конфига ${COLOR_FILENAME}${CONFIG_FILE}${COLOR_OFF}
                        Программа для редактирования может быть указана в конфиге строкой вида: 
                        EDITOR=<Программа>
                        Путь к программе-редактору должен быть без пробелов. 
                        Или укажите программу без пути, если она есть в PATH

${COLOR_INFO}При добавлении скрипта в crontab${COLOR_OFF} нужно добавить в cron-скрипт переменные окружения, 
    которые нужны этому скрипту, и которые отсутсвуют при выполнении скрипта 
    не в пользовательском окружении: cron, systemd, или другой фоновый запуск.
    примерно так:

    ${COLOR_CODE}USER=${USER}
    HOME=${HOME}
    PATH=/usr/local/bin:/usr/bin:/bin:${HOME}/bin:${HOME}/.local/bin
    SHELL=/bin/bash
    BASH_ENV=${HOME}/.bashrc

    1  *  *  *  *    ${HOME}/bin/${APP_NAME} папка${COLOR_OFF}

    для контроля исполнения скрипта можно добавить логирование работы самого скрипта:
    ${COLOR_CODE}1  *  *  *  *    ${HOME}/bin/${APP_NAME} папка >> ${HOME}/sync_all_cron.log 2>&1${COLOR_OFF}

${COLOR_INFO}Если вы используете SELinux, то могут быть проблемы с доступом к ssh${COLOR_OFF}
    из-за ограничений безопасности.
    В этом случае можно временно отключить SELinux командой:
    ${COLOR_CODE}sudo setenforce 0${COLOR_OFF} (очень плохая идея с точки зрения безопасности)
    или настроить SELinux на разрешение доступа к ssh.
    Подробнее в интернете по запросу: ${COLOR_CODE}SELinux ssh access${COLOR_OFF}
    Суть ограничений SELinux в том, что запрещён доступ по ssh напрямую к администраторской учётной записи.
    Административный доступ будет доступен только после подключения через ограниченную, непривилегированную 
    учётную запись с последующим переходом на root через sudo.

${COLOR_INFO}Если вы используете файрвол, то могут быть проблемы с доступом к ssh${COLOR_OFF}
    из-за ограничений безопасности.
    В этом случае нужно разрешить доступ к ssh.
    Подробнее в интернете по запросу:
    ${COLOR_CODE}firewall ssh access${COLOR_OFF}

${COPYRIGHT}
EOF
)"
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

printf "%b\n" "\
${APP_TITLE}
Использование: ${COLOR_USAGE}${APP_NAME} [папка | число_строк | cloud_path] [команда]${COLOR_OFF}
    ${COLOR_USAGE}[папка]${COLOR_OFF}         — путь к локальной папке (по умолчанию: .)
    ${COLOR_USAGE}[число_строк]${COLOR_OFF}   — только для команды ${SHOW_LOG} (по умолчанию: ${LOG_COUNT_ROWS})
    ${COLOR_USAGE}[cloud_path]${COLOR_OFF}    — путь вида user@host:/path/to/cloud_folder (только для ${SYNC_CMD_CLOUD_UP_INIT})
    ${COLOR_USAGE}[команда]${COLOR_OFF}       — одна из: [ ${str1} ]
                             [ ${str2} ]
                             [ ${str3} ]
                             [ ${str4} ]
                             По умолчанию: ${SYNC_CMD_REGULAR}
    ${COLOR_USAGE}--usage${COLOR_OFF}     | ${COLOR_USAGE}-u${COLOR_OFF}    Показать краткое использование
    ${COLOR_USAGE}--help${COLOR_OFF}      | ${COLOR_USAGE}-h${COLOR_OFF}    Показать эту подсказку
    ${COLOR_USAGE}--version${COLOR_OFF}   | ${COLOR_USAGE}-v${COLOR_OFF}    Показать версию
    ${COLOR_USAGE}--edit-conf${COLOR_OFF} | ${COLOR_USAGE}-e${COLOR_OFF}    Редактирование конфига

${COPYRIGHT}
"
}



#
#  Вывод последних сообщений этого скрипта из системного лога
#
print_syslog() {
    local count="${1:-${LOG_COUNT_ROWS}}"
    # journalctl -p info --since "2 days ago" | grep -- "$LOG_PREFIX" || true | tail -n "$count"
    # journalctl -t "${LOG_PREFIX}" --since "2 days ago" || true | tail -n "$count"
    journalctl -t "${LOG_PREFIX}" -n "$count"

}



#
#  Обёртка для ssh
#   $1 -- host вида user@host
#   $2 -- Команда выполняемая на удалённом хосте
#
ssh_exec() 
{
    local host="${1:?ssh_exec: укажите хост вида 'user@host'}"
    shift
    ssh -p "${SSH_PORT:?SSH_PORT не задан}" -o BatchMode=yes "$host" "$@"
}



#
# Проверяет доступ к хосту, 
# наличие папки cloud_dir и 
# доступность записи в папку cloud_dir
# Входные данные:
#   $1 -- Строка вида user@host:/path/to/cloud_dir
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


    # Сначала проверяем доступ на запись
    if ssh_exec "${user_host}" "touch \"${remote_path}/${test_file}\" && rm -f \"${remote_path}/${test_file}\"" 2>/dev/null; then
        # echo "Папка ${remote_path} на хосте ${user_host} доступна для записи"
        return 0
    fi

    echo "Ошибка: нет доступа на запись в [${user_host}:${remote_path}]"

    # Проверяем доступность хоста (ssh)
    if ssh_exec "${user_host}" "true" >/dev/null 2>&1; then
        echo "Доступ к хосту ${user_host} есть"
    else
        echo "Нет доступа к хосту ${user_host}"
    fi

    # Проверяем наличие папки
    if ssh_exec "${user_host}" "test -d '${remote_path}'"; then
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
# Проверяет, что переданное значение cloud_cmd допустимо
#   $1 -- значение команды сервера
# Возвращает:
#   0 -- если значение допустимо
#   1 -- если значение недопустимо
# Правильные значения команд перечислены в массиве VALID_CLOUD_COMMANDS
#
validate_cloud_cmd() 
{
    local cloud_cmd="${1:?validate_cloud_cmd: укажите значение команды}"

    for cmd in "${VALID_CLOUD_COMMANDS[@]}"; do
        if [[ "$cloud_cmd" == "$cmd" ]]; then
            return 0
        fi
    done

    # Если дошли сюда — значение не найдено
    log_error "Недопустимая команда сервера: [$cloud_cmd]"
    return 1
}



#
# Проверяет, что переданное значение cloud_stat допустимо
#   $1 -- значение статуса сервера
# Возвращает:
#   0 -- если значение допустимо
#   1 -- если значение недопустимо
# Правильные значения статусов перечислены в массиве VALID_CLOUD_STATS
#
validate_cloud_stat() 
{
    local cloud_stat="${1:?validate_cloud_stat: укажите значение статуса}"

    for cmd in "${VALID_CLOUD_STATS[@]}"; do
        if [[ "$cloud_stat" == "$cmd" ]]; then
            return 0
        fi
    done

    # Если дошли сюда — значение не найдено
    log_error "Недопустимый статус сервера: [$cloud_stat]"
    return 1
}



#
# Получение глобального статуса сервера
# Использует глобальные переменные:
#   DIR_CLOUD
# Результат записывает в переменную: 
#   CLOUD_STAT
#
get_cloud_stat() 
{

    local cloud_url="${DIR_CLOUD}"
    local cloud_host="${cloud_url%%:*}"
    local cloud_path="${cloud_url#*:}"
    local status

    # Проверка корректности user@host
    if [[ ! "${cloud_host}" =~ ^[^@]+@[^@]+$ ]] || [ -z "${cloud_path}" ]; then
        exit_with_msg "Неверный облачный путь: [${cloud_url}]" 1
    fi

    status=$(ssh_exec "${cloud_host}" cat "${cloud_path}/${CLOUD_STAT_FILE}" 2>/dev/null) || {
        log_error "Не удалось прочитать статус сервера ${cloud_path}/${CLOUD_STAT_FILE}"
        CLOUD_STAT_CHECK="-"
        return 1
    }

    # Проверка корректности статуса
    if ! validate_cloud_stat "${status}"; then
        exit_with_msg "get_cloud_stat: Недопустимый статус сервера: [${status}]" 1
    fi

    CLOUD_STAT_CHECK="√"
    CLOUD_STAT="${status}"
}



#
# Установка глобального статуса сервера
# Использует глобальные переменные:
#   DIR_CLOUD
# Записывает указанный статус в файл статуса на сервере
#   $1 -- статус (строка, которая будет записана в user@host:/path/to/cloud_dir/.sync/status)
#
set_cloud_stat()
{
    local new_stat="${1:?set_cloud_stat: укажите значение статуса}"
    local cloud_url="${DIR_CLOUD}"
    local cloud_host="${cloud_url%%:*}"
    local cloud_path="${cloud_url#*:}"

    # Проверка корректности статуса
    if ! validate_cloud_stat "${new_stat}"; then
        exit_with_msg "set_cloud_stat: Недопустимый статус сервера: [${new_stat}]" 1
    fi

    # Проверка корректности user@host
    if [[ ! "${cloud_host}" =~ ^[^@]+@[^@]+$ ]] || [ -z "${cloud_path}" ]; then
        exit_with_msg "Неверный облачный путь: [${cloud_url}]" 1
    fi

    # Проверка наличия каталога .sync
    if ! ssh_exec "${cloud_host}" "test -d '${cloud_path}/${DIR_SYNC}'"; then
        exit_with_msg "set_cloud_stat: Ошибка: каталог '${cloud_path}/${DIR_SYNC}' не найден на хосте ${cloud_host}" 1
    fi

    # Пишем статус в файл
    if ! ssh_exec "${cloud_host}" "echo '${new_stat}' > '${cloud_path}/${CLOUD_STAT_FILE}'"; then
        exit_with_msg "set_cloud_stat: Ошибка записи статуса в '${cloud_path}/${CLOUD_STAT_FILE}' на хосте ${cloud_host}" 1
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
# Находит и устанавливает путь к корневой синхронизируемой папке DIR_LOCAL
# Использует глобальные переменные:
#       DIR_LOCAL, DIR_SYNC
# Результат пишет в переменные:
#       DIR_LOCAL
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
# Инициализируются переменные 
#       CMD_TRANSFER_SERV 
#       CMD_TRANSFER_DATA 
# должны инициализироваться только после parse_args(), 
# поскольку именно там инициализируется переменная DIR_LOCAL
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

    log_info "ACT DL START: [${LOCAL}] -> [${DEST}]"
    if [ "${TYPE_TRANSFER}" = "${SYNC_TYPE_SERVICE}" ]; then
        # echo "Сервисное копирование"
        "${CMD_TRANSFER_SERV[@]}" "${LOCAL}" "${DEST}"
    else
        # echo "Копирование данных"
        "${CMD_TRANSFER_DATA[@]}" "${LOCAL}" "${DEST}"
    fi
    log_info "ACT DL END: [$LOCAL] -> [$DEST]"
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

    log_info "ACT DL_INIT START: [$LOCAL] -> [$DEST]"

    "${CMD_TRANSFER_DATA[@]}" --delete "${LOCAL}" "${DEST}"

    log_info "ACT DL_INIT END: [$LOCAL] -> [$DEST]"
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
    dl "$LOCAL" "$DEST" "${SYNC_TYPE_DATA}" || exit_with_msg  "sync_regular: Ошибка при выполнении dl '$LOCAL' '$DEST' '${SYNC_TYPE_DATA}'" 1

    echo   "${MSG__DIV_}"
    echo   "${MSG_TO_DN}"
    dl "$DEST"  "$LOCAL" "${SYNC_TYPE_DATA}" || exit_with_msg "sync_regular: Ошибка при выполнении dl '$DEST' '$LOCAL' '${SYNC_TYPE_DATA}'" 1
}



#
# В локальной папке создает папку .sync
# и в ней создаст файл имени этого хоста $MY_NAME (USER_<hostname>)
# для последующей регистрации на удаленном хосте
#
init_local()
{
    local STATUS="${1:?init_local CMD не передана или пуста. Это программная ошибка скрипта.}"
    echo "INIT_LOCAL: Создание файла ${DIR_LOCAL}/${DIR_SYNC}/${MY_NAME}"
    touch "${DIR_LOCAL}/${DIR_SYNC}/${MY_NAME}" || \
        exit_with_msg "init_local(${STATUS}): По какой-то причине не удалось создать/обновить файл '${DIR_LOCAL}/${DIR_SYNC}/${MY_NAME}'" 1
    echo "${STATUS}"  > "${DIR_LOCAL}/${DIR_SYNC}/${MY_NAME}"
}



#
# Регистрация MY_NAME на сервере
# 
# Копирует файл ${MY_NAME} на сервер в ${DIR_CLOUD}/${DIR_SYNC}/${MY_NAME}
# Файл ${DIR_LOCAL}/${DIR_SYNC}/${MY_NAME} должен быть и иметь внутри команду сервера.
#
# Используемые глобальные переменные:
#       ${DIR_CLOUD}  —  путь вида user@host:/path/to/cloud
#       ${DIR_SYNC}   —  имя служебной папки (.sync)
#       ${MY_NAME}    —  имя текущего компьютера (например, USER_myhost)
#
init_dest()
{
    local cloud_url="${DIR_CLOUD:?init_dest: переменная DIR_CLOUD не задана}"
    local cloud_host="${cloud_url%%:*}"
    local cloud_path="${cloud_url#*:}"
    local local_file="${DIR_LOCAL:?init_dest: DIR_LOCAL не задан}/${DIR_SYNC:?init_dest: DIR_SYNC не задан}/${MY_NAME:?init_dest: MY_NAME не задан}"

    log_info "INIT_DEST: Регистрация компьютера в ${cloud_url}/${DIR_SYNC}/${MY_NAME}"

    # Проверка формата cloud_url
    if [[ ! "${cloud_host}" =~ ^[^@]+@[^@]+$ ]] || [ -z "${cloud_path}" ]; then
        exit_with_msg "init_dest: Неверный формат DIR_CLOUD: [${cloud_url}]" 1
    fi

    # Проверяем наличие каталога ${DIR_SYNC} на сервере (ошибка, если нет)
    if ! ssh_exec "${cloud_host}" test -d "${cloud_path}/${DIR_SYNC}"; then
        exit_with_msg "init_dest: Каталог '${cloud_path}/${DIR_SYNC}' не найден на сервере ${cloud_host}" 1
    fi

    # Проверяем, что локальный файл с именем компьютера существует
    if [ ! -f "${local_file}" ]; then
        exit_with_msg "init_dest: Локальный файл '${local_file}' не найден" 1
    fi

    # Копирование на сервер локального файла ${MY_NAME}
    dl  "${local_file}" \
        "${cloud_url}/${DIR_SYNC}/${MY_NAME}" \
        "${SYNC_TYPE_SERVICE}" || \
        exit_with_msg "init_dest: Ошибка при передаче файла '${local_file}' на '${cloud_url}/${DIR_SYNC}/'" 1

    log_info "INIT_DEST: Успешно записан ${MY_NAME} в ${cloud_url}/${DIR_SYNC}/"
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
    echo -e "Установка статуса синхронизации в [${COLOR_STATUS}${STATUS}${COLOR_OFF}]... "
    echo -e "${STATUS}" > "${DIR_LOCAL}/${DIR_SYNC}/${MY_NAME}"
    touch   "${DIR_LOCAL}/${DIR_SYNC}/${MY_NAME}"
    dl      "${DIR_LOCAL}/${DIR_SYNC}/${MY_NAME}" "${DIR_CLOUD}/${DIR_SYNC}/${MY_NAME}" "${SYNC_TYPE_SERVICE}" || exit_with_msg  "set_status_my: Ошибка при выполнении dl \"${DIR_LOCAL}/${DIR_SYNC}/${MY_NAME}\" \"${DIR_CLOUD}/${DIR_SYNC}/${MY_NAME}\" \"${SYNC_TYPE_SERVICE}\"" 1
    echo -e " Выполнено."
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
#  Функция для проверки доступности записи в файл
#
check_file_access() {
    local logfile=${1:?}

    # Проверка доступности записи в файл
    if [ -w "$logfile" ]; then
        # ${VERB_MODE} && echo "Файл доступен для записи: $logfile"
        return 0
    fi

    # Если файл существует, но недоступен для записи
    if [ -e "$logfile" ]; then
        ${VERB_MODE} && echo "Файл существует, но недоступен для записи: $logfile"
        return 1
    fi

    # Файл не существует — проверим, существует ли директория
    local dir
    dir=$(dirname "$logfile")

    if [ -d "$dir" ]; then
        ${VERB_MODE} && echo "Файл '$logfile' не существует. Папка '$dir' существует."
        # Пробуем создать файл
        if touch "$logfile" 2>/dev/null; then
            ${VERB_MODE} && echo "Файл успешно создан: '$logfile'"
            if [ -w "$logfile" ]; then
                ${VERB_MODE} && echo "Файл '$logfile' теперь доступен для записи."
                return 0
            else
                ${VERB_MODE} && echo "Файл '$logfile' создан, но недоступен для записи."
                return 1
            fi
        else
            ${VERB_MODE} && echo "Не удалось создать файл: '$logfile'"
            return 1
        fi
    else
        ${VERB_MODE} && echo "Папка для файла не существует: '$dir'"
        return 1
    fi
}



#
# Считывает команду сервера для этого хоста и записывает её в переменную
#   CMD_CLOUD
# Если файла регистрации на сервере нет, то регистрирует, 
# предлагает перезапустить синхронизацию снова, завершает скрипт.
#
update_cloud_cmd()
{
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
}



#
# Проверка, заполнение и обновление путей и переменных
#       DIR_SYNC        # Проверка наличия папки синхронизатора
#       FILE_DEST       # файл, в котором записан адрес удаленного каталога
#       DIR_CLOUD       # Переменная содержащая удалённый адрес
#       CLOUD_STAT      # Переменная содержащая статус сервера
#       CMD_CLOUD       # Переменная содержащая команду синхронизации с сервера для клиента
#       FILE_EXCLUDES   # Файл исключений для rsync
#
update_sync_variables()
{
    #
    #  "Проверка служебной папки синхронизатора \"${DIR_LOCAL}/${DIR_SYNC}\"..."
    #

    # DIR_SYNC                  # папка параметров синхронизации
    if [ ! -d "${DIR_LOCAL}/${DIR_SYNC}" ]; then
        exit_with_msg   "${LINE_TOP_}\n"\
                        "${LINE_FREE}\n"\
                        "║      ОЩИБКА: Служебной папки синхронизатора нет.                              ║\n"\
                        "║              Возможно, вы указали не верную папку для синхронизации           ║\n"\
                        "║                                                                               ║\n"\
                        "$(printf "║      В папке для синхронизации нужно создать папку:        %-15s    ║\n" "${DIR_SYNC}")"\
                        "$(printf "║      файл, в котором записан адрес удаленного каталога:    %-15s    ║\n" "${FILE_DEST}")"\
                        "$(printf "║      файл со списком шаблонов исключений из синхронизации: %-15s    ║\n" "${FILE_EXCLUDES}")"\
                        "║                                                                               ║\n"\
                        "║              ЭТО КРИТИЧЕСКАЯ ОШИБКА.                                          ║\n"\
                        "${LINE_FREE}\n"\
                        "${LINE_BOT_}"\
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

    
    # CLOUD_STAT                # Считывает статус сервера
    get_cloud_stat

    # CMD_CLOUD                 # Команда синхронизации с сервера
    update_cloud_cmd

    # FILE_EXCLUDES             # Файл исключений для rsync
    if [ ! -f "${DIR_LOCAL}/${FILE_EXCLUDES}" ]; then
        echo -e         "╔═══════════════════════════════════════════════════════════════════════════════╗\n"\
                        "║                                                                               ║\n"\
              "$(printf "║      ОЩИБКА: Нет файла %-14s,                                        ║\n" "[ ${FILE_EXCLUDES} ]")"\
                        "║              в котором записаны исключения для rsync.                         ║\n"\
                        "║              Создаём дефолтный (из внутреннего массива).                      ║\n"\
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
#  Печат заголовка перед выполнением команды
#
do_sync_print_header()
{
        echo   "${TITLE}"
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
    local MSG="${1:-}"
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
    set_cloud_stat "${SYNC_CMD_REGULAR}"

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
    set_cloud_stat "${SYNC_CMD_PAUSE}"

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
    set_cloud_stat "${SYNC_CMD_REGULAR}"

    {   # Баннер
        echo   "${LINE_BOT_}"
    }
}



#
# Парсинг входных параметров:
#   Выполняет стравочные команды, просмотр логов и редактирования конфига
#   Устанавливает значения переменных:
#       CMD_USER
#       DIR_LOCAL
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
            -ec|--edit-conf)
                echo "Редактирование конфига: ${CONFIG_FILE}"
                exec ${EDITOR} "${CONFIG_FILE}"
                exit 0;
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
            -v|--verbose)
                VERB_MODE=$(true);
                ;;
                          


        esac

        # Проверка на правильность пользовательской команды
        for cmd_true in "${VALID_COMMANDS[@]}"; do
            if [[ "$arg" == "${cmd_true}" ]]; then
                CMD_USER="$arg"
                continue 2
            fi
        done

        # Проверка чтобы пользовательская папка была указана один раз
        if [[ $DIR_LOCAL_SET -eq 0 ]]; then
            DIR_LOCAL="$arg"
            DIR_LOCAL_SET=1
        else
            exit_with_msg "Ошибка: неизвестный параметр '$arg'" 2
        fi
    done

    # Проверка команды LOG и выполнние её
    if [[ "${CMD_USER}" == "${SHOW_LOG}" ]]; then
        if [[ ${DIR_LOCAL_SET} -eq 1 ]]; then
            if [[ "${DIR_LOCAL}" =~ ^[0-9]+$ ]]; then
                LOG_COUNT_ROWS="${DIR_LOCAL}"
                DIR_LOCAL="${DIR_LOCAL_DEFAULT}"
                print_syslog "${LOG_COUNT_ROWS}"
                exit 0
            else
                exit_with_msg "Ошибка: для команды LOG можно указать число строк, а не путь к папке." 2
            fi
        fi

    #
    # Проверка команды SHOW_DEST и выполнние её
    # 
    elif [[ "${CMD_USER}" == "${SHOW_DEST}" ]]; then
        # установить правильное значение DIR_LOCAL
        find_sync_dir
        #  Показать строку dest
        read -r DIR_CLOUD <"${DIR_LOCAL}/${FILE_DEST}" || exit_with_msg "Ошибка чтения '${DIR_LOCAL}/${FILE_DEST}'" 1
        echo "${DIR_CLOUD}"
        exit 0;

    #
    # Проверка команды CLOUD_UP_INIT и выполнние её
    # 
    elif [[ "${CMD_USER}" == "${SYNC_CMD_CLOUD_UP_INIT}" ]]; then
        if [[ ${DIR_LOCAL_SET} -eq 0 ]]; then
            exit_with_msg "Ошибка: необходимо указать путь для загрузки в облако (user@host:/путь/к/новая_папка)" 2
        fi

        DIR_CLOUD="${DIR_LOCAL}"
        DIR_LOCAL="."

        if ! validate_cloud_up_init "${DIR_CLOUD}"; then
            exit_with_msg "Ошибка: ${DIR_CLOUD} не прошла валидацию." 1
        fi

        # Создание репозитория на сервере из указанной локальной папки
        do_cloud_up_init
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
    DIR_LOCAL="$(get_abs_path "${DIR_LOCAL}")"
}



#
#
#
# =================================== MAIN ====================================
#
#
#



#
# Читает конфиг-файл.
# Если его нет, то создаёт.
#
read_config_file



#
# Парсинг входных параметров:
#   Выполняет стравочные команды, просмотр логов и редактирования конфига
#   Устанавливает значения переменных:
#       CMD_USER
#       DIR_LOCAL
#
parse_args "$@"



#
# Если CMD_USER в списке команд требующих синхронизацию, то вызываем find_sync_dir
# для правильной установки папки DIR_LOCAL
#
# for cmd_sync in "${COMMANDS_REQUIRING_SYNC[@]}"; do
#     if [[ "$CMD_USER" == "${cmd_sync}" ]]; then
#         find_sync_dir
#         break
#     fi
# done
#
# Если мы в этом месте скрипта, то далее в любом случает работаем с синхронизацией
# Так что, находим папку в любом случае
#
find_sync_dir



#
# Инициализируются переменные 
#       CMD_TRANSFER_SERV 
#       CMD_TRANSFER_DATA 
# должны инициализироваться только после parse_args(), 
# поскольку именно там инициализируется переменная DIR_LOCAL
# 
init_transfer_commands



#
# Проверка, заполнение и обновление путей и переменных
#       DIR_SYNC        # Проверка наличия папки синхронизатора
#       FILE_DEST       # файл, в котором записан адрес удаленного каталога
#       DIR_CLOUD       # Переменная содержащая удалённый адрес
#       CLOUD_STAT      # Переменная содержащая статус сервера
#       CMD_CLOUD       # Переменная содержащая команду синхронизации с сервера для клиента
#       FILE_EXCLUDES   # Файл исключений для rsync
#
update_sync_variables



#
# Обработка простых команд, требующих инициализации переменных
#
case "$CMD_USER" in
    "${SHOW_CLOUD_STAT}")
        #   Показывает статус сервера
        echo "${CLOUD_STAT}"
        exit 0;
        ;;
    "${SHOW_CLOUD_CMD}")
        #  Показать серверную команду
        echo "${CMD_CLOUD}"
        exit 0;
        ;;
esac



#
#  Проверка записи в лог-файл
#
if check_file_access "${DIR_LOCAL}/${LOG_FILE}"; then
    LOG_FILE_CHECK="√"
else
    LOG_FILE_CHECK="-"
fi



#
#
#
#   ===========================================================================
#   Дальше обрабатывается то, что нужно синхронизировать
#
#
#



TITLE=$(printf "%-50s" "${DIR_LOCAL}" | sed 's/ /═/g')
TITLE=$(printf "╔═════════════════%s════════════╗\n" "${TITLE}")

echo   "╔══════════════╤════════════════════════════════════════════════════════════════╗"
printf "║  STAT CLOUD  │  ${COLOR_STATUS}%-57s${COLOR_OFF}  ${CLOUD_STAT_CHECK}  ║\n" "${CLOUD_STAT}"
printf "║  CMD  CLOUD  │  ${COLOR_STATUS}%-57s${COLOR_OFF}  √  ║\n" "${CMD_CLOUD}"
printf "║  CMD  LOCAL  │  ${COLOR_STATUS}%-57s${COLOR_OFF}  √  ║\n" "${CMD_USER}"
printf "║  MY:         │  %-57s  √  ║\n" "${MY_NAME}"
printf "║  DIR CLOUD   │  %-57s  √  ║\n" "${DIR_CLOUD}"
printf "║  DIR LOCAL   │  %-57s  √  ║\n" "${DIR_LOCAL}"
printf "║  EXCLUDES    │  %-57s  √  ║\n" "${FILE_EXCLUDES}"
printf "║  TEMP        │  %-57s  √  ║\n" "${DIR_TEMP}"
printf "║  LOG (opt)   │  %-57s  ${LOG_FILE_CHECK}  ║\n" "${LOG_FILE}"
echo   "╚══════════════╧════════════════════════════════════════════════════════════════╝"



#
#   Если команда SHOW_TEST, то больше ничего делать не нужно.
#
if [[ "${CMD_USER}" == "${SHOW_TEST}" ]]; then
    echo "${SHOW_TEST} -- Ok."
    exit 0;
fi



log_info "BEG: $(date)"
log_info "VER: ${VERSION}"
log_info "CMD: $0 ${*@Q}"



#                          Таблица действий 
#                          в зависимости от 
#          статуса сервера, серверной команды и клиентской команды
#
#   ----------------    ----------------    ----------------    -------
#   SERVER STATUS       SERVER CMD          USER CMD            ACTION
#   ----------------    ----------------    ----------------    -------
#                       
#   SYNC_CMD_REGULAR    SYNC_CMD_REGULAR    SYNC_CMD_REGULAR    REGULAR
#   SYNC_CMD_REGULAR    SYNC_CMD_REGULAR    SYNC_CMD_UP         UP
#   SYNC_CMD_REGULAR    SYNC_CMD_REGULAR    SYNC_CMD_DL         DL
#   SYNC_CMD_REGULAR    SYNC_CMD_REGULAR    SYNC_CMD_UP_INIT    UP_INIT
#   SYNC_CMD_REGULAR    SYNC_CMD_REGULAR    SYNC_CMD_DL_INIT    DL_INIT
#   SYNC_CMD_REGULAR    SYNC_CMD_REGULAR    SYNC_CMD_PAUSE      PAUSE
#   SYNC_CMD_REGULAR    SYNC_CMD_REGULAR    SYNC_CMD_UP_EDIT    -
#   SYNC_CMD_REGULAR    SYNC_CMD_REGULAR    SYNC_CMD_UNPAUSE    -
#
#   SYNC_CMD_REGULAR    SYNC_CMD_DL_INIT    SYNC_CMD_REGULAR    DL_INIT
#   SYNC_CMD_REGULAR    SYNC_CMD_DL_INIT    SYNC_CMD_UP         -
#   SYNC_CMD_REGULAR    SYNC_CMD_DL_INIT    SYNC_CMD_DL         DL_INIT
#   SYNC_CMD_REGULAR    SYNC_CMD_DL_INIT    SYNC_CMD_UP_INIT    -
#   SYNC_CMD_REGULAR    SYNC_CMD_DL_INIT    SYNC_CMD_DL_INIT    DL_INIT
#   SYNC_CMD_REGULAR    SYNC_CMD_DL_INIT    SYNC_CMD_PAUSE      -
#   SYNC_CMD_REGULAR    SYNC_CMD_DL_INIT    SYNC_CMD_UP_EDIT    -
#   SYNC_CMD_REGULAR    SYNC_CMD_DL_INIT    SYNC_CMD_UNPAUSE    -
#
#   SYNC_CMD_REGULAR    SYNC_CMD_PAUSE      SYNC_CMD_REGULAR    ERR
#   SYNC_CMD_REGULAR    SYNC_CMD_PAUSE      SYNC_CMD_UP         ERR
#   SYNC_CMD_REGULAR    SYNC_CMD_PAUSE      SYNC_CMD_DL         ERR
#   SYNC_CMD_REGULAR    SYNC_CMD_PAUSE      SYNC_CMD_UP_INIT    ERR
#   SYNC_CMD_REGULAR    SYNC_CMD_PAUSE      SYNC_CMD_DL_INIT    ERR
#   SYNC_CMD_REGULAR    SYNC_CMD_PAUSE      SYNC_CMD_PAUSE      ERR
#   SYNC_CMD_REGULAR    SYNC_CMD_PAUSE      SYNC_CMD_UP_EDIT    ERR
#   SYNC_CMD_REGULAR    SYNC_CMD_PAUSE      SYNC_CMD_UNPAUSE    ERR
#
#   ----------------    ----------------    ----------------    -------
#   SERVER STATUS       SERVER CMD          USER CMD            ACTION
#   ----------------    ----------------    ----------------    -------
#
#   SYNC_CMD_PAUSE      SYNC_CMD_REGULAR    SYNC_CMD_REGULAR    -
#   SYNC_CMD_PAUSE      SYNC_CMD_REGULAR    SYNC_CMD_UP         -
#   SYNC_CMD_PAUSE      SYNC_CMD_REGULAR    SYNC_CMD_DL         -
#   SYNC_CMD_PAUSE      SYNC_CMD_REGULAR    SYNC_CMD_UP_INIT    -
#   SYNC_CMD_PAUSE      SYNC_CMD_REGULAR    SYNC_CMD_DL_INIT    -
#   SYNC_CMD_PAUSE      SYNC_CMD_REGULAR    SYNC_CMD_PAUSE      SYNC_CMD_PAUSE
#   SYNC_CMD_PAUSE      SYNC_CMD_REGULAR    SYNC_CMD_UP_EDIT    SYNC_CMD_UP_EDIT, SYNC_CMD_PAUSE
#   SYNC_CMD_PAUSE      SYNC_CMD_REGULAR    SYNC_CMD_UNPAUSE    -
#
#   SYNC_CMD_PAUSE      SYNC_CMD_DL_INIT    SYNC_CMD_REGULAR    -
#   SYNC_CMD_PAUSE      SYNC_CMD_DL_INIT    SYNC_CMD_UP         -
#   SYNC_CMD_PAUSE      SYNC_CMD_DL_INIT    SYNC_CMD_DL         -
#   SYNC_CMD_PAUSE      SYNC_CMD_DL_INIT    SYNC_CMD_UP_INIT    -
#   SYNC_CMD_PAUSE      SYNC_CMD_DL_INIT    SYNC_CMD_DL_INIT    -
#   SYNC_CMD_PAUSE      SYNC_CMD_DL_INIT    SYNC_CMD_PAUSE      SYNC_CMD_PAUSE
#   SYNC_CMD_PAUSE      SYNC_CMD_DL_INIT    SYNC_CMD_UP_EDIT    SYNC_CMD_UP_EDIT, SYNC_CMD_PAUSE
#   SYNC_CMD_PAUSE      SYNC_CMD_DL_INIT    SYNC_CMD_UNPAUSE    -
#
#   SYNC_CMD_PAUSE      SYNC_CMD_PAUSE      SYNC_CMD_REGULAR    -
#   SYNC_CMD_PAUSE      SYNC_CMD_PAUSE      SYNC_CMD_UP         -
#   SYNC_CMD_PAUSE      SYNC_CMD_PAUSE      SYNC_CMD_DL         -
#   SYNC_CMD_PAUSE      SYNC_CMD_PAUSE      SYNC_CMD_UP_INIT    -
#   SYNC_CMD_PAUSE      SYNC_CMD_PAUSE      SYNC_CMD_DL_INIT    -
#   SYNC_CMD_PAUSE      SYNC_CMD_PAUSE      SYNC_CMD_PAUSE      -
#   SYNC_CMD_PAUSE      SYNC_CMD_PAUSE      SYNC_CMD_UP_EDIT    SYNC_CMD_UP_EDIT
#   SYNC_CMD_PAUSE      SYNC_CMD_PAUSE      SYNC_CMD_UNPAUSE    SYNC_CMD_UNPAUSE



case "${CLOUD_STAT}" in
    # CLOUD_STAT
    "${SYNC_CMD_REGULAR}")
        case "${CMD_CLOUD}" in
            # CMD_CLOUD
            "${SYNC_CMD_REGULAR}")
                case "${CMD_USER}" in
                    # CMD_USER
                    "${SYNC_CMD_REGULAR}")
                        do_sync_regular
                        ;;
                    # CMD_USER
                    "${SYNC_CMD_UP}")
                        do_sync_up
                        ;;
                    # CMD_USER
                    "${SYNC_CMD_DL}")
                        do_sync_dl
                        ;;
                    # CMD_USER
                    "${SYNC_CMD_UP_INIT}")
                        do_sync_up_init
                        ;;
                    # CMD_USER
                    "${SYNC_CMD_DL_INIT}")
                        do_sync_dl_init
                        ;;
                    # CMD_USER
                    "${SYNC_CMD_PAUSE}")
                        do_sync_pause
                        ;;
                    # CMD_USER
                    "${SYNC_CMD_UP_EDIT}"|"${SYNC_CMD_UNPAUSE}")
                        exit_with_msg "Эти команды можно отправлять только если сервер в статусе [${SYNC_CMD_PAUSE}]" 2
                        ;;
                    # CMD_USER
                    *)
                        exit_with_msg "Необработанная ситуация: USER: [${CMD_USER}] | CLOUD: [${CMD_CLOUD}]\nОбратитесь к разработчикам." 2
                        ;;
                esac
                ;;
            # CMD_CLOUD
            "${SYNC_CMD_DL_INIT}")
                case "${CMD_USER}" in
                    # CMD_USER
                    "${SYNC_CMD_REGULAR}"|"${SYNC_CMD_DL}"|"${SYNC_CMD_DL_INIT}")
                        do_sync_dl_init "ТРЕБОВАНИЕ СЕРВЕРА:"
                        ;;
                    # CMD_USER
                    "${SYNC_CMD_UP}"|"${SYNC_CMD_UP_INIT}"|"${SYNC_CMD_PAUSE}"|"${SYNC_CMD_UP_EDIT}"|"${SYNC_CMD_UNPAUSE}")
                        echo -e "При статусе сервера ${SYNC_CMD_DL_INIT} отправка данных на сервер запрещена.\nСперва нужно скачать данные.\nДейстий нет."
                        ;;
                    # CMD_USER
                    *)
                        exit_with_msg "Необработанная ситуация: CLOUD: [${CMD_CLOUD}] и USER: [${CMD_USER}]\nОбратитесь к разработчикам." 2
                        ;;
                esac
                ;;
            # CMD_CLOUD
            "${SYNC_CMD_PAUSE}")
                # 5 -- Ошибка синхронизации или состояния
                exit_with_msg "Недопустимое состояние: \nСтатус сервера: [${CLOUD_STAT}] -- Команда сервера: [${CMD_CLOUD}].\nОбратитесь к разработчикам." 5
                ;;
            # CMD_CLOUD
            *)
                exit_with_msg "Необработанная ситуация: CLOUD: [${CMD_CLOUD}]\nОбратитесь к разработчикам." 2
                ;;
        esac
        ;;
    # CLOUD_STAT
    "${SYNC_CMD_PAUSE}")
        case "${CMD_CLOUD}" in
            # CMD_CLOUD
            "${SYNC_CMD_PAUSE}")
                case "${CMD_USER}" in
                    # CMD_USER
                    "${SYNC_CMD_REGULAR}"|"${SYNC_CMD_UP}"|"${SYNC_CMD_DL}"|"${SYNC_CMD_UP_INIT}"|"${SYNC_CMD_DL_INIT}"|"${SYNC_CMD_PAUSE}")
                        echo -e "При статусе сервера ${SYNC_CMD_PAUSE} обмен данными запрещён."
                        echo -e "Доступны команды редактирования данных ${SYNC_CMD_UP_EDIT}"
                        echo -e "и снятия с паузы ${SYNC_CMD_UNPAUSE}.\nДейстий нет."
                        ;;
                    # CMD_USER
                    "${SYNC_CMD_UP_EDIT}")
                        do_sync_up_edit
                        ;;
                    # CMD_USER
                    "${SYNC_CMD_UNPAUSE}")
                        do_sync_unpause
                        ;;
                    # CMD_USER
                    *)
                        exit_with_msg "Необработанная ситуация: STAT: [${CLOUD_STAT}] -- CLOUD: [${CMD_CLOUD}] -- USER: [${CMD_USER}]\nОбратитесь к разработчикам." 2
                        ;;
                esac
                ;;
            *)
                case "${CMD_USER}" in
                    # CMD_USER
                    "${SYNC_CMD_PAUSE}")
                        do_sync_pause
                        ;;
                    # CMD_USER
                    "${SYNC_CMD_UP_EDIT}")
                        do_sync_up_edit
                        do_sync_pause
                        ;;
                    # CMD_USER
                    "${SYNC_CMD_UNPAUSE}")
                        do_sync_unpause
                        ;;
                    # CMD_USER
                    *)
                    # 5 -- Ошибка синхронизации или состояния
                    exit_with_msg "Недопустимое состояние: \nСтатус сервера: [${CLOUD_STAT}] -- Команда сервера: [${CMD_CLOUD}].\nОбратитесь к разработчикам." 5
                    ;;
                esac
                ;;
        esac
        ;;
    # CLOUD_STAT
    *)
        # 5 -- Ошибка синхронизации или состояния
        exit_with_msg "Неизвестный статус сервера: [${CLOUD_STAT}].\nОбратитесь к разработчикам." 5 
        ;;
esac

log_info "END: $(date)"
