# CANFAR: OpenStack integration with LDAP

In this document we explore the details of integrating LDAP with OpenStack for CANFAR. It builds on concepts described [here](https://github.com/canfar/openstack-sandbox/blob/master/doc/OpenStack_identity.md).

## Phase I: WestGrid LDAP, UVic Domains/tenants

Initially we will be using an IceHouse OpenStack deployment at UVic. While multi-domain support exists in this release, it has an important limitation: **it is not possible to specify a different identity backend for each domain**. Regardless, having a separate domain for CANFAR users is useful both for practical and conceptual reasons as it should assist with resource accounting, and is a step towards using an LDAP server under our control for the CANFAR domain in the next OpenStack release (Juno).

### Prototype system

Presently, UVic uses a read-only LDAP slave from WestGrid to provide user authentication (name, password). Our understanding is that all other relationships and privilieges (e.g., tenants, roles) are stored in the Keystone SQL database local to the cloud.

Using an IceHouse OpenStack distribution installed locally (with multi-domain support enabled), and our local development LDAP server, we have set up a system which should be at least superficially similar to that at UVic. [This guide](http://www.mattfischer.com/blog/?p=545) was very useful.

1. **Backups and account/role/tenant IDs**

   Before switching over to LDAP for authentication, a backup of the SQL database was made:
   ```
   $ mysqldump --opt --all-databases > openstack.sql
   ```
   Next, lists of users, roles, and tenants were made (as the admin user) using the keystone CLI, e.g.,
   ```
   $ keystone user-list > userlist.txt
   $ keystone role-list > roles.txt
   $ keystone tenant-list > tenants.txt
   $ for id in `grep True tenants.txt | cut -d" " -f2`; do echo; echo --- tenant ID $id ---; keystone user-list --tenant-id $id; done > tenant_members.txt
   ```
   Also check through ```/etc/[openstack service]/``` to find all of the passwords for the service accounts and the admin user: **admin**, **ceilometer**, **cinder**, **glance**, **neutron**, **nova**, and **swift**.

2. **Add OpenStack service accounts to LDAP**

   Add the users mentioned in the previous step to the directory. If the test LDAP server has a lot of users (>1000) it is a good idea to add a common feature to these accounts so that they can be easily filtered. For example, change the last name (sn) to "openstack". If filtering is not used, you may see errors related to exceeding maximum numbers of results when querying the directory. Remember to use the same passwords for these admin/service accounts as in the original SQL setup.

3. **Configure LDAP as the authentication backend**

   In order to use LDAP for authentication, and the local SQL database for everything else, edit ```/etc/keystone/keystone.conf``` in the following way:
   ```
   [identity]
   driver = keystone.identity.backends.ldap.Identity

   [assignment]
   driver = keystone.assignment.backends.sql.Assignment

   [ldap]
   url=ldap://server.cadc.dao.nrc.ca
   user=uid=admin,ou=Users,ou=ds,dc=canfar,dc=net
   password=xxxxxxxx
   suffix=cn=canfar,cn=net

   user_tree_dn=ou=users,ou=ds,dc=canfar,dc=net
   user_objectclass=inetOrgPerson

   user_allow_create=false
   user_allow_update=false
   user_allow_delete=false

   # only return users with a surname of 'openstack'
   user_filter=(sn=openstack)

   # check actual attributes of users!
   user_id_attribute=uid      # argh... this is broken in IceHouse
   user_name_attribute=uid
   user_mail_attribute=mail
   ```
   Note that this will be a read-only connection. Also, the attribute named for ```user_name_attribute``` is what a user will use to log in to the dashboard. It would be nice to be able to set ```user_id_attribute``` to something else, like ```nsuniqueid```, but unfortunately there is a [bug in this feature](https://bugs.launchpad.net/keystone/+bug/1361306). Otherwise it would have enabled the LDAP server to contain two of the same name, as long as their IDs are different.

4. **Update roles for admin and service users**

   Next, restart keystone, and grant the **admin role** to the **admin user** in the **default domain**.
   We bootstrap the system by using the service token. Look up the ```admin_token``` in ```keystone.conf``` and export the following variables:
   ```
   $ export SERVICE_TOKEN=[value of admin_token here]
   $ export SERVICE_ENDPOINT=http://132.246.194.41:35357/v2.0
   ```
   Then add the role:
   ```
   $ keystone user-role-add --user-id=admin --tenant-id=[see step 1 for admin id] --role-id=[see step 1 for admin role]
   ```
   We can now use the admin user to set up the remaining roles for the service accounts:
   ```
   $ unset SERVICE_ENDPOINT
   $ unset SERVICE_TOKEN
   $ . ~/keystonerc_admin
   $ for user in ceilometer cinder glance neutron nova swift; do \
      keystone user-role-add --user-id=$user \
      --tenant-id=[...services tenant id...] \
      --role-id=[...admin role id...]; done
   $ keystone user-role-add --user-id=ceilometer \
      --tenant-id=[...services tenant id...] \
      --role-id=[...ResellerAdmin id...]
   ```

5. **Setup admin domain and a cloud admin**

   [This guide](http://www.florentflament.com/blog/setting-keystone-v3-domains.html) describes the process of setting up delegated administrators for each domain. Key to this setup is the creation of a special **cloud admin** user, in an **admin domain**. Only this user, and *not* the default admin, can create new domains. Once this user/domain have been set up, the policy file for keystone is changed, after which the default admin user has no capabilities outside of the default domain.

   Obtain a default admin token:
   ```
   $ ADMIN_TOKEN=$(\
   curl http://132.246.194.41:5000/v3/auth/tokens \
       -s \
       -i \
       -H "Content-Type: application/json" \
       -d '
   {
       "auth": {
           "identity": {
               "methods": [
                   "password"
               ],
               "password": {
                   "user": {
                       "domain": {
                           "name": "Default"
                       },
                       "name": "admin",
                       "password": "d9745dc79407411c"
                   }
               }
           },
           "scope": {
               "project": {
                   "domain": {
                       "name": "Default"
                   },
                   "name": "admin"
               }
           }
       }
   }' | grep ^X-Subject-Token: | awk '{print $2}' )
   ```

   Create the new ```admin_domain```:
   ```
   ID_ADMIN_DOMAIN=$(\
   curl http://localhost:5000/v3/domains \
       -s \
       -H "X-Auth-Token: $ADMIN_TOKEN" \
       -H "Content-Type: application/json" \
       -d '
   {
       "domain": {
       "enabled": true,
       "name": "admin_domain"
       }
   }' | jq .domain.id | tr -d '"' )
   ```

   Create the ```cloud_admin``` user in this domain:
   ```
   ID_CLOUD_ADMIN=$(\
   curl http://localhost:5000/v3/users \
       -s \
       -H "X-Auth-Token: $ADMIN_TOKEN" \
       -H "Content-Type: application/json" \
       -d "
   {
       \"user\": {
           \"description\": \"Cloud administrator\",
           \"domain_id\": \"$ID_ADMIN_DOMAIN\",
           \"enabled\": true,
           \"name\": \"cloud_admin\",
           \"password\": \"password\"
       }
   }" | jq .user.id | tr -d '"' )
   ```

   Give ```cloud_admin``` the ```admin``` role on the ```admin_domain```:
   ```
   ADMIN_ROLE_ID=$(\
   curl http://localhost:5000/v3/roles?name=admin \
       -s \
       -H "X-Auth-Token: $ADMIN_TOKEN" \
   | jq .roles[0].id | tr -d '"' )

   curl -X PUT http://localhost:5000/v3/domains/${ID_ADMIN_DOMAIN}/users/${ID_CLOUD_ADMIN}/roles/${ADMIN_ROLE_ID} \
       -s \
       -i \
       -H "X-Auth-Token: $ADMIN_TOKEN" \
       -H "Content-Type: application/json"
   ```

6. **Switch to the v3 auth API**

   Configure OpenStack services to use the v3 auth API, and then enable the v3 policy file (```policy.v3cloudsample.json```) for keystone. See
   [this link](https://github.com/canfar/openstack-sandbox/blob/master/doc/OpenStack_identity.md#basic-setup) for details. Be sure to update ```admin_domain_id``` with the ID of the actual ```admin_domain``` that was just created. Restart keystone.

   If you now connect to a [domain-enabled dashboard](https://github.com/canfar/openstack-sandbox/blob/master/doc/OpenStack_identity.md#basic-setup) for this cloud, you should be able to log in with the admin account (specify the **default** domain). It should also be possible to launch VMs etc.

7. **Create the CANFAR domain**

   Obtain a domain-scoped token for the ```cloud_admin```:
   ```
   $ CLOUD_ADMIN_TOKEN=$(\
   curl http://localhost:5000/v3/auth/tokens \
       -s \
       -i \
       -H "Content-Type: application/json" \
       -d '
   {
       "auth": {
           "identity": {
               "methods": [
                   "password"
               ],
               "password": {
                   "user": {
                       "domain": {
                           "name": "admin_domain"
                       },
                       "name": "cloud_admin",
                       "password": "password"
                   }
               }
           },
           "scope": {
               "domain": {
               "id": "admin_domain"
               }
           }
       }
   }' | grep ^X-Subject-Token: | awk '{print $2}' )
   ```

   With this token we can create the canfar domain:
   ```
   $ curl -s \
     -H "X-Auth-Token: $CLOUD_ADMIN_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{ "domain": { "description": "CANFAR domain", "name": "canfar.net"}}' \
     http://localhost:5000/v3/domains
   ```
   The response will include the domain ID.

8. **Create a CANFAR domain admin**

   First ensure that the user ```canfar_admin``` has been added to LDAP. Then grant the admin role on the CANFAR domain:
   ```
   $ curl -X PUT http://localhost:5000/v3/domains/${ID_CANFAR_DOMAIN}/users/canfar_admin/roles/${ADMIN_ROLE_ID} \
    -s \
    -i \
    -H "X-Auth-Token: $CLOUD_ADMIN_TOKEN" \
    -H "Content-Type: application/json"
   ```

### Add user-group relationships to SQL backend

With users now being authenticated successfully in the LDAP backend, we need to update the local keystone database to include information about CANFAR groups (tenants or projects in OpenStack language) and membership.

The original intention was to create a CANFAR domain, move these users into that domain, create all of the tenants, and then associate users with tenants. As it turns out, when LDAP is used in IceHouse, there is no way to specify which domain a user belongs to, so [default is assumed](https://ask.openstack.org/en/question/47217/how-to-change-user-domain-in-v2-v3-migration-icehouse/).

However, **projects** can be created within domains, and the LDAP users can be associated with those projects. This setup *should* be sufficient for domain-based accounting purposes.

These commands are executed by someone with access to the **$CANFAR_ADMIN_TOKEN**. See this reference for the full [v3 API](http://developer.openstack.org/api-ref-identity-v3.html).

1. **Create a project**

   ```
   $ curl -s \
     -H "X-Auth-Token: $CANFAR_ADMIN_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{ "project": { "description": "a canfar group", "domain_id": "8d372ada740a477e856c11fe6e3a4909", "name": "scuba2"}}' \
     http://localhost:5000/v3/projects
   ```
   The reponse includes the new project ID.

2. **Add an existing LDAP user 'echapin' to the project**

   This step is accomplished by granting them the **_member_** role on the project. We may also want to investigate granting the **admin** role for group owners as well.

   ```
   $ curl -X PUT -s -i \
     -H "X-Auth-Token: $CANFAR_ADMIN_TOKEN" \
     http://localhost:5000/v3/projects/[...project ID...]/users/echapin/roles/[...member role id...]
   ```

Note that these commands are simply updating tables in the mysql database. For example. To connect:
   ```
   $ mysql --user=keystone_admin --password=xxxxx keystone
   ```
   For the password check ```connection``` in ```keystone.conf```.

   The tables ```domain```, ```project```, and ```assignment``` contain the domains, projects, and roles for users on projects and domains, respectively.


### Limiting capabilities of domain administrator

While the above setup enables a domain administrator to manage users, projects, and tenants within their domain, it also grants them more generic administrative capabilities for the other services. For example, both the original "default" domain administrator, ```admin```, and the new ```canfar_admin``` are both capable of modifying **flavors**, and network **aggregates**, which are then visible in all domains. These are functions of **nova**, and inspecting ```/etc/nova/policy.json``` there appear to be three broad classes of rules:

1. **none**

    Actions that are available to everyone, such as listing public flavors.

2. **rule:admin_or_owner**

    Actions involving things like user VMs (e.g., starting, stopping).

3. **rule:admin_api**

    Service configuration actions, such as defining flavors and
    setting quotas.

It may be desirable to limit this last class of actions to a single administrator, as **nova** does not seem to make any use of domain-scoped tokens. A simple redefinition of ```admin_api``` in ```/etc/nova/policy.json``` has the desired effect:

```
"admin_api": "is_admin:True and user_id:admin",
```

This rule will require both the **admin** role, *and* the ```user_id``` must be ```admin```, which is the original administrator of the default domain.

Similar rule changes should also be possible for the other services if needed.

### Domain-based accounting

With this setup, it is possible for an admin to enter 'identity' -> 'domains', and click on the 'set domain context' button next to a given domain. This nominally filters the visible items in the other pages under 'identity'. In practice, it will still display all users in the LDAP server since **domain information is not stored for LDAP users**. However, it will list only the projects that belong in this domain (which is useful).

The **admin** window is used to display, among other things, usage statistics. This will give total and per-project breakdowns, but unfortunately it will not give a domain overview (this appears to be a dashboard shortcoming more than anything else).

Given these limitations, **the benefits of using domains in IceHouse are minimal**. For WestGrid to do accounting, it can find projects in the canfar domain easily enough, and use that to filter the usage statistics on a per-project basis. It is also a good step in the direction we ultimately want to go using a canfar-specific LDAP backend.
