# CANFAR: Identity management with OpenStack

A major goal of the migration to OpenStack is to retain the concept of a shared identity for all of the related services. A user should only have to authenticate once, and be able to:

* access their VOSpace

* define groups / permissions

* access proc and vmod compute services

* share VMs amongst other users in their groups


## OpenStack identity concepts

[This page](http://docs.openstack.org/admin-guide-cloud/content/keystone-admin-concepts.html) describes identity concepts in OpenStack. To summarize:

* **Users** are humans (e.g., name, password, email)

* **Projects (Tenants)** are generally synonymous with allocations (quotas). All users that are a member of a project usually share VMs, as well as compute resources (cores, memory, storage)

* **Roles** define operations that users can perform in particular projects (it is up to the individual services to assign meaning to these roles -- see policies below)

* **Groups (new in API v3)** are collections of users with shared roles. Roll/project management can then be handled for blocks of users rather than on an individual basis.

* **Domains** are top-level administrative boundaries. A domain is a collection of tenants, users and roles.

The rights and privileges of a particular role for a service are defined by its **policies** (a ```policy.json``` file -- see [this page](http://docs.openstack.org/user-guide-admin/content/section_dashboard_admin_manage_roles.html)). As an example, [this page](http://docs.openstack.org/developer/glance/policies.html) lists the configurable policies for the **Glance** (image service) public API. Typically it will be configured such that the **admin** role can perform all actions in any project, whereas normal users can only access images in projects to which they belong (any other role).

**Question:**

Is CANFAR seen as a **domain** or a **project** to a given cloud provider? For batch processing we are using Condor and Cloud Scheduler to distribute the work. In this case we probably don't want to specify individual allocations for each user/group in the CANFAR sense. However, we may wish to have individual projects for vmod (i.e., a single core + static IP is granted to each user for configuration purposes).


## Basic integration with LDAP

The basic Keystone configuration to use LDAP as an identity service backend is fairly straightforward, although *domain-specific* drivers will probably not be available until the OpenStack Juno release (see below). The basic modifications to ```keystone.conf``` according to [this page](http://docs.openstack.org/admin-guide-cloud/content/configuring-keystone-for-ldap-backend.html) are as follows:

```
[ldap]
url = ldap://localhost
user = dc=Manager,dc=example,dc=org
password = samplepassword
suffix = dc=example,dc=org
use_dumb_member = False
allow_subtree_delete = False

user_tree_dn = ou=Users,dc=example,dc=org
user_objectclass = inetOrgPerson

tenant_tree_dn = ou=Groups,dc=example,dc=org
tenant_objectclass = groupOfNames

role_tree_dn = ou=Roles,dc=example,dc=org
role_objectclass = organizationalRole
```

In other words, users, tenants(projects), and roles map to some equivalent organizational units (OU) in the LDAP directory.

**Question:**

Do we need to add **roles** to our LDAP schema?

If we choose not to, a hybrid system in which [role authorization is handled independently](http://docs.openstack.org/admin-guide-cloud/content/configuring-keystone-for-ldap-backend-assignments.html) using the sql backend is possible.


## Sharing VM Images

If we simply map OpenStack tenants(projects) to our concept of groups, we should have the desired behaviour of **image sharing** between members of the same group. However, users will also be restricted by the resources allocated to that procject (CPU cores, memory). In other words, if a VM is created in project "A" which contains 10 users, and they all wish to execute jobs using that VM within that project, they will have to fight over whatever computer resources were allocated to the project.

Alternatively, if a user wishes to allow someone in a different tenant to merely boot an image, the **glance member-create** command can be used to share a particular VM with that external tenant. In the Horizon dashboard the user from the shared tenant will not see the image in the default "Images & Snapshots"; they will need to switch to the "Shared with Me" tab. They can also launch an instance from the "Instances" window. They will not, however, be able to delete the image. In addition, an image can be marked "public" so that any tenant can boot it.

Note that *image protection* is an unrelated feature (e.g., using **glance** or the dashboard). This is simply a read-only flag that can be set by users in the tenant that owns the image to prevent accidental modification / deletion. It can be unset at any time.

## A hybrid model for CANFAR

OpenStack's management of identities and resources does not map perfectly on to the existing system. Presently CANFAR provides a custom-built portal for creating VMs from golden images and saving them, using our identity/group management services. Single (submitting) user accounts on external cloud providers are then used to execute batch jobs from the Condor queue. We wish to use the OpenStack dashboard for vmod services, while retaining the flexibility of the existing model for batch processing.

Here a model in which individual user accounts / tenants exist on a "master" OpenStack cloud to satisfy the needs of vmod are discussed. Batch processing can then proceed on this, and other external clouds using submission by a single, dedicated canfar user.


### vmod

The Horizon dashboard for OpenStack clouds provides a user-friendly interface for creating, launching, and managing images. If a single OpenStack cloud is to be used for vmod, and the LDAP backend is used to manage identities, the user will probably have an initial small allocation (a personal tenant). If they belong to other groups (in LDAP), those groups should also be given their own, allocations (enabling multiple users to share a single instance, for example). The dashboard has a project/tenant switcher to gain access to the different VM images that are available.

If this activity occurs on a single OpenStack cloud, the glance image repository associated with it might be considered the "master" repository.


### batch processing

Cloud Scheduler already has the ability to submit jobs to OpenStack clouds. The location of the cloud and a user that has permission to submit the jobs is given in the ```cloud_resources.conf``` file. Note that this includes a username/password that allows cloud scheduler to launch instances with the **nova** API. An important thing to note is that the **VM image must already be present in the target cloud's image store**, meaning that it must be uploaded to the tenant to which the submitting user has access, in advance. Presently there is no good way to specify **personal/subgroup tenants** for job submission. If it is decided to pursue this, additional development of Cloud Scheduler will be required.

If, for the moment, we assume a generic account will submit the jobs, it might work in the following way. A special canfar user and tenant may be requested on both the master cloud referred to in the previous section, and any additional clouds that are added over time. These would have very large quotas since they will execute jobs on behalf of many users. It would be the job of the CANFAR proc service to:

1. Ensure that the user that owns the job has the correct privilege to access the requested VM in the submission file

2. Ensure that the version of the VM mentioned in the sumission file in the master glance repository is propagated to the repositories for any target clouds that may execute the job (for the canfar user/tenant). This will involve downloading the image with glance (impersonating the owner of the job), and uploading it to the target location (as the user that will execute the job) as needed.

**Note:** even in the case of a single cloud, this model will require two copies of the image -- one in the particular user/tenant, and another for the generic job submission user/tenant. Alternatively, we may simply enforce a policy whereby all user VMs are shared with the submission user/tenant for read-only access (using **glance member-create**).

## OpenStack quota management

Each project/tenant typically has quotas for resources (CPU cores, memory, storage etc.). Assuming we work with the hybrid model mentioned above (a CANFAR domain, including individual user projects, and a seperate project for batch processing) it will probably make sense to have:

* **a very large quota for the batch project**, but leaving enough resources so that a few vmod sessions can always be executed


* **default project quotas** (including individual users) that include  a single public IP. If a project wants larger vmod resources (i.e., more IPs for long-lived VMs) they can be requested.

Quotas are managed by the individual services in an OpenStack cloud. We will probably be the most interested in managing computer resources (numbers of cores, instances, memory, fixed and static IPs). [This document](http://docs.openstack.org/user-guide-admin/content/cli_set_quotas.html) gives a good overview. For example, these are the nova quotas for the CANFAR project on the Cybera cloud:

    ```
    $ nova quota-show
    +-----------------------------+-------+
    | Quota                       | Limit |
    +-----------------------------+-------+
    | instances                   | 8     |
    | cores                       | 8     |
    | ram                         | 8192  |
    | floating_ips                | 3     |
    | fixed_ips                   | -1    |
    | metadata_items              | 128   |
    | injected_files              | 5     |
    | injected_file_content_bytes | 10240 |
    | injected_file_path_bytes    | 255   |
    | key_pairs                   | 100   |
    | security_groups             | 10    |
    | security_group_rules        | 20    |
    +-----------------------------+-------+``
    ```

An administrator would then be able to modify these.

It would be desirable if the entire CANFAR domain could be assigned a single top-level quota, which we could then subdivide as we see fit. However, **there is currently no domain-based quota managenment**. [This document](https://wiki.openstack.org/wiki/DomainQuotaManagementAndEnforcement) provides a blueprint for domain-based quotas, and information about its driver dvelopment is [given here](https://blueprints.launchpad.net/nova/+spec/domain-quota-driver). It's interesting to note from that latter document that administrators will probably have to **choose between domain and project-based quotas**, i.e., a hybrid of both methods will probably not be possible when this is eventually implemented.

## Domain configuration

If CANFAR is granted a domain that can be self-administered, it may be possible to add/remove CANFAR users, create flavours (for batch processing, etc.) without requiring additional server-side configuration. If a prototype needs to be set up, see [this guide](http://www.florentflament.com/blog/setting-keystone-v3-domains.html) for details on setting up domains, designating domain administrators, and managing resources within domains (there is a two-step bootstrap process which must be followed).

### Domain-specific Keystone drivers

The **next** release of OpenStack (Juno) will have a feature that is very useful: [domain-specific drivers](http://docs.openstack.org/developer/keystone/configuration.html#domain-specific-drivers).
This would enable the cloud provider to completely delegate auhorization within that domain to our LDAP back end. Also see [this post](http://www.gossamer-threads.com/lists/openstack/dev/39786) and this [git repo](https://github.com/openstack/keystone-specs/blob/master/specs/juno/multi-backend-uuids.rst) which gives a very detailed overview of what is coming in Juno.

Note that there is a *Key New Feature* in the [IceHouse release notes](https://wiki.openstack.org/wiki/ReleaseNotes/Icehouse#Key_New_Features_5) for **OpenStack Identity (Keystone)** which mentions ```Additional plugins are provided to handle external authentication via REMOTE_USER with respect to single-domain versus multi-domain deployments.``` However, this feature does not seem to apply to the domain-specific problem. See [this page](http://docs.openstack.org/developer/keystone/external-auth.html) for further information regarding external authentication with Keystone.

At some point someone found some information about chaining Keystone instances together. The only thing that seems to mention this is an [old email from 2012](https://www.redhat.com/archives/rhos-list/2012-September/msg00021.html).

### Alternatives to domain-specific Keystone drivers

* It may be possible to configure an **IceHouse** Keystone to support multiple identity provides using [Shibboleth](https://shibboleth.net/), according to the [IceHouse release notes](https://wiki.openstack.org/wiki/ReleaseNotes/Icehouse#Key_New_Features_5). This feature is also mentioned in [this presentation](http://dolphm.com/openstack-juno-design-summit-outcomes-for-keystone/) (see Identity Federation). From that same presentation, they also describe the future of hierarchical tenants which will probably replace the currently flat concepts of domains and projects.

* It is possible to configure **stacked authorization** which uses an LDAP server as a fallback if a user cannot be located in the local SQL database. [This blog post](http://www.mattfischer.com/blog/?p=576) describes the method using this [GitHub project](https://github.com/SUSE-Cloud/keystone-hybrid-backend).

* If CANFAR has an administrative user that is capable of creating new users, it would be possible to write an **agent for populating the cloud providers identity service** with CANFAR users (i.e., by issuing **keystone** commands as the domain admin user).
