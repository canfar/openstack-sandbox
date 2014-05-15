# CANFAR Migration to OpenStack

Summarized here are some initial experiments modifying CANFAR Xen-based VMs (images) so that they can be executed with the OpenStack hypervisor.


## CANFAR VMs

Three CANFAR "golden" VMs have been tested: sl5_amd64, sl6_amd64, and ubuntu12.04_amd64.


## Cybera Test environment

The Cybera Rapid Access Cloud has been used for these tests: http://www.cybera.ca/projects/cloud-resources/rapid-access-cloud/

Cybera has some good documentation here that is probably useful for OpenStack usage in general:
http://www.cybera.ca/projects/cloud-resources/rapid-access-cloud/documentation/

### Account generation and login to work VM

Account generation using a gmail address is trivial through that first web page. A group called **canfar** was created for us to share resources while testing. Switching between the initial user's project and the shared project is achieved through the **Current Project** pull-down menu on the left under **Project**. Their helpdesk email address is rac-admin@cybera.ca

Modifications to CANFAR VMs have been undertaken on a Cybera VM to which the single floating ip available to the project has been associated. The base image is Ubuntu 14.04, and the initial instance was called **canfar_work**. Snapshots of this instance are being saved periodically to **canfar_work_snapshot**.

Extra persistent storage for our work is accomplished using Volumes. Current work is using a 100GB volume named **canfar_image_store**. Once a new volume is created and associated with a running instanced (through the dashboard), the virtual device can be identified using
```
$ sudo fdisk -l
```
It can then be formatted and mounted like this:
```
$ sudo mkfs -t ext4 /dev/vdc
$ sudo mkdir /mnt/images
$ sudo mount /dev/vdc /mnt/image_store
```

The floating ip is associated with the running instance through **Access & Security** -> **Floating IPs**.

In order to access VMs, keypairs must be generated. This is accomplished through **Access & Security** -> **Keypairs**. When you **Create Keypair** the system will provide you with the private key for download. For shared access to VMs we distribute amongst ourselves copies of this private key. The public key is injected when an instance is launched.

You then connect like this (to an ubuntu VM, and you obtain the ip address from the **Instances** window):
```
$ ssh -i canfar_cybera.pem ubuntu@199.116.235.82
```

### Testing VMs

Initially CANFAR VMs are simply copied to the mounted volume on our work VM, e.g.,
```
$ scp -i canfar_cybera openstack_testing_sl6.img.gz ubuntu@199.116.235.82:/mnt/image_store/
```

In order to make the image available, it needs to be uploaded using **glance**. To install some of the basic OpenStack command-line tools on Ubuntu:
```
$ sudo apt-get install pip python-dev libffi-dev libssl-dev
$ sudo pip install python-novaclient
$ sudo pip install python-glanceclient
$ sudo pip install python-cinderclient
```
Next, some environment variables need to be set to enable authentication. In the Cybera dashboard navigate to **Access & Security** -> **API Access** where you can download an **OpenStack RC File**. It should be saved on the work VM somewhere (e.g., ~/canfar-openrd-echapin.sh) and then sourced.

To see if it is working, request a list of images with **glance**:
```
$ glance index

ID                                   Name                           Disk Format          Container Format     Size          
------------------------------------ ------------------------------ -------------------- -------------------- --------------
3601cea1-f4ec-4add-9f6b-2e712b071372 ed_test_sl5_kernel2_initrd     raw                  bare                     6166376448
fba0e422-ad15-4fe2-a334-9e249921f9f3 ed_test_sl5_kernel3_initrd     raw                  bare                     6166376448
6ed03338-7bfe-403f-b561-41880832c669 canfar_work_snapshot           qcow2                bare                     2139881472
18f83c1e-dd49-4b8d-a429-7a29ebdcbaef ed_test_sl5_4                  raw                  bare                     5974061056
ffe6c15f-d79a-4563-9ebf-baa328779156 ed_test_sl6_5                  raw                  bare                    10568916992
b6dc060a-cdf1-40cb-a289-8336b6422fca ed_test_12.04_nopart2_generic  raw                  bare                    10568916992
372dfcac-445f-4caa-a57a-0abcddce8558 canfar-ubuntu-12.04-mbr        raw                  bare                    11811160064
cc4a5014-1a99-4d65-811a-8c0184b15dd7 Ubuntu 14.04                   qcow2                bare                      252707328
65c97140-0390-4446-a639-923afb712f16 Debian 7.4                     qcow2                bare                      279679488
8e7f5081-69de-4836-be72-660d03088f00 RAC Proxy                      qcow2                bare                      500367360
12a51c55-b7cb-4fdb-8055-1138a9ccab4f CentOS 6.5                     qcow2                bare                      841613312
1039d5c9-7c78-499e-84e9-62275d0f87bc Ubuntu 13.10                   qcow2                bare                      248119808
6ad274e3-9fd9-40ae-9e4f-2e5fec13bebe Ubuntu 12.04.4                 qcow2                bare                      260178432
8d3d6016-8eb3-41dd-b886-d388044b5faf Fedora 20                      qcow2                bare                      214106112
79f01306-8ea4-40d5-972e-6c78247009a6 Windows Server 2012 R2         qcow2                bare                     7980056576
a9e4eb3a-aba1-4a87-b455-b780f888d20b Windows Server 2008 R2         qcow2                bare                     7209615360
```

