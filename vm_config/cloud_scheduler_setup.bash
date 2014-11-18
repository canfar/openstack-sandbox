#!/bin/bash
# Shell script for installing and configuring Condor to enable dynamically

EXEC_NAME=$(basename $0 .${0##*.})
EXEC_VERSION=0.1_alpha

EPHEMERAL_DIR="/ephemeral"
CS_CENTRAL_MANAGER="batch"

msg() {
    echo "${EXEC_NAME}: $1"
}

die() {
    echo "${EXEC_NAME}: $1" 1>&2
    exit 1
}

usage() {
    echo $"Usage: ${EXEC_NAME} [OPTION]... CENTRAL_MANAGER
Install HTCondor if needed and configure it for cloud-scheduler

  -e, --ephemeral-dir       scratch directory where condor will execute jobs (default: ${EPHEMERAL_DIR})
  -h, --help                display help and exit
  -v, --version             output version information and exit
"
    exit
}

# install condor for rpm or deb distros
cs_condor_install() {
   condor_version > /dev/null 2>&1 && msg "condor is already installed" && return 0
   # determine os
   if yum --version >&2 > /dev/null; then
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
   elif apt-get --version >&2 > /dev/null; then
       msg "apt/dpkg distribution detected"
       export DEBIAN_FRONTEND=noninteractive
       local condordeb="deb http://research.cs.wisc.edu/htcondor/debian/stable/ wheezy contrib"
       if [[ -d /etc/apt/sources.list.d ]]; then
	   echo "${condordeb}" > /etc/apt/sources.list.d/condor
       else
	   echo "${condordeb}" >> /etc/apt/sources.list
       fi
       apt-get -y update
       msg "installing htcondor..."
       if apt-get -y install htcondor ; then
	   msg "didn't work, now installing condor..."
	   apt-get -y install condor || die "didn't work either, bye!"
       fi
   else
       die "unable to detect distribution type"
   fi
}

# configure condor for cloud scheduler
cs_configure_condor() {
    msg "updating condor config"
    type -P condor_config_val || die "condor does not seem to be installed"
    local condorconfig="$(condor_config_val LOCAL_CONFIG_DIR)"
    if [[ -n ${condorconfig} ]]; then
	mkdir -p ${condorconfig}
	condorconfig="${condorconfig}/cloud_scheduler"
    else
	condorconfig="$(condor_config_val LOCAL_CONFIG_FILE)"
	[[ -n ${condorconfig} ]] || die "condor configuration file '${condorconfig}' is undefined"
    fi
    cat >> ${condorfile} <<-EOF
	#########################################################
	# Automatically added for cloud_scheduler by ${EXEC_NAME}
	EXECUTE = ${EPHEMERAL_DIR}
	CONDOR_HOST = ${CS_CENTRAL_MANAGER}
	HOSTALLOW_WRITE = \$(FULL_HOSTNAME), \$(CONDOR_HOST), \$(IP_ADDRESS)
	ALLOW_WRITE = \$(FULL_HOSTNAME), \$(CONDOR_HOST), \$(IP_ADDRESS)
	CCB_ADDRESS = \$(CONDOR_HOST)
	TRUST_UID_DOMAIN = False
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
	######################################################
    EOF
    echo "${CS_CENTRAL_MANAGER}" > /etc/condor/central_manager
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

[[ $# -eq 0 ]] && usage

# Store all options
OPTS=$(getopt \
    -o e:hv \
    -l ephemeral-dir: \
    -l help \
    -l version \
    -- "$@")

eval set -- "${OPTS}"

# Process options
while true; do
    case "$1" in
	-e | --ephemeral-dir) EPHEMERAL_DIR=${2##=}; shift ;;
	-h | --help) usage ;;
	-V | --version) echo ${EXEC_VERSION}; exit ;;
	--)  shift; break ;; # no more options
	*) break ;; # parameters
    esac
    shift
done

# Main argument
[[ $# -eq 0 ]] && die "missing central manager hostname"
CS_CENTRAL_MANAGER=$1

cs_install_condor
cs_configure_condor
cs_setup_etc_hosts
