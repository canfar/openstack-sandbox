#!/bin/bash
# Shell script to configure Condor for cloud scheduler

EXEC_NAME=$(basename $0 .${0##*.})
EXEC_VERSION=0.4.2

EPHEMERAL_DIR="/ephemeral"

CM_HOST_NAME="batch.canfar.net"
# need to specify local ip because no local dns on nefos
CM_HOST_IP="10.21.0.20"

VMSTORAGE_HOST_NAME="vmstore.canfar.net"
VMSTORAGE_HOST_IP="10.21.0.25"

UPDATE_CS=false
SUBMITTER=${USER}
VM_IMAGE_NAME=${HOSTNAME}

msg() {
    echo " >> ${EXEC_NAME}: $1"
}

die() {
    echo "${EXEC_NAME} Error: $1" 1>&2
    exit 1
}

usage() {
    echo $"Usage: ${EXEC_NAME} [OPTION]
Configure HTCondor for cloud-scheduler on VM execution hosts

  -c, --central-manager     set the central manager hostname (default: ${CM_HOST_NAME})
  -i, --central-manager-ip  set the central manager local IP (default: ${CM_HOST_IP})
  -e, --ephemeral-dir       scratch directory where condor will execute jobs (default: ${EPHEMERAL_DIR})
  -t, --vm-image-name       specify the VM image name (default: ${HOSTNAME})
  -s, --submitter           specify the user submitting the condor jobs (default: ${USER})
  -u, --update-cloud-scheduler update cloud scheduler configuration if set
  -h, --help                display help and exit
  -v, --version             output version information and exit
"
    exit
}

# install condor for rpm or deb distros
canfar_condor_install() {
    local cv=$(condor_version 2> /dev/null | awk '/BuildID/ {print $2}')
    # 8.4.5 has a critical bug that does not work with dynamic slots
    [[ -n ${cv} ]] && [[ ${cv} != 8.4.5 ]] && msg "condor is already installed" && return 0
    msg "installing/updating condor"
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
       yum -y install condor || die "failed to install condor"
    elif apt-get --version > /dev/null 2>&1 ; then
	msg "apt/dpkg distribution detected assume debian wheezy"
	export DEBIAN_FRONTEND=noninteractive
	local condordeb="deb http://research.cs.wisc.edu/htcondor/debian/stable/ wheezy contrib"
	if [[ -d /etc/apt/sources.list.d ]]; then
	    echo "${condordeb}" > /etc/apt/sources.list.d/condor.list
	else
	    echo "${condordeb}" >> /etc/apt/sources.list
	fi
	wget -qO - http://research.cs.wisc.edu/htcondor/debian/HTCondor-Release.gpg.key | apt-key add - > /dev/null
	apt-get -q update -y
	msg "installing condor..."
	# htcondor is the name of the package in debian repo, condor is the name in the condor repo
	apt-get -q install -y condor || die "condor didn't install properly"
    else
	die "unable to detect distribution type"
    fi
}

# configure condor for cloud scheduler
canfar_condor_configure() {
    msg "updating condor configuration"
    type -P condor_config_val > /dev/null || die "condor does not seem to be installed"
    local condorconfig="$(condor_config_val LOCAL_CONFIG_DIR)"
    if [[ -n ${condorconfig} ]]; then
	mkdir -p ${condorconfig}
	rm -f ${condorconfig}/*
	condorconfig="${condorconfig}/cloud_scheduler"
    else
	condorconfig="$(condor_config_val LOCAL_CONFIG_FILE)"
	[[ -n ${condorconfig} ]] || die "condor configuration file '${condorconfig}' is undefined"
    fi
    local execdir=${EPHEMERAL_DIR}/condor

    service condor stop
    msg "cleaning up condor logs"
    rm -rf $(condor_config_val LOG)/*

    cat > ${condorconfig} <<-EOF
	#########################################################
	# Automatically added for cloud_scheduler by ${EXEC_NAME}
	EXECUTE = ${execdir}
	CONDOR_HOST = ${CM_HOST_NAME}
	ALLOW_WRITE = \$(FULL_HOSTNAME), \$(CONDOR_HOST), \$(IP_ADDRESS)
	CCB_ADDRESS = \$(CONDOR_HOST)
	DAEMON_LIST = MASTER, STARTD
	MaxJobRetirementTime = 3600 * 24 * 2
	SHUTDOWN_GRACEFUL_TIMEOUT = 3600 * 25 * 2
	STARTD_ATTRS = COLLECTOR_HOST_STRING VMType
	START = ( Owner == ${SUBMITTER} )
	VMType = ${VM_IMAGE_NAME}
	SUSPEND = FALSE
	CONTINUE = TRUE
	PREEMPT = FALSE
	KILL = FALSE
	RUNBENCHMARKS = FALSE
	UID_DOMAIN = ${CM_HOST_NAME#*.}
	TRUST_UID_DOMAIN = TRUE
	SOFT_UID_DOMAIN = TRUE
	STARTER_ALLOW_RUNAS_OWNER = TRUE
	UPDATE_COLLECTOR_WITH_TCP = TRUE
	NUM_SLOTS = 1
	NUM_SLOTS_TYPE_1 = 1
	SLOT_TYPE_1_PARTITIONABLE = TRUE
	######################################################
	EOF
    echo "${CM_HOST_NAME}" > /etc/condor/central_manager
    [[ -d ${execdir} ]] || mkdir -p ${execdir}
    chown condor:condor ${EPHEMERAL_DIR}
    chown condor:condor ${execdir}
    chmod ugo+rwxt ${execdir}
    # on CentOS 7 /var/lock/condor is incorrectly owned by root
    if condor_version | grep -q RedHat_7; then
        msg "RedHat 7 derivatives need hack for /var/lock/condor ownership."
        mkdir -p /var/lock/condor
        chown condor:condor /var/lock/condor
    fi
    msg "restart condor services to include configuration changes"
    service condor start
}

canfar_setup_etc_hosts() {
    # set up condor ccb only if private networking is available
    local etc_hosts=${1:-/etc/hosts}
    local ethname=$(ip -o link show | awk -F': ' '{print $2}' | grep ^e)
    local priv_ip=$(ip -o -4 addr show ${ethname} | awk -F '[ /]+' '/global/ {print $4}')
    [[ -z ${priv_ip} ]] && die "failed to detect IP address"
    echo ${priv_ip} | egrep -v "127.|192.|172.|10." > /dev/null && return 0
    msg "updating ${etc_hosts}"
    # ip are private
    local addstr="# Added for cloud_scheduler to connect to condor CCB"
     if grep -q ${priv_ip} ${etc_hosts} ; then
	sed -i -e "/^[[:space:]]*${priv_ip}/s:\(.*${priv_ip}\).*:\1 ${HOSTNAME} ${addstr}:" ${etc_hosts}
    else
	echo "${priv_ip} ${HOSTNAME} ${addstr}" >> ${etc_hosts}
    fi
    addstr="# Added for condor to specify central manager of local network"
    sed -i -e "/${CM_HOST_NAME}/d" ${etc_hosts}
    if grep -q "${CM_HOST_IP}[[:space:]]*" ${etc_hosts} ; then	
	sed -i -e "s:[[:space:]]${CM_HOST_IP}[[:space:]]*.*:${CM_HOST_IP} ${CM_HOST_NAME} ${addstr}:" ${etc_hosts}
    else
	echo "${CM_HOST_IP} batch ${CM_HOST_NAME} ${addstr}" >> ${etc_hosts}
    fi

    # glusterfs in local network
    addstr="# Added for glusterfs to connect locally"
    sed -i -e "/${VMSTORAGE_HOST_NAME%%.*}/d" ${etc_hosts}
    echo "${VMSTORAGE_HOST_IP} vmstore ${VMSTORAGE_HOST_NAME} ${addstr}" >> ${etc_hosts}
}

canfar_remove_selinux() {
    # selinux not friendly with condor in our configuration
    # enabled on RHEL images by default
    if getenforce > /dev/null 2>&1 && [[ $(getenforce) != Disabled ]]; then
	msg "disabling selinux"
	[[ -e /etc/selinux/config ]] && \
	    sed -i -e 's/^SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config
	setenforce 0
    fi
}

canfar_disable_firewall() {
    # usually only needed on centos6
    # ultimately should be more robust using iptables on condor ports
    if service iptables status 2> /dev/null; then
	msg "disabling IPV4 firewall for condor"
	service iptables stop
    fi
    if service ip6tables status 2> /dev/null; then
	msg "disabling IPV6 firewall for condor"
	service ip6tables stop
    fi
}

canfar_fix_resolv_conf() {
    # frequent dns issues with openstack on nefos
    # adding google one
    msg "adding google dns"
    sed -i -e '1inameserver 8.8.8.8' /etc/resolv.conf
}

canfar_tweak_tcp() {
    # should exist but we never know
    mkdir -p  /etc/sysctl.d
    cat > /etc/sysctl.d/20-canfar-batch.conf <<-EOF
	kernel.numa_balancing = 0
	net.core.somaxconn = 1000
	net.core.netdev_max_backlog = 5000
	net.core.rmem_max = 16777216
	net.core.wmem_max = 16777216
	net.ipv4.neigh.default.gc_thresh1 = 2048
	net.ipv4.neigh.default.gc_thresh2 = 3072
	net.ipv4.neigh.default.gc_thresh3 = 4096
	net.ipv4.tcp_keepalive_time=200
	net.ipv4.tcp_keepalive_intvl=200
	net.ipv4.tcp_keepalive_probes=5
	net.ipv4.tcp_wmem = 4096 12582912 16777216
	net.ipv4.tcp_rmem = 4096 12582912 16777216
	net.ipv4.tcp_max_syn_backlog = 8096
	net.ipv4.tcp_slow_start_after_idle = 0
	net.ipv4.tcp_tw_reuse = 1
	vm.dirty_ratio = 80
	vm.dirty_background_ratio = 5
	vm.dirty_expire_centisecs = 12000
	vm.swappiness = 0
	EOF

    sysctl --system
}

canfar_setup_ephemeral() {
    msg "setting up ephemeral storage"
    if mount | grep -q vdb; then
	if  mount | grep vdb | grep -q vfat; then
	    msg "workaround some ephemeral are vfat in openstack"
	    umount /dev/vdb
	    mkfs.ext3 /dev/vdb
	else
	    umount /dev/vdb
	fi
    fi
    mkdir -p ${EPHEMERAL_DIR}
    mount /dev/vdb ${EPHEMERAL_DIR}
    chmod 777 ${EPHEMERAL_DIR}
}

# Store all options
OPTS=$(getopt \
    -o c:i:e:s:t:uhv \
    -l central-manager: \
    -l central-manager-ip: \
    -l ephemeral-dir: \
    -l submitter: \
    -l vm-image-name: \
    -l update-cloud-scheduler \
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
	-s | --submitter) SUBMITTER=${2##=}; shift ;;
	-t | --vm-image-name) VM_IMAGE_NAME=${2##=}; shift ;;
        -u | --update-cloud-scheduler) UPDATE_CS=true ;;
	-h | --help) usage ;;
	-V | --version) echo ${EXEC_VERSION}; exit ;;
	--)  shift; break ;; # no more options
	*) break ;; # parameters
    esac
    shift
done

export PATH="/sbin:/usr/sbin:${PATH}"

#canfar_fix_resolv_conf
canfar_tweak_tcp
canfar_setup_ephemeral
canfar_remove_selinux
canfar_condor_install

if [[ ${UPDATE_CS} == true ]]; then
   canfar_setup_etc_hosts
   canfar_condor_configure
   canfar_disable_firewall
fi
