#!/bin/sh

sessionid=$1
token=$2

session_url="http://test.url.com?"

if [ ! -z "$token" ]; then
    session_url="${session_url}token=yes&"
fi

session_url="${session_url}sessionid=${sessionid}"

echo "$session_url"
exit 0

