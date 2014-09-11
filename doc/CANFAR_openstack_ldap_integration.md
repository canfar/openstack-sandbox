# CANFAR: OpenStack integration with LDAP

In this document we explore the details of integrating LDAP with OpenStack for CANFAR. It builds on concepts described [here](https://github.com/canfar/openstack-sandbox/blob/master/doc/OpenStack_identity.md).

## Phase I: WestGrid LDAP, UVic Domains

Initially we will be using an IceHouse OpenStack deployment at UVic. While multi-domain support exists in this release, it has an important limitation: **it is not possible to specify a different identity backend for each domain**. Regardless, having a separate domain for CANFAR users is useful both for practical and conceptual reasons as it should assist with resource accounting, and is a step towards using an LDAP server under our control for the CANFAR domain in the next OpenStack release (Juno).

### Prototype system

Presently, UVic uses a read-only LDAP slave from WestGrid to provide user authentication (name, password). Our understanding is that all other relationships and privilieges (e.g., tenants, roles) are stored in the Keystone SQL database local to the cloud.

Using an IceHouse OpenStack distribution installed locally, and our local development LDAP server, we have set up a system which should be at least superficially similar to that at UVic. [This guide](http://www.mattfischer.com/blog/?p=545) was very useful. Also see [this question](https://ask.openstack.org/en/question/47217/how-to-change-user-domain-in-v2-v3-migration-icehouse/).


1. **Backups and account/role/tenant IDs**

   Before switching over to LDAP for authentication, a backup of the SQL database was made:
   ```
   $ mysqldump --opt --all-databases > openstack.sql
   ```
   Next, lists of users, roles, and tenants were made (as the admin user) using tje keystone CLI, e.g.,
   ```
   $ keystone user-list > userlist.txt
   $ keystone role-list > roles.txt
   $ keystone tenant-list > tenants.txt
   $ for id in `grep True tenants.txt | cut -d" " -f2`; do echo; echo --- tenant ID $id ---; keystone user-list --tenant-id $id; done > tenant_members.txt
   ```
   Also check through ```/etc/[openstack service]/``` to find all of the passwords for the service accounts and the admin user: **admin**, **ceilometer**, **cinder**, **glance**, **neutron**, **nova**, and **swift**.

2. **Add OpenStack service accounts to LDAP**

   Add the users mentioned in the previous step to the directory. If the test LDAP server has a lot of users (>1000) it is a good idea to add a common feature to these accounts so that they can be easily filtered. For example, change the last name (sn) to "openstack". Remember to use the same passwords for these admin/service accounts as in the original SQL setup.

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
   Note that this will be a read-only connection. Also, the attribute named for ```user_name_attribute``` is what a user will use to log in to the dashboard. It would be nice to be able to set ```user_id_attribute``` to something else, like ```nsuniqueid``, but unfortunately there is a [bug in this feature](https://bugs.launchpad.net/keystone/+bug/1361306). This is unfortunate because it would probably have enabled the LDAP server to contain two of the same name, as long as their IDs are different.

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
   If you now connect to a dashboard for a [domain-enabled IceHouse OpenStack cloud](https://github.com/canfar/openstack-sandbox/blob/master/doc/OpenStack_identity.md#basic-setup), you should now be able to log in with the admin account (specify the **default** domain). It should also be possible to launch VMs etc.


5. **Grant admin role to admin user on default domain**

   Finally, it's probably a good idea to make the admin account an admin (role) on the entire default domain.
   First, obtain a project-scoped token:
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
   With this token we add the admin role on the domain:
   ```
   curl -s -X PUT http://localhost:5000/v3/domains/default/users/admin/roles/[...admin role id...] -i -H "X-Auth-Token: $ADMIN_TOKEN"
   ```
   Now we can obtain a domain-scoped token like this:
   ```
   ADMIN_TOKEN_DOMAIN=$(\
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
               "domain": {
               "id": "default"
               }
           }
       }
   }' | grep ^X-Subject-Token: | awk '{print $2}' )
   ```

