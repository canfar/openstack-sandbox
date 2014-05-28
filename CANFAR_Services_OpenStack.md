# CANFAR (vmod+proc) services with OpenStack

This document explores how to implement CANFAR vmod and proc services using VMs modified to run in the KVM hypervisor (https://github.com/canfar/openstack-sandbox/blob/master/CANFAR2OpenStack.md). The test environment for this work is the Cybera Rapid Access Cloud (https://github.com/canfar/openstack-sandbox#cybera-test-environment).

Features that are required to implement CANFAR services:

* Dynamic resource requests (users can request specific amounts of **memory**, **numbers of cores**, and **temporary storage space** on execution nodes) (proc)

* Central repository for VMs that resides outside of specific OpenStack clouds, with a URL that can be provided to access it (proc/vmod)

* A time limit for the life of an instance (vmod)

## Dynamic resource requests

CANFAR submission files can specify **memory**, **CPU cores**, and **temporary storage space**. In OpenStack, one must predefine **flavors**, which are specific choices for these (and other) parameters, required of the execution hardware. See http://docs.openstack.org/user-guide-admin/content/dashboard_manage_flavors.html. The relevant parameters in OpenStack parlance are:

| Parameter            | Meaning                                                |
|----------------------|--------------------------------------------------------|
| ```RAM```            | RAM to use (MB)                                        |
| ```VCPUs```          | Number of virtual CPUs                                 |
| ```Ephemeral Disk``` | Temporary disk space (GB) available for ```/staging``` |
| ```Root Disk```      | Disk space (GB) for the root (```/```) partition       |

It appears that any flavor (a hardware template) can be chosen to boot a given VM image, with some caveats:

1. The ```Root Disk``` must be large enough to accomodate the image. If not, when executed through the OpenStack dashboard, it fails with the following message: ```Error: Instance type's disk is too smal for requested image```.

2. Additional minimum requirements on the ```Root Disk``` and ```RAM``` can be set *in the image* using, e.g., ```glance image-update [image_name] --min-ram=2000 --min-disk 1```.

The size of an image, and the values of ```min_disk``` and ```min_ram``` may be queried from the command line with **glance**. For example, the following shows the details of a CANFAR Scientific Linux 5 VM that was modified to dual-boot under KVM and Xen:

```
$ glance image-show vm_partitioned_sl5_console
+------------------+--------------------------------------+
| Property         | Value                                |
+------------------+--------------------------------------+
| checksum         | d5256289d1ce8b0d73cefb768b772911     |
| container_format | bare                                 |
| created_at       | 2014-05-26T21:50:25                  |
| deleted          | False                                |
| disk_format      | raw                                  |
| id               | 40ad960b-61e0-4fee-94ee-ee0dd43910f6 |
| is_public        | False                                |
| min_disk         | 0                                    |
| min_ram          | 0                                    |
| name             | vm_partitioned_sl5_console           |
| owner            | 3fde3fdfae384a659215d0197953722f     |
| protected        | False                                |
| size             | 10737418240                          |
| status           | active                               |
| updated_at       | 2014-05-26T21:52:41                  |
+------------------+--------------------------------------+
```

In order to boot this VM any values of ```RAM``` and ```Root Disk``` may be chosen, although the latter must be >= 10G to accomodate the image ```size```.

It is also interesting to look at the properties of a **snapshot**. The following details are for a VM instantiated from one of Cybera's base Ubuntu 14.04 images:

```
$ glance image-show canfar_work_snapshot
+---------------------------------------+--------------------------------------+
| Property                              | Value                                |
+---------------------------------------+--------------------------------------+
| Property 'base_image_ref'             | 17b24f7d-acff-4f4e-845e-4d3858d9197e |
| Property 'image_location'             | snapshot                             |
| Property 'image_state'                | available                            |
| Property 'image_type'                 | snapshot                             |
| Property 'instance_type_ephemeral_gb' | 0                                    |
| Property 'instance_type_flavorid'     | 2                                    |
| Property 'instance_type_id'           | 32                                   |
| Property 'instance_type_memory_mb'    | 2048                                 |
| Property 'instance_type_name'         | m1.small                             |
| Property 'instance_type_root_gb'      | 20                                   |
| Property 'instance_type_rxtx_factor'  | 1                                    |
| Property 'instance_type_swap'         | 2048                                 |
| Property 'instance_type_vcpus'        | 2                                    |
| Property 'instance_uuid'              | fe02831d-b0de-42b7-989d-2fb9f6363732 |
| Property 'os_type'                    | None                                 |
| Property 'owner_id'                   | 3fde3fdfae384a659215d0197953722f     |
| Property 'user_id'                    | 95b8822c449d401fa224710395262e06     |
| container_format                      | ovf                                  |
| created_at                            | 2014-05-28T17:27:45                  |
| deleted                               | False                                |
| disk_format                           | qcow2                                |
| id                                    | c530476e-5d87-4a4b-a0e6-10e297c868e0 |
| is_public                             | False                                |
| min_disk                              | 20                                   |
| min_ram                               | 0                                    |
| name                                  | canfar_work_snapshot                 |
| owner                                 | 3fde3fdfae384a659215d0197953722f     |
| protected                             | False                                |
| size                                  | 0                                    |
| status                                | queued                               |
| updated_at                            | 2014-05-28T17:27:45                  |
+---------------------------------------+--------------------------------------+
```

Note that the ```size``` is 0, but ```min_disk``` is set to 20 (presumably matching the root disk size for the flavor, ```m1.small```).

### Flavor handling

It will probably be necessary to generate a grid of flavors to accomodate the full range of CANFAR user requests, following some naming convention, like ```m1024c1s10``` for 1024 M of memory, 1 core, and 10 G of temporary storage. At job submission time we then identify the closest flavor that *meets or exceeds* the criteria requested by the user.

To list existing flavors:

```
$ nova flavor-list
+--------------------------------------+-----------+-----------+------+-----------+------+-------+-------------+-----------+
| ID                                   | Name      | Memory_MB | Disk | Ephemeral | Swap | VCPUs | RXTX_Factor | Is_Public |
+--------------------------------------+-----------+-----------+------+-----------+------+-------+-------------+-----------+
| 1                                    | m1.tiny   | 512       | 5    | 0         | 512  | 1     | 1.0         | True      |
| 2                                    | m1.small  | 2048      | 20   | 0         | 2048 | 2     | 1.0         | True      |
| 3                                    | m1.medium | 4096      | 40   | 0         | 4096 | 2     | 1.0         | True      |
| 4                                    | m1.large  | 8192      | 80   | 0         | 4096 | 4     | 1.0         | True      |
| 5                                    | m1.xlarge | 16384     | 160  | 0         | 4096 | 8     | 1.0         | True      |
| 5d234569-c3e9-4875-a2eb-8137a131b964 | jt.large  | 16384     | 10   | 10        | 2048 | 4     | 1.0         | True      |
| db9e8d81-fe54-4910-9489-a7867a288d56 | me1.small | 2048      | 20   | 20        | 4096 | 2     | 1.0         | False     |
+--------------------------------------+-----------+-----------+------+-----------+------+-------+-------------+-----------+
```

Deleting and creating flavors can be accomplished with ```nova flavor-create``` and ```nova flavor-delete```.

Since adding flavors is trivial, perhaps they can be generated on-the-fly as needed? Questions:

1. Is it easy to generate flavors on all of the OpenStack clouds that will be serving CANFAR?

2. What is the actual limit on number of flavors. Would we need to clean up old flavors that we're not using? Based on this bug report, it looks like we can have *at least* 1000: https://bugs.launchpad.net/nova/+bug/1166455

### Mounting the /staging partition

CANFAR VM instances have temporary storage mounted at /staging. Presently the device used for this space is hard-wired in ```/etc/fstab``` as ```/dev/sdb```. With OpenStack, **ephemeral** storage may be defined as part of the flavor. When an instance is executing under **KVM**, the local device will probably be something like ```/dev/vdb```.

One possible solution is to use filesystem labels to identify ```/staging```, so that the ```/etc/fstab``` entry can be changed to something generic:
```
LABEL=/staging               /staging                ext2    defaults        0 0
```

With OpenStack, it may be possible to configure the ephemeral partition so that it has a labeled partition using the ```virt_mkfs``` option in ```nova.conf``` (see https://access.redhat.com/site/documentation/en-US/Red_Hat_Enterprise_Linux_OpenStack_Platform/4/html/Configuration_Reference_Guide/list-of-compute-config-options.html).

In the existing system, the device mounted as ```/staging``` in a vmod does not appear to have a label. However, there is something about a hard-wired partition name of ```blankdisk1``` in the cloud scheduler generation of a nimbus XML file (https://github.com/hep-gc/cloud-scheduler/blob/master/cloudscheduler/nimbus_xml.py). It may be possible to modify things so that the staging partition is indeed labeled.

Another brute-force method is to detect the devices at boot time using an init script. For example, with a Scientific Linux 5 VM, comment-out the line that mounts ```/staging``` in ```/etc/fstab```:

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

## Central VM Repository

Presently the VM images available to a given OpenStack cloud are stored internally, and must be uploaded using **glance**. If this is the only option, then some sort of mirroring from our VOSpace repository to the clouds will be necessary.

## vmod time limits

There is no obvious way to implement a time limit for a vmod using intrinsic features of OpenStack. It will probably be necessary to implement a cron job that checks the ages of instances, and shuts them down explicitly, e.g.,

```
$ nova delete vmod_instance_name
```
