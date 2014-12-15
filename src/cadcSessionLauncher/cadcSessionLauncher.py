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
import uuid

from settings import *

# --- globals ---

__version__ = '0.1'

_form = None             # query parameters
_authenticated = False   # True if authenticated, False if anonymous
_expiration = None       # session expiry
_sessionid = None        # UUID for session

# --- some helpers for clarity ---
def html_terminate_header():
    print

def html_start_body():
    print '<title>CADC Session Launcher '+__version__+'</title>'
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
    global _form, _authenticated, _expiration, _sessionid, _token

    print >> sys.stderr, "New session:", message
    cookie = Cookie.SimpleCookie()
    token = _token

    try:
        # See if we have an existing valid uuid
        sessionid = str(uuid.UUID(_sessionid))
    except:
        sessionid = None

    if _authenticated:
        # Authenticated access requires CADC credentials.
        #   - If the form has a token in it, we just came back from
        #     the delegation login page so we grab the token
        #   - if we have sessionid and token cookies, and
        #     SESSION_SCRIPT_MANAGE set, we have already
        #     authenticated. We just continue and let the session
        #     starter script reconnect us
        #   - otherwise we need to direct the user to the delefation pahge
        if has_authenticated(_form):
            token = _form.getvalue('token')
        elif SESSION_SCRIPT_MANAGE and sessionid and token:
            pass
        else:
            html_redirect(LOGIN_PAGE)
            return

    # If session starter handles session management (SESSION_SCRIPT_MANAGE)
    # generate a new sessionid if needed
    if SESSION_SCRIPT_MANAGE and not sessionid:
        sessionid = str(uuid.uuid4())

    # We have now authenticated, or this is an anonymous session.
    # Execute the session script. This should display URL to stdout.
    arguments = [SESSION_SCRIPT]
    if sessionid:
        arguments.append(sessionid)
    if token:
        arguments.append(token)

    try:
        p = subprocess.Popen(arguments,
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

    # Store session UUID
    if sessionid:
        cookie['sessionid'] = sessionid

    # Store token
    if token:
        cookie['token'] = token

    # Store session type
    if _authenticated:
        cookie['auth'] = 'yes'
    else:
        cookie['auth'] = 'no'

    # cookie expiration
    for c in cookie:
        cookie[c]['expires'] = _expiration

    print cookie.output()

    # Finish with session redirect
    html_redirect(cookie['sessionlink'].value)
    return

# --- Session Launcher ---
def session_launcher():
    global _form, _authenticated, _expiration, _sessionid, _token

    # set here to help with unit tests
    _form = None
    _authenticated = False
    _expiration = None
    _sessionid = None
    _token = None

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

        # was stored previous session authenticated?
        last_authenticated = False
        if 'auth' in cookie and cookie['auth'].value == 'yes':
            last_authenticated = True

        if 'sessionid' in cookie:
            _sessionid = cookie['sessionid'].value

        if 'token' in cookie:
            _token = cookie['token'].value

        # --- cookie retrieved, we have been here before ---
        if new_session_requested(_form):
            # want to create a new _sessionid
            _sessionid = None
            start_new_session(message='Requested.')
        elif has_authenticated(_form):
            # want to create a new _sessionid
            _sessionid = None
            start_new_session(message='Token re-authentication.')
        elif SESSION_SCRIPT_MANAGE:
            # If session type doesn't match cookie, remove sessionid so
            # that we tell session starter to start a completely new session
            if _authenticated != last_authenticated:
                _sessionid = None
            start_new_session(message='Session starter manages sessions')
        else:
            # CGI manages sessions. Handle stored session link here
            if 'sessionlink' in cookie:
                if _authenticated == last_authenticated:
                    # redirect to stored session if same session time
                    html_redirect(cookie['sessionlink'].value)
                    return
                else:
                    # otherwise new session
                    start_new_session(message=\
                                          'Requested session type does not ' +\
                                          'match stored session type.')
            else:
                start_new_session(message='Previous session missing link.')

    except (Cookie.CookieError, KeyError):
        start_new_session(message="No previous session detected.")
    except Exception as e:
        html_error(httplib.INTERNAL_SERVER_ERROR,
                   'Unhandled exception parsing cookies: %s' % str(e))


# --- Entrypoint ---
if __name__ == '__main__':
    session_launcher()
    sys.exit(0)
