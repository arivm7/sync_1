#!/usr/bin/env bash
set -euo pipefail

##
##  Project     : sync_1
##  Description : Инсталятор.
##                Часть пакета индивидуальной синхронизации sync_1.
##  File        : sync_1.sh
##  Author      : Ariv <ariv@meta.ua> | https://github.com/arivm7
##  Org         : RI-Network, Kiev, UK
##  License     : GPL v3
##    
##  Copyright (C) 2006-2025 Ariv <ariv@meta.ua> | https://github.com/arivm7 | RI-Network, Kiev, UK
##



APP_TITLE="Инсталятор персонального синхронизатора sync_1"
VERSION="1.5.0 (2026-07-11)"
COPYRIGHT="Copyright (C) 2006-2025 Ariv <ariv@meta.ua> | https://github.com/arivm7 | RI-Network, Kiev, UK"
APP_NAME=$(basename "$0")
LAST_CHANGES="\
v1.5.0 (2026-07-11): .desktop-файлы теперь генерируются через desktop-generator-installer.sh (вместо копирования шаблона + sed); шаблоны desktop/*.desktop остались только источником текстовых значений (Name/Comment/Categories/MimeType)
v1.4.1 (2026-04-27): Исправлена ошибка в указании пути назначения при копировании файлов
v1.4.0 (2025-07-10): Поддержка установки sync_watcher
v1.3.1 (2025-05-25): Переделывание установки зависимостей
v1.3.0 (2025-04-29): Добавление установки зависимостей.
"
APP_PATH=$(cd "$(dirname "$0")" && pwd)

cd "${APP_PATH}"



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
    ["xdg-user-dir"]="xdg-user-dirs"
    ["tr"]="coreutils"
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
    img/sync_watcher_icon.svg
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



# Список шаблонов .desktop, из которых берутся текстовые значения
# (Name, Comment, Categories, MimeType) для генерации через
# desktop-generator-installer.sh. Сами шаблоны никуда не копируются.
desktop_files=(
desktop/sync_regular.desktop
desktop/sync_up.desktop
)

# папка назначения .desktop-файлов (совпадает с --target menu в desktop-generator-installer.sh)
desktop_to="${HOME}/.local/share/applications"



# конфиг-файл, к которому нужно подключить алиасы
BASHRC="${HOME}/.bashrc"

# Файл алиасов и автодополнений
ALIASES="${scripts_to}/sync_1_aliases.sh"



print_help()
{
    echo -e "${APP_TITLE}" 
    echo -e "${APP_NAME} -- Версия ${VERSION}" 
    echo -e "Скрипт установки в систему рабочих скриптов, иконок и .desktop-файлов." 
    echo -e "Вспомогательный скрипт из комплекта персональной синхронизации sync_1." 
    echo -e ""
    echo -e "Краткое описание инсталлятора:"
    echo -e "    - Исполняемые скрипты копирются в папку ~/bin"
    echo -e "      (sync_1.sh, sync_all.sh, sync_1_aliases.sh, sync_backuper.sh)"
    echo -e "    - Конфиг-файлы и лист-файлы копируются в папаку ~/.config/sync"
    echo -e "    - Иконки копируются в папаку ~/.local/share/icons/sync"
    echo -e "    - .desktop-файлы создаются в папке ~/.local/share/applications"
    echo -e "      (через desktop-generator-installer.sh, на основе шаблонов desktop/*.desktop)"
    echo -e "    - Скрипт с алиасами и автодополнением добавляется в ~/.bashrc"
    echo -e ""
    echo -e "Подробности о работе скриптов смотрите в справках соответствующих скриптов." 
    echo -e ""
    echo -e "Последние изменения"
    echo -e "${LAST_CHANGES}"
    echo -e ""
    echo -e "${COPYRIGHT}"
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
                    sudo apt update && sudo apt install -y "$pkg" || true
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
    local COPY_TO=$2
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
    local COPY_TO=$2
    mkdir -p "${COPY_TO}" || { echo -e "${COLOR_ERROR}ОШИБКА${COLOR_OFF}: Ошибка созданя папки для конфигов '${COPY_TO}'."; exit 1; }
    for element in "${local_array[@]}"; do
        if [ -f "${element}" ]; then
            echo -e "==== Устанавливаем ${element} -> ${COPY_TO}"
            #  $1 -- путь назначения
            #  $2 -- имя конфиг-файла
            install_config_file "${COPY_TO}" "${element}"
        else
            echo -e "[${COLOR_ERROR}Ошибка${COLOR_OFF}] ${element} -- НЕ ФАЙЛ или НЕВЕРНОЕ УКАЗАНИЕ"
            echo -e "Аварийное прекращение работы."
            exit 1;
        fi
    done
    echo -e "==== ${COLOR_OK}Копирование завершено${COLOR_OFF}\n"
}

