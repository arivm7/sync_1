#!/usr/bin/env bash



# Версия скрипта
# VERSION="1.5.0 (2025-07-10)"
# v1.3.1 (2025-05-08): Добавлено автодополнение для sync_all.sh и поддержка комманды LOG
# v1.3.2 (2025-05-08): Добавлено автодополнение для sync_1.sh и поддержка комманды LOG
# v1.3.3 (2025-05-17): Добавлен параметр SHOW_DEST показывает облачные пути
# v1.4.0 (2025-06-12): Добавлена команда TEST, которая проверяет и показывает состояние синхронизатора
# v1.5.0 (2025-07-10): Поддержка sync_watcher.sh. Переделана поддержка s1

# Алиасы
alias s1='sync_1.sh'

alias s1_REGULAR='s1 REGULAR'
alias s1_UP_INIT='s1 UP_INIT'
alias s1_UP_EDIT='s1 UP_EDIT'
alias s1_ALL='sync_all.sh'

alias s1_regular='s1 REGULAR'
alias s1_up_init='s1 UP_INIT'
alias s1_up_edit='s1 UP_EDIT'
alias s1_all='sync_all.sh'

# Авдополнение в командной строке
_sync1_completions() {
    # shellcheck disable=SC2034
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    opts="REGULAR UP DL DL_INIT UP_INIT PAUSE UP_EDIT UNPAUSE SHOW_DEST SHOW_CLOUD_CMD TEST LOG CLOUD_UP_INIT CLOUD_DL_INIT --usage -u --help -h --version -v"
    # если аргумент начинается с '/', './', '../' — автодополняем путь
    if [[ "$cur" == /* || "$cur" == ./* || "$cur" == ../* ]]; then
        # shellcheck disable=SC2207
        COMPREPLY=( $(compgen -f -- "$cur") )
    else
        # автодополнение опций
        # shellcheck disable=SC2207
        COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
    fi
    return 0
}

# Привязка функции к скрипту
complete -F _sync1_completions sync_1.sh s1
complete -W "REGULAR UP DL DL_INIT UP_INIT PAUSE UP_EDIT UNPAUSE SHOW_DEST SHOW_CLOUD_CMD TEST LOG     --edit-conf --edit-list --usage -u --help -h --version -v" sync_all.sh   s1_all
complete -W "                                                                             --dry-run -n --edit-conf --edit-list --usage -u --help -h --version -v" sync_backuper.sh
complete -W "                                                                             --dry-run -n --edit-conf --edit-list --usage -u --help -h --version -v" sync_watcher.sh
