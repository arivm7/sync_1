#!/usr/bin/env bash
set -euo pipefail



APP_TITLE="Инсталятор персонального синхронизатора sync_1"
VERSION="1.3.1 (2025-05-25)"
APP_NAME=$(basename "$0")
LAST_CHANGES="\
v1.3.0 (2025-04-29): Добавление установки зависимостей.
v1.3.1 (2025-05-25): Переделывание установки зависимостей
"

echo "SYNC INSTALLER VER: ${VERSION}"



# Обязательные зависимости
# shellcheck disable=SC2034
declare -A DEPENDENCIES_REQUIRED=(
    ["rsync"]="rsync"
    ["ssh"]="openssh-client"
    ["figlet"]="figlet"
    ["tar"]="tar"
    ["du"]="coreutils"
    ["df"]="coreutils"
    ["awk"]="gawk"
    ["gzip"]="gzip"
)

# Рекомендованные зависимости
# shellcheck disable=SC2034
declare -A DEPENDENCIES_OPTIONAL=(
    ["pv"]="pv"
    ["realpath"]="coreutils"
    ["readlink"]="coreutils"
)



print_help()
{
    echo "" 
    echo "${APP_TITLE}" 
    echo "${APP_NAME} -- Версия ${VERSION}" 
    echo "Скрипт установки в систему рабочих скриптов, иконок и .desktop-файлов." 
    echo "Вспомогательный скрипт из комплекта персональной синхронизации sync_1." 
    echo "Подробности о работе смотрите в справках соответствующих скриптов." 
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
            echo "[OK] Утилита '$cmd' установлена."
        else
            echo "[!!] Утилита '$cmd' не найдена. Пакет: '$pkg'"

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



# Список имен файлов скриптов для копирования
# shellcheck disable=SC2034
scripts_files=(
sync_1.sh
sync_all.sh
sync_1_aliases.sh
sync_backuper.sh
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
icon_to="${HOME}/bin/icons"



# Конфиг файл для массовой синхронизации
SYNC_ALL_LIST_FILE="sync_all.list"
SYNC_BACKUPER_LIST="sync_backuper.list"


# Список имен файлов .desktop для копирования
# shellcheck disable=SC2034
desktop_files=(
sync_regular.desktop
sync_up.desktop
)
# папка назначения для копирования скриптов
desktop_to="${HOME}/bin"



# конфиг-файл, к которому нужно подключить алиасы
BASHRC="${HOME}/.bashrc"
# Файл алиасов и автодополнений
ALIASES="${scripts_to}/sync_1_aliases.sh"




# Копирование файлов в рабочий каталог
# $1 -- имя массива со списком файлов
# $2 -- папка назначения
copy_file_to()
{
    local -n local_array=$1
    COPY_TO=$2
    for element in "${local_array[@]}"; do
        if [ -f "${element}" ]; then
            printf "==== Копируем файл %s -> %s\n" "${element}" "${COPY_TO}"
            cp --force "${element}" "${COPY_TO}"
        else
            echo "${element} -- НЕ ФАЙЛ или НЕВЕРНОЕ УКАЗАНИЕ"
            echo "Аварийное прекращение работы."
            exit 1;
        fi
    done
    printf "==== Копирование завершено\n\n"
}



copy_file_to scripts_files "${scripts_to}"
copy_file_to icon_files    "${icon_to}"
copy_file_to desktop_files "${desktop_to}"



#
#  Устанавлвивает конфиг файл, если его нет.
# Если есть. то сообщает об этом и ничего не делает
# install_config_file <путь_установки> <файл>
#
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
    echo ""
}

install_config_file "${scripts_to}" "${SYNC_ALL_LIST_FILE}"
install_config_file "${scripts_to}" "${SYNC_BACKUPER_LIST}"


echo ""
echo "Исправляем пути в .desktop-файлах"

sed -i "s#Exec=sync_all.sh#Exec=${scripts_to}/sync_all.sh#g" "${desktop_to}/sync_regular.desktop"
sed -i "s#Exec=sync_all.sh#Exec=${scripts_to}/sync_all.sh#g" "${desktop_to}/sync_up.desktop"
sed -i "s#Path=.#Path=${scripts_to}#g" "${desktop_to}/sync_regular.desktop"
sed -i "s#Path=.#Path=${scripts_to}#g" "${desktop_to}/sync_up.desktop"
sed -i "s#Icon=sync_1.icon.svg#Icon=${icon_to}/sync_1.icon.svg#g"       "${desktop_to}/sync_regular.desktop"
sed -i "s#Icon=sync_1_up.icon.svg#Icon=${icon_to}/sync_1_up.icon.svg#g" "${desktop_to}/sync_up.desktop"

echo "Закончили исправлять пути в .desktop-файлах"
echo ""



echo "# Добавление include вставки файла ${ALIASES} в файл ${BASHRC} "
echo "# для работы алиаcов и автодополнения"
if ( grep -q "${ALIASES}" "${BASHRC}" ); 
then 
    echo "В файле [${BASHRC}] вставка [${ALIASES}] есть."; 
    echo "Ничего не делаем"; 
else 
    echo "В файле [${BASHRC}] НЕТ вставки [${ALIASES}]."; 
    printf "Добавляем..."; 
    {
        echo ""
        echo ". \"${ALIASES}\""
        echo ""
    } >> "${BASHRC}"
    printf "...Ok.\n"; 
fi


echo ""
echo "Установка завершена успешно."
echo "ok."

