#!/bin/sh
# Example of a session script that is called by cadcSessionLauncher.py

token=$1

# Uncomment this block to generate bad exit status
#echo "We had a problem."
#echo "An error message that will appear in the web server log." >&2
#exit 1

# anonymous URL
session_url='http://google.com'

if [ ! -z "$token" ]; then
    # This is where you might perform VOSpace operations (vcp, mountvofs...)
    # using the --cookie="$token" parameter

    # authenticated URL if token supplied
    session_url="http://www.google.com/maps/@48.519248,-123.417835,15z?hl=en"
fi

echo $session_url
echo "A message for the web server log despite good exit status: $token" >&2
exit 0