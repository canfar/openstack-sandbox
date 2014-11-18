#!/bin/bash
# Shell script for installing and configuring Condor to enable dynamically

EXEC_NAME=$(basename $0 .${0##*.})

EPHEMERAL_DEVICE=/dev/disk/by-label/ephemeral0
EPHEMERAL_DIR=/staging

CS_CENTRAL_MANAGER=queue
CS_CENTRAL_MANAGER_IP=192.168.0.3
CS_VM_TYPE=$(hostname)

msg() {
    echo "${EXEC_NAME}: $1"
}

die() {
    echo "${EXEC_NAME}: $1" 1>&2
    exit 1
}

# mount ephemeral disk as scratch disk
# would need something more portable than /proc grepping
cs_mount_ephemeral() {
    grep -q ${EPHEMERAL_DIR} /proc/mounts && msg "scratch already directory mounted" && return 0
    msg "mount ephemeral disk at ${EPHEMERAL_DIR}..."
    mkdir -p ${EPHEMERAL_DIR}
    if [[ -b ${EPHEMERAL_DEVICE} ]] ; then
	mount -o defaults ${EPHEMERAL_DEVICE} ${EPHEMERAL_DIR} || die "failed to mount ${EPHEMERAL_DEVICE} at ${EPHEMERAL_DIR}"
	msg "ephemeral directory mounted on ${EPHEMERAL_DIR}"
    else
	msg "partition labeled 'ephemeral0' does not exist"
	msg "${EPHEMERAL_DIR} will not be configured"
    fi
    chmod ugo+rwxt ${EPHEMERAL_DIR}
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
    # now add central manager host in case of no dns
    local addstr="# Added for cloud_scheduler to connect to central manager"
    if grep -q "${addstr}" /etc/hosts ; then
	sed -i -e "s:.*\(${addr}\):${CS_CENTRAL_MANAGER_IP} ${CS_CENTRAL_MANAGER} \1:" /etc/hosts
    else
	echo >> /etc/hosts "${CS_CENTRAL_MANAGER_IP} ${CS_CENTRAL_MANAGER} ${addstr}"
    fi
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
	EXECUTE = ${CS_EPHEMERAL_DIR}
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
        VMType = \"${CS_VM_TYPE}\"
	STARTD_ATTRS = COLLECTOR_HOST_STRING VMType
	HIGHPORT = 50000
	LOWPORT = 40000
	######################################################
    EOF
    echo "${CS_CENTRAL_MANAGER}" > /etc/condor/central_manager
    chown condor:condor ${EPHEMERAL_DIR}
    msg "restart condor services to include configuration changes"
    service condor restart
}

cs_mount_ephemeral
cs_install_condor
cs_configure_condor
cs_setup_etc_hosts
