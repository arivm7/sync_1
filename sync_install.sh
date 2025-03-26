#!/bin/bash



VERSION="1.2.3 (2025-03-25)"
echo "SYNC INSTALLER VER: ${VERSION}"



# Список имен файлов скриптов для копирования
scripts_files=(
sync_1.sh
sync_all.sh
sync_1_aliases.sh
)
# папка назначения для копирования скриптов
scripts_to="${HOME}/bin"



# Список имен файлов .desktop для копирования
icon_files=(
sync_1.icon.svg
sync_1_up.icon.svg
)
# папка назначения для копирования скриптов
icon_to="${HOME}/bin/icons"



# Список имен файлов .desktop для копирования
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
# $1 -- список файлов
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
            echo "Прекращение работы."
            exit 1;
        fi
    done
    printf "==== Копирование завершено\n\n"
}


copy_file_to scripts_files "${scripts_to}"
copy_file_to icon_files    "${icon_to}"
copy_file_to desktop_files "${desktop_to}"



echo ""
echo "Исправляем путив .desktop-файлах"

sed -i "s#Exec=sync_all.sh#Exec=${scripts_to}/sync_all.sh#g" "${desktop_to}/sync_regular.desktop"
sed -i "s#Exec=sync_all.sh#Exec=${scripts_to}/sync_all.sh#g" "${desktop_to}/sync_up.desktop"
sed -i "s#Path=.#Path=${scripts_to}#g" "${desktop_to}/sync_regular.desktop"
sed -i "s#Path=.#Path=${scripts_to}#g" "${desktop_to}/sync_up.desktop"
sed -i "s#Icon=sync_1.icon.svg#Icon=${icon_to}/sync_1.icon.svg#g"       "${desktop_to}/sync_regular.desktop"
sed -i "s#Icon=sync_1_up.icon.svg#Icon=${icon_to}/sync_1_up.icon.svg#g" "${desktop_to}/sync_up.desktop"

echo "Закончили исправлять путив .desktop-файлах"
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


