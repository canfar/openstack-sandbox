#!/usr/bin/python
# -*- coding: utf-8 -*-
#************************************************************************
#*******************  CANADIAN ASTRONOMY DATA CENTRE  *******************
#**************  CENTRE CANADIEN DE DONNÉES ASTRONOMIQUES  **************
#*
#*  (c) 2014.                            (c) 2014.
#*  Government of Canada                 Gouvernement du Canada
#*  National Research Council            Conseil national de recherches
#*  Ottawa, Canada, K1A 0R6              Ottawa, Canada, K1A 0R6
#*  All rights reserved                  Tous droits réservés
#*
#*  NRC disclaims any warranties,        Le CNRC dénie toute garantie
#*  expressed, implied, or               énoncée, implicite ou légale,
#*  statutory, of any kind with          de quelque nature que ce
#*  respect to the software,             soit, concernant le logiciel,
#*  including without limitation         y compris sans restriction
#*  any warranty of merchantability      toute garantie de valeur
#*  or fitness for a particular          marchande ou de pertinence
#*  purpose. NRC shall not be            pour un usage particulier.
#*  liable in any event for any          Le CNRC ne pourra en aucun cas
#*  damages, whether direct or           être tenu responsable de tout
#*  indirect, special or general,        dommage, direct ou indirect,
#*  consequential or incidental,         particulier ou général,
#*  arising from the use of the          accessoire ou fortuit, résultant
#*  software.  Neither the name          de l'utilisation du logiciel. Ni
#*  of the National Research             le nom du Conseil National de
#*  Council of Canada nor the            Recherches du Canada ni les noms
#*  names of its contributors may        de ses  participants ne peuvent
#*  be used to endorse or promote        être utilisés pour approuver ou
#*  products derived from this           promouvoir les produits dérivés
#*  software without specific prior      de ce logiciel sans autorisation
#*  written permission.                  préalable et particulière
#*                                       par écrit.
#*
#*  This file is part of the             Ce fichier fait partie du projet
#*  OpenCADC project.                    OpenCADC.
#*
#*  OpenCADC is free software:           OpenCADC est un logiciel libre ;
#*  you can redistribute it and/or       vous pouvez le redistribuer ou le
#*  modify it under the terms of         modifier suivant les termes de
#*  the GNU Affero General Public        la “GNU Affero General Public
#*  License as published by the          License” telle que publiée
#*  Free Software Foundation,            par la Free Software Foundation
#*  either version 3 of the              : soit la version 3 de cette
#*  License, or (at your option)         licence, soit (à votre gré)
#*  any later version.                   toute version ultérieure.
#*
#*  OpenCADC is distributed in the       OpenCADC est distribué
#*  hope that it will be useful,         dans l’espoir qu’il vous
#*  but WITHOUT ANY WARRANTY;            sera utile, mais SANS AUCUNE
#*  without even the implied             GARANTIE : sans même la garantie
#*  warranty of MERCHANTABILITY          implicite de COMMERCIALISABILITÉ
#*  or FITNESS FOR A PARTICULAR          ni d’ADÉQUATION À UN OBJECTIF
#*  PURPOSE.  See the GNU Affero         PARTICULIER. Consultez la Licence
#*  General Public License for           Générale Publique GNU Affero
#*  more details.                        pour plus de détails.
#*
#*  You should have received             Vous devriez avoir reçu une
#*  a copy of the GNU Affero             copie de la Licence Générale
#*  General Public License along         Publique GNU Affero avec
#*  with OpenCADC.  If not, see          OpenCADC ; si ce n’est
#*  <http://www.gnu.org/licenses/>.      pas le cas, consultez :
#*                                       <http://www.gnu.org/licenses/>.
#*
#*
#************************************************************************
# CGI script for launching sessions

import cgi
import Cookie
import datetime
import httplib
import os
import subprocess
import sys
import urllib

from settings import *

# --- globals ---
_form = None             # query parameters
_authenticated = False   # True if authenticated, False if anonymous
_expiration = None       # session expiry

# --- some helpers for clarity ---
def html_terminate_header():
    print

def html_start_body():
    print '<html><body>'

def html_terminate_body():
    print '</body></html>'

def html_redirect(url):
    # add redirect to header, terminate, and simple body providing link
    print 'Status: 303 See other'
    print 'Location: '+url
    html_terminate_header()
    html_start_body()
    print '<a href="%s">Click here if you are not redirected</a>' % url
    html_terminate_body()

