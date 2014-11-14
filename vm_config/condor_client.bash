#!/bin/bash
# Shell script for installing Condor to enable batch processing with CANFAR

# Install Condor if needed
if [ ! -d /etc/condor ]; then
    echo "++++++ (HT)Condor will now be installed..."

    # Determine OS
    OSTYPE=
    OSVERS=
    if [ -e /etc/redhat-release ]; then
	#  --- Redhat derivative ---
	isredhat=`rpm -qa \*-release | grep -Ei "redhat|centos" | cut -d"-" -f3`
	if [[ ! -z "$isredhat" ]]; then
	    # stable Redhat Enterprise Linux-like distro
	    OSTYPE=redhat
	    OSVERS=$isredhat

	    # need to add a repo to get condor
	    repo="/etc/yum.repos.d/htcondor_stable_rhel${OSVERS}.repo"
	    echo "[htcondor_stable_rhel${OSVERS}]" > ${repo}
	    echo "gpgcheck = 0" >> ${repo}
	    echo "enabled = 1" >> ${repo}
	    echo "baseurl = http://research.cs.wisc.edu/htcondor/yum/stable/rhel${OSVERS}" >> ${repo}
	    echo "name = HTCondor Stable RPM Repository for Redhat Enterprise Linux ${OSVERS}"
	elif [[ ! -z `grep -i fedora /etc/redhat-release` ]]; then
	    # Fedora - should already have condor in repos
	    OSTYPE=fedora
	    OSVERS=cut /etc/redhat-release -d " " -f3
	fi


	if [ -z "$OSTYPE" ]; then
	    echo "++++++ ERROR: Unable to identify Redhat-like OS"
	    exit 1
	else
	    echo "Installing wget and condor..."
	    yum -y install wget condor
	    if [[ "$?" != "0" ]]; then
		echo "++++++ ERROR: failed to install wget and/or condor"
		exit 1
	    fi
	fi
    else
	# --- Debian/Ubuntu/Mint ---
	isdeb=`lsb_release -a | grep -Ei "debian|ubuntu|mint"`

	if [[ ! -z "${isdeb}" ]]; then
	    # Debian-like distro
	    OSTYPE=`lsb_release -a | grep -i distributor | cut -d":" -f2`
	    OSVERS=`lsb_release -a | grep -i release | cut -d":" -f2`

	    apt-get -y update

	    echo "++++++ Installing htcondor..."
	    DEBIAN_FRONTEND=noninteractive apt-get -y install htcondor
	    if [[ "$?" != "0" ]]; then
		echo "++++++ Didn't work. Try installing condor..."
		DEBIAN_FRONTEND=noninteractive apt-get -y install condor
		if [[ "$?" != "0" ]]; then
		    echo "++++++ Still didn't work. Exiting..."
		    exit 1
		fi
	    fi

	    echo "++++++ Installing wget..."
	    apt-get -y install wget

	else
	    echo "++++++ Unable to identify OS. Exiting..."
	    exit 1
	fi
    fi
fi

# Configure condor
echo "++++++ Updating condor config..."
wget "https://raw.githubusercontent.com/canfar/openstack-sandbox/master/vm_config/condor_config.canfar" -O /etc/condor/config.d/condor_config.canfar

if [[ "$?" != "0" ]]; then
    echo "++++++ Error: Failed to update the condor configuration."
    exit 1
fi

# Configure staging mount point
if ! grep -q /staging /proc/mounts; then
    echo "++++++ Mount ephemeral disk at /staging..."

    mkdir -p /staging

    if [ -b /dev/disk/by-label/ephemeral0 ]; then
	DEVICE=/dev/disk/by-label/ephemeral0
	mount -o defaults ${DEVICE} /staging
	if [ "$?" -ne "0" ]; then
	    echo "++++++ Failed to mount ${DEVICE} at /staging."
	    exit 1
	fi

	mkdir /staging/condor
	chown condor:condor /staging/condor
	mkdir /staging/tmp
	chmod ugo+rwxt /staging/tmp
    else
	echo "++++++ Partition labeled 'ephemeral0' does not exist."
	echo "++++++ /staging will not be configured"
    fi
fi

echo "++++++ Restart condor services to reflect configuration changes"
service condor restart

# Normal exit status
echo "++++++ Finished!"
exit 0
