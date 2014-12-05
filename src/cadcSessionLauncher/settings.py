#------------------------------------------------------------------------------
# Settings for cadcSessionLauncher
#
# For a list of CGI environment variables see:
#   http://www.cgi101.com/book/ch3/text.html
#
#------------------------------------------------------------------------------

import os
import sys
import urllib
import urlparse

# Enable to display nice html-formatted debugging information in browser
import cgitb
cgitb.enable()

# how long (in days) do session cookies last?
EXPIRATION_DAYS = 1

# URLs of external services (Authenticated=True).
# LOGIN_PAGE has a couple of options:
#   - target is set to the current page URL so that it can return afterwards.
#   - scope is a full VOSpace URI for which a scoped token is being requested.
_base_url = 'www.canfar.phys.uvic.ca'
_delegation_url = _base_url+'/canfar/loginDelegation.html'
_scope =  urllib.quote_plus('vos://cadc.nrc.ca~vospace/echapin')

_request = 'http://'+os.environ["HTTP_HOST"]+os.environ["REQUEST_URI"]
_url = urlparse.urlparse(_request)._replace(query='')
_target = urlparse.urlunparse(_url)  # CGI script URL without query parameters

LOGIN_PAGE = 'http://'+_delegation_url + \
    '?target=' + _target + '&scope=' + _scope

# Script for starting sessions. It should have the following properties:

# 1a. If SESSION_SCRIPT_MANAGE = False, session management is left to the
#     CGI script. The session starting script optionally takes one argument
#     for the VOS token string. If not supplied assume anonymous
#     session request. When a user returns to the page, a redirect to the
#     stored link is used rather than launching a new session.
# 1b. If SESSION_SCRIPT_MANAGE = True, the script takes the UUID for the
#     session as an argument, and the optional second argument is the VOS
#     token string. Each time a user returns to the page the session launcher
#     script is called, although the UUID will not be updated if it is already
#     present (i.e., the session launching script manages sessions itself
#     using UUID as a key).
# 2.  upon good exit status (0), a URL for the new session is written to stdout
# Notes:
# - on bad exit status (nonzero) both stdout/stderr captured by CGI script and
#   written to stderr so that they appear in the web server logs.
# - on good exit status, stderr will still end up in the web server logs
_path = os.path.dirname(os.environ["SCRIPT_FILENAME"])
SESSION_SCRIPT_MANAGE= True
SESSION_SCRIPT = _path + '/session_example.sh'
