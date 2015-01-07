#!/bin/bash


EXEC_NAME=$(basename $0 .${0##*.})
EXEC_VERSION=0.1_beta

msg() {
    echo " >> ${EXEC_NAME}: $1"
}

die() {
    echo "${EXEC_NAME}: $1" 1>&2
    exit 1
}

CANFAR_URLS=(
    www.canfar.phys.uvic.ca
    www.canfar.net
)

usage() {
    echo $"Usage: ${EXEC_NAME} [OPTIONS] USERNAME
  -h, --help                display help and exit
  -v, --version             output version information and exit
"
    exit
}

# Check .netrc for password. if not, ask for it
canfar_password() {
    local dotnetrc=$1 psswd url
    if [[ -f ${dotnetrc} ]]; then
	for url in ${CANFAR_URLS[@]}; do
            psswd=$(awk -v url=${url} '$0 ~ url {print $6;exit}' ${dotnetrc} 2> /dev/null)
            [[ -n ${psswd} ]] && echo ${psswd} && return
	done
    fi
    local c prompt="CANFAR password: "
    while IFS= read -p "${prompt}" -r -s -n 1 c; do
        [[ ${c} == $'\0' ]] && break
        prompt='*'
        psswd+="${c}"
    done
    echo ${psswd}
}

# Check .netrc for username. if not, ask for it
canfar_username() {
    local user=$1 url dotnetrc=$1/.netrc
    if [[ -f ${dotnetrc} ]]; then
	for url in ${CANFAR_URLS[@]}; do
            user=$(awk -v url=${url} '$0 ~ url {print $4;exit}' ${dotnetrc} 2> /dev/null)
            [[ -n ${user} ]] && echo ${user} && return
	done
    fi
    read -p "CANFAR username: " user
    echo ${user}
}

# Get a valid proxy certificate and put it in the proper directory. Number of days is optional argument.
canfar_get_proxy() {
    local userdir=$(echo ~$1) age=${2:-8}
    local certdir=${HOME}/.ssl certfile=cadcproxy.pem
    local cert=$(find ${certdir} -name ${certfile} -mtime -${age} 2> /dev/null)
    if [[ -n ${cert} ]]; then
        msg "user $1 already has a valid proxy certificate"
        return
    fi
    mkdir -p ${certdir}
    if wget -q -O ${certdir}/${certfile} \
        --http-user=$(canfar_username) \
        --http-password=$(canfar_password) \
        http://${CANFAR_URLS[0]}/cred/proxyCert\?daysValid=${age}
    then
        msg "user $1 has a new proxy certificate valid for ${age} days"
    fi
}

# Check the user credential from CANFAR
canfar_check_dotnetrc() {
    local dotnetrc=$1 url
    for url in ${CANFAR_URLS[@]}; do
	egrep -q "\s*(${url})[[:space:]]+(login|password)[[:space:]]+.*[[:space:]]+(login|password)[[:space:]]+.*" \
	      ${dotnetrc} 2> /dev/null || return 1
    done
}


# Append CANFAR sites with username and password to .netrc
canfar_make_dotnetrc() {
    local user=$1 answ url
    local dotnetrc=~${user}/.netrc
    if [[ ! -e ${dotnetrc} ]]; then
        read -p "Do you want to create a .netrc file for user ${user} [Y/n]? " answ
        [[ ${answ} == [nN]* ]] && return
    elif canfar_check_dotnetrc ${dotnetrc}; then
        echo "User ${user} .netrc was already setup for CANFAR."
        read -p "Do you need to change user/password [y/N]? " answ
        [[ ${answ} != y ]] && return
	for url in ${CANFAR_URLS[@]}; do
            sed -i -e "/${url}/d" ${dotnetrc}
	done
    else
        read -p "Do you want to setup user ${user} .netrc for CANFAR [Y/n]? "
        [[ ${answ} == [nN]* ]] && return
    fi
    user=$(canfar_username) psswd=$(canfar_password)
    for url in ${CANFAR_URLS[@]}; do
	echo >> ${dotnetrc} "machine ${url} login ${user} password ${psswd}"
    done
    echo
    chmod 600 ${dotnetrc}
    msg "User ${user} .netrc is ready for CANFAR"
}

# Store all options
OPTS=$(getopt \
    -o hv \
    -l help \
    -l version \
    -- "$@")

eval set -- "${OPTS}"

# Process options
while true; do
    case "$1" in
	-h | --help) usage ;;
	-V | --version) echo ${EXEC_VERSION}; exit ;;
	--)  shift; break ;; # no more options
	*) break ;; # parameters
    esac
    shift
done

canfar_make_dotnerc $1
