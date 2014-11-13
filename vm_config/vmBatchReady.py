#!/usr/bin/env python
#
# Script for sharing a user's VM image with the batch processing tenant
# by supplying only the name.

import argparse
import glanceclient.v2.client as glclient
from glanceclient.exc import HTTPConflict
import keystoneclient.v2_0.client as ksclient
import json
import os
import requests
import sys

# ID of the batch tenant we need to share with
batch_tenant = '4267ed6832cd4a1f8d7057142fb36520'

# Parse command line
parser = argparse.ArgumentParser(description='Flag VM as ready for batch processing')
parser.add_argument('imagename',help='name of the image')
args = parser.parse_args()
imagename=args.imagename

# Check for auth environment variables
for key in ['OS_USERNAME','OS_PASSWORD','OS_AUTH_URL','OS_TENANT_NAME']:
    if key not in os.environ:
        print "Environment not configured. Source openrc file."
        sys.exit(1)

# Create a keystone client to get the glance endpoint and a list of
# tenants that the user belongs to. We need to use the rest API
# with the token explicitly because this function does not seem to be
# exposed by the python libraries
keystone = ksclient.Client(username=os.environ['OS_USERNAME'],
                           password=os.environ['OS_PASSWORD'],
                           tenant_name=os.environ['OS_TENANT_NAME'],
                           auth_url=os.environ['OS_AUTH_URL'])

glance_endpoint = keystone.service_catalog.url_for(service_type='image')


token = keystone.auth_token
headers = {'X-Auth-Token': token }
tenant_url = os.environ['OS_AUTH_URL']+'/tenants'
r = requests.get(tenant_url, headers=headers)
tenant_data = r.json()

# Loop over tenants and search for the requested image name
matches = []
for tenant in tenant_data['tenants']:
    print "Searching tenant %s: %s" % (tenant['name'],tenant['id'])

    # Get a keystone client scoped to this tenant
    k = ksclient.Client(username=os.environ['OS_USERNAME'],
                        password=os.environ['OS_PASSWORD'],
                        tenant_name=tenant['name'],
                        auth_url=os.environ['OS_AUTH_URL'])

    # Glance client in this same tenant
    glance = glclient.Client(glance_endpoint, token=k.auth_token)

    for image in glance.images.list():
        if image['name'].lower() == imagename.lower():
            # found a (case-insensitive) match to the name
            matches.append({'tenant':tenant['name'],
                            'id':image['id'],
                            'glclient':glance})


# We should only get one match
if len(matches) == 0:
    print "Error: Couldn't find image named " + imagename
    sys.exit(1)
elif len(matches) > 1:
    print "Error: Multiple matches"
    for match in matches:
        print "Tenant '%s', id '%s'" % (match['tenant'],match['id'])
    sys.exit(1)

# Share the image, and catch exception caused by previous shares
match = matches[0]
print "Found image in Tenant '%s', id '%s'" % \
    (match['tenant'],match['id'])
glance = match['glclient']
try:
    glance.image_members.create(match['id'],batch_tenant)
except HTTPConflict as E:
    if E.code == 409:
        print "Image already shared."
    else:
        raise E
