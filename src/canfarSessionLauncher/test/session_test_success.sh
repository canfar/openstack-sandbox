#!/bin/sh

token=$1

session_url='http://test.url.com'

if [ ! -z "$token" ]; then
    session_url="$session_url?token=yes"
fi

echo $session_url
#echo "A message for stderr despite good exit status." >&2
exit 0

