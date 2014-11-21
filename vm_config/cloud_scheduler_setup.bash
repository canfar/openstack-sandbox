#!/bin/bash
# Shell script to configure Condor for cloud scheduler

EXEC_NAME=$(basename $0 .${0##*.})
EXEC_VERSION=0.1_beta

EPHEMERAL_DIR="/ephemeral"
EPHEMERAL_DEVICE="/dev/disk/by-label/ephemeral0"
CM_HOST_NAME="batch"
# need to specify local ip because no local dns on nefos
CM_HOST_IP="192.168.0.3"

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

  -c, --central-manager     set the central manager hostname (default: ${CM_HOST_NAME})
  -i, --central-manager-ip  set the central manager local IP (default: ${CM_HOST_IP})
  -e, --ephemeral-dir       scratch directory where condor will execute jobs (default: ${EPHEMERAL_DIR})
  -h, --help                display help and exit
  -v, --version             output version information and exit
"
    exit
}

# install condor for rpm or deb distros
condor_install() {
   condor_version > /dev/null 2>&1 && msg "condor is already installed" && return 0
   # determine os
   if yum --version > /dev/null 2>&1 ; then
       msg "rpm/yum based distribution detected - now identifiying"
       local rh_vers=$(rpm -qa \*-release | grep -Ei "redhat|centos|sl" | cut -d "-" -f3)
       if [[ -n ${rh_vers} ]]; then
	   msg "RHEL distribution detected, adding extra repo to install condor"
	   cat <<-EOF > /etc/yum.repos.d/htcondor_stable_rhel${rh_vers}.repo
	[htcondor_stable_rhel${rh_vers}]
	gpgcheck = 0
	enabled = 1
	baseurl = http://research.cs.wisc.edu/htcondor/yum/stable/rhel${rh_vers}
	name = HTCondor Stable RPM Repository for Redhat Enterprise Linux ${rh_vers}
	EOF
       else
	   msg "non-RHEL distribution, assuming condor is in repos"
       fi
       msg "installing condor..."
       yum -y install condor || die "failed to install condor"
   elif apt-get --version > /dev/null 2>&1 ; then
       msg "apt/dpkg distribution detected"
       export DEBIAN_FRONTEND=noninteractive
       local condordeb="deb http://research.cs.wisc.edu/htcondor/debian/stable/ wheezy contrib"
       if [[ -d /etc/apt/sources.list.d ]]; then
	   echo "${condordeb}" > /etc/apt/sources.list.d/condor.list
       else
	   echo "${condordeb}" >> /etc/apt/sources.list
       fi
       wget -qO - http://research.cs.wisc.edu/htcondor/debian/HTCondor-Release.gpg.key | apt-key add - > /dev/null
       apt-get -y update
       msg "installing condor..."
       # htcondor is the name of the package in debian repo, condor is the name in the condor repo
       apt-get -y install condor || die "condor didn't install properly"
   else
       die "unable to detect distribution type"
   fi
}

# mount ephemeral partition
# would need something more portable than /proc grepping
cs_mount_ephemeral() {
    grep -q ${EPHEMERAL_DIR} /proc/mounts && msg "scratch already directory mounted" && return 0
    msg "mounting ephemeral disk on ${EPHEMERAL_DIR}"
    mkdir -p ${EPHEMERAL_DIR}
    if [[ -b ${EPHEMERAL_DEVICE} ]]; then
        mount -o defaults ${EPHEMERAL_DEVICE} ${EPHEMERAL_DIR} \
	    || die "failed to mount ${EPHEMERAL_DEVICE} at ${EPHEMERAL_DIR}"
    else
        msg "partition labeled 'ephemeral0' does not exist."
        msg "${EPHEMERAL_DIR} will not be configured."
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
	CONDOR_HOST = ${CM_HOST_NAME}
	HOSTALLOW_WRITE = \$(FULL_HOSTNAME), \$(CONDOR_HOST), \$(IP_ADDRESS)
	ALLOW_WRITE = \$(FULL_HOSTNAME), \$(CONDOR_HOST), \$(IP_ADDRESS)
	CCB_ADDRESS = \$(CONDOR_HOST)
	DAEMON_LIST = MASTER, STARTD
	MaxJobRetirementTime = 3600 * 24 * 2
	SHUTDOWN_GRACEFUL_TIMEOUT = 3600 * 25 * 2
	START = TRUE
	SUSPEND = FALSE
	CONTINUE = TRUE
	PREEMPT = FALSE
	KILL = FALSE
	STARTD_ATTRS = COLLECTOR_HOST_STRING VMType
	HIGHPORT = 50000
	LOWPORT = 40000
	RUNBENCHMARKS = FALSE
	UID_DOMAIN = canfar.net
	TRUST_UID_DOMAIN = TRUE
	SOFT_UID_DOMAIN = TRUE
	STARTER_ALLOW_RUNAS_OWNER = TRUE
	######################################################
	EOF
    echo "${CM_HOST_NAME}" > /etc/condor/central_manager
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
    addstr="# Added for condor to specify central manager of local network"
    if grep -q "${addstr}" /etc/hosts ; then
	sed -i -e "s:.*\(${addr}\):${CM_HOST_IP} ${CM_HOST_NAME} \1:" /etc/hosts
    else
	echo >> /etc/hosts "${CM_HOST_IP} ${CM_HOST_NAME} ${addstr}"
    fi
}

# Store all options
OPTS=$(getopt \
    -o c:e:i:hv \
    -l central-manager: \
    -l central-manager-ip: \
    -l ephemeral-dir: \
    -l help \
    -l version \
    -- "$@")

eval set -- "${OPTS}"

# Process options
while true; do
    case "$1" in
	-c | --central-manager) CM_HOST_NAME=${2##=}; shift ;;
	-i | --central-manager-ip) CM_HOST_IP=${2##=}; shift ;;
	-e | --ephemeral-dir) EPHEMERAL_DIR=${2##=}; shift ;;
	-h | --help) usage ;;
	-V | --version) echo ${EXEC_VERSION}; exit ;;
	--)  shift; break ;; # no more options
	*) break ;; # parameters
    esac
    shift
done

condor_install
cs_mount_ephemeral
cs_condor_configure
cs_setup_etc_hosts
