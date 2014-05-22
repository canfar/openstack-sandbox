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


## Making CANFAR VMs bootable with OpenStack

There don't appear to be any standard tools for migrating Xen-based VMs to KVM, with one possible exception:
https://access.redhat.com/site/documentation/en-US/Red_Hat_Enterprise_Virtualization/3.2/html-single/V2V_Guide/index.html
However, it seems to be very specialized.

There are also many web pages describing various ways of attacking to the problem. After considerable experimentation, a relatively simple approach seems to work, based on tools provided by **libguestfs**. First install it:
```
$ sudo apt-get install libguestfs
```
While there are many things that can be done with it, the two main features that have been used are **guestmount** which mounts the image and allows you to make modifications directly without needing to boot the VM in a host, and **guestfish** which is a (scriptable) shell that also provides access to many features of **libguestfs**.
This web page is a cookbook for *many* useful tasks: http://libguestfs.org/guestfs-recipes.1.html

### Bleeding-edge build of libguestfs

Note that the version of **libguestfs** provided by Ubuntu 14.04 is 1.24.5, and even though it is < 1 year old, it does not provide all of the tools mentioned in the cookbook. One notable command missing in this version is **virt-customize** which, among other things, allows you to install packages using the native package management system of the image (yum, apt...). Building a bleeding-edge version of **libguestfs** is not hard, but there are other ways to install packages, so this step is not really necessary.

A local build has been made. The code is cloned from a git repository, http://libguestfs.org/guestfs-recipes.1.html. You will also need the source code for an important dependence called supermin, also a git clone, from https://github.com/libguestfs/supermin. In the **libguestfs** README it describes the build dependencies. You can install most of them on Debian/Ubuntu systems like this:
```
$ sudo apt-get build-dep libguestfs
```
Next, go read http://rwmj.wordpress.com/2014/03/08/tip-old-supermin-new-libguestfs-and-v-v/
about how to build supermin first, and include the local copy when you build libguestfs. Don't install the code to the system, you execute the local libguestfs commands using the **run** shell script prefix in the build directory (see the README). A local build has been done on the work VM in ```~/source/libguestfs```.

### SYSLINUX boot loader

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
The KERNEL and INITRD will be different for each VM depending on the name of the kernel. Note that the root file system is mounted from a labelled the device. The label is set using **e2label**, and for CANFAR VMs this seems to have already been done (**e2label** can be executed inside **guestfish** if needed). This means that we don't need to specify a device name which should help with interoperability, since under Xen the virtual devices have names like ```/dev/xvde```, whereas under KVM they have names like ```/dev/vda```.

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

## Variations for specific golden VMs

### ubuntu12.04_amd64

The kernel in these VMs already supports both Xen and KVM, so no update was required. There are links from ```/vmlinuz``` and ```/initrd.img``` to the particular versions used in ```/boot``` so the ```syslinux.cfg``` requires no further editing. Only ```/etc/fstab``` was modified to to use ```LABEL=/``` for the root partition instead of a device name. 

### sl6_amd64

Similar to the ubuntu12.04_amd64 image, the kernel is new enough that it doesn't require an upgrade. ```/boot/syslinux.cfg``` requires hard-wired particular values of```KERNEL``` and ```INITRD``` as no top-level generic links are provided (and notice that scientific linux use a file called ```initramfs-x.x.x``` instead of ```initrd-x.x.x```).

### sl5_amd64

These older VMs are more complicated, and unfortunately they are probably the most common. When SL5 came out it was still necessary to provide a xen-specific kernel, and it does not appear to work with OpenStack. In order to get one of these images working, it was necessary to install a new kernel, and also make a new ```initrd```.

First, install the **SYSLINUX** bootloader as in the other cases.

