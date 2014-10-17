Actions for the OpenStack transition
====================================

List of actions to perform to switch from CADC/Nimbus to Westgrid/OpenStack.

# On the user side

## Interactive VMs
* point the current portal Processing URL to the OpenStack dashboard
* document the URL portal for the dashboard
* document (selected links) to OpenStack VM management documentation
* document (selected links) the new resources and features users will have access to (persistent VM, persistent volume, floating IP,...)
* [if necessary] update of the tutorial, or link to a decent one on the internet
* move the current documentation to an accessible archive

## Batch processing
* document how to write a condor OpenStack capable submission file
* [if needed] document how to share a VM image for batch processing
* [if needed] document the new login address in the case of a Westgrid submission host

# On the CADC side

## Identity management
* define projects and users from existing ones
* register all projects and users with westgrid
* [if needed]

## Batch processing
* update cloud scheduler with nefos cluster
* add canfarcs user to every project
* add hook to cloud-scheduler to share VM between projects
* [if needed] build submission host VM with public IP on nefos
* [if needed] deploy /proc on the submission host

## VMs
* translate and upload all users current CANFAR VMs to OpenStack
* convince Westgrid to get more template VMs before Nov. 30
* [if needed] support one template VM
* convince Westgrid to get resource-based set of flavours
* [if needed] define CANFAR flavours

## Testing
* run full test VMs

