# Running CANFAR (vmod+proc) services with OpenStack

This document explores how to implement CANFAR vmod and proc services using VMs modified to run in the KVM hypervisor (https://github.com/canfar/openstack-sandbox/blob/master/CANFAR2OpenStack.md). The test environment for this work is the Cybera Rapid Access Cloud (https://github.com/canfar/openstack-sandbox#cybera-test-environment).

## Dynamic resource scheduling

CANFAR submission files can specify **memory**, **CPU cores**, and **temporary storage space**. In OpenStack, one must predefine **flavours**, which are specific choices for these three parameters. See http://docs.openstack.org/user-guide-admin/content/dashboard_manage_flavors.html.

It will be necessary to generate a grid of flavours following some naming convention, like ```m1024c1s10``` for 1024 M of memory, 1 core, and 10 G of temporary storage. If we proceed with the same style of submission file, at the time of scheduling it will be necessary to find the closest flavour that *meets or exceeds* the criteria requested by the user.

Adding flavours seems to be trivial, and there is no obvious limit to how many can be defined. Perhaps they could be generated on-the-fly?

## /staging partition

CANFAR VM instances have temporary storage mounted at /staging. This is storage local to the execution node, and therefore fast. Presently the device used for this space is hard-wired in ```/etc/fstab``` as ```/dev/sdb```. With OpenStack, **ephemeral** storage may be defined as part of the flavour. When an instance is executing under **KVM**, the local device will probably be something like ```/dev/vdb```.

One way to handle this problem is to detect the devices at boot time using an init script. For example, with a Scientific Linux 5 VM, comment-out the line that mounts ```/staging``` in ```/etc/fstab```:

```
#/dev/sdb               /staging                ext2    defaults        0 0
```

Next, create an executable script that will do this dynamically with the following contents in ```/etc/init.d/mount_staging```:

```
#!/bin/bash
# Mount staging... expect /dev/vdb for KVM, /dev/sdb for Xen


# Already Mounted?
if mount | grep -q /staging; then
        exit 0
fi

# Create mount point if needed
if [ ! -d /staging ]; then
        mkdir /staging
fi

# Choose a device
if [ -e /dev/vdb ]; then
        DEVICE=/dev/vdb
elif [ -e /dev/sdb ]; then
        DEVICE=/dev/sdb
else
        echo "Couldn't mount /staging! No /dev/vda (KVM) nor /dev/sdb (Xen)"
        exit 1
fi

# Try mounting
mount -o defaults ${DEVICE} /staging

if [ "$?" -ne "0" ]; then
        echo "Failed to mount ${DEVICE} at /staging."
fi

```

Finally, edit ```/etc/rc.d/rc.local``` to call the mount script before creating directories within ```/staging```:

```
#!/bin/sh
#
# This script will be executed *after* all the other init scripts.
# You can put your own initialization stuff in here if you don't
# want to do the full Sys V style init stuff.

touch /var/lock/subsys/local

# Mount /staging
/etc/init.d/mount_staging

# Create condor EXECUTE dir
mkdir -p /staging/condor
chown condor:condor /staging/condor

# Create user /staging/tmp dir
mkdir -p /staging/tmp
chmod ugo+rwxt /staging/tmp

```

Note that we may want to skip the ```mkdir``` lines if the call to ```mount_staging``` fails (otherwise they will simply create the ```/staging``` directory on the root filesystem.
