# CANFAR: Using PAM modules to facilitate VM access

We are considering using Pluggable Authentication Modules (PAM) to allow users to connect to newly-instantiated VMs using their CANFAR identity, without having previously created accounts for them. There are two main methods that we might pursure:

1. A PAM module that consults Keystone for identity information. Note that a [PAM backend exists for Keystone](http://docs.openstack.org/developer/keystone/api/keystone.identity.backends.pam.html), but this is the opposite of what we want. We would most likely have to write our own Keystone module for PAM at this stage. The benefit of this method is that the complexity of the interface with LDAP is left to Keystone.

2. A PAM module that uses LDAP directly. The benefit of this method is that [such a thing already exists](https://wiki.debian.org/LDAP/PAM).


## Feasibility of writing a Keystone PAM module

PAM modules in Linux are written in C, meaning that we will have to get into autoconf/automake to make it portable amongst Linux distributions. [The detailed guide](http://www.linux-pam.org/Linux-PAM-html/Linux-PAM_MWG.html) is moderately dense, but there are some good examples out there [like this one](http://www.rkeene.org/projects/info/wiki/222) (note at the bottom of that page is a link to a second example called "pam_success" which is a tarball of a skeleton project using GNU autotools).

This module will need to talk to Keystone, and fortunately there is already a [C Keystone Client](https://github.com/RedHatEMEA/c-keystoneclient). This project includes ```libkeystoneclient``` which supports UUID and PKI-based tokens or username/password authentication, and Keystone 2.0 API endpoints. There is also a sample ```keystoneclient``` that shows how to use it.

[From the guide](http://www.linux-pam.org/Linux-PAM-html/mwg-expected-of-module-overview.html), a PAM module needs to provide all of the service functions for at least one of four main groups: *authentication*; *account*; *session*; and *password*.

## PAM with an LDAP backend

The following is a test of PAM using LDAP as a backend. All work was performed on Cybera VMs.

### LDAP server VM

First, CentOS 6.5 was chosen as the OS in which to setup a basic LDAP server. Note that LDAP uses port 389, so an ldap security group was created through the dashboard and then assigned it to the VM when it was instantiated (LDAP is one of the pull-down options).

Once booted, [this guide](http://www.server-world.info/en/note?os=CentOS_6&p=ldap) was followed almost verbatim to install an LDAP server, configure it using a basic/standard schema, and import local users.

1. The default from the example ```dc=server,dc=world``` was used

2. All of the ```sudo ldapadd``` commands to add the core/cosine/nis/inetorgperson schema failed with messages like:
   ```
      SASL/EXTERNAL authentication started
      SASL username: gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth
      SASL SSF: 0
      adding new entry "cn=inetorgperson,cn=schema,cn=config"
      ldap_add: Other (e.g., implementation specific) error (80)
          additional info: olcAttributeTypes: Duplicate attributeType:   "2.16.840.1.113730.3.1.1"
    ```
    This is probably because they are already there?

3. Next, a user called ```echapin``` was created (with password), and then the instructions were followed to create/run scripts for importing the existing users (```echapin,centos```) into the LDAP database.

4. Logging was activated:
   ```
   $ sudo vi /etc/rsyslog.conf
   # LDAP logging
   local4.*                        /var/log/ldap.log
   $ sudo service rsyslog restart
   ```
   and finally we check that things are working
   ```
   $ ldapsearch -x -b 'dc=server,dc=world' 'objectclass=*'
   ```

### Ubuntu 14.04 LDAP client VM

In order to test PAM authentication using LDAP, we instantiate a stock Ubuntu 14.04 VM (using the LDAP security group mentioned above). Then we mainly follow [this guide](https://help.ubuntu.com/community/LDAPClientAuthentication) with some additional information from [here](http://devnotcorp.wordpress.com/2011/05/10/ldap-authentication-for-ubuntu-client/)

1. First we install and configure client packages: ```$ sudo apt-get install ldap-auth-client nscd```
   The configuration asks some questions, to which we answer: ```ldap://199.116.235.100,dc=server,dc=world,3,no,no```

2. ```$ sudo auth-client-config -t nss -p lac_ldap```

3. By default many cloud VMs don't seem to allow password authentication. So, we enable it in the ssh client/server config files:
   ```
   $ sudo vi /etc/ssh/ssh_config
   PasswordAuthentication yes
   
   $ sudo vi /etc/ssh/sshd_config
   PasswordAuthentication yes
   ```

4. When a user logs in they will have no home directory. In order to have one made automatically from the system skeleton account configuration:
   ```
   $ sudo vi /usr/share/pam-configs/mk_mkhomedir
   me: activate mkhomedir
   Default: yes
   Priority: 900
   Session-Type: Additional
   Session:
       required                        pam_mkhomedir.so umask=0022 skel=/etc/ske
   $ sudo pam-auth-update
   $ sudo /etc/init.d/nscd restart
   ```

It is now possible to ssh as ```echapin``` to this client computer, for which no ```echapin``` account has been made before, and it should authenticate using a password (stored on the LDAP server), and create a home directory.

### CentOS 6.5 LDAP client VM

Client configuration is slightly different from the previous Ubuntu example. [This guide](http://www.6tech.org/2013/01/ldap-server-and-centos-6-3/) was mostly followed, but also see [this page](http://www.centos.org/docs/5/html/Deployment_Guide-en-US/s1-ldap-pam.html). The main difference is that ```authconfig``` sets most things up, instead of the ```ldap-auth-client``` package configuration for Ubuntu.

1. Install packages: ```$ sudo yum install openldap openldap-clients nss_ldap pam_ldap nss-pam-ldapd```.

2. Turn on LDAP name service daemon: ```$ sudo chkconfig nslcd on```

3. Edit ```authconfig```:
   ```
   $ sudo vim /etc/sysconfig/authconfig
   USELDAPAUTH=yes
   USELDAP=yes
   ```

4. Enable the LDAP backend for PAM and auto home-directory generation:
   ```
   $ sudo vim /etc/pam.d/system-auth
   auth        sufficient    pam_ldap.so use_first_pass
   account     [default=bad success=ok user_unknown=ignore] pam_ldap.so
   password    sufficient    pam_ldap.so use_authok
   session     optional      pam_ldap
   session     required      pam_mkhomedir.so skel=/etc/skel umask=0077
   ```

5. Run ```authconfig``` to setup config files: ```sudo authconfig --enableldap --ldapserver="ldap://199.116.235.100" --ldapbasedn="dc=server,dc=world" --updateall```

6. Allow password authentication with ssh (step 3 from the Ubuntu client example).




