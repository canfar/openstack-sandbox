# CANFAR: Using PAM modules to facilitate VM access

We are considering using Pluggable Authentication Modules (PAM) to allow users to connect to newly-instantiated VMs using their CANFAR identity, without having previously created accounts for them. There are two main methods that we might pursure:

1. A PAM module that consults Keystone for identity information. Note that a [PAM backend exists for Keystone](http://docs.openstack.org/developer/keystone/api/keystone.identity.backends.pam.html), but this is the opposite of what we want. We would most likely have to write our own Keystone module for PAM at this stage. The benefit of this method is that the complexity of the interface with LDAP is left to Keystone.

2. A PAM module that uses LDAP directly. The benefit of this method is that [such a thing already exists](https://wiki.debian.org/LDAP/PAM).


## Feasibility of writing a Keystone PAM module

PAM modules in Linux are written in C, meaning that we will have to get into autoconf/automake to make it portable amongst Linux distributions. [The detailed guide](http://www.linux-pam.org/Linux-PAM-html/mwg-see-programming-sec.html) is moderately dense, but there are some good examples out there [like this one](http://www.rkeene.org/projects/info/wiki/222) (note at the bottom of that page is a link to a second example called "pam_success" which is a tarball of a skeleton project using GNU autotools).

This module will need to talk to Keystone, and fortunately there is already a [C Keystone Client](https://github.com/RedHatEMEA/c-keystoneclient). This project includes ```libkeystoneclient``` which supports UUID and PKI-based tokens or username/password authentication, and Keystone 2.0 API endpoints. There is also a sample ```keystoneclient``` that shows how to use it.

[From the guide](http://www.linux-pam.org/Linux-PAM-html/mwg-expected-of-module-overview.html), a PAM module needs to provide all of the service functions for at least one of four main groups: *authentication*; *account*; *session*; and *password*.
