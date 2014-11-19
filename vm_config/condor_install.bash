#!/bin/bash

EXEC_NAME=$(basename $0 .${0##*.})
EXEC_VERSION=0.1_alpha

msg() {
    echo " >> ${EXEC_NAME}: $1"
}

die() {
    echo "${EXEC_NAME}: $1" 1>&2
    exit 1
}

usage() {
    echo $"Usage: ${EXEC_NAME} [OPTION]
Install HTCondor if needed

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

condor_install
