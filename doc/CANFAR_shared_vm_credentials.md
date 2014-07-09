# CANFAR batch processing using shared VMs

There is presently no good system in place for the following scenario: someone creates a VM that they wish to share with collaborators. Collaborators execute batch jobs with this VM, but supply their own CADC credentials so that their (potentially proprietary) data may be accessed at run time, and results can be stored back into their VOSpace with group privileges.


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

One simple method for injecting a user's proxy certificate into a batch VM executing as **nobody** is to use the ```transfer_input_files``` [option](http://research.cs.wisc.edu/htcondor/manual/v7.6/2_5Submitting_Job.html#SECTION00354400000000000000) in the submission file, as in the following example:
```
RunAsOwner = False
getenv = False
transfer_input_files=.ssl/cadcproxy.pem
```
This option takes a command-separated list, and all files will appear (without a subdirectory) in ```$TMPDIR```. In order for this certificate to be available for most commands (e.g., **vcp**), one might set ```$HOME``` to ```$TMPDIR```, and then move the proxy certificate into ```$HOME/.ssl```. For example, the beginning of the executable script referred to by the submission file might look like this:

```
# Initialize $HOME and proxy cert
export HOME=$TMPDIR
mkdir $HOME/.ssl
chmod 644 cadcproxy.pem
mv cadcproxy.pem $HOME/.ssl/

# Now start processing...
```

Alternatively, one might leave the certificate in ```$TMPDIR``` and simple specify its location explicitly as needs, e.g., ```vcp --certfile=$TMPDIR/cadcproxy.pem```. For jobs that use **curl** this scenario might be more complicated.


## Inject certificate: ```x509userproxy``` method

Condor has a built-in method for handling user proxy certificates. Similar to the previous method, the name of the proxy is supplied in the submission file:
```
x509userproxy = .ssl/cadcproxy.pem
```

However, byt itself this method will not work, and a submitted job fails immediately in the following way:
```
Submitting job(s)
ERROR: 
GSS Major Status: General failure
GSS Minor Status Error Chain:
globus_gsi_gssapi: Unable to read credential for import
globus_gsi_gssapi: Error with gss credential handle
globus_gsi_gssapi: Error with GSI credential
globus_sysconfig: Could not find a valid trusted CA certificates directory: The trusted certificates directory could not be found in any of the following locations: 
1) env. var. X509_CERT_DIR
2) $HOME/.globus/certificates
3) /etc/grid-security/certificates
4) $GLOBUS_LOCATION/share/certificates
```
