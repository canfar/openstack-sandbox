# Migrating CANFAR VMs to OpenStack and KVM

Existing CANFAR virtual machines (VMs) are executed within the **Xen** hypervisor, while future operations using **OpenStack** will likely target **KVM**. This document describes a procedure for modifying these VMs so that they will work with **KVM**. Additional, optional modifications can also be made to maintain backwards compatibility with **Xen**.

## Overview

There are two main differences between **Xen** and **KVM** that are relevant to this conversion:

1. Virtual device names are different. For example, a partition that might normally be called ```/dev/sda1``` becomes ```/dev/xvda1``` under **Xen**, and ```/dev/vda1``` under **KVM**. This affects things like the kernel options, and mount points in ```/etc/fstab```.

2. In **Xen** the kernel usually resides outside of the guest VM (domU), in the host filesystem (dom0). However, a **Xen** utility called **PyGrub** is used by CANFAR to search for typical bootloader configuration files, e.g., ```/boot/grub/menu.lst``` to identify which kernel to load within the guest itself at runtime. **KVM** on the other hand requires the installation of a real bootloader on the guest.


## Prerequisites

The test environment for this work is the Cybera Rapid Access Cloud (http://www.cybera.ca/projects/cloud-resources/rapid-access-cloud/). Modifications to CANFAR VMs are made using an Ubuntu 14.04 provisioning VM running on the Cybera RAC (to obtain root access). The modified images are then uploaded using **glance** from this provisioning VM, and finally executed for testing purposes from the **OpenStack dashboard**. For further details on how it was used, see https://github.com/canfar/openstack-sandbox#cybera-test-environment.

A software suite called **libguestfs** is used to modify VMs. It provides a number of tools (especially **guestfish**) that are scriptable. To install on an Ubuntu system:
```
$ sudo apt-get install libguestfs
```

It is also necessary to install **extlinux** which is a version of the **SYSLINUX** bootloader for **EXT** partitions:
```
$ sudo apt-get install extlinux
```

## Make CANFAR VMs bootable with KVM

1. **Figure out which OS is installed** on a given CANFAR image, e.g., ```megapipe.img.gz``` (based on http://libguestfs.org/guestfs-recipes.1.html#get-the-operating-system-product-name-string).

    First, save this to a file called ```os-name.sh```, and make it executable:
    ```
    #!/bin/sh -
    set -e
    eval "$(guestfish --ro -a "$1" --listen)"
    guestfish --remote run
    root="$(guestfish --remote inspect-os)"
    guestfish --remote inspect-get-product-name "$root"
    guestfish --remote exit
    ```

    Note that we have used a remote **guestfish** session to make commands easily scriptable (commands that you would normally provide to the **guestfish** shell are executed with ```guestfish --remote <cmd>```).

    Then,
    ```
    $ gunzip megapipe.img.gz
    $ sudo ./os-name megapipe.img
    Scientific Linux release 5.9 (Boron)
    ```

    The output will tell you whether you are dealing with Scientific Linux 5.x, Scientific Linux 6.x, Ubuntu 12.04, or Ubuntu 13.10.

    Note that we have used a remote **guestfish** session to make commands easily scriptable (commands that you would normally provide to the **guestfish** shell are executed with ```guestfish --remote <cmd>```).

2. **Install a bootloader**. CANFAR VMs generally *do not* have partitions (e.g., ```/dev/sda1```), just a single block device for the OS (e.g., ```/dev/sda```). While it is not possible to install **grub** easily due to: (a) the lack of a partition; and (b) limitations of **libguestfs** (see http://rwmj.wordpress.com/2013/04/04/new-in-libguestfs-use-syslinux-or-extlinux-to-make-bootable-guests/), one can install another bootloader called **SYSLINUX** (from http://libguestfs.org/guestfs-recipes.1.html#install-syslinux-bootloader-in-a-guest).

    Create a file called ```syslinux.cfg``` with something like:
    ```
     DEFAULT linux
     LABEL linux
       SAY Booting the kernel
       KERNEL /vmlinuz
       INITRD /initrd.img
       APPEND ro root=/dev/vda
    ```

    The ```KERNEL```, ```INITRD```, and ```APPEND``` lines need to be modified depending on the OS, but this can be done later.

    Next, make a local copy of the master boot record file from the **extlinux** installation:

    ```
    $ cp /usr/lib/extlinux/mbr.bin .
    ```

    Then we install the bootloader using **guestfish**:

    ```
    $ cp megapipe.img megapipe-kvm.img
    $ sudo guestfish -a megapipe.img -i
    libguestfs: error: mount: mount_stub: /dev/sdb: device not found
    libguestfs: error: mount: mount_stub: /dev/sdc: No such file or directory
    guestfish: some filesystems could not be mounted (ignored)

    Welcome to guestfish, the guest filesystem shell for
    editing virtual machine filesystems and disk images.

    Type: 'help' for help on commands
          'man' to read the manual
          'quit' to quit the shell

    Operating system: Scientific Linux release 5.9 (Boron)
    /dev/sda mounted on /
    /dev/sdb mounted on /staging
    /dev/sdc mounted on /vmstore

    ><fs> upload mbr.bin /boot/mbr.bin
    ><fs> upload syslinux.cfg  /boot/syslinux.cfg
    ><fs> copy-file-to-device /boot/mbr.bin /dev/sda size:440
    ><fs> extlinux /boot
    ```

3. **OS-specific modifications**

    It is necessary at this stage to check, and probably edit ```/etc/fstab``` and ```/boot/syslinux.cfg``` on each modified VM image. In general, for flexibility, ```/etc/fstab``` should use a label to identify the root of the filesystem, ```LABEL=/``` instead of a hard-wired device name, like ```/dev/vda```. ```/boot/syslinux.cfg``` should be modified to point to the correct kernel, initrd, and root.

    Perhaps the easiest way to view and edit files in the VM is to use **guestfish**. For example, to view a file:

    ```
    ><fs> cat /etc/fstab
    ```

    To get a directory listing:
    ```
    ><fs> ls /boot
    ><fs> ll /boot
    ```

    To edit a file using **vi**:
    ```
    ><fs> vi /etc/fstab
    ```

    From a script (using a **guestfish** remote) you may wish to **download** the file from the image, edit the file, and then **upload** the modified version, e.g.,

    ```
    ><fs> download /etc/fstab fstab_local
    [...modify as needed...]
    ><fs> upload fstab_local /etc/fstab
    ```

    1. **Scientific Linux 5**

        This is the trickiest type of VM to get working because generic kernels from this distribution do not support both **Xen** and **KVM** as in the newer operating systems; currently a special ```.el5xen``` kernel is installed. First we need to **guestmount** the VM image and use **chroot** to allow us to install the latest generic kernel with **yum**:

        ```
        $ sudo -i
        $ mkdir /mnt/guestos
        $ guestmount -a megapipe-kvm.img -i /mnt/guestos
        $ cd /mnt/guestos
        $ cp /etc/resolv.conf etc/
        $ mount --bind /dev dev
        $ mount --bind /dev/pts dev/pts
        $ mount --bind /proc proc
        $ mount --bind /sys sys
        $ chroot /mnt/guestos
        $ yum install kernel
        ...
        Installed:
          kernel.x86_64 0:2.6.18-371.8.1.el5

        Complete!
        ```
        Next, the initial ram disk needs to be updated so that it includes the ```/dev/vda``` device where the root partition resides (see http://www.ctlai.com/?p=10):

        ```
        $ cd /boot
        $ cp initrd-2.6.18-371.8.1.el5.img initrd-2.6.18-371.8.1.el5.img.backup
        $ mkinitrd -f --with=virtio_blk --with=virtio_pci --builtin=xenblk initrd-2.6.18-371.8.1.el5.img 2.6.18-371.8.1.el5
        ```

        Note that this command is copied verbatim from the example linked above, and the ```--builtin=xenblk``` is probably irrelevant to this kernel since it does not support **Xen**.

        Exit **chroot** and **guestunmount** the image:

        ```
        $ exit             # chroot
        $ umount dev/pts
        $ umount dev
        $ umount proc
        $ umount sys
        $ exit             # sudo -i
        $ sudo guestunmount /mnt/guestos
        ```

        Edit ```syslinux.cfg``` so that it uses the new kernel and initrd:

        ```
        DEFAULT linux
        LABEL linux
          SAY Booting the kernel
          KERNEL /boot/vmlinuz-2.6.18-371.8.1.el5
          INITRD /boot/initrd-2.6.18-371.8.1.el5.img
          APPEND ro root=/dev/vda
        ```

        The VM should now boot under **KVM**.

        However, **no console is presented through a VNC session**. Note that the old **grub** configuration (```/boot/grub/menu.lst```), used by **Xen**, specifies ```console=xvc0``` on the kernel command line. This **Xen**-specific virtual device is also listed in ```/etc/inittab```. It is probably possible to get the console to work by changing things to an equivalent **KVM** virtual device called ```ttyS0``` although initial tests have been unsuccessful.

        Regardless of this problem, it is possible to **ssh** in to a running instance.

    2. **Scientific Linux 6**

        For some reason **guestfish** is not able to automount the partitions for these images (```-i``` option) and exits with an error. However, it is possible to explicitly mount only the ```/dev/sda``` device like this:

        ```
        $ sudo guestfish -a test_sl6.img

        Welcome to guestfish, the guest filesystem shell for
        editing virtual machine filesystems and disk images.

        Type: 'help' for help on commands
              'man' to read the manual
              'quit' to quit the shell

        ><fs> run
        ><fs> mount /dev/sda /
        ```

        Henceforth **SYSLINUX** can be installed as described above in point #2.

        For these images it is necessary to change the root device from ```/dev/xvde``` to ```LABEL=/``` in ```/etc/fstab```:
        ```
        #/dev/xvde              /                       ext3    defaults        1 1
        LABEL=/                 /                       ext3    defaults        1 1
        ```

        Then find the newest kernel installed using ```ls /boot``` and edit ```/boot/syslinux.cfg```:
        ```
        DEFAULT linux
        LABEL linux
          SAY Booting the kernel
          KERNEL /boot/vmlinuz-2.6.32-431.11.2.el6.x86_64
          INITRD /boot/initramfs-2.6.32-431.11.2.el6.x86_64.img
          APPEND ro root=/dev/vda
        ```

        These modified VMs appear to be fully-functional (including the console).

    3. **Ubuntu 12.04**

        ```/etc/fstab``` already uses ```LABEL=/``` so no changes should be required.

        We also don't need to make any changes to ```/boot/syslinux.cfg```. Note that Ubuntu places links from ```/vmlinuz``` and ```/initrf.img``` to the currently installed versions in ```/boot```:
        ```
        DEFAULT linux
        LABEL linux
          SAY Booting the kernel
          KERNEL /vmlinuz
          INITRD /initrd.img
          APPEND ro root=/dev/vda
        ```

        These modified VMs appear to be fully-functional (including the console).

    4. **Ubuntu 13.10**

        Same procedure as Ubuntu 12.04.


## Make CANFAR VMs dual-boot Xen/KVM

The VM conversion to KVM as described in the previous section has the advantage that it can be done with existing VMs *in-place*. However, **these VMs are not backwards-compatible with Xen**. Attempting to instantiate one of these VMs with CANFAR results in an error: ```Boot loader didn't return any data!```. This message results from **PyGrub**'s failure to locate a valid kernel and boot parameters. Experimentation with **PyGrub** on the command-line reveals that the problem is caused by **extlinux** when applied to a block device instead of a partition, e.g., ```/dev/sda``` instead of ```/dev/sda1```. It is possible to make an image dual-boot by creating a copy of the original VM with a partitioned file system.

1. **Create a partitioned VM**

    Following http://libguestfs.org/guestfs-recipes.1.html#convert-xen-style-partitionless-image-to-partitioned-disk-image, do the following:

    ```
    $ sudo guestfish --ro -a vm.img
    ><fs> sparse vm_partitioned.img 10G
    ><fs> run
    ><fs> part-init /dev/sdb mbr
    ><fs> part-add /dev/sdb p 2048 -2048
    ><fs> copy-device-to-device /dev/sda /dev/sdb1 sparse:true
    ```

    Ensure that the size of ```vm_partitioned.img``` matches the input size (in this case ```10G```).

    Within **guestfish** the first (input) image becomes the ```/dev/sda``` device, and the second "disk" containing the output image, appears in partition ```/dev/sdb1```. At this stage one can exit **guestfish** and re-start, providing ```-a vm_partitioned.img``` on the command-line, and the partition will appear as ```/dev/sda1```. An alternative, and probably faster method, is to continue with the same session and simply mount ```/dev/sdb1``` as root, and then continue with the installation of the bootloader. This second method is assumed for the next section.

    ```
    ><fs> mount /dev/sdb1 /
    ```

2. **Install a bootloader**. We can install **SYSLINUX** in the same way as the previous section with some minor modifications to account for the partition, and the addition of ```part-set-bootable /dev/sdb 1 true``` which is probably redundant, but follows the example from **libguestfs** recipes:

    ```
    ><fs> upload mbr.bin /boot/mbr.bin
    ><fs> upload syslinux.cfg /boot/syslinux.cfg
    ><fs> copy-file-to-device /boot/mbr.bin /dev/sdb size:440
    ><fs> extlinux /boot
    ><fs> part-set-bootable /dev/sdb 1 true
    ```

3. **OS-specific modifications**

    We again modify ```/etc/fstab``` and ```/boot/syslinux.cfg``` for the correct device names and kernel versions. Note that regardless of the fact that the image appears as ```/dev/sdb1``` within **guestfish**, when booted by **KVM** it will appear as the first partition on the first virtual block device, ```/dev/vda1```.

    Unlike the case of a VM that only targets **KVM**, to maintain backwards compatibility with **Xen** we have to consider the behaviour of **PyGrub** to obtain the location and parameters of the kernel. After reviewing the Python source code, and experimenting, it appears that it searches for configuration files of several bootloaders (GRUB, LILO, SYSLINUX), and stops when one is encountered. Since it searches for GRUB *first*, it will locate ```/boot/grub/menu.lst``` with the kernel parameters for **Xen**, and completely ignore **SYSLINUX**. In other words, it is possible to specify **Xen**-specific boot parameters in ```/boot/grub/menu.lst```, and **KVM**-specific boot parameters in ```/boot/syslinux.cfg```. Usually the only modification to ```/boot/grub/menu.lst``` required after partitioning is to change block device names like ```/dev/xvda``` to the first partition, ```/dev/xvda1```.

    1. **Scientific Linux 5**

        The ability to specify different boot parameters for **Xen** and **KVM** is fortunate because we require different kernels in each case. Once the partitioned version of the VM is made, and a bootloader installed, exit **guestfish** and follow the instructions for a pure **KVM** VM to **guestmount/chroot** and install a generic kernel/initrd that will be used by **KVM**.

        Once the generic kernel is installed, update ```/dev/syslinux.cfg``` to use the new kernel/initrd, and ensure that ```root=/dev/vda1```.

        You do not need to edit ```/boot/grub/menu.lst``` as it already uses the older ```.el5xen``` kernel, and ```root=LABEL=/``` seems to work (i.e., you do not need to give a specific **Xen** virtual device name as with the other VMs).

        Again, under **KVM**, **there is no console available through VNC**. However, it is possible to **ssh** in.

        **An alternative to this 2-kernel solution may be the installation of a newer kernel** with support for both **Xen** and **KVM**, as with the newer distributions. Some progress to this end was made by adding a new **yum** repo that can provide a more recent long-term release kernel. Instead of installing the generic kernel during the **guestmount/chroot** session, do the following:
        ```
        $ rpm -Uvh http://www.elrepo.org/elrepo-release-5-5.el5.elrepo.noarch.rpm
        $ vi /etc/yum.repos.d/elrepo.repo   # find [elrepo-kernel] and set enabled=1
        $ yum install kernel-lt
        ```
        This installs kernel ```3.2.58-1.el5.elrepo``` and you must again run **mkinitrd** to get the necessary virtual devices for boot (being sure to use the new kernel version). Once ```/boot/syslinux.cfg``` has been updated, the VM appears to boot under **KVM**, although **neither the console, nor ssh access** work. It may simply be a case of experimenting with kernel options to get it going.

    2. **Scientific Linux 6**

        Follow the instructions for a pure **KVM** VM, but remember to set ```root=/dev/vda1``` in ```/boot/syslinux.cfg```.

        You must also edit ```/boot/grub/menu.lst``` and replace occurences of ```root=/dev/xvde``` with ```root=/dev/xvde1```.

    3. **Ubuntu 12.04**

        Follow the instructions for a pure **KVM** VM, but remember to set ```root=/dev/vda1``` in ```/boot/syslinux.cfg```.

        You must also edit ```/boot/grub/menu.lst``` and replace occurences of ```root=/dev/xvda``` with ```root=/dev/xvda1```.

    4. **Ubuntu 13.10**

        Same procedure as Ubuntu 12.04.
