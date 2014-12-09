#!/bin/bash

EXEC_NAME=$(basename $0 .${0##*.})
EXEC_VERSION=0.1

msg() {
    echo " >> ${EXEC_NAME}: $1"
}

die() {
    echo "${EXEC_NAME}: $1" 1>&2
    exit 1
}

usage() {
    echo $"Usage: ${EXEC_NAME}
Create a local user with propagated keys and sudo privileges. Run as sudo.
  -h, --help                display help and exit
  -v, --version             output version information and exit
"
    exit
}

# create a user with sudo privs and ssh on the fly for debian or fedora based distros
# need to be run as root or sudo
create_user() {
    local username=$1
    local sshdir=/home/${username}/.ssh
    useradd -m -s /bin/bash -d /home/${username} ${username} || die "failed to create user ${username}"
    # centos || ubuntu proof
    usermod -a -G wheel ${username} || usermod -a -G sudo ${username}
    msg "Enter your CANFAR password below"
    passwd ${username}
    mkdir -p ${sshdir}
    chmod 700 ${sshdir}
    # ouch - nasty
    local ciuser    
    for ciuser in cloud-user ubuntu centos ec2-user; do
	cp /home/${ciuser}/.ssh/authorized_keys ${sshdir} && break
    done
    chown -R ${username}:${username} ${sshdir}
    chmod 600 ${sshdir}/authorized_keys
    local sudofile=/etc/sudoers
    [[ -d /etc/sudoers.d ]] && sudofile=/etc/sudoers.d/90canfar
    echo "${username} ALL=(ALL) NOPASSWD:ALL" >> ${sudofile}
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

read -p "CANFAR username: " username
create_user ${username}
