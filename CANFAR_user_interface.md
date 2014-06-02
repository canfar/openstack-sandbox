# CANFAR User Interface

## Central Dashboard

CANFAR currently has a single, custom dashboard that handles jobs on all of the available clouds. The standard dashboard for OpenStack is **Horizon**, and it is likely that each OpenStack cloud used by CANFAR will have its own instance of Horizon running.

A simple way to manage multiple clouds is to provide a CANFAR-themed "Summary Usage" page for the user, querying the cloud resource usage API, with a link to each cloud dashboard.

However, it may be desirable to run a local instance of Horizon with CANFAR branding. According to this web page, http://docs.openstack.org/developer/horizon/topics/deployment.html, one modifies ```local_settings.py```, primarily to set
```
OPENSTACK_HOST = "keystone-yyc.cloud.cybera.ca"
```
which in this example enables us to interface the Cybera cloud.

For further information on dashboard installation and configuration see: http://docs.openstack.org/grizzly/openstack-compute/install/apt/content/installing-openstack-dashboard.html

Judging from the Horizon source code (https://github.com/openstack/horizon), it's clear that Horizon is using the Python SDK (look in ```openstack_dashboard/api/```), similar to the Python CLI (e.g., **glance**, **nova**, **keystone**), which wraps underling REST calls. See http://docs.openstack.org/api/quick-start/content/ for further details.

According to this web page, http://www.metacloud.com/2014/03/17/openstack-horizon-controlling-cloud-using-django/, Horizon consists of a modular base library, and a reference dashboard that combines them in to a useable application. If at some point in the future we wish to build a "meta dashboard" to handle multiple clouds, it's conceivable that we might build such an application from existing components in the Horizon core libraries. If and when this is needed, we might also tackle the problem of the central VM repository mentioned in the previous section as part of this work.

In the short term it will probably suffice to install and customize a local CANFAR horizon dashboard from package repositories.

### Horizon and regions

Note that Horizon already understands an OpenStack concept called **regions**. As an example, on the Cybera RAC, the user is presented with a choice of region at login time (https://cloud.cybera.ca/). This is the coarsest segregation scheme available with OpenStack (see http://docs.openstack.org/trunk/openstack-ops/content/scaling.html). Another good blog post is here: http://kimizhang.wordpress.com/2013/08/26/openstack-zoning-regionavailability-zonehost-aggregate/. Regions have separate **nova** installations, and separate API endpoints (i.e., with something like **glance** you would have to specify which region you are talking about). The only shared service is **keystone**.

Question:

Might it be possible to support multiple OpenStack clouds under the CANFAR umbrella using regions? These documents look interesting:

* DAIR OpenStack Modifications: https://docs.google.com/document/d/1Dxxhgc2USQrxCAfYzD8Nk3RS9ZZpocavIHie0FfN7Ls/edit

* Support multiple endpoints for the same service in Horizon: https://blueprints.launchpad.net/horizon/+spec/multiple-service-endpoints

