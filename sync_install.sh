#!/usr/bin/env bash
set -e
set -u
set -o pipefail



VERSION="1.3.0 (2025-04-29)"
APP_NAME=$(basename "$0")
LAST_CHANGES="\
v1.3.0 (2025-04-29): Добавление установки зависимостей."

echo "SYNC INSTALLER VER: ${VERSION}"



APP_SYNC="rsync";    PKG_SYNC="rsync";
APP_SSH="ssh";       PKG_SSH="openssh-client";
APP_FIGLET="figlet"; PKG_FIGLET="figlet";



print_help()
{
    echo "" 
    echo "${APP_NAME} -- Версия ${VERSION}" 
    echo "Скрипт установки в систему рабочих скриптов, иконок и .desktop-файлов." 
    echo "Вспомогательный скрипт из комплекта персональной синхронизации sync_1." 
    echo "Подробности о работе смотрите в справках соответствующих скриптов." 
    echo ""
    echo "Последние изменения"
    echo "${LAST_CHANGES}"
    echo ""
}



#
# Проверяет установлена ли программа. 
# Если нет, то устанавливает пакет, в котором она находится
# $1 -- Программа
# $2 -- Пакет, в котором эта программа. Для установки программы.
#
install_if_not()
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
    { \
        [ "$1" = "--help" ] || [ "$1" = "-h" ] || [ "$1" = "-H" ] || \
        [ "$1" = "--version" ] || [ "$1" = "-v" ] || [ "$1" = "-V" ]; \
    }; 
then
    print_help
    exit 0
fi



install_if_not "${APP_SYNC}"   "${PKG_SYNC}"
install_if_not "${APP_SSH}"    "${PKG_SSH}"
install_if_not "${APP_FIGLET}" "${PKG_FIGLET}"



# Список имен файлов скриптов для копирования
# shellcheck disable=SC2034
scripts_files=(
sync_1.sh
sync_all.sh
sync_1_aliases.sh
)
# папка назначения для копирования скриптов
scripts_to="${HOME}/bin"



# Список имен файлов .desktop для копирования
# shellcheck disable=SC2034
icon_files=(
sync_1.icon.svg
sync_1_up.icon.svg
)
# папка назначения для копирования скриптов
icon_to="${HOME}/bin/icons"



# Конфиг файл для массовой синхронизации
SYNC_ALL_LIST_FILE="sync_all.list"



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



echo ""
echo "Устанавливаем конфиг-файл для SYNC_ALL [${SYNC_ALL_LIST_FILE}]"

if [ -f "${SYNC_ALL_LIST_FILE}" ]; then
    echo "Дефолтный конфиг для списка синхронизации есть"
    if [ -f "${scripts_to}/${SYNC_ALL_LIST_FILE}" ]; then
        echo "Установленный конфиг для списка синхронизации есть."
        echo "Если Вам нужно установить дефолтный конфиг, "
        echo "то удалите уже установленный конфиг-файл [${scripts_to}/${SYNC_ALL_LIST_FILE}]"
        echo "Оставляем существующий конфиг-файл [${SYNC_ALL_LIST_FILE}]."
    else
        printf "==== Копируем файл %s -> %s\n" "${SYNC_ALL_LIST_FILE}" "${scripts_to}/${SYNC_ALL_LIST_FILE}"
        cp --force "${SYNC_ALL_LIST_FILE}" "${scripts_to}/${SYNC_ALL_LIST_FILE}"
        echo "Дефолтный конфиг-файл [${SYNC_ALL_LIST_FILE}] установлен."
    fi

else
    echo "Дефолтный конфиг для списка синхронизации отсутствует [${SYNC_ALL_LIST_FILE}]."
    echo "Аварийное прекращение работы."
    exit 1;
fi
echo ""



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

