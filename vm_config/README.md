# CANFAR Migration to OpenStack - configure VMs for batch

This directory contains scripts relevant to the configuration of user
VMs for use with Cloud Scheduler, and job submission.

## First time configuration

The only initial configuration that is recommended is the installation
of Condor. ```canfar_batch_setup.bash``` may be supplied as **user data** when intantiating a new VM for the first time, or by executing it (with no arguments) as **root** from within the running VM. If launching an instance from the dashboard, the file may be copy-and-pasted into the **Post-Creation** tab, or even more simply using an ```#include``` with a link to the script in the GitHub repo, e.g.:
```
#include
https://raw.githubusercontent.com/canfar/openstack-sandbox/master/vm_config/canfar_batch_setup.bash
```

## Job submission

When a user launches a job, their VM will need to be **shared** with the batch processing tenant. ```canfar_submit``` is a Python script that first shares the VM and then calls ```condor_submit```.

## Cloud Scheduler

The cloud scheduler configuration may be updated dynamically by injecting a configuration script into the VM. We use a **cloud-config** script as it provides a clean mechanism for mounting ephemeral partitions, and it also wraps the ```canfar_batch_setup.bash``` (although now providing the ```--update-cloud-scheduler``` option to set, among other things, the central manager). The cloud-config script itself is a YAML file, generated at submission time from ```cansub``` or ```canfar_submit`` wrapper scripts.

