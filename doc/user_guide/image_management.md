# Managing Virtual Machine Images

There are a number of requirements on virtual machine (VM) images for
use in OpenStack clouds
([summarized here](http://docs.openstack.org/image-guide/content/ch_openstack_images.html)). The
most important are: (i) the inclusion of
[Kernel-based Virtual Machine (KVM) extensions](http://www.linux-kvm.org/page/Main_Page)
(standard since kernel version 2.6.20); and (ii) a series of
customizations to facilitate virtual devices (e.g., network, storage)
and user management (e.g., ssh key injection on startup).

Most modern Linux distributions now provide **cloud images** that are
ready for use in virtual environments, and handle customization
tasks with a special package called **cloud-init**. This is the standard method [used by OpenStack](http://docs.openstack.org/grizzly/openstack-compute/admin/content/user-data.html).

CANFAR keeps copies of some popular cloud images in the image
repository (e.g., Ubuntu and CentOS), although users are free to use
any image they deem fit for their work. For VM-on-demand (VMOD) in
particular, there are no additional requirements on VMs beyond what is
needed for OpenStack, although some CANFAR and CADC services may not be supported by some obscure and/or older distributions (e.g., VOSpace clients, PAM authentication using CANFAR credentials).

For batch processing, VMs will require the installation of
[HTCondor](http://research.cs.wisc.edu/htcondor/) so that running
instances will be able to consume jobs from the processing queue. A script that may be provided to a VM as **user data** (executed by cloud-init when instantiated) can perform this installation.

In this guide we will cover several major topics related to the management of VMs:

**Using the dashboard**

* obtaining and instantiating (starting-up) VMs
* saving VM snapshots
* installing HTCondor for batch processing

**Command line interface**

* introduction to the OpenStack command-line client

## Using the dashboard

The old CANFAR VMOD page is now replaced by the **OpenStack Horizon Dashboard**. This is a web application developed by OpenStack that provides a user-friendly interface to most OpenStack services. Numerous guides are available on-line, and we direct users to [this page](http://www.cybera.ca/projects/cloud-resources/rapid-access-cloud/documentation) for some excellent quick-start documentation, and the complete [OpenStack user guide](http://docs.openstack.org/user-guide/content/ch_dashboard.html).
Please note the following:

* Our dashboard **does not have a stand-alone login page** as it is integrated with the CANFAR single sign-on service.

* An OpenStack **project** (sometimes referred to as a **tenant**) can be considered a single *resource allocation*. Users are members of projects, and all VM Images are shared amongst users in a project. CANFAR has configured projects so that they map on to CADC **groups**, and are thus handled through the **group management pages**. A user switches between different projects in the dashboard using the **project pulldown menu** near the top-left of the page (affecting the available resources, and VM images that are available).

In the following sections we outline some common tasks for CANFAR users.

### Launch an instance

Once logged into the dashboard, switch to the Project -> Compute -> Images window. Tabs at the top are used to switch the view between images that are owned by the **Project**, images that have been **Shared with Me** (a project has granted explicit permission to another project so that it may be instantiated), and **Public** images.

The **Public** images are periodically tested for compatibility with CANFAR services and are a good choice unless there is some feature that they do not offer.

To launch an instance of a given image, click on the **Launch** button in the last column of the image of interest. A number of parameters for this instance are then requested:

* **Details tab:** provide a name for the instance, and select a **flavor** (a hardware profile). It must be sufficient for the image that you are launching!

* **Access & Security tab:** In order to access the VM, an SSH public key will need to be injected into a user account on the VM. A key can also be uploaded here, if you have not done so already, by clicking on the '+'. You will also require a Security Group which defines, primarily, the ports that are open (you will need to open port 22 for SSH, for example).

### Save a snapshot

To save the current state of the VM, switch to the Instances window and click on the Create Snapshot button next to the instance of interest. After selecting a name, it will be stored in the Project tab of the Images window, and available for subsequent instantiation.

### Provide image from an external source

VM images from external sources can be added through the Create button at the top-right of the Images window. A variety of options are available, including a URL for the image, and directly uploading it. The image Format is a required option, and the most typical values are Raw (e.g., for a **.iso** cloud image from a Linux distribution), or **QCOW2** (format normally used by OpenStack internally, e.g., for snapshots).

## Command-line interface