def html_error(code,message=None):
    # Display HTTP response code, and write optional message to stderr
    # so that it shows up in Apache error log
    if code not in httplib.responses:
        code = httplib.INTERNAL_SERVER_ERROR
    err_msg = 'Status: ' + str(code) + ' ' + httplib.responses[code]
    print err_msg
    html_terminate_header()
    if message:
        html_start_body()
        print '<H1>'+err_msg+'</H1>'
        html_terminate_body()
        print >> sys.stderr, message

def new_session_requested(form):
    if 'new' in form:
        return True
    else:
        return False

def has_authenticated(form):
    if 'token' in form:
        return True
    else:
        return False

# --- start a new session ---
def start_new_session(message=None):
    global _form, _authenticated, _expiration

    print >> sys.stderr, "New session:", message
    cookie = Cookie.SimpleCookie()
    token = ''

    if _authenticated:
        # Authenticated access requires CADC credentials
        if not has_authenticated(_form):
            # no token, so must be first time in. Redirect to login page.
            html_redirect(LOGIN_PAGE)
            return

        # just came back from the login page so initialize a session using
        # the token (contents of the CADC_DELEG cookie).
        # Note: Even though this value will be placed in a cookie in
        #       VOS calls, it needs to be encoded. For various reasons
        #       URL encoding is the chosen serializer.
        token = urllib.quote_plus(_form.getvalue('token'))

    # We have now authenticated, or this is an anonymous session.
    # Execute the session script. This should display URL to stdout.
    try:
        p = subprocess.Popen([SESSION_SCRIPT,token],
                             stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        out,err = p.communicate()
    except:
        html_error(httplib.INTERNAL_SERVER_ERROR,
                   'Unable to execute '+SESSION_SCRIPT+':\n'+\
                       str(sys.exc_info()[0]))
        return

    out = out.rstrip('\n')
    err = err.rstrip('\n')
    if p.returncode:
        # bad exit status - couldn't launch session for some reason
        outputs='stdout: %s\nstderr: %s' % (out,err)
        html_error(httplib.BAD_GATEWAY,
                   '%s unable to launch session:\n%s' % \
                       (SESSION_SCRIPT,outputs))
        return
    else:
        # good exit status. Still print stderr if present, then extract
        # the link.
        if err:
            print >> sys.stderr, SESSION_SCRIPT+' stderr:\n'+err
        cookie['sessionlink'] = out
        cookie['sessionlink']['expires'] = _expiration

    # Store session type
    if _authenticated:
        cookie['auth'] = 'yes'
        cookie['auth']['expires'] = _expiration
    else:
        cookie['auth'] = 'no'
        cookie['auth']['expires'] = _expiration

    print cookie.output()

    # Finish with session redirect
    html_redirect(cookie['sessionlink'].value)
    return

# --- Session Launcher ---
def session_launcher():
    global _form, _authenticated, _expiration

    # set here to help with unit tests
    _form = None
    _authenticated = False
    _expiration = None

    # Start the header
    print "Content-Type: text/html"

    try:
        _form = cgi.FieldStorage()
    except Exception as e:
        html_error(httplib.INTERNAL_SERVER_ERROR,
                   'Unhandled exception parsing form: %s' % str(e))

    # Authenticated session if requested, or if token supplied
    if ('auth' in _form and _form.getvalue('auth') == 'yes') or \
            has_authenticated(_form):
        _authenticated = True

    # Get expiration time in a format useable for cookies
    expiration_datetime = datetime.datetime.now() + \
        datetime.timedelta(days=EXPIRATION_DAYS)
    _expiration = expiration_datetime.strftime('%a, %d %b %Y %H:%M:%S')

    # Check for an existing session
    try:
        cookie = Cookie.SimpleCookie(os.environ["HTTP_COOKIE"])

        # --- cookie retrieved, we have been here before ---
        if new_session_requested(_form):
            start_new_session(message='Requested.')
        elif has_authenticated(_form):
            start_new_session(message='Token re-authentication.')
        elif 'sessionlink' in cookie:
            previous_session_authenticated = ('auth' in cookie and \
                                                  cookie['auth'].value == 'yes')
            if _authenticated == previous_session_authenticated:
                html_redirect(cookie['sessionlink'].value)
                return
            else:
                start_new_session('Requested session type does not ' +\
                                      'match stored session type.')
        else:
            start_new_session('Previous session missing link.')

    except (Cookie.CookieError, KeyError):
        start_new_session(message="No previous session detected.")
    except Exception as e:
        html_error(httplib.INTERNAL_SERVER_ERROR,
                   'Unhandled exception parsing cookies: %s' % str(e))


# --- Entrypoint ---
if __name__ == '__main__':
    session_launcher()
    sys.exit(0)