# $1 -- имя массива со списком файлов
# $2 -- папка назначения
install_config_all list_files "${list_to}"



#
# Извлекает значение поля из .desktop-файла-шаблона (форма Key=значение)
# $1 -- путь к файлу-шаблону
# $2 -- имя поля (Name, Comment, Categories, MimeType, ...)
#
get_desktop_field() {
    local file="${1:?}"
    local field="${2:?}"
    grep -m1 "^${field}=" "${file}" 2>/dev/null | cut -d'=' -f2-
}

#
# Генерирует один .desktop-файл через desktop-generator-installer.sh.
# Текстовые значения (Name, Comment, Categories, MimeType) берутся из
# файла-шаблона, путь запуска и путь к иконке передаются явно.
# $1 -- путь к файлу-шаблону (источник Name/Comment/Categories/MimeType)
# $2 -- команда для Exec= (полный путь к исполняемому скрипту)
# $3 -- полный путь к иконке
#
generate_desktop_entry() {
    local template="${1:?}"
    local exec_cmd="${2:?}"
    local icon_path="${3:?}"

    if [ ! -f "${template}" ]; then
        echo -e "${COLOR_ERROR}${template} -- НЕ ФАЙЛ или НЕВЕРНОЕ УКАЗАНИЕ${COLOR_OFF}"
        echo -e "Аварийное прекращение работы."
        exit 1
    fi

    if ! is_installed "desktop-generator-installer.sh"; then
        echo -e "[${COLOR_ERROR}!!${COLOR_OFF}] Утилита 'desktop-generator-installer.sh' не найдена."
        echo -e "${COLOR_INFO}Пропускаем создание .desktop-файла из '${template}' (не критично).${COLOR_OFF}"
        return 0
    fi

    local name comment category mimetype
    name="$(get_desktop_field "${template}" "Name")"
    comment="$(get_desktop_field "${template}" "Comment")"
    category="$(get_desktop_field "${template}" "Categories")"
    mimetype="$(get_desktop_field "${template}" "MimeType")"

    echo -e "==== Генерируем .desktop из шаблона ${template}"
    if ! desktop-generator-installer.sh \
        --name       "${name}" \
        --exec       "${exec_cmd}" \
        --terminal   true \
        --category   "${category}" \
        --target     menu \
        --comment    "${comment}" \
        --mimetype   "${mimetype}" \
        --icon       "${icon_path}" \
        --overwrite
    then
        echo -e "[${COLOR_ERROR}!!${COLOR_OFF}] Не удалось создать .desktop-файл из шаблона '${template}' (desktop-generator-installer.sh завершился с ошибкой)."
        echo -e "${COLOR_INFO}Продолжаем установку без него — это не критично.${COLOR_OFF}"
    fi
}

echo ""
echo "Создаём .desktop-файлы"

# Иконка для каждого шаблона из desktop_files (Exec у обоих один и тот же -- sync_all.sh)
declare -A DESKTOP_ICON_MAP=(
    ["desktop/sync_regular.desktop"]="sync_1.icon.svg"
    ["desktop/sync_up.desktop"]="sync_1_up.icon.svg"
)

for template in "${desktop_files[@]}"; do
    generate_desktop_entry "${template}" "${scripts_to}/sync_all.sh" "${icon_to}/${DESKTOP_ICON_MAP[$template]}"
done

# У sync_watcher нет отдельного .desktop-шаблона в desktop_files —
# значения заданы прямо здесь.
if is_installed "desktop-generator-installer.sh"; then
    if ! desktop-generator-installer.sh \
        --name     "sync_watcher" \
        --exec     "${scripts_to}/sync_watcher.sh" \
        --terminal true \
        --category "Accessibility;System;Utility;" \
        --target   menu \
        --comment  "Скрипт следящий за изменениями и запускающий синхронизатор" \
        --mimetype "text/x-shellscript;" \
        --icon     "${icon_to}/sync_watcher_icon.svg" \
        --overwrite
    then
        echo -e "[${COLOR_ERROR}!!${COLOR_OFF}] Не удалось создать .desktop-файл для sync_watcher (desktop-generator-installer.sh завершился с ошибкой)."
        echo -e "${COLOR_INFO}Продолжаем установку без него — это не критично.${COLOR_OFF}"
    fi
else
    echo -e "[${COLOR_ERROR}!!${COLOR_OFF}] Утилита 'desktop-generator-installer.sh' не найдена."
    echo -e "${COLOR_INFO}Пропускаем создание .desktop-файла для sync_watcher (не критично).${COLOR_OFF}"
fi

echo "Закончили создавать .desktop-файлы"
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
