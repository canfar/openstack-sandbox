Actions for the OpenStack transition
====================================

# User side

## batch
* document a condor OpenStack capable job
* [if needed] document how to share a VM image for batch processing
* [if needed] document the new login IP for a Westgrid submission host

## interactive
* document the URL portal for the dashboard
* document links for OpenStack documentation
* document the new resources users have access to (persistent VM, persistent volume, floating IP,...)
* [if necessary] update of the tutorial, or link to a decent one on the internet

# CADC side

## identity
* define keystone projects and users
## batch
* update cloud scheduler with nefos cluster
* deploy /proc
* add canfarcs user to every project
* [if needed] build submission host VM with public IP on nefos
## VMs
* translate and upload all users current CANFAR VMs to OpenStack
* convince Westgrid to get more template VMs before Nov. 30
* [if needed] support one template VM
* convince Westgrid to get resource-based set of flavours
* [if needed] define CANFAR flavours
