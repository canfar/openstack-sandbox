#!/usr/bin/python
# -*- coding: utf-8 -*-
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
    print '<title>CANFAR Session Launcher '+__version__+'</title>'
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
    token_new = False
    sessionid_new = False

    try:
        # See if we have an existing valid uuid
        sessionid = str(uuid.UUID(_sessionid))
    except:
        sessionid = None

    if _authenticated:
        # Authenticated access requires CANFAR credentials.
        #   - If the form has a token in it, we just came back from
        #     the delegation login page so we grab the token
        #   - if we have sessionid and token cookies, and
        #     SESSION_SCRIPT_MANAGE set, we have already
        #     authenticated. We just continue and let the session
        #     starter script reconnect us
        #   - otherwise we need to direct the user to the delefation pahge
        if has_authenticated(_form):
            token = _form.getvalue('token')
            token_new = True
        elif SESSION_SCRIPT_MANAGE and sessionid and token:
            pass
        else:
            html_redirect(LOGIN_PAGE)
            return

    # If session starter handles session management (SESSION_SCRIPT_MANAGE)
    # generate a new sessionid if needed
    if SESSION_SCRIPT_MANAGE and not sessionid:
        sessionid = str(uuid.uuid4())
        sessionid_new = True

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

    # Store new session UUID
    if sessionid_new:
        cookie['sessionid'] = sessionid
        cookie['sessionid']['expires'] = _expiration

    # Store new token
    if token_new:
        cookie['token'] = token
        cookie['token']['expires'] = _expiration

    # Store session type
    if _authenticated:
        cookie['auth'] = 'yes'
    else:
        cookie['auth'] = 'no'
    cookie['auth']['expires'] = _expiration

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

        # obtain previous session information from cookie
        last_authenticated = False
        if 'auth' in cookie and cookie['auth'].value == 'yes':
            last_authenticated = True

        if 'sessionid' in cookie:
            _sessionid = cookie['sessionid'].value

        if 'token' in cookie and _authenticated:
            _token = cookie['token'].value

        # --- cookie retrieved, we have been here before ---
        if new_session_requested(_form):
            # Caller requests new session / token.
            _sessionid = None
            start_new_session(message='Requested.')
        elif has_authenticated(_form):
            # Just back from login page. New sessionid / token.
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
