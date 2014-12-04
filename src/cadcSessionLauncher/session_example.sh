#!/bin/sh
# Example of a session script that is called by cadcSessionLauncher.py


TOKEN=$1

# Uncomment this block to generate bad exit status
#echo "We had a problem."
#echo "An error message that will appear in the web server log." >&2
#exit 1

# anonymous URL
session_url='http://google.com'

if [ ! -z "$TOKEN" ]; then
    # This is where you might perform VOSpace operations (vcp, mountvofs...)
    # using the --token="$TOKEN" parameter. In this example we extract the
    # canfar user name from the token string, and use vls on the portion
    # of VOS space for which the token should be scoped to validate the
    # identity of the user
    part=`echo ${TOKEN} | cut -d"&" -f1`
    canfaruser=`echo $part | cut -d"=" -f2`
    vls vos:${canfaruser} --token="${TOKEN}" >& /dev/null

    # Note in the user log whether user was validated or not
    if [ "$?" == 0 ]; then
        # authenticated URL if validated user
        echo "user ${canfaruser} validated" >&2
        session_url="http://www.google.com/maps/@48.519248,-123.417835,15z?hl=en"
    else
        # fail
        echo "user ${canfaruser} not validated" >&2
        exit 1
    fi


fi

echo $session_url

exit 0