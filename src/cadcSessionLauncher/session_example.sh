#!/bin/sh
# Example of a session script that is called by cadcSessionLauncher.py

SESSIONID=$1
TOKEN=$2

echo "Starting session: ${SESSIONID}" >&2

# anonymous URL
session_url='http://google.com'

if [ ! -z "$TOKEN" ]; then
    # This is where you might perform VOSpace operations (vcp, mountvofs...)
    # using the --token="$TOKEN" parameter. In this example we extract the
    # canfar user name from the token string, and use vls on the portion
    # of VOSpace for which the token should be scoped to validate the
    # identity of the user
    part=`echo ${TOKEN} | cut -d"&" -f1`
    canfaruser=`echo $part | cut -d"=" -f2`
    vls vos:${canfaruser} --token="${TOKEN}" >& /dev/null

    # Note in the web server log whether user was validated or not
    if [ "$?" == 0 ]; then
        # authenticated URL if validated user
        echo "user ${canfaruser} validated" >&2
        session_url="http://www.google.com/maps/@48.519248,-123.417835,15z?hl=en"
    else
        # fail
        echo "user ${canfaruser} not validated" >&2
        exit 1
    fi

else
    # Here we would need some intelligence to check whether $SESSIONID
    # already exists, and return the old URL if needed

    echo "Need additional intelligence to determine if this is a new or old session" >&2

    echo $session_url
fi



exit 0