# CANFAR batch processing using shared VMs

There is presently no good system in place for the following scenario: someone creates a VM that they wish to share with collaborators. Collaborators execute batch jobs with this VM, but supply their own CADC credentials so that their (potentially proprietary) data may be accessed at run time, and results can be stored back into their VOSpace with group privileges.

Throughout this document we assume [(HT)Condor 7.8.8](http://research.cs.wisc.edu/htcondor/manual/v7.8/ref.html) which is the version used by CANFAR at the time of writing.


## Submitting jobs as **nobody**

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

The idea is to set up Condor so that the authentication of users and communication between host and client machines uses certificates. Once this is enabled, the user will typically add this line to their submission file:
```
x509userproxy = .ssl/cadcproxy.pem
```

Once a job is scheduled, and the VM instantiated, the certificate will be copied into its Condor workspace, and an environment variable ```$X509_USER_PROXY``` will be set, pointing to that location.

In the present CANFAR system, a much simpler method is used in which the ability to submit jobs is simply limited to user accounts on the submission host (```canfar.dao.nrc.ca```).


### Setting up GSI infrastructure

This [document](https://wiki.heprc.uvic.ca/twiki/bin/view/Main/CsGsiSupport) from Cloud Scheduler describes the procedure for setting things up. It is also worth reading the [GSI](http://research.cs.wisc.edu/htcondor/manual/v7.8/3_6Security.html#SECTION00463100000000000000) section in the Condor documentation.

To summarize:

* A CA is required to sign dummy host certificates for the VMs (possibly already available?)
* The Globus Toolkit must be installed on the machine running Cloud Scheduler
* The condor configuration must be updated


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
