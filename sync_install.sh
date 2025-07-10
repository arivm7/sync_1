#!/usr/bin/env bash
set -euo pipefail



APP_TITLE="Инсталятор персонального синхронизатора sync_1"
VERSION="1.4.0 (2025-07-10)"
APP_NAME=$(basename "$0")
LAST_CHANGES="\
v1.3.0 (2025-04-29): Добавление установки зависимостей.
v1.3.1 (2025-05-25): Переделывание установки зависимостей
v1.4.0 (2025-07-10): Поддержка установки sync_watcher
"



SYNC_CONFIG_DIRNAME="sync"
SYNC_CONFIG_PATH="${XDG_CONFIG_HOME:-${HOME}/.config}/${SYNC_CONFIG_DIRNAME:+${SYNC_CONFIG_DIRNAME}}"


# shellcheck disable=SC2034
{
    COLOR_USAGE="\e[1;32m"            # Терминальный цвет для вывода переменной статуса
    COLOR_OK="\e[0;32m"                 # Терминальный цвет для вывода Успешного сообщения
    COLOR_ERROR="\e[0;31m"              # Терминальный цвет для вывода ошибок
    COLOR_INFO="\e[0;34m"             # Терминальный цвет для вывода информации (об ошибке или причине выхода)
    COLOR_FILENAME="\e[1;36m"         # Терминальный цвет для вывода имён файлов
    COLOR_OFF="\e[0m"                   # Терминальный цвет для сброса цвета
}



echo "SYNC INSTALLER VER: ${VERSION}"



#
# Обязательные зависимости в виде ассоциаливного массива
# [программа]=пакет
# где "программа" -- собственно сама исполняемая програма
#     "пакет"     -- пакет внутри которого находится эта программа 
#                    для установки в систму
# shellcheck disable=SC2034
declare -A DEPENDENCIES_REQUIRED=(
    ["rsync"]="rsync"
    ["ssh"]="openssh-client"
    ["tar"]="tar"
    ["du"]="coreutils"
    ["df"]="coreutils"
    ["awk"]="gawk"
    ["gzip"]="gzip"
)

#
# Рекомендованные зависимости в виде ассоциаливного массива
# [программа]=пакет
# где "программа" -- собственно сама исполняемая програма
#     "пакет"     -- пакет внутри которого находится эта программа 
#                    для установки в систму
# shellcheck disable=SC2034
declare -A DEPENDENCIES_OPTIONAL=(
    ["pv"]="pv"
    ["figlet"]="figlet"
    ["realpath"]="coreutils"
    ["readlink"]="coreutils"
    ["inotifywait"]="inotify-tools"
    ["envsubst"]="gettext"
)



# Список имен файлов скриптов для копирования
# shellcheck disable=SC2034
scripts_files=(
sync_1.sh
sync_all.sh
sync_1_aliases.sh
sync_backuper.sh
sync_watcher.sh
)

# папка назначения для копирования скриптов
scripts_to="${HOME}/bin"



# Список имен файлов .desktop для копирования
# shellcheck disable=SC2034
icon_files=(
img/sync_1.icon.svg
img/sync_1_up.icon.svg
)

# папка назначения для копирования скриптов
icon_to="${HOME}/.local/share/icons/sync"



# # Лист-файл для массовой синхронизации
# SYNC_ALL_LIST_FILE="sync_all.list"
# # Лист-файл для бакапера
# SYNC_BACKUPER_LIST="sync_backuper.list"
# # Лист-файл для автосихронизатора
# SYNC_WATCHER_LIST="sync_watcher.list"

# Список лист-файлов для копирования
# shellcheck disable=SC2034
list_files=(
    sync_all.list
    sync_backuper.list
    sync_watcher.list
)

# папка назначения для копирования конфигов
list_to="${SYNC_CONFIG_PATH}"



# Список имен файлов .desktop для копирования
# shellcheck disable=SC2034
desktop_files=(
sync_regular.desktop
sync_up.desktop
)

# папка назначения для копирования скриптов
desktop_to="${HOME}/.local/share/applications"



# конфиг-файл, к которому нужно подключить алиасы
BASHRC="${HOME}/.bashrc"

# Файл алиасов и автодополнений
ALIASES="${scripts_to}/sync_1_aliases.sh"



print_help()
{
    echo "" 
    echo "${APP_TITLE}" 
    echo "${APP_NAME} -- Версия ${VERSION}" 
    echo "Скрипт установки в систему рабочих скриптов, иконок и .desktop-файлов." 
    echo "Вспомогательный скрипт из комплекта персональной синхронизации sync_1." 
    echo ""
    echo "Краткое описание инсталлятора:"
    echo "    - Исполняемые скрипты копирются в папку ~/bin"
    echo "      (sync_1.sh, sync_all.sh, sync_1_aliases.sh, sync_backuper.sh)"
    echo "    - Конфиг-файлы и лист-файлы копируются в папаку ~/.config/sync"
    echo "    - Иконки копируются в папаку ~/.local/share/icons/sync"
    echo "    - .desktop-файлы копируются в папку ~/.local/share/applications"
    echo "    - Скрипт с алиасами и автодополнением добавляется в ~/.bashrc"
    echo ""
    echo "Подробности о работе скриптов смотрите в справках соответствующих скриптов." 
    echo ""
    echo "Последние изменения"
    echo "${LAST_CHANGES}"
    echo ""
}