Next, navigate to the directory with the CANFAR VM, unzip it, and upload it:
```
$ cd /mnt/image_store
$ gunzip canfar_cybera openstack_testing_sl6.img.gz
$ image-create --name="canfar_cybera openstack_testing_sl6" --container-format=bare --disk-format=raw < canfar_cybera openstack_testing_sl6.img
```

Back on the dashboard you can now see this VM under **Images & Snapshots**. Next to its name you can click on **Launch** to create an instance. The **Instance Name** is your choice. A **Flavor** of at least *m1.small* is probably necessary to accomodate the space requirements of most CANFAR VMs. If these are CANFAR VMs you will already be in possession of the relevant certs, so no extra keypair (under **Access & Security**) need be specified. You then click **launch** and wait a couple of minutes.

When finished, the new instance is visible under **Instances**, including the local ip address (only accessible from the work VM with the floating ip). Clicking on its name gives you additional details. Switching to the **Console** tab provides a VNC connection to view the console. Unmodified CANFAR VMs will not boot.


### Making CANFAR VMs bootable with OpenStack

There don't appear to be any standard tools for migrating Xen-based VMs to KVM, with one possible exception:
https://access.redhat.com/site/documentation/en-US/Red_Hat_Enterprise_Virtualization/3.2/html-single/V2V_Guide/index.html
However, it seems to be very specialized.

There are also many web pages describing various ways of attacking to the problem. After considerable experimentation, a relatively simple approach seems to work, based on tools provided by **libguestfs**. First install it:
```
$ sudo apt-get install libguestfs
```
While there are many things that can be done with it, the two main features that have been used are **guestmount** which mounts the image and allows you to make modifications directly without needing to boot the VM in a host, and **guestfish** which is a (scriptable) shell that also provides access to many features of **libguestfs**.
This web page is a cookbook for *many* useful tasks: http://libguestfs.org/guestfs-recipes.1.html

#### Bleeding-edge build of libguestfs

Note that the version of **libguestfs** provided by Ubuntu 14.04 is 1.24.5, and even though it is < 1 year old, it does not provide all of the tools mentioned in the cookbook. One notable command missing in this version is **virt-customize** which, among other things, allows you to install packages using the native package management system of the image (yum, apt...). Building a bleeding-edge version of **libguestfs** is not hard, but there are other ways to install packages, so this step is not really necessary.

A local build has been made. The code is cloned from a git repository, http://libguestfs.org/guestfs-recipes.1.html. You will also need the source code for an important dependence called supermin, also a git clone, from https://github.com/libguestfs/supermin. In the **libguestfs** README it describes the build dependencies. You can install most of them on Debian/Ubuntu systems like this:
```
$ sudo apt-get build-dep libguestfs
```
Next, go read http://rwmj.wordpress.com/tag/supermin/ about how to build supermin first, and include the local copy when you build libguestfs. Don't install the code to the system, you execute the local libguestfs commands using the **run** shell script prefix in the build directory (see the README). A local build has been done on the work VM in ```~/source/libguestfs```.

#### SYSLINUX boot loader

CANFAR images do not seem to be bootable. This cookbook entry solves most of our problems by installing the **SYSLINUX** bootloader:

http://libguestfs.org/guestfs-recipes.1.html#install-syslinux-bootloader-in-a-guest

As a pre-requisite we need to install:
```
$ sudo apt-get install extlinux
```
You then need to locate the master boot record from the extlinux install, /usr/lib/extlinux/mbr.bin

Next you create a configuration file for the bootloader, syslinux.cfg, with something like:
```
 DEFAULT linux
 LABEL linux
   SAY Booting the kernel
   KERNEL /vmlinuz
   INITRD /initrd.img
   APPEND ro root=LABEL=/
```
The KERNEL and INITRD will be different for each VM depending on the name of the kernel. Note that the root file system is mounted from a labelled the device. The label is set using **e2label**, and for CANFAR VMs this seems to have already been done (**e2label** can be executed inside **guestfish** if needed). This means that we don't need to specify a specific device name which should help with interoperability, since under Xen the virtual devices have names like ```/dev/xvde```, whereas under KVM they have names like ```/dev/vda```.

Next we fire up **guestfish** to make modifications to the VM, e.g.,

```
$ guestfish -a openstack_testing_sl5_converted.img -i
```
The ```-i``` tries to mount everything in fstab. In one case this failed for some reason. In that case you can ommit the ```-i``` and simply type ```run``` at the guestfish prompt to load the image, and then mount the partition ```mount /dev/sda /```. Otherwise, continue like this:

```

Welcome to guestfish, the guest filesystem shell for
editing virtual machine filesystems and disk images.

Type: 'help' for help on commands
      'man' to read the manual
      'quit' to quit the shell

Operating system: Scientific Linux release 5.9 (Boron)
/dev/sda mounted on /

><fs> upload mbr.bin /boot/mbr.bin
><fs> upload syslinux.cfg  /boot/syslinux.cfg
><fs> copy-file-to-device /boot/mbr.bin /dev/sda size:440
><fs> extlinux /boot
><fs>
```
You will probably still need to edit some files. For example, you may need to change **fstab** to ensure that none of the old ```/dev/xvde``` devices are in there. Switch to using ```LABEL``` if needed. You will also need to check the name and location of the kernel, and edit ```/boot/syslinux.cfg``` accordingly. Note that you can list directory contents and edit files directly from guestfish using, e.g.,

```
><fs> ll /boot
><fs> vi /etc/fstab
><fs> vi /boot/syslinux.cfg
```

When you are finished, exit with ```CTRL-D```.



