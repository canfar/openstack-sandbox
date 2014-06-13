# CANFAR User Interface

The current CANFAR graphical user interface is a web-based dashboard that handles jobs on all of the available clouds. OpenStack also has a standard dashboard called **Horizon**, and each cloud used by CANFAR will have its own instance of Horizon running.

Initially, it may be wise to consider each OpenStack cloud independently, and simply provide a CANFAR-themed "Summary Usage" page for the user, querying the cloud resource usage API, with a link to each cloud dashboard.

With time, however, it may be desirable to run a local instance of Horizon with CANFAR branding, with some features added to make it easier to manage the resources of various clouds from one place.

## Horizon

Horizon is a stand-alone application that appears to use a Python SDK to wrap the underling REST calls (source code here: https://github.com/openstack/horizon). From a stock installation from repos, according to this web page, http://docs.openstack.org/developer/horizon/topics/deployment.html, the primary configuration task is to set something like
```
OPENSTACK_HOST = "keystone-yyc.cloud.cybera.ca"
```
in ```local_settings.py```. In this example, this value should enable us to interface the Cybera cloud.

For further information on dashboard installation and configuration see: http://docs.openstack.org/grizzly/openstack-compute/install/apt/content/installing-openstack-dashboard.html

An overview of the OpenStack API is given here: http://docs.openstack.org/api/quick-start/content/.

According to this web page, http://www.metacloud.com/2014/03/17/openstack-horizon-controlling-cloud-using-django/, Horizon consists of a modular base library, and a reference dashboard that combines them in to a useable application. If at some point in the future we wish to build a "meta dashboard" to handle multiple clouds, it's conceivable that we might build such an application from existing components in the Horizon core libraries. If and when this is needed, we might also tackle the problem of the central VM repository mentioned in the previous section as part of this work.

In the short term it will probably suffice to install and customize a local CANFAR horizon dashboard from package repositories.

### Image distribution using Glint

The HEP group at UVic is developing a stand-alone service that extends Horizon with the ability to distribute VM images to a range of external clouds.

An old version of the source code for Glint is hosted here: https://github.com/alexjlam/vmdist (also with some interesting notes about developing Horizon).

Briefly, the current version works in the following way:

1. Glint is a plugin for a standard installation of Horizon that provides an additional tab beyond the existing "Images & Snapshots", with lists of multiple clouds.

2. The first cloud listed is a local, "master" cloud.

3. Credentials for all of the external clouds must be input when they are registered through the UI (user name, password, tennant/group ID, and URL).

4. The user selects which of these external clouds will have copies from the local master cloud propagated to them.

5. A local database (independent of the local OpenStack installation) keeps track of the metadata needed to populate the Glint tab in Horizon.

6. While fundamentally a Horizon extension, a command-line tool with the same functionality will also be developed.

Note that there is presently no communication between Glint and Cloud Scheduler with the UVic setup. It is up to the user to ensure that images they want to execute have been propagated to clouds that could potentially receive jobs from the scheduler. If the images are not found, jobs will fail with an error message.


### Horizon and regions

OpenStack has a concept called **regions** aimed at segregating cloud resources (see http://docs.openstack.org/trunk/openstack-ops/content/scaling.html, and http://kimizhang.wordpress.com/2013/08/26/openstack-zoning-regionavailability-zonehost-aggregate/). Regions have separate **nova** installations, and separate API endpoints (i.e., with something like **glance** you would have to specify which region you are talking about). The only shared service is **keystone**. As an example, on the Cybera RAC, the user is presented with a choice of region at login time (https://cloud.cybera.ca/). However, this functionality is something that was added by DAIR to Horizon, and it's not clear whether these customizations have been adopted upstream by OpenStack.


Question:

Might it be possible to support multiple OpenStack clouds under the CANFAR umbrella using regions? These documents look interesting:

* DAIR OpenStack Modifications: https://docs.google.com/document/d/1Dxxhgc2USQrxCAfYzD8Nk3RS9ZZpocavIHie0FfN7Ls/edit

* Support multiple endpoints for the same service in Horizon: https://blueprints.launchpad.net/horizon/+spec/multiple-service-endpoints