# Проверка наличия команды в системе
is_installed() {
    command -v "$1" &>/dev/null
}

# Проверка доступности пакета в APT
is_available_in_repo() {
    apt-cache show "$1" &>/dev/null
}


#
#  Проверка и установка зависимости
#   check_dependency_group <массив> [0|1]
#   <массив> -- Ассоциативный массив, где 
#               ключ -- программа, значение -- пакет.
#   [0|1]    -- 0 -- не оязательные зависимости
#               1 -- обязательные зависимости. По умолчани.
#   После проверки при отсутсвии предлагает установить программу.
#   При подтверждении -- устанавливает.
#
check_dependency_group() {
    local -n dep_array=${1:?}    # ссылка на ассоциативный массив
    local is_required=${2:-1}    # 1 - обязательная, 0 - необязательная

    for cmd in "${!dep_array[@]}"; do
        local pkg="${dep_array[$cmd]}"

        if is_installed "$cmd"; then
            echo -e "[${COLOR_OK}OK${COLOR_OFF}] Утилита '${COLOR_OK}$cmd${COLOR_OFF}' установлена."
        else
            echo -e "[${COLOR_ERROR}!!${COLOR_OFF}] Утилита '${COLOR_ERROR}$cmd${COLOR_OFF}' не найдена. Пакет: '$pkg'"

            if [[ "$is_required" == "1" ]]; then 
                echo "(пакет обязательный)"
            else 
                echo "(пакет рекомендуемый, не обязатеьный)"
            fi

            if is_available_in_repo "$pkg"; then
                echo -n "Желаете установить '$pkg'? [Yes/n]: "
                read -r answer
                answer="${answer,,}"  # в нижний регистр
                if [[ "$answer" =~ ^(y|yes|)$ ]]; then
                    sudo apt update && sudo apt install -y "$pkg"
                    if is_installed "$cmd"; then
                        echo "[OK] '$cmd' успешно установлен."
                    else
                        echo "[Ошибка] Не удалось установить '$cmd'."
                        [[ "$is_required" == "1" ]] && exit 1
                    fi
                else
                    echo "Вы отказались от установки '$pkg'."
                    if [[ "$is_required" == "1" ]]; then
                        echo "Это обязательная зависимость. Прерывание."
                        exit 1
                    fi
                fi
            else
                echo "[Ошибка] Пакет '$pkg' не найден в репозиториях."
                [[ "$is_required" == "1" ]] && exit 1
            fi
        fi
    done
}



#
# Проверяет установлена ли программа. 
# Если нет, то устанавливает пакет, в котором она находится
# $1 -- Программа
# $2 -- Пакет, в котором эта программа. Для установки программы.
#
install_if_not_()
{
    APP="$1"
    PKG="$2"
    CMD_INST="sudo apt install ${PKG}"

    eval "set -- $(whereis "${APP}")"
    if [ "$#" -lt 2 ]; then
        # shellcheck disable=SC2059
        printf "[${APP}] из пакета [${PKG}] не установлена. Установить? (1/0) "
        read -r -n 1 YES
        echo ""
        if  [ "#${YES}#" == "#1#" ]; then
            echo "--Устанавливаем---------------------------------"
            ${CMD_INST}
            exit_code=$?
            echo "------------------------------------------------"
            if [ $exit_code -eq 0 ]; then
                echo "${PKG} Установлена успешно."
            else
                echo "Установка [${PKG}] не удалась."
            fi
            echo "------------------------------------------------"
        fi
    else
        echo "Программа [${APP}] из пакета [${PKG}] есть."
    fi
}



if  [ "$#" -ge 1 ] && \
    { 
        [ "$1" = "--help" ] || [ "$1" = "-h" ] || \
        [ "$1" = "--usage" ] || [ "$1" = "-u" ] || \
        [ "$1" = "--version" ] || [ "$1" = "-v" ]; 
    }; 
then
    print_help
    exit 0
fi



check_dependency_group DEPENDENCIES_REQUIRED 1
check_dependency_group DEPENDENCIES_OPTIONAL 0



# Копирование файлов в рабочий каталог
# $1 -- имя массива со списком файлов
# $2 -- папка назначения
copy_file_to()
{
    local -n local_array=$1
    COPY_TO=$2
    mkdir -p "${COPY_TO}" || { echo -e "${COLOR_ERROR}ОШИБКА${COLOR_OFF}: По какой-то причине не удаётся создать папаку '${COPY_TO}'."; exit 1; }
    for element in "${local_array[@]}"; do
        if [ -f "${element}" ]; then
            printf "==== Копируем файл %s -> %s\n" "${element}" "${COPY_TO}"
            cp --force "${element}" "${COPY_TO}"
        else
            echo -e "${COLOR_ERROR}${element} -- НЕ ФАЙЛ или НЕВЕРНОЕ УКАЗАНИЕ${COLOR_OFF}"
            echo -e "Аварийное прекращение работы."
            exit 1;
        fi
    done
    echo -e "==== ${COLOR_OK}Копирование завершено${COLOR_OFF}\n"
}