Then, a normal (non-xen) kernel is installed. This can be accomplished two ways. The first uses **virt-customize**, but requires a bleeding-edge build of **libguestfs**, e.g.,
```
$ virt-customize -a sl5_amd64.img --install kernel
[   0.0] Examining the guest ...
[  56.0] Setting a random seed
[  56.0] Installing packages: kernel
[ 332.0] Finishing off
```
However, since we also need to do some other customizations, it's probably easier just to **guestmount** and **chroot** (can use the older version of **libguestfs**) to do the installation:
```
$ sudo -i
$ guestmount -i -a sl5_amd64.img /mnt/guestos
$ cd /mnt/guestos
$ cp /etc/resolv.conf etc/
$ mount --bind /dev dev
$ mount --bind /dev/pts dev/pts
$ mount --bind /proc proc
$ mount --bind /sys sys
$ chroot /mnt/guestos
```
We are now using the filesystem from the image, and we can execute **yum** commands:
```
$ yum install kernel
$ vi /etc/syslinux.cfg   # Edit to point at the newly-installed kernel and initrd
```
After doing this, the VM still wouldn't boot. Referring to this page http://www.ctlai.com/?p=10 it seems that the ```initrd``` that ships with the kernel can't handle the virtual device used to mount the root partition. So, continuing with our **chroot** session above, we generate a new one with what we need (check the actual kernel version numbers):
```
$ cd /boot
$ cp initrd-2.6.18-371.8.1.el5.img initrd-2.6.18-371.8.1.el5.img.backup
$ mkinitrd -f --with=virtio_blk --with=virtio_pci --builtin=xenblk initrd-2.6.18-371.8.1.el5.img 2.6.18-371.8.1.el5
```
Check ```/etc/fstab```, but it is probably already in good shape as it uses ```LABEL=/``` for the root partition.

The VM should now boot, although it does not start a useful console (visibible to VNC). It is, however, possible to **ssh** in to verify that it is working. This can probably be sorted out by modifying ```/etc/inittab``` and playing with the ```*getty*``` lines -- the ```xvc0``` device seems to be xen-specific.

