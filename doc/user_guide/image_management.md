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

* **Post-Creation tab:** If you wish to **install Condor for batch processing**, you can call a CANFAR customization script in this tab. Simply enter the following lines:
  ```
  #include https://raw.githubusercontent.com/canfar/openstack-sandbox/master/vm_config/condor_client.bash
  ```
  The **cloud-init** package will download customization scripts from this URL and execute them. In this case it will install Condor and the CANFAR configuration. It should work with most modern Debian-derived (including Ubunutu) and Redhat-derived (including CentOS) flavours of Linux.

### Provide image from an external source

VM images from external sources can be added through the Create button at the top-right of the Images window. A variety of options are available, including providing a URL for an image, or directly uploading it. The image Format is a required option, and the most typical values are Raw (e.g., for a **.iso** cloud image from a Linux distribution), or **QCOW2** (format normally used by OpenStack internally, e.g., for snapshots).

### Check status of instances

The Instances window shows all running instances.

Clicking on the **Instance Name** gives further detailed information about the instance in the Overview tab (how long it has been up, security groups, which image it was instantiated from). The Log tab will show startup information as well as a number of useful details provided by the cloud-init package (helpful for debugging boot/device problems for example). This log will not always have useful information, and sometimes problems are best debugged in the Console tab. This shows an embedded VNC client that is able to show console output for the entire boot process. If a user account (+ password) exists on the VM, it is possible to log in directly through this client, without requiring SSH access. The VNC client can send "Ctrl-Alt-Delete" (button near top of the screen) to attempt to reboot the VM. This is sometimes a convenient feature as it restarts the VM while preserving any changes (e.g., installed / changed files) that may be on it.

### Log into an instance

By default, the IP address associated with a VM is internal (not publically accessible). Each project will typically have a small quota of public IPs that are managed through the Access & Security window under the Floating IPs tab. Click on Allocate IP to Project to obtain a number, and then Associate and Disassociate with the running VMs of your choice.

Once a public IP is obtained, you can ssh in. The generic user account into which the supplied SSH key has been injected by cloud-init depends on how the VM has been configured by each Linux distribution. The easiest way to find out is to attempt to connect as the root user, e.g.,
    ```
    $ ssh root@10.1.0.224
    Please login as the user "ubuntu" rather than the user "root".
    ```
### Save a snapshot

To save the current state of the VM (e.g., once a VM is configured and ready for batch processing), switch to the Instances window and click on the Create Snapshot button next to the instance of interest. After selecting a name, it will be stored in the Project tab of the Images window, and available for subsequent instantiation.

### Shut down a VM

A VM is shut down by clicking on the check box next to it in the Instances window, and then clicking on the Terminate Instance button at the top-right.

## Command-line interface

While the full functionality of OpenStack is available through a
[REST API](http://docs.openstack.org/api/api-ref-guides.html), it is
generally much simpler to use command-line clients written in
Python. Until recently, there were a number of different clients
associated with each service, such as **glance**, **keystone** and
**nova**.  These clients are usually referenced in guides on the web.
However, these older clients **do not support multiple domains**. The
OpenStack project has decided to cease development on these separate
clients, and instead concentrate on a **single unified openstack
client**. While not yet widely used, the syntax for this client is
similar to that of the older, separate clients.

We recommend following [this guide](https://docs.google.com/document/d/1zxnuyi1NoO-Hi52OWpmQZKu4dD3DipvZB-fy91mZ18Q/edit) to get started, but keeping the following in mind:

1. Instead of installing all the separate clients, e.g.,
   ```
   $ sudo pip install python-novaclient
   $ sudo pip install python-cinderclient
   ...
   ```
   install the single new client
   ```
   $ sudo sudo pip install python-openstackclient
   ```
   **Note:** The client is also hosted in a [GitHub repository](https://github.com/openstack/python-openstackclient)

2. The simplest way to **create an Openrc file** (contains environment variables used by the client to communicate with the OpenStack cloud) is to: (i) log into the dashboard; (ii) navigate to Access & Security, and click on the API Access tab at the top; and (iii) click on the Download OpenStack RC File button. **Note:** The ```OS_TENANT``` variables change depending on the selected project in the dashboard.

3. Generally speaking, service-specific commands from the guide have similar arguments with the new client, although the first argument refers to the general area of functionality. The following table shows some examples of how to translate **old commands** into arguments for the new **single client**

    old                          | new
    -----------------------------|-------------------------------
    ```glance index```           | ```openstack image list```
    ```glance image-create```    | ```openstack image create```
    ```nova secgroup-create```   | ```openstack security group create```
    ```nova floating-ip-create```| ```openstack ip floating create```
    ```nova boot```              | ```openstack server create```
    ```nova image-create```      | ```openstack snapshot create```
