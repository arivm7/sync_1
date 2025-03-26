#!/bin/bash



VERSION="1.2.3 (2025-03-25)"

logger -p info "SYNC_ALL: BEG: $(date)"
logger -p info "SYNC_ALL: VER: ${VERSION}"
logger -p info "SYNC_ALL: CMD: $0 $1 $2 $3 $4 $5 $6 $7 $8 $9"

SYNC1="${HOME}/bin/sync_1.sh"


# Поддерживаемые пользовательские комманды
SYNC_STATUS_UP="UP"
SYNC_STATUS_DL="DL"
SYNC_STATUS_REGULAR="REGULAR"
SYNC_STATUS_UP_INIT="UP_INIT"
SYNC_STATUS_DL_INIT="DL_INIT"
SYNC_STATUS_PAUSE="PAUSE"
SYNC_STATUS_UP_EDIT="UP_EDIT"
SYNC_STATUS_UNPAUSE="UNPAUSE"


# Пользовательская комманда из списка выше
USER_CMD="$1"

if [  -n "${USER_CMD}" ]                             && \
   ((( ! "${USER_CMD}" = "${SYNC_STATUS_UP}" )       && \
     ( ! "${USER_CMD}" = "${SYNC_STATUS_DL}" )       && \
     ( ! "${USER_CMD}" = "${SYNC_STATUS_REGULAR}" )  && \
     ( ! "${USER_CMD}" = "${SYNC_STATUS_UP_INIT}" )  && \
     ( ! "${USER_CMD}" = "${SYNC_STATUS_DL_INIT}" )  && \
     ( ! "${USER_CMD}" = "${SYNC_STATUS_PAUSE}" )    && \
     ( ! "${USER_CMD}" = "${SYNC_STATUS_UP_EDIT}" )  && \
     ( ! "${USER_CMD}" = "${SYNC_STATUS_UNPAUSE}" ))); 
then
    ERR="SYNC_ALL: ERROR: Пользовательская комманда ${USER_CMD} не верна."
    logger -p info "${ERR}"
    echo "${ERR}"
    exit 1;
fi


run_one_dir()
{
    # $1 -- папка для синхронизации
    P="$1"
    echo "[${P}/.sync/dest] -- Проверка наличия файла"
    if [ -f "${P}/.sync/dest" ]; then
        echo "[${P}/.sync/dest] -- Есть"
        echo "[${P}/.sync/excludes] -- Проверка папки"
        if [ -f "${P}/.sync/excludes" ]; then
            echo "[${P}/.sync/excludes] -- Есть"
            echo "Стартуем..."
            $SYNC1 "${P}" "${USER_CMD}"
            echo "...закончили"
        else
            echo "[${P}/.sync/excludes] -- Нет файла"
            echo "см.: sync_1.sh --help"
        fi
    else
        echo "[${P}/.sync/dest] -- Нет файла"
        echo "см.: sync_1.sh --help"
    fi
}



run_banner()
{
    # $1 -- Папка синхронизации
    FOLDER=$1
    # $2 -- Строка-баннер для красивого отображени на экране
    BANNER=$2

    printf "\n\n\n\n"

    if [ "#$BANNER#" == "##" ]; then
        BANNER="${FOLDER}"
    fi
    echo   "${BANNER}"
    figlet -k "${BANNER}" -f "big"
    run_one_dir "${FOLDER}"
}



##  =============================================
##                                              =
##  Собственно, список синхронизируемых папок   =
##                                              =

run_banner "${HOME}/bin"         "BIN"           
run_banner "${HOME}/Documents"   "DOCUMENTS"     
run_banner "${HOME}/Public/Soft" "SOFT"          
run_banner "${HOME}/Games/SC"    "SC saves"      
run_banner "${HOME}/Games/SC2"   "SC2 saves"     

##                                              =
##  конец списка синхронизации                  =
##                                              =
##  =============================================



WAIT_END=15 #seconds

echo "===================="
echo "Все выполнено. Окно можно закрыть."
echo "Автоматическое закрытие через [${WAIT_END}] сек."
logger -p info "SYNC_ALL: END: $(date)"
echo "===================="
sleep ${WAIT_END}