To exit the **chroot** and **sudo -i** sessions:
```
$ exit
$ exit
```
Probably the main problem with this procedure is that we have now installed a kernel that is *definitely not* backwards compatible with the old system since it lacks xen support. Some time was spent looking for a newer kernel that might support both (as in the cases of the newer VMs). One possibility is installing a long-term support kernel from the Community Enterprise Linux Repository (http://elrepo.org) as it is fairly straightforward. Continuing with the **chroot** session from above, do the following:
```
$ rpm -Uvh http://www.elrepo.org/elrepo-release-5-5.el5.elrepo.noarch.rpm
$ vi /etc/yum.repos.d/elrepo.repo   # find [elrepo-kernel] and set enabled=1
$ yum install kernel-lt
```
This operation installs kernel 3.2.58-1.el5.elrepo. As in the case of the older kernel, it does not boot unless you run **mkinitrd** (being sure to use the new kernel version).

After this it seems to boot, although once again there is no console, and it also seems to lack **ssh** access. While watching the kernel boot in the VNC window, one thing that seems to be missing when compared to the earlier kernel (which works) is the following message:
```
Ebtables v2.0 registered
ip6_tables: (C) 2000-2006 Netfilter Core Team
```
So this may be the smoking gun of some network thing that isn't bein initialized properly (although **sshd** *does* seem to start).

## Making modified VMs boot on CANFAR

Presently the VMs modified with the **SYSLINUX** bootloader for OpenStack no longer work with CANFAR. Here is some typical output from a failed job (this message about the **Boot loader** is repeated in many places all the way up the call stack):
```
Problem with http://iris.cadc.dao.nrc.ca/openstack_testing_sl6_converted.img.gz: Unexpected issue
STDERR: libvir: Xen error : Domain not found: xenUnifiedDomainLookupByName
libvir: Xen Daemon error : POST operation failed: xend_post: error from xen daemon: (xend.err "Error creating domain: Boot loader didn't return any data!")
```
In this context the **Boot loader** refers to something called **PyGrub** (http://wiki.xen.org/wiki/PyGrub). It seems that Xen, rather than using the actual boot loader of the image (grub or whatever) can optionally query the *configuration* files of various boot loaders (such as grub, LILO, SYSLINUX) with **PyGrub** to determine where the kernel is, and how to boot. **OpenStack**, on the other hand, seems to use the *actual* boot loader itself on the image.

After some experimentation it was discovered that PyGrub can simply be executed on the command-line with a VM image file to see whether it is retrieving the correct information. On the Cybera work VM, we simply install the Xen tools and try running it on pure CANFAR images, and images converted for OpenStack:
```
$ sudo apt-get install xen-tools
$ cd /mnt/image_store
$ /usr/lib/xen-4.4/bin/pygrub --debug openstack_testing_12.04.img
Trying offset  0
Using <class 'grub.GrubConf.Grub2ConfigFile'> to parse /boot/grub/grub.cfg
...
```
With this CANFAR image it briefly displays a grub selection menu, and it clearly shows that it is parsing the grub2 configuration file. A number of other error messages are then displayed which appear to be related to the fact that we are not in the correct environment for actually launching an instance.

Repeating this test on an image after each step of the modifications required for OpenStack in the previous section pinpoints the operation that breaks PyGrub:

```
# Within guestfish
><fs> extlinux /boot

# Then checking with pygrub
$ /usr/lib/xen-4.4/bin/pygrub --debug openstack_testing_12.04_converted.img 
Traceback (most recent call last):
  File "/usr/lib/xen-4.4/bin/pygrub", line 813, in <module>
    fs = fsimage.open(file, offset, bootfsoptions)
IOError: [Errno 95] Operation not supported
Traceback (most recent call last):
  File "/usr/lib/xen-4.4/bin/pygrub", line 813, in <module>
    fs = fsimage.open(file, offset, bootfsoptions)
IOError: [Errno 95] Operation not supported
Traceback (most recent call last):
  File "/usr/lib/xen-4.4/bin/pygrub", line 813, in <module>
    fs = fsimage.open(file, offset, bootfsoptions)
IOError: [Errno 95] Operation not supported
Traceback (most recent call last):
  File "/usr/lib/xen-4.4/bin/pygrub", line 838, in <module>
    raise RuntimeError, "Unable to find partition containing kernel"
RuntimeError: Unable to find partition containing kernel
```
The particular error reported by pygrub is inside the module ```fsimage``` which appears to be low-level code written in C to extract information from the disk image. Installing the **SYSLINUX** boot loader using **extlinux** has done something that **pygrub** doesn't know how to deal with.

### A modified procedure that makes a VM boot with both hypervisors (Ubuntu 12.04)

The following modified procedure makes a VM bootable both on the existing CANFAR system, and with OpenStack. The trick is creating a partition.

The first, additional step is to copy the contents of the original, un-partitioned data in the ```/dev/sda``` block device, to a partition in a new image.

```
$ guestfish
><fs> add-ro openstack_testing_12.04.img
><fs> sparse partition_12.04.img 10G
><fs> run
><fs> part-init /dev/sdb mbr
><fs> part-add /dev/sdb p 2048 -2048
><fs> copy-device-to-device /dev/sda /dev/sdb1 sparse:true
><fs> exit
```
We now have a new VM called ```partition_12.04.img``` with a size of 10G and the contents of the old image stored in a partition. We probably don't need to exit and re-start **guestfish**, but it is a convenient way to get it to re-mount things as we did in the earlier examples. We then install the **SYSLINUX** boot loader etc.,
```
$ sudo guestfish -i -a partition_12.04.img

Operating system: Ubuntu 12.04.4 LTS
/dev/sda1 mounted on /
/dev/sdb mounted on /staging
/dev/sdc mounted on /vmstore

><fs> upload mbr.bin /boot/mbr.bin
><fs> upload syslinux.cfg /boot/syslinux.cfg
><fs> copy-file-to-device /boot/mbr.bin /dev/sda size:440
><fs> extlinux /boot
><fs> part-set-bootable /dev/sda 1 true
><fs> vi /etc/fstab          # here just check that LABEL=/ used for / -- should be the case
><fs> vi /boot/syslinux.cfg  # ensure APPEND ro root=/dev/vda1
><fs> vi /boot/grub/menu.lst # ensure root=/dev/xvda1 in all kernel lines
><fs> exit
```
This VM will now boot on both systems! Some notes:

- inside ```syslinux.cfg``` it seems to be necessary to specify ```root=/dev/vda1``` for **OpenStack**. When ```root=LABEL=/``` was tried it gave some strange messages, required console interaction to skip problems, and then mounted ```/``` read-only.

- this could cause a problem for **Xen** since the virtual partition name is ```/dev/xvda1```. However, **PyGrub** doesn't care about the actual boot loader, and simply reads the boot loader configuration files. It looks as though it searches for ```/boot/grub/grub.cfg``` *before* ```/boot/syslinux.cfg``` (confirmed by executing **PyGrub** on the command-line with the resulting image), which means that we can put **Xen**-specific boot options in the **grub** configuration files, as we've done here to set ```root=/dev/xvda1``` (it used to be ```/dev/xvda``` before we added the partition). This may allow us to automagically use different kernels for the problematic SL5 images.

#### Further modifications for SL5

Exploring the suggestion above, it is indeed possible to make a dual-boot SL5 image, although it requires two kernels. First, create the partitioned version of the initial CANFAR image:

```
$ guestfish
><fs> add-ro openstack_testing_sl5.img
><fs> sparse openstack_testing_sl5_converted.img 10G
><fs> run
><fs> part-init /dev/sdb mbr
><fs> part-add /dev/sdb p 2048 -2048
><fs> copy-device-to-device /dev/sda /dev/sdb1 sparse:true
><fs> exit
```

Next **guestmount** the image, and **chroot**. We can then install the stock (non-xen) kernel, update initrd etc. as in the earlier attempt that resulted in an SL5 image that could only boot with OpenStack:

```
$ yum install kernel
$ cd /boot
$ cp initrd-2.6.18-371.8.1.el5.img initrd-2.6.18-371.8.1.el5.img.backup
$ cp mkinitrd -f --with=virtio_blk --with=virtio_pci --builtin=xenblk initrd-2.6.18-371.8.1.el5.img 2.6.18-371.8.1.el5
```

Finally we exit the **chroot** session and unmount the image, then install **SYSLINUX** and update configuration files:

```
$ sudo guestfish -i -a openstack_testing_sl5_converted.img
><fs> upload mbr.bin /boot/mbr.bin
><fs> upload syslinux.cfg /boot/syslinux.cfg
><fs> copy-file-to-device /boot/mbr.bin /dev/sda size:440
><fs> extlinux /boot
><fs> part-set-bootable /dev/sda 1 true
><fs> vi /etc/fstab
><fs> vi /boot/syslinux.cfg

 DEFAULT linux
 LABEL linux
   SAY Booting the kernel
   KERNEL /boot/vmlinuz-2.6.18-371.8.1.el5
   INITRD /boot/initrd-2.6.18-371.8.1.el5.img
   APPEND ro root=/dev/vda1

><fs> vi /boot/grub/menu.lst


title Scientific Linux (2.6.18-348.16.1.el5xen)
        root (hd0,0)
        kernel /boot/vmlinuz-2.6.18-348.16.1.el5xen ro root=LABEL=/ console=xvc0
        initrd /boot/initrd-2.6.18-348.16.1.el5xen.img
title Scientific Linux (2.6.18-348.12.1.el5xen)
        root (hd0,0)
        kernel /boot/vmlinuz-2.6.18-348.12.1.el5xen ro root=LABEL=/ console=xvc0
        initrd /boot/initrd-2.6.18-348.12.1.el5xen.img

```

And now it should work on both systems. Note that in this case, in ```/boot/grub/menu.lst``` we *don't* specify ```root=/dev/xvda1``` as in the previous Ubuntu example. For whatever reason that didn't work, and it was happier using ```root=LABEL=/```. No attempt has been made to set ```LABEL=/``` in ```/boot/syslinux.cfg``` as well, but it may work. **PyGrub** will only look at ```/boot/grub/menu.lst```, so it will pick up the original **xen** kernel that is required for CANFAR.

## TODO

* We need to figure out what to do about things like ```/staging```. **Cybera** has created a **flavour** for our CANFAR project called **me1.small** that has ephemeral storage that we can start experimenting with.
