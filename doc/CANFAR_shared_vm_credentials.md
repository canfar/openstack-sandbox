# CANFAR batch processing using shared VMs

There is presently no good system in place for the following scenario: someone creates a VM that they wish to share with collaborators. Collaborators execute batch jobs with this VM, but supply their own CADC credentials so that their (potentially proprietary) data may be accessed at run time, and results can be stored back into their VOSpace with group privileges. Related to this is the desire to move away from maintaining individual accounts on the CANFAR login/submission host for all users. Instead, we wish to explore the possibility of a web service handling job submission using a single account on the Condor submission host on behalf of the users.

Throughout this document we assume [(HT)Condor 7.8.8](http://research.cs.wisc.edu/htcondor/manual/v7.8/ref.html) which is the version used by CANFAR at the time of writing.


## Executing jobs as **nobody**

In the CANFAR submission file there is a Condor option that is normally set
```
RunAsOwner = True
```
such that the batch process is executed as the same user that submitted the job. When sharing a VM with an arbitrary set of people, it is not desirable for the VM maintainer to create individual user accounts for each of them. If instead this option is turned off,
```
RunAsOwner = False
```
the process is executed as the user **nobody**. The current working directory is initially set to ```$TMPDIR``` which is inside the staging area, e.g., ```/staging/condor/dir_1752```. However, in initial tests, ```$HOME``` is still set to the home directory of the submitting user (not the owner of the VM). The reason for this is the following option:
```
getenv = True
```
If instead it is set to ```False```, the submitter's environment will not be transferred to the process executed in the batch job.

It may be a good idea for the executed script to set ```$HOME``` to ```$TMPDIR```


## Inject certificate: ```transfer_input_files``` method

One simple method for injecting a user's proxy certificate into a batch VM executing as **nobody** is to use the ```transfer_input_files``` [option](http://research.cs.wisc.edu/htcondor/manual/v7.8/2_5Submitting_Job.html#SECTION00354300000000000000) in the submission file, as in the following example:
```
RunAsOwner = False
getenv = False
transfer_input_files=.ssl/cadcproxy.pem
```
This option takes a comma-separated list, and all files will appear (without a subdirectory) in ```$TMPDIR```. In order for this certificate to be available for most commands (e.g., **vcp**), one might set ```$HOME``` to ```$TMPDIR```, and then move the proxy certificate into ```$HOME/.ssl```. For example, the beginning of the executable script referred to by the submission file might look like this:

```
# Initialize $HOME and proxy cert
export HOME=$TMPDIR
mkdir $HOME/.ssl
chmod 644 cadcproxy.pem
mv cadcproxy.pem $HOME/.ssl/

# Now start processing...
```

Alternatively, one might leave the certificate in ```$TMPDIR``` and simply specify its location explicitly as needed, e.g., ```vcp --certfile=$TMPDIR/cadcproxy.pem```. For jobs that use **curl** this scenario might be more complicated.


## Inject certificate: GSI ```x509userproxy``` method

The "correct" way to handle the injection of credentials is to use Condor's built-in method, which is based on Grid Security Infrastructure (GSI). This is the technique that is used by the HEP group at UVic.

The idea is to set up Condor so that the authentication of users and communication between host and client machines uses certificates. Once this is enabled, the user will typically add this line to their submission file,
```
x509userproxy = .ssl/cadcproxy.pem
```
or set an environment variable to that location, ```X509_USER_PROXY```.

Once a job is scheduled, and the VM instantiated, the certificate will be copied into its Condor workspace, and an environment variable ```$X509_USER_PROXY``` will be set, pointing to that location.

In the present CANFAR system, a much simpler method is used in which the ability to submit jobs is simply limited to user accounts on the submission host (```canfar.dao.nrc.ca```).


### Setting up GSI infrastructure

This [document](https://wiki.heprc.uvic.ca/twiki/bin/view/Main/CsGsiSupport) from Cloud Scheduler describes the procedure for setting things up. It is also worth reading the [GSI](http://research.cs.wisc.edu/htcondor/manual/v7.8/3_6Security.html#SECTION00463100000000000000) section in the Condor documentation. Finally, this [presentation](http://www.google.ca/url?sa=t&rct=j&q=&esrc=s&source=web&cd=3&ved=0CCwQFjAC&url=http%3A%2F%2Fresearch.cs.wisc.edu%2Fhtcondor%2FCondorWeek2011%2Fpresentations%2Fzmiller-ssl-tutorial.pdf&ei=5yvEU-qmLMaayAT-4IK4Dg&usg=AFQjCNHHRHtMpQJiTUYfRnMXk2sKg5FGOA&sig2=1KFnMeXXn1FWowB9-Ct2qw&bvm=bv.70810081,d.aWw&cad=rja) has a lot of information.

The following basic steps were used to configure canfardev (development Condor submission node), and bifrostdev (development Condor central manager) so that jobs can be submitted to the queue.

1. **Install Globus Toolkit / Certificate Authority (CA)**
    A certificate authority (CA) will be used to sign certificates to authenticate communications between the various machines involved (submit, central manager, processing). It can also be used to make user certificates, although we can also use CANFAR user proxy certificates.
    * Set up the Globus installer repo (an equivalent exists for Debian/Ubuntu... see [Globus docs](http://toolkit.globus.org/toolkit/docs/5.2/5.2.0/admin/install/#q-toolkit)):
      
      ```$ sudo rpm -hUv http://www.globus.org/ftppub/gt5/5.2/5.2.5/installers/repo/Globus-5.2.stable-config.sl-5.5-1.noarch.rpm```
    * Install Globus components required to set up the CA
      
      ```$ sudo yum install globus-simple-ca globus-gsi-cert-utils-progs```
      
      Executables will be in ```/usr/bin```, and other stuff is also installed to ```/usr/share/globus*```, ```/etc/grid-security```, and ```/usr/sbin/grid```.
    * Set up our Globus Simple CA. Fill in things like the name of the CA, choose an email for the person who is responsible, and choose a passphrase (important to remember).
      ```
      $ grid-ca-create -dir $HOME/globus


          C e r t i f i c a t e    A u t h o r i t y    S e t u p

      This script will setup a Certificate Authority for signing Globus
      users certificates.  It will also generate a simple CA package
      that can be distributed to the users of the CA.

      The CA information about the certificates it distributes will
      be kept in:

      /home/canfradm/globus

      The unique subject name for this CA is:

      cn=Globus Simple CA, ou=simpleCA-bifrostdev.cadc.dao.nrc.ca, ou=GlobusTest, o=Grid

      Do you want to keep this as the CA subject (y/n) [y]: 

      Enter the email of the CA (this is the email where certificate
      requests will be sent to be signed by the CA) [canfradm@bifrostdev.cadc.dao.nrc.ca]: ed.chapin@nrc-cnrc.gc.ca
          The CA certificate has an expiration date. Keep in mind that 
                  once the CA certificate has expired, all the certificates 
                  signed by that CA become invalid.  A CA should regenerate 
                  the CA certificate and start re-issuing ca-setup packages 
                  before the actual CA certificate expires.  This can be done 
                  by re-running this setup script.  Enter the number of DAYS 
                  the CA certificate should last before it expires.
      [default: 5 years 1825 days]: 

      Enter PEM pass phrase:
      Verifying - Enter PEM pass phrase:
      Insufficient permissions to install CA into the trusted certifiicate
      directory (tried ${sysconfdir}/grid-security/certificates and
      ${datadir}/certificates)
      Creating RPM source tarball... unable to write 'random state'
      done
              globus_simple_ca_f3d4caab.tar.gz
      ```
    * Create an RPM that will be used to install information about this CA on machines that will use its certificates (this is probably the same information that is in the tarball from the previous step):
      
      ```$ grid-ca-package -r -cadir $HOME/globus```
      
      which produces a file with a name like ```globus-simple-ca-f3d4caab-1.0-1.noarch.rpm```.
    * Install the CA package from the previous step on condordev and canfardev:
      
      ```$ sudo rpm -i globus-simple-ca-f3d4caab-1.0-1.noarch.rpm```
      
      This step places files in /etc/grid-security and is equivalent to saying "certificates signed by the Certificate Authority that we created in the previous step are to be trusted".
      Check to see if the new certificate authority is listed as the default:
      
      ```
         $ sudo /usr/sbin/grid-default-ca -list
         The available CA configurations installed on this host are:

         Directory: /etc/grid-security/certificates

         1) 1b6c4ffc -  /O=CADC/OU=CADC Internal Root CA
         2) b7f6f6dd -  /O=Grid/OU=GlobusTest/OU=simpleCA-irisdev/CN=Globus Simple CA
         3) bffbd7d0 -  /C=CA/O=Grid/CN=Grid Canada Certificate Authority
         4) cfef249b -  /O=Auto/OU=CADCInternalCA/CN=CA
         5) f3d4caab -  /O=Grid/OU=GlobusTest/OU=simpleCA-bifrostdev.cadc.dao.nrc.ca/CN=Globus Simple CA


         The default CA is: /O=Grid/OU=GlobusTest/OU=simpleCA-bifrostdev.cadc.dao.nrc.ca/CN=Globus Simple CA
                  Location: /etc/grid-security/certificates/f3d4caab.0
      ```
      Edit ```/etc/grid-security/certificates/f3d4caab.signing_policy``` to change the ```cond_subjects``` line:
      ```cond_subjects     globus       '"/O=Grid/*"'```
2. **Request certificates**
    * Host certificates are required for the machines used by condor (canfardev and bifrostdev in this case). For example, on bifrostdev:
      ```
       $ sudo grid-cert-request -force -host bifrostdev.cadc.dao.nrc.ca

           /etc/grid-security/hostcert_request.pem already exists
           /etc/grid-security/hostcert.pem already exists
           /etc/grid-security/hostkey.pem already exists

       Generating a 1024 bit RSA private key
       ...............................................................................++++++
       ......++++++
       writing new private key to '/etc/grid-security/hostkey.pem'
       -----
       You are about to be asked to enter information that will be incorporated
       into your certificate request.
       What you are about to enter is what is called a Distinguished Name or a DN.
       There are quite a few fields but you can leave some blank
       For some fields there will be a default value,
       If you enter '.', the field will be left blank.
       -----
       Level 0 Organization [Grid]:Level 0 Organizational Unit [GlobusTest]:Level 1 Organizational Unit [simpleCA-bifrostdev.cadc.dao.nrc.ca]:Name (E.g., John 
       A private host key and a certificate request has been generated
       with the subject:

       /O=Grid/OU=GlobusTest/OU=simpleCA-bifrostdev.cadc.dao.nrc.ca/CN=host/bifrostdev.cadc.dao.nrc.ca

       ----------------------------------------------------------

       The private key is stored in /etc/grid-security/hostkey.pem
       The request is stored in /etc/grid-security/hostcert_request.pem

       Please e-mail the request to the Globus Simple CA ed.chapin@nrc-cnrc.gc.ca
       You may use a command similar to the following:

        cat /etc/grid-security/hostcert_request.pem | mail ed.chapin@nrc-cnrc.gc.ca

       Only use the above if this machine can send AND receive e-mail. if not, please
       mail using some other method.

       Your certificate will be mailed to you within two working days.
       If you receive no response, contact Globus Simple CA at ed.chapin@nrc-cnrc.gc.ca
      ```
      Then, back on the machine where we set up the CA, sign the request. Copy ```hostcert_request.pem``` over, and execute

      ```$ grid-ca-sign /etc/grid-security/hostcert_request.pem -out hostsigned.pem```

      where it will request the passphrase that you selected when setting up the CA. Then copy the output ```hostsigned.pem``` to ```/etc/grid-security/hostcert.pem``` on bifrostdev. It is probably also a good idea to:
      ```
      $ sudo chown root:root hostcert.pem```
      $ sudo chmod 644 hostcert.pem
      ```
      Repeat for other machines as needed.
    * User certificates from this CA can also be requested using ```$ grid-cert-request``` and then signed in the same manner as the host certificates on the CA machine. The signed user cert should then be copied into ```$HOME/.globus/usercert.pem``` on the machines where the user needs them (also remember to install that CA rpm to indicate that the CA is a trusted authority!)
3. **Add the CANFAR CA**

    * Add the certificate authority for CANFAR user proxy certificates to canfardev and bifrostdev. The following should be added to ```/etc/grid-security/certificates```:
      ```
      -rw-r--r-- 1 root root  875 Jul 17 13:45 ca.crt
      lrwxrwxrwx 1 root root    6 Jul 17 13:45 1b6c4ffc.0 -> ca.crt
      -rw-r--r-- 1 root root 1258 Jul 17 13:46 1b6c4ffc.signing_policy
      ```
      where ```1b6c4ffc.signing_policy``` looks something like this:
      ```# ca-signing-policy.conf, see ca-signing-policy.doc for more information
         #
         # This is the configuration file describing the policy for what CAs are
         # allowed to sign whoses certificates.
         #
         # This file is parsed from start to finish with a given CA and subject
         # name.
         # subject names may include the following wildcard characters:
         #    *    Matches any number of characters.
         #    ?    Matches any single character.
         #
         # CA names must be specified (no wildcards). Names containing whitespaces
         # must be included in single quotes, e.g. 'Certification Authority'.
         # Names must not contain new line symbols.
         # The value of condition attribute is represented as a set of regular
         # expressions. Each regular expression must be included in double quotes.
         #
         # This policy file dictates the following policy:
         #   -The Globus CA can sign Globus certificates
         #
         # Format:
         #------------------------------------------------------------------------
         #  token type  | def.authority |                value
         #--------------|---------------|-----------------------------------------
         # EACL entry #1|

         access_id_CA      X509         '/O=CADC/OU=CADC Internal Root CA'

         pos_rights        globus        CA:sign

         cond_subjects     globus       '"/C=ca/O=hia/OU=cadc/*"'

         # end of EACL
         ```
4. **Configure Condor to use certificate-based authentication**
    * Edit ```/etc/condor/condor_config.local``` on condordev and bifrostdev to add the following lines:
      
      ```
      # GSI - set up to be the same as the nimbus locations
      #
      SEC_DEFAULT_AUTHENTICATION = REQUIRED
      SEC_DEFAULT_AUTHENTICATION_METHODS = GSI
      SEC_DEFAULT_ENCRYPTION = REQUIRED
      SEC_DEFAULT_ENCRYPTION_METHODS = 3DES
      #GRIDMAP = /etc/condor/grid-mapfile.condor
      CERTIFICATE_MAPFILE=/etc/condor/certificate_mapfile.condor

      ```
      The ```SEC_DEFAULT*``` turn on/require GSI/cert authentication, both for users and hosts.
      ```CERTIFICATE_MAPFILE``` maps distinguished names in certificates to canonical Condor users. An example is the following:
      ```
      GSI "O=Grid/OU=GlobusTest/OU=simpleCA-bifrostdev.cadc.dao.nrc.ca/OU=local/CN=Ed Chapin" echapin
         GSI CN=echapin_716 echapin
         GSI CN=canfradm canfradm
      ```
      Here the first line has the full subject for a user cert that was generated using our Globus Simple CA, and it maps to a user called ```echapin```. The next line simply checks the subject for a Common Name (CN) ```echapin_716```, which corresponds to a CANFAR user proxy certificate, and also maps to a user ```echapin```. The last line is another Globus Simple CA signed certificate for a subject with ```CN=canfradm``` and maps to the user ```canfradm```. Other authentication methods are also handled by these "unified mapfiles", and regex's etc. may be used. See the [documentation](http://research.cs.wisc.edu/htcondor/manual/v7.8/3_6Security.html#SECTION00464000000000000000).

      Note that this file is an alternative to the more restrictive Globus ```GRIDMAP``` files. Initial tests failed when using this method.
    * Mappings for subjects of host certificates are probably also required. In earlier tests, grid mapfiles, e.g., ```/etc/condor/grid-mapfile.condor``` had entries like this:
      
      ```
         "/O=Auto/OU=CADCDevCA/CN=john.ouellette@nrc-cnrc.gc.ca" not_a_real_account
         "/C=CA/O=Grid/OU=nrc-cnrc.gc.ca/CN=Sharon Goliath" goliaths
         "/C=CA/O=Grid/OU=nrc-cnrc.gc.ca/CN=Sharon Goliath" jjk
         "/O=Grid/CN=host/canfardev.cadc.dao.nrc.ca" condor
         "/O=Grid/CN=host/bifrostdev.cadc.dao.nrc.ca" condor
         "/O=Grid/OU=GlobusTest/OU=simpleCA-irisdev/OU=local/CN=Sharon Goliath" condor
         "/C=ca/O=hia/OU=cadc/CN=jouellet_c3d" jouellet
         ```
    * Nimbus has its own Globus installation and location for CA certificates etc. You may need to copy things from ```/etc/grid-security``` into ```/opt/nimbus/lib/certs```. To use its Globus installation you can
      ```$ cd /opt/nimbus/lib/
         $ source this-globus-environment.sh
      ```


## Relative merits of both methods

1. The first method is extremely simple:
   * no modifications to Condor or Cloud Scheduler required
   * only need to supply documentation to users
   * However, it continues to rely on our "weak" authentication mechanism that merely restricts job submission to accounts on the login host.

2. The second GSI method is more complicated, and requires updates to the Condor central manager as well as the execution hosts and user VMs. However:
   * it provides a more secure method for users to communicate with their VMs
   * a long-lived VM will only execute jobs by the user that instantiated it (a security feature: you don't want multiple users on that VM running as "nobody" able to see/use eachother's proxy certificates to impersonate them)
   * it conforms to Condor's built-in credential injection mechanism
   * it is the system used by UVic
   * there may be some [issues related to incompatibility between different versions of openssl](https://wiki.heprc.uvic.ca/twiki/bin/view/Main/CsGsiSupport#A_note_about_CA_root_cert_hash_v)

Since the first method has already been demonstrated to work (as a fall back), there is probably some merit in using our development system to test the GSI technique. Another reason for considering this now, rather than later, is that we already need to modify the user VMs for compatibility with OpenStack, so this might be a good time to update their configuration to support GSI as well.


## Submitting jobs from a single account for all users

Presently a user submits a job by ssh'ing to the login/submission host using their personal account, and typing ```condir_submit <submission file>```. The owner of that job is the user that submitted it. If we wish to move to a model whereby submission is handled by a web service, that service will perform the actual submission using a single, generic user account.

In order for a user to submit jobs on behalf of another user, a super user can be defined. For example, this line can be added to ```/etc/condor_config.local```:

```QUEUE_SUPER_USERS = root, condor, condoradm```

The user ```condoradm``` has been added in this case, whereas the other two were already there by default in ```condor_config```.

Next, the submission file needs to have a line added to it to indicate who the owner is, e.g.,
```
+Owner = "echapin"
```

Finally, if we are using GSI for authentication, an environment variable needs to be pointed at the user's proxy certificate, e.g.,
```$ export X509_USER_PROXY=/home/canfradm/echapin/cadcproxy.pem``` (alternatively it can be added to the submission file in the ```x509userproxy``` field).

Now, the user ```condoradm``` should be able to submit a job on behalf of ```echapin```:
```
canfradm(canfardev)$ condor_submit silly_sgwyn_x509userproxy.cansub
Submitting job(s).
1 job(s) submitted to cluster 1178.
canfradm(canfardev)$ condor_q


-- Submitter: canfardev.cadc.dao.nrc.ca : <132.246.195.119:9618> : canfardev.cadc.dao.nrc.ca
 ID      OWNER            SUBMITTED     RUN_TIME ST PRI SIZE CMD               
 911.0   majorb          6/25 15:53   0+00:00:00 I  0   0.0  echoHome          
 912.0   majorb          8/6  12:55   0+00:00:00 I  0   0.0  echoHome          
1178.0   echapin         7/17 15:39   0+00:00:00 I  0   0.0  silly_runme_x509us

3 jobs; 0 completed, 0 removed, 3 idle, 0 running, 0 held, 0 suspended
```

Another Condor configuration variable can be used give authorization to *all* users to modify jobs on behalf of eachother. We are not using it here, but it is called ```QUEUE_ALL_USERS_TRUSTED```.
