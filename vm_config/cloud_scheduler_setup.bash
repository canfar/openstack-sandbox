#!/bin/bash
# Shell script to configure Condor for cloud scheduler

EXEC_NAME=$(basename $0 .${0##*.})
EXEC_VERSION=0.1_beta

EPHEMERAL_DIR="/ephemeral"
CENTRAL_MANAGER="192.168.0.3"

msg() {
    echo " >> ${EXEC_NAME}: $1"
}

die() {
    echo "${EXEC_NAME}: $1" 1>&2
    exit 1
}

usage() {
    echo $"Usage: ${EXEC_NAME} [OPTION]
Configure HTCondor for cloud-scheduler on VM execution hosts

  -c, --central-manager     set the central manager hostname (default: ${CENTRAL_MANAGER})
  -e, --ephemeral-dir       scratch directory where condor will execute jobs (default: ${EPHEMERAL_DIR})
  -h, --help                display help and exit
  -v, --version             output version information and exit
"
    exit
}

# mount ephemeral partition
cs_mount_ephemeral() {
    if ! grep -q $EPHEMERAL_DIR /proc/mounts; then
        echo "Try to mount ephemeral disk at ${EPHEMERAL_DIR}..."
        mkdir -p $EPHEMERAL_DIR
        if [ -b /dev/disk/by-label/ephemeral0 ]; then
            DEVICE=/dev/disk/by-label/ephemeral0
            mount -o defaults ${DEVICE} ${EPHEMERAL_DIR}
            if [ "$?" -ne "0" ]; then
                echo "Failed to mount ${DEVICE} at ${EPHEMERAL_DIR}"
            fi
            mkdir ${EPHEMERAL_DIR}/condor
            chown condor:condor ${EPHEMERAL_DIR}/condor
            mkdir ${EPHEMERAL_DIR}/tmp
            chmod ugo+rwxt ${EPHEMERAL_DIR}/tmp
        else
            echo "Partition labeled 'ephemeral0' does not exist."
            echo "${EPHEMERAL_DIR} will not be configured."
        fi
    fi
}

# configure condor for cloud scheduler
cs_condor_configure() {
    msg "updating condor config"
    type -P condor_config_val > /dev/null || die "condor does not seem to be installed"
    local condorconfig="$(condor_config_val LOCAL_CONFIG_DIR)"
    if [[ -n ${condorconfig} ]]; then
	mkdir -p ${condorconfig}
	condorconfig="${condorconfig}/cloud_scheduler"
    else
	condorconfig="$(condor_config_val LOCAL_CONFIG_FILE)"
	[[ -n ${condorconfig} ]] || die "condor configuration file '${condorconfig}' is undefined"
    fi
    cat >> ${condorconfig} <<-EOF
	#########################################################
	# Automatically added for cloud_scheduler by ${EXEC_NAME}
	EXECUTE = ${EPHEMERAL_DIR}
	CONDOR_HOST = ${CENTRAL_MANAGER}
	HOSTALLOW_WRITE = \$(FULL_HOSTNAME), \$(CONDOR_HOST), \$(IP_ADDRESS)
	ALLOW_WRITE = \$(FULL_HOSTNAME), \$(CONDOR_HOST), \$(IP_ADDRESS)
	CCB_ADDRESS = \$(CONDOR_HOST)
	START = TRUE
	DAEMON_LIST = MASTER, STARTD
	MaxJobRetirementTime = 3600 * 24 * 2
	SHUTDOWN_GRACEFUL_TIMEOUT = 3600 * 25 * 2
	SUSPEND = False
	CONTINUE = True
	PREEMPT = False
	KILL = False
	STARTD_ATTRS = COLLECTOR_HOST_STRING VMType
	HIGHPORT = 50000
	LOWPORT = 40000
	RUNBENCHMARKS = False
	######################################################
	EOF
    echo "${CENTRAL_MANAGER}" > /etc/condor/central_manager
    chown condor:condor ${EPHEMERAL_DIR}
    chmod ugo+rwxt ${EPHEMERAL_DIR}
    msg "restart condor services to include configuration changes"
    service condor restart
}

cs_setup_etc_hosts() {
    # set up condor ccb if only private networking is available
    ifconfig | grep "inet addr" | egrep -v "addr:127.|addr:192.|addr:172.|addr:10." > /dev/null && return 0
    # ip are local
    local addstr="# Added for cloud_scheduler to connect to condor CCB"
    local ip=$(ifconfig eth0 | grep -oP '(?<=inet addr:)[0-9.]*')
    if grep -q "${addstr}" /etc/hosts ; then
	sed -i -e "s:.*\(${addr}\):${ip} ${HOSTNAME} \1:" /etc/hosts
    else
	echo >> /etc/hosts "${ip} ${HOSTNAME} ${addstr}"
    fi
}

# Store all options
OPTS=$(getopt \
    -o c:e:hv \
    -l central-manager: \
    -l ephemeral-dir: \
    -l help \
    -l version \
    -- "$@")

eval set -- "${OPTS}"

# Process options
while true; do
    case "$1" in
	-c | --central-manager) CENTRAL_MANAGER=${2##=}; shift ;;
	-e | --ephemeral-dir) EPHEMERAL_DIR=${2##=}; shift ;;
	-h | --help) usage ;;
	-V | --version) echo ${EXEC_VERSION}; exit ;;
	--)  shift; break ;; # no more options
	*) break ;; # parameters
    esac
    shift
done

cs_mount_ephemeral
cs_condor_configure
cs_setup_etc_hosts
