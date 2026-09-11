#!/bin/bash


if [ -n "$1" ]; then
    arg1=$(type -P $1)

    if [ -x "${arg1}" ]; then
        set -x
        exec $@
    fi
fi

msg() {
    echo -e "\033[42;30m\033[J>> $*\033[0m"
}

error() {
    local delay=${ERROR_DELAY:-3600}
    echo -e "\033[41;30m\033[JERROR: $*\nSLEEPING ${delay} SECONDS BEFORE EXIT.\033[0m"
    sleep ${delay}
    exit ${2:-100}
}

warning() {
    echo -e "\033[43;30m\033[JWARNING: $*\033[0m"
    echo -n "Pausing "
    for i in 5 4 3 2 1
    do
        echo -n "${i}..."
    done
    echo "continuing."
}

if [ ! -d "${HOME_DIR}/mysql" ]; then
    source /firstboot/functions
    core3_firstboot
fi

core3_boot() {
    if [ -f ${HOME_DIR}/.env ]; then
        source ${HOME_DIR}/.env
    else
        env |
        egrep -v '^SHELL=|^PWD=|^LOGNAME=|^HOME=|^LANG=|^LS_COLORS=|^TERM=|^USER=|^SHLVL=|^PATH=|^MAIL=|^OLDPWD=|^_=' |
        sort |
        sed -e "s/=\(.*\)$/='\1'/" -e 's/^/export /' > ${HOME_DIR}/.env
        chown ${RUN_USER}:${RUN_USER} ${HOME_DIR}/.env
    fi
}

core3_boot

core3_start_services() {
    # firstboot starts mariadb itself, but on every later container start nothing
    # does, and ~/bin/run needs a live database. Start it here so the shell always
    # comes up with a usable server.
    if ! pgrep -x mariadbd > /dev/null && ! pgrep -x mysqld > /dev/null; then
        msg "Starting mariadb..."
        chown -R mysql:mysql /var/lib/mysql/. || true
        /etc/init.d/mariadb start || warning "mariadb failed to start"
    fi
}

core3_start_services

msg "Starting interactive shell..."

set -x

exec /bin/su - ${RUN_USER}
