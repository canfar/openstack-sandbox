# CANFAR (vmod+proc) services with OpenStack

This document explores the implementation CANFAR vmod and proc services with OpenStack using VMs modified to run in the KVM hypervisor (https://github.com/canfar/openstack-sandbox/blob/master/CANFAR2OpenStack.md). The test environment for this work is the Cybera Rapid Access Cloud (https://github.com/canfar/openstack-sandbox#cybera-test-environment).

Features that are required to implement CANFAR services include:

* **Dynamic resource allocation** (users can request specific amounts of **memory**, **numbers of cores**, and **temporary storage space** on execution nodes) (proc)

* **Central repository for VMs** that resides outside of specific OpenStack clouds, with a URL that can be provided to access it (vmod/proc)

* **A time limit for instances** (vmod/proc)

* **Ability to use images created during OpenStack vmod sessions for batch processing** (proc)

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

2. Additional minimum requirements on the ```Root Disk``` and ```RAM``` can be set *intrinsically to the VM image*, using, e.g., ```glance image-update [image_name] --min-ram=2000 --min-disk 1```.

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

Note that the ```size``` is 0, but ```min_disk``` is set to 20, matching the root disk size for the flavor, ```m1.small```.

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

In current OpenStack clouds, users cannot generate flavors, which gives them less fine-grained control of their VM instances. However, most users probably do not care about this level of control, and giving them a small number of flavors (less than 20 say) should be perfectly manageable, and would most likely meet all user requirements. Adding flavors to an OpenStack cloud is trivial for an administrator, and will not happen very often, so we can handle this manually at first.

**Question:** is managing cross-clouds flavors necessary?

Note that flavors can be customized to make them accessible only to specific users, e.g.
```$ nova flavor-access-add <flavor-id> <project-id>```

This would allow us to generate [flavors](http://docs.openstack.org/admin-guide-cloud/content/customize-flavors.html) that don't interfere with other users of a given OpenStack cloud.

For batch processing, the flavors defined on OpenStack clouds will define the requirements for Nimbus.

**Question:** could Cloud Scheduler actually force the fine-grained requirements on VMStorage, VMMemory, VMCores to Nimbus clouds instead of the user?

### Ephemeral storage and the /staging partition

As we saw above, the temporary scratch storage space (called Ephemeral Storage in the OpenStack/Amazon world) is part of a given VM flavor. Use cases of large scratch storage spaces (more than ~100GB) have yet to be demonstrated to be efficient.

**Question:** are we imposing a limit to the ephemeral storage? If yes, are we offering a more efficient (such as shared VM distributed efficient storage with full POSIX compliance) to users requiring more?

CANFAR VM instances have temporary storage mounted at /staging. Presently the device used for this space is hard-wired in ```/etc/fstab```, typically as ```/dev/sdb``` or ```/dev/xvdb```. With OpenStack, **ephemeral** storage may be defined as part of the flavor. When an instance is executed under **KVM**, the local device will be set to ```/dev/vdb```.


#### Handling scratch space with filesystem labels

One possible solution is to use filesystem labels to identify ```/staging```, so that the ```/etc/fstab``` entry can be changed to something generic:
```
LABEL=/staging               /staging                ext2    defaults        0 0
```

With OpenStack, it may be possible to configure the ephemeral partition so that it has a label using the ```virt_mkfs``` option in ```nova.conf``` ([some information about it](https://access.redhat.com/site/documentation/en-US/Red_Hat_Enterprise_Linux_OpenStack_Platform/4/html/Configuration_Reference_Guide/list-of-compute-config-options.html]). The default label is ```ephemeral0```. See also ```nova boot --ephemeral size=<size>[,format=<format>]```. After consulting with people at Cybera, this is a general configuration option that would affect all users. We could ulimately replace the few Nimbus clouds (where we are the only users) scratch disk label to match the label of the OpenStack cloud default. Therefore the ```/etc/fstab``` entry would become:

```
LABEL=ephemeral0               /staging                ext2    defaults        0 0
```

For configuration, we will only use OpenStack, so this simple solution can easily be made to work.

For batch processing, Cloud Scheduler gives a hard-coded value of ```blankdisk1``` in the cloud scheduler generation of a nimbus XML file ([link to code](https://github.com/hep-gc/cloud-scheduler/blob/master/cloudscheduler/nimbus_xml.py)). It may be possible to modify things so that the staging partition is indeed labeled, with the same value as that used by KVM.

#### Handling scratch space with an init script

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

    See [this web page](http://docs.openstack.org/trunk/openstack-ops/content/snapshots.html) for additional issues regarding the state of memory, disk flushes etc.

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

## VM time limits

OpenStack only supports "persistent" VMs, so VMs will remain up until a shutdown call (or a system crash). This is actually a preferable solution for users, if sufficient resources are available. However, for batch processing a few hundreds VMs might boot up, and lifetime management needs to be included. Cloud Scheduler already implements the ability to explicitly delete instances once they have timed-out (e.g., automatically issuing ```$ nova delete vmod_instance_name```), so no additional development should be required.


## VM Pool of IP addresses

For persistent VMs, it is necessary to have at least one floating IP available for one tenant (group). It is possible to work only with the VNC console for basic commands, so the IP does not always have to be available. However for heavier development on the OpenStack VM, it would be necessary to have it available at all times. This is a requirement we could handle case by case.
Once connected to an OpenStack cloud through either the VNC console or a floating IP, any VMs booted by the same tenant can be connected. Complex network schemes can be designed for the OpenStack tenant with the neutron client. Connecting between tenants may or may not be possible, but this has yet to be explored in the [documentation](http://docs.openstack.org/admin-guide-cloud/content/tenant-provider-networks.html).
For cloud to cloud communication, one floating IP for each cloud is necessary. Between OpenStack clouds, one could discover the pool of IPs used by the tenant using the nova client, e.g. `nova floating-ip-list `.

## Batch processing after OpenStack vmod session

If we use OpenStack/KVM for vmod sessions, but continue to use Nimbus/Xen for batch processing, we will need to ensure that these images are backwards compatible.

### Modifying existing VMs

The most basic usage scenario is maintenance of an existing CANFAR VM that has already been upgraded to dual-boot Nimbus/Xen and OpenStack/KVM. The image would have to be uploaded to the OpenStack cloud using **glance** and then instantiated, either with **nova** commands, or through the dashboard. When configuration work is finished, there are two ways to store the work:

1. Using the existing **vmsave** method within the VM, which would ultimately copy the image back to a user's VOSpace, preserving the **raw** format that is currently used (and compatible with both cloud types).

2. Using the native OpenStack **snapshot** method (either through the dashboard, or executing a **nova** command outside the running VM), and then downloading the resulting image using **glance**. The image type is **qcow2** in this case.

* **Nimbus may be able to execute an image stored in qcow2 format** although with a number of caveats (http://www.nimbusproject.org/docs/current/admin/reference.html#qcow2):
  1. install qemu-nbd on execution hosts
  2. set qcow2 support to true (http://www.nimbusproject.org/docs/current/admin/reference.html#qcow2-config)
  3. **KVM** is a prerequisite
  4. **nimbus >= 1.2** is a prerequisite (versions at UVic and Breezy are not new enough)

  None of this has been successfully tested yet.

* **qcow2 images can be converted back to raw:**
  * ```qemu-img convert -f qcow2 -O raw vm_12.04_staging_snapshot.qcow2 vm_12.04_staging_snapshot.img``` - **very fast**, sparse image file.
  or
  * ```sudo virt-sparsify --convert raw vm_12.04_staging_snapshot.qcow2 vm_12.04_staging_snapshot.img``` - **slower**, not a sparse image file.

  It has been demonstrated that these raw-converted images can boot both under Nimbus/Xen and OpenStack/KVM.

### Size of VM snapshots

Snapshots of an instance taken with OpenStack end up with the size of the instance, rather than the original image that was uploaded. For example, the following shows the size of a dual-boot raw image before uploading with glance:
```
$ qemu-img info vm_partitioned_12.04_staging.img
image: vm_partitioned_12.04_staging.img
file format: raw
virtual size: 10G (10737418240 bytes)
disk size: 10G
```
If we use glance to show its properties after uploading, we see the same size:
```
$ glance image-show vm_12.04_staging
+------------------+--------------------------------------+
| Property         | Value                                |
+------------------+--------------------------------------+
| checksum         | 21eac02c6924680bc10b29032532af08     |
| container_format | bare                                 |
| created_at       | 2014-05-30T18:57:50                  |
| deleted          | False                                |
| disk_format      | raw                                  |
| id               | 01e99af7-5351-41eb-886f-06d0091cc86f |
| is_public        | False                                |
| min_disk         | 0                                    |
| min_ram          | 0                                    |
| name             | vm_12.04_staging                     |
| owner            | 3fde3fdfae384a659215d0197953722f     |
| protected        | False                                |
| size             | 10737418240                          |
| status           | active                               |
| updated_at       | 2014-05-30T18:59:59                  |
+------------------+--------------------------------------+
```
Now if we take a snapshot, it appears larger. The smallest stock image that could handle a 10G image was m1.small with 20G for root:
```
$ glance image-show vm_12.04_staging_snapshot
+---------------------------------------+--------------------------------------+
| Property                              | Value                                |
+---------------------------------------+--------------------------------------+
| Property 'base_image_ref'             | 01e99af7-5351-41eb-886f-06d0091cc86f |
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
| Property 'instance_uuid'              | fdf39e8e-c67d-48f3-baf2-65630a2e4e99 |
| Property 'os_type'                    | None                                 |
| Property 'owner_id'                   | 3fde3fdfae384a659215d0197953722f     |
| Property 'user_id'                    | 95b8822c449d401fa224710395262e06     |
| checksum                              | 83c374cfba262300ec6de13fe501289a     |
| container_format                      | bare                                 |
| created_at                            | 2014-06-05T20:09:57                  |
| deleted                               | False                                |
| disk_format                           | qcow2                                |
| id                                    | 2209094e-b618-4c17-8d12-9906e09900c8 |
| is_public                             | False                                |
| min_disk                              | 20                                   |
| min_ram                               | 0                                    |
| name                                  | vm_12.04_staging_snapshot            |
| owner                                 | 3fde3fdfae384a659215d0197953722f     |
| protected                             | False                                |
| size                                  | 696132096                            |
| status                                | active                               |
| updated_at                            | 2014-06-05T20:13:23                  |
+---------------------------------------+--------------------------------------+
```
If we download the snapshot, here is what qemu-img tells us about the qcow2 file:
```
$ qemu-img info vm_12.04_staging_snapshot.qcow2
image: vm_12.04_staging_snapshot.qcow2
file format: qcow2
virtual size: 20G (21474836480 bytes)
disk size: 664M
cluster_size: 65536
Format specific information:
    compat: 0.10
```
Converting this to raw:
```
$ qemu-img convert -f qcow2 -O raw vm_12.04_staging_snapshot.qcow2 vm_12.04_staging_snapshot.img
$ qemu-img info vm_12.04_staging_snapshot.img
image: vm_12.04_staging_snapshot.img
file format: raw
virtual size: 20G (21474836480 bytes)
disk size: 1.8G
```
The output image is *sparse*, which is why the disk size is 1.8G, whereas the virtual size is 20G. If we use the ```virt-sparsify --convert``` method, the file will actually occupy 20G.

You can then resize the image to the original size of 10G (if you are sure, in advance, that no data exist in the extra 10G!):
```
$ qemu-img resize vm_12.04_staging_snapshot.img 10737418240
Image resized.
$ qemu-img info vm_12.04_staging_snapshot.img
image: vm_12.04_staging_snapshot.img
file format: raw
virtual size: 10G (10737418240 bytes)
disk size: 1.8G
```

**Question:** If we continue to use **vmsave**, what happens to the image size when executed from an instance running in an OpenStack cloud?

### Creating new VMs from stock images

The other usage scenario is the creation of completely new VMs.

* We can continue to support **dual-bootable golden images** using the Linux distributions of our choosing (probably dropping SL5), ensuring they are uploaded to the OpenStack clouds and available to users in advance.

* It would be nice to support **stock cloud images provided by major distributions**. However, there are a number of issues:
  1. We will need to provide scripts, or at least describe, the installation of software required by our batch system:
      1. install condor (```apt-get|yum install condor```)
      2. ```wget http://www.canfar.phys.uvic.ca/vospace/nodes/canfar/config/condor_config.local?view=data -O /etc/condor/condor_config.local```
      3. then, depending on the distribution, it needs to put another file in ```/etc/init.d/coud_scheduler and /etc/sysconfig/cloud_scheduler```
  2. We may need to convert the resulting qcow2 images into raw format
  3. **Initial tests** to boot stock cloud Ubuntu 14.04 images (converted to raw format) have been **unsuccessful**.
     Perhaps the problem is that hosts are using Scientific Linux 5 with no support for ext4 filesystems? Tried converting to ext3:
    ```
    $ truncate -s 5368709120 test_14.04_snapshot_raw_ext3.img
    $ virt-format -a test_14.04_snapshot_raw_ext3.img --partition=mbr --filesystem=ext3
    $ sudo guestfish --ro -a test_14.04_snapshot_raw.img -m /dev/sda1  -- tar-out / - | sudo guestfish --rw -a test_14.04_snapshot_raw_ext3.img -m /dev/sda1 -- tar-in - /
    ```
    This procedure will lose the bootloader, so install **SYSLINUX** from guestfish. Update ```/boot/syslinux.cfg``` and ```/etc/fstab```. Also ```set-e2label /dev/sda1 cloudimg-rootfs```.

    This gets us to:

    ```
    Booting from Hard Disk...
    Booting the kernel
    Loading /boot/vmlinuz-3.13.0-24-generic........
    Loading /boot/initrd.img-3.13.0-24-generic.........ready.
    ```
    at which point it halts.
    Further tests ongoing...
