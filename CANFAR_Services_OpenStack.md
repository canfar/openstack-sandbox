# CANFAR (vmod+proc) services with OpenStack

This document explores the implementation CANFAR vmod and proc services with OpenStack using VMs modified to run in the KVM hypervisor (https://github.com/canfar/openstack-sandbox/blob/master/CANFAR2OpenStack.md). The test environment for this work is the Cybera Rapid Access Cloud (https://github.com/canfar/openstack-sandbox#cybera-test-environment).

Features that are required to implement CANFAR services include:

* **Dynamic resource allocation** (users can request specific amounts of **memory**, **numbers of cores**, and **temporary storage space** on execution nodes) (proc)

* **Central repository for VMs** that resides outside of specific OpenStack clouds, with a URL that can be provided to access it (vmod/proc)

* **Central dashboard** to provide a single interface to multiple OpenStack clouds

* **A time limit for the life of an instance** (vmod/proc)

## Dynamic resource allocation

CANFAR submission files can specify **memory**, **CPU cores**, and **temporary storage space**. In OpenStack, one must predefine **flavors**, which are specific choices for these (and other) parameters, required of the execution hardware. See http://docs.openstack.org/user-guide-admin/content/dashboard_manage_flavors.html. The relevant parameters in OpenStack parlance are:

| Parameter            | Meaning                                                |
|----------------------|--------------------------------------------------------|
| ```RAM```            | RAM to use (MB)                                        |
| ```VCPUs```          | Number of virtual CPUs                                 |
| ```Ephemeral Disk``` | Temporary disk space (GB) available for ```/staging``` |
| ```Root Disk```      | Disk space (GB) for the root (```/```) partition       |

It appears that any flavor (a hardware template) can be chosen to boot a given VM image, with some caveats:

1. The ```Root Disk``` must be large enough to accomodate the image. If not, when executed through the OpenStack dashboard, it fails with the following message: ```Error: Instance type's disk is too small for requested image```.

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

It is also interesting to look at the properties of a **snapshot**. The following details are for a VM instantiated from one of Cybera's base Ubuntu 14.04 images):

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

It will probably be necessary to generate a grid of flavors to accomodate the full range of CANFAR user requests, following some naming convention, like ```m1024c1s10``` for 1024 M of memory, 1 core, and 10 G of temporary storage. At job submission time we will identify the closest flavor that *meets or exceeds* the criteria requested by the user.

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

1. Is it easy to generate flavors on all of the OpenStack clouds that will be serving CANFAR? If not, we can require each cloud provider to incorporate a CANFAR defined "flavor matrix".

    Note that flavors can be customized to make them accessible only to specific users, e.g.,
    
    ```$ nova flavor-access-add <flavor-id> <project-id>```

    This would allow us to generate flavors that don't interfere with other users of a given OpenStack cloud. See http://docs.openstack.org/admin-guide-cloud/content/customize-flavors.html.

2. What is the actual limit on number of flavors? Would we need to clean up old flavors that we're not using? Based on this bug report, it looks like we can have *at least* 1000: https://bugs.launchpad.net/nova/+bug/1166455

### Mounting the /staging partition

CANFAR VM instances have temporary storage mounted at /staging. Presently the device used for this space is hard-wired in ```/etc/fstab``` as ```/dev/sdb```. With OpenStack, **ephemeral** storage may be defined as part of the flavor. When an instance is executing under **KVM**, the local device will be set to ```/dev/vdb```.


#### filesystem labels

One possible solution is to use filesystem labels to identify ```/staging```, so that the ```/etc/fstab``` entry can be changed to something generic:
```
LABEL=/staging               /staging                ext2    defaults        0 0
```

With OpenStack, it may be possible to configure the ephemeral partition so that it has a label using the ```virt_mkfs``` option in ```nova.conf``` (see https://access.redhat.com/site/documentation/en-US/Red_Hat_Enterprise_Linux_OpenStack_Platform/4/html/Configuration_Reference_Guide/list-of-compute-config-options.html). The default label is ```ephemeral0```. See also ```nova boot --ephemeral size=<size>[,format=<format>]```. After consulting with people at Cybera, this is a general configuration option that would affect all users, and could not be associated only with CANFAR users. It is therefore **not a good solution**.

In the existing system, the device mounted as ```/staging``` in a vmod does not appear to have a label. However, there is something about a hard-wired partition name of ```blankdisk1``` in the cloud scheduler generation of a nimbus XML file (https://github.com/hep-gc/cloud-scheduler/blob/master/cloudscheduler/nimbus_xml.py). It may be possible to modify things so that the staging partition is indeed labeled. If it isn't possible to change the label used by OpenStack, maybe the Nimbus label could be changed to match what OpenStack uses.

#### init script

Another brute-force method is to detect the devices at boot time using an init script.

First, comment-out the line that mounts ```/staging``` in ```/etc/fstab```:

```
#/dev/sdb               /staging                ext2    defaults        0 0
```

Next, create an executable script that will mount the device dynamically, with the following contents, in ```/etc/init.d/mount_staging```:

```
#!/bin/bash
#
# Mount /staging
#
# - Under OpenStack/KVM we expect nova to add the label "ephemeral0"
#   on /dev/vdb
#
# - Under Nimbus/Xen we expect the label "blankpartition0"
#   on /dev/sdb or /dev/xvdb depending on the distro
#

# Already Mounted?
if grep -q /staging /etc/mtab; then
    exit 0
fi

# Create mount point if needed
mkdir -p /staging

# Choose a device
if [ -b /dev/disk/by-label/ephemeral0 ]; then
    # The nova default for OpenStack
    DEVICE=/dev/disk/by-label/ephemeral0

elif [ -b /dev/disk/by-label/blankpartition0 ]; then
    # The label expected for Nimbus/Xen
    DEVICE=/dev/disk/by-label/blankpartition0

elif [ -b /dev/vdb ]; then
    # If no label, this might be the device under KVM
    DEVICE=/dev/vdb

elif [ -b /dev/sdb ]; then
    # If no label, this might be the device under Xen (SL 5)
    DEVICE=/dev/sdb

elif [ -b /dev/xvdb ]; then
    # If no label, this might be the device under Xen (Ubuntu 12.04)
    DEVICE=/dev/xvdb

else
    echo "Couldn't mount /staging! No valid device could be found."
    exit 1
fi

# Try mounting
mount -o defaults ${DEVICE} /staging

if [ "$?" -ne "0" ]; then
    echo "Failed to mount ${DEVICE} at /staging."
    exit 1
fi

```

With **guestfish**, if the script already exists locally, you can add it to an image like this

```
><fs> upload mount_staging /etc/init.d/mount_staging
><fs> chmod 0755 /etc/init.d/mount_staging
```

For **Scientific Linux VMs**, edit ```/etc/rc.d/rc.local``` to call the mount script before creating directories within ```/staging```:

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

Similarly, for **Ubuntu VMs**, edit ```/etc/rc.local```:

```
#!/bin/sh -e
#
# rc.local
#
# This script is executed at the end of each multiuser runlevel.
# Make sure that the script will "exit 0" on success or any other
# value on error.
#
# In order to enable or disable this script just change the execution
# bits.
#
# By default this script does nothing.

# Mount /staging
/etc/init.d/mount_staging

# Create condor EXECUTE dir
mkdir -p /staging/condor
chown condor:condor /staging/condor

# Added for CANFAR VM
mkdir -p /staging/tmp
chmod ugo+rwxt /staging/tmp

exit 0
```

Note that we may want to check for bad exit status from ```mount_staging```, otherwise the following ```mkdir``` calls will create the ```/staging``` directory on the root filesystem.

## VM Repository

In the existing CANFAR system, all images reside in VOSpace. A snapshot of running VMs can be stored to a user's VOSpace using **vmsave**. This feature is primarily used to store images that will subsequently be used for batch processing (proc), following an interactive vmod session to install software. The job submission file used by proc then provides a URL to the stored image location.

OpenStack stores images internally, and they are managed using **glance** (upload/download images, list available images, etc.). Snapshots of running VMs can be made in two ways:

1. **From outside of the running VM** using ```nova image-create```. Even though this is executed externally, the resulting image is stored within the cloud, and would need to be fetched using **glance** if a "local" copy in VOSpace were desired.

    Note: The image creation happens asynchronously... we need to figure out how to query whether it's finished or not. One silly way is to check the ```status``` column for the given image name in the output from ```glance image-list```. There will certainly be something in the REST API for this.

    See this web page for additional issues regarding the state of memory, disk flushes etc.: http://docs.openstack.org/trunk/openstack-ops/content/snapshots.html.

2. **From a Horizon Dashboard instance**. This is equivalent to executing **nova** commands, and again, **glance** would be needed to copy an image into VOSpace once it is completed.

When it comes to batch processing, if we intend to continue providing a URL to the image in VOSpace in the submission files, it will be up to the scheduler to ensure that the cloud that ultimately executes the job has a copy of the desired VM.

**Initially we will only have access to a single OpenStack cloud**. To make life easier, we might simply let OpenStack manage our VMs for us in the early stages. The only modification needed would be to provide an **image name** in the job submission file, rather than a full URL.

**When we scale to multiple clouds** there are two obvious models that we might pursue:

1. Use a **central** repository (i.e., VOSpace) to store the images:
    * We will need a mechanism to ensure that snapshots of running configuration instances are copied back into VOSpace so that they can later be used for batch processing. A simple solution may be a script that initiates ```nova image-create```, waits until it is done, and then uses **glance** to copy it back to VOSpace. Alternatively, if we create our own CANFAR-themed dashboard, we might add this functionality there.
    * For batch processing the scheduler will have to ensure that the correct version of the VM image exists on the target cloud. The checksum of images stored internally to an OpenStack cloud can be queried, so we can avoid unnecessarily uploading images.
    
2. A **distributed** model in which we attempt to synchronize the images stored among the various clouds as needed:
    * We wouldn't necessarily need to download a snapshot image from a cloud once a configuration session is finished.
    * Whenever we start a new job (either proc, or vmod), we provide a name for the image that we want to instantiate. We would have to query all of the clouds to see which one has the newest version (with that name), and transfer a copy of it to a different target cloud if needed. If the job is executed on the same cloud where this newest version exists, no transfer is needed.
    * This is sort of like VOSpace, so we would need to ensure full sets of the data on redundant subsets of the clouds to account for downtime.

## Central Dashboard

CANFAR currently has a single, custom dashboard that handles jobs on all of the available clouds. The standard dashboard for OpenStack is **Horizon**, and it is likely that each OpenStack cloud used by CANFAR will have its own instance of Horizon running.

A simple way to manage multiple clouds is to provide a CANFAR-themed "Summary Usage" page for the user, querying the cloud resource usage API, with a link to each cloud dashboard.

However, it may be desirable to run a local instance of Horizon with CANFAR branding. According to this web page, http://docs.openstack.org/developer/horizon/topics/deployment.html, one modifies ```local_settings.py```, primarily to set
```
OPENSTACK_HOST = "keystone-yyc.cloud.cybera.ca"
```
which in this example enables us to interface the Cybera cloud.

For further information on dashboard installation and configuration see: http://docs.openstack.org/grizzly/openstack-compute/install/apt/content/installing-openstack-dashboard.html

Judging from the Horizon source code (https://github.com/openstack/horizon), it's clear that Horizon is using the Python SDK (look in ```openstack_dashboard/api/```), similar to the Python CLI (e.g., **glance**, **nova**, **keystone**), which wraps underling REST calls. See http://docs.openstack.org/api/quick-start/content/ for further details.

According to this web page, http://www.metacloud.com/2014/03/17/openstack-horizon-controlling-cloud-using-django/, Horizon consists of a modular base library, and a reference dashboard that combines them in to a useable application. If at some point in the future we wish to build a "meta dashboard" to handle multiple clouds, it's conceivable that we might build such an application from existing components in the Horizon core libraries. If and when this is needed, we might also tackle the problem of the central VM repository mentioned in the previous section as part of this work.

In the short term it will probably suffice to install and customize a local CANFAR horizon dashboard from package repositories.

### Horizon and regions

Note that Horizon already understands an OpenStack concept called **regions**. As an example, on the Cybera RAC, the user is presented with a choice of region at login time (https://cloud.cybera.ca/). This is the coarsest segregation scheme available with OpenStack (see http://docs.openstack.org/trunk/openstack-ops/content/scaling.html). Another good blog post is here: http://kimizhang.wordpress.com/2013/08/26/openstack-zoning-regionavailability-zonehost-aggregate/. Regions have separate **nova** installations, and separate API endpoints (i.e., with something like **glance** you would have to specify which region you are talking about). The only shared service is **keystone**.

Question:

Might it be possible to support multiple OpenStack clouds under the CANFAR umbrella using regions? These documents look interesting:

* DAIR OpenStack Modifications: https://docs.google.com/document/d/1Dxxhgc2USQrxCAfYzD8Nk3RS9ZZpocavIHie0FfN7Ls/edit

* Support multiple endpoints for the same service in Horizon: https://blueprints.launchpad.net/horizon/+spec/multiple-service-endpoints

## vmod time limits

There is no obvious way to implement a time limit for a vmod using intrinsic features of OpenStack. However, Cloud Scheduler will have the ability to explicitly delete instances once they have timed-out (e.g., automatically issuing ```$ nova delete vmod_instance_name```), so no additional development should be required.
