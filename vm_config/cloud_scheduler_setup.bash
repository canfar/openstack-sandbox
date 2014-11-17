#!/bin/bash
# Shell script for installing and configuring Condor to enable dynamically

EXEC_NAME=$(basename $0 .${0##*.})
EPHEMERAL_DEVICE=/dev/disk/by-label/ephemeral0
STAGING_DIR=${TMPDIR:-/staging}

CS_CENTRAL_MANAGER=canfarhead
CS_CENTRAL_MANAGER_IP=192.168.0.3
CS_CONDOR_CONFIG="/etc/condor/config.d/cloud_scheduler"
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
cs_mount_scratch() {
    grep -q ${STAGING_DIR} /proc/mounts && msg "scratch already directory mounted" && return 0
    msg "mount ephemeral disk at ${STAGING_DIR}..."
    mkdir -p ${STAGING_DIR}
    if [[ -b ${EPHEMERAL_DEVICE} ]] ; then
	mount -o defaults ${EPHEMERAL_DEVICE} ${STAGING_DIR} || die "failed to mount ${EPHEMERAL_DEVICE} at ${STAGING_DIR}"
	msg "scratch directory mounted on ${STAGING_DIR}"
    else
	msg "partition labeled 'ephemeral0' does not exist"
	msg "${STAGING_DIR} will not be configured"
    fi
}

# set up condor ccb if only private networking is available
cs_setup_etc_hosts() {
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
    cat > ${CS_CONDOR_CONFIG} <<-EOF
	#########################################################
	# Automatically added for cloud_scheduler by ${EXEC_NAME}
	EXECUTE = ${CS_STAGING_DIR}
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
    chown condor:condor ${STAGING_DIR}
    msg "restart condor services to include configuration changes"
    service condor restart
}
