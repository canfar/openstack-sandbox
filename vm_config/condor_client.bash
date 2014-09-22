#!/bin/bash
# Shell script for installing Condor to enable batch processing with CANFAR

# Check for previously-installed Condor and exit if found
if [ -d /etc/condor ]; then
    echo "(HT)Condor already installed. Exiting..."
    exit 0
fi

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
        echo "ERROR: Unable to identify Redhat-like OS"
        exit 1
    else
        echo "Installing wget and condor..."
        yum -y install wget condor
        if [[ "$?" != "0" ]]; then
            echo "ERROR: failed to install wget and/or condor"
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

        echo "Installing condor..."
        DEBIAN_FRONTEND=noninteractive apt-get -y install condor
        if [[ "$?" != "0" ]]; then
            echo "Didn't work. Try installing htcondor..."
            DEBIAN_FRONTEND=noninteractive apt-get -y install htcondor
            if [[ "$?" != "0" ]]; then
                echo "Still didn't work. Exiting..."
                exit 1
            fi
        fi

        echo "Installing wget..."
        apt-get -y install wget

    else
        echo "Unable to identify OS. Exiting..."
        exit 1
    fi
fi

# Copy in custom configuration
echo "Updating condor config..."
wget "https://raw.githubusercontent.com/canfar/openstack-sandbox/master/vm_config/condor_config.canfar" -O /etc/condor/config.d/condor_config.canfar

if [[ "$?" != "0" ]]; then
    echo "Error: Failed to update the condor configuration."
    exit 1
fi

# Normal exit status
exit 0