copy_file_to scripts_files "${scripts_to}"
copy_file_to icon_files    "${icon_to}"
copy_file_to desktop_files "${desktop_to}"



#
#  Устанавлвивает конфиг файл, если его нет.
#  Если есть. то сообщает об этом и ничего не делает
#  install_config_file <путь_установки> <файл>
#  $1 -- путь назначения
#  $2 -- имя конфиг-файла
install_config_file() {
    local target_dir="${1:?}"       # путь назначения
    local config_file="${2:?}"      # имя конфиг-файла
    echo ""
    echo "Устанавливаем конфиг-файл [${config_file}]"

    if [ -f "${config_file}" ]; then
        echo "Дефолтный конфиг есть"
        if [ -f "${target_dir}/${config_file}" ]; then
            echo "Установленный конфиг есть."
            echo "Если Вам нужно установить дефолтный конфиг, "
            echo "то удалите уже установленный конфиг-файл [${target_dir}/${config_file}]"
            echo "Оставляем существующий конфиг-файл [${config_file}]."
        else
            printf "==== Копируем файл %s -> %s\n" "${config_file}" "${target_dir}/${config_file}"
            cp --force "${config_file}" "${target_dir}/${config_file}"
            echo "Дефолтный конфиг-файл [${config_file}] установлен."
        fi
    else
        echo "Файл дефолтного конфига отсутствует [${config_file}]."
        echo "Аварийное прекращение работы."
        exit 1
    fi
    echo -e "${COLOR_OK}Ok${COLOR_OFF}.\n"
}


# Копирование файлов в рабочий каталог только если файла нет
# $1 -- имя массива со списком файлов
# $2 -- папка назначения
# с помощью вызова install_config_file()
install_config_all()
{
    local -n local_array=$1
    COPY_TO=$2
    mkdir -p "${COPY_TO}" || { echo -e "${COLOR_ERROR}ОШИБКА${COLOR_OFF}: Ошибка созданя папки для конфигов '${COPY_TO}'."; exit 1; }
    for element in "${local_array[@]}"; do
        if [ -f "${element}" ]; then
            echo -e "==== Устанавливаем ${element} -> ${COPY_TO}"
            #  $1 -- путь назначения
            #  $2 -- имя конфиг-файла
            install_config_file "${list_to}" "${element}"
        else
            echo -e "[${COLOR_ERROR}Ошибка{COLOR_OFF}] ${element} -- НЕ ФАЙЛ или НЕВЕРНОЕ УКАЗАНИЕ$"
            echo -e "Аварийное прекращение работы."
            exit 1;
        fi
    done
    echo -e "==== ${COLOR_OK}Копирование завершено${COLOR_OFF}\n"
}

# $1 -- имя массива со списком файлов
# $2 -- папка назначения
install_config_all list_files "${list_to}"



echo ""
echo "Исправляем пути в .desktop-файлах"

sed -i "s#Exec=sync_all.sh#Exec=${scripts_to}/sync_all.sh#g" "${desktop_to}/sync_regular.desktop"
sed -i "s#Exec=sync_all.sh#Exec=${scripts_to}/sync_all.sh#g" "${desktop_to}/sync_up.desktop"
sed -i "s#Path=.#Path=${scripts_to}#g" "${desktop_to}/sync_regular.desktop"
sed -i "s#Path=.#Path=${scripts_to}#g" "${desktop_to}/sync_up.desktop"
sed -i "s#Icon=sync_1.icon.svg#Icon=${icon_to}/sync_1.icon.svg#g"       "${desktop_to}/sync_regular.desktop"
sed -i "s#Icon=sync_1_up.icon.svg#Icon=${icon_to}/sync_1_up.icon.svg#g" "${desktop_to}/sync_up.desktop"

echo "Закончили исправлять пути в .desktop-файлах"
echo -e "${COLOR_OK}Ok${COLOR_OFF}.\n"



echo "# Добавление include вставки файла ${ALIASES} в файл ${BASHRC} "
echo "# для работы алиаcов и автодополнения"
if ( grep -q "${ALIASES}" "${BASHRC}" ); 
then 
    echo "В файле [${BASHRC}] вставка [${ALIASES}] есть."; 
    echo -e "${COLOR_OK}Ничего не делаем${COLOR_OFF}"; 
else 
    echo "В файле [${BASHRC}] НЕТ вставки [${ALIASES}]."; 
    printf "Добавляем..."; 
    {
        echo ""
        echo ". \"${ALIASES}\""
        echo ""
    } >> "${BASHRC}"
    echo -e "...${COLOR_OK}Ok${COLOR_OFF}."; 
fi


echo -e ""
echo -e "${COLOR_OK}Установка завершена успешно.\nok.${COLOR_OFF}"

