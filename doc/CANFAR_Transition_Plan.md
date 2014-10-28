Actions for the OpenStack transition
====================================

List of actions to perform to switch from CADC/Nimbus to Westgrid/OpenStack.

# Identity management
* define projects and users from existing ones
* register all projects and users with westgrid

# Batch processing
* update cloud scheduler with nefos cluster
* build submission / proc host VM with public IP on nefos
* point the current portal Processing URL to the OpenStack dashboard
* document how to write a condor OpenStack capable submission file
* document how to share a VM image for batch processing
* [if needed] document the new login address
* run a full test of batch processing for a migrated CANFAR user
* run a full test of batch processing for a new CANFAR user

# VM Management
* migrate and upload all users current CANFAR VMs to OpenStack
* document the URL portal for the dashboard
* document (selected links) to OpenStack VM management documentation
* document (selected links) the new resources and features users will have access to (persistent VM, persistent volume, floating IP,...)
* update the tutorial, or link to a decent one on the internet
* move the current documentation to the accessible doc archive on github
* convince Westgrid to get more template VMs before Nov. 30
* [if needed] support one template VM, so build it
* convince Westgrid to get resource-based set of flavours
* [if needed] define CANFAR flavours
* run a full test of interactive VM for a migrated CANFAR user
* run a full test of interactive VM for a new CANFAR user
