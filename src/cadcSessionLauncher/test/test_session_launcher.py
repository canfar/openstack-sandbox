#!/usr/bin/env python2.7

import Cookie
import httplib
import os
import sys
from mock import Mock
from mock import patch
from cStringIO import StringIO
import unittest

# Initialize some basic CGI environment variables. Others will be
# modified for each test case (changing cookies and form values)
os.environ['HTTP_HOST'] = 'right.here.net'
os.environ['REQUEST_URI'] = '/path/to/cgi/scripts'
os.environ['SCRIPT_FILENAME'] = '.'

# HTTP_COOKIE strings for anonymous and authenticated sessions
http_cookie_anon = 'sessionlink="http://test.url.com"'
http_cookie_anon2 = 'sessionlink="http://another.url.com"'
http_cookie_auth = 'auth=yes; sessionlink="http://test.url.com?token=yes"'
http_cookie_auth2 = 'auth=yes; sessionlink="http://another.url.com?token=yes"'
http_cookie_junk = 'useless=value'

# import after basic CGI variables defined
import cadcSessionLauncher

# success/fail session launcher scripts
script_success = 'test/session_test_success.sh'
script_test_manage = 'test/session_test_manage.sh'
script_fail = 'test/session_test_fail.sh'
cadcSessionLauncher.SESSION_SCRIPT=script_success

# Since we're testing a CGI script we need to capture and parse the
# HTML pages that it is writing to stdout. Use this context manager
# solution from:
#   http://stackoverflow.com/questions/16571150/how-to-capture-stdout-output-from-a-python-function-call
# Added in the stderr bits to make sure that they don't go to the screen

# set this to False for more debugging output:
SQUASH_STDERR = True

class Capturing(list):
    def __enter__(self):
        self._stdout = sys.stdout
        sys.stdout = self._stringio_out = StringIO()

        if SQUASH_STDERR:
            self._stderr = sys.stderr
            sys.stderr = self._stringio_err = StringIO()
        return self
    def __exit__(self, *args):
        self.extend(self._stringio_out.getvalue().splitlines())
        sys.stdout = self._stdout
        if SQUASH_STDERR:
            sys.stderr = self._stderr

# Parse the output of the session launcher script and return header dict
def parse_session_launcher():
    # Get the output and parse the header
    with Capturing() as output:
        cadcSessionLauncher.session_launcher()

    # Turn output into a file-like object and feed to HTTPMessage
    # constructor to pick off the header from the body
    f = StringIO('\n'.join(output))
    m = httplib.HTTPMessage(f)

    header = dict()
    header['cookies'] = dict()

    for line in str(m).split("\n"):
        try:
            key,val = line.split(':',1)
            val = val.strip()
            key = key.lower()
            if key == 'set-cookie':
                c = Cookie.SimpleCookie(val)
                for k in c:
                    header['cookies'][k] = c[k].value
            if key == 'status':
                header['status'] = val.split()[0]
                continue
            if key == 'location':
                header['location'] = val
                continue
        except:
            continue

    return header

# --- Start tests -------------------------------------------------------------

class TestSessionLauncher(unittest.TestCase):

    # An anonymous user
    def test_anon(self):

        # First tests don't let the session script manage sessions
        cadcSessionLauncher.SESSION_SCRIPT_MANAGE=False

        # first time in no cookie, create session and redirect
        h = parse_session_launcher()
        self.assertEqual(h['status'],'303')
        self.assertEqual(h['location'],'http://test.url.com')

        # second time in with a cookie redirect to existing session
        os.environ['HTTP_COOKIE'] = http_cookie_anon
        h = parse_session_launcher()
        self.assertEqual(h['status'],'303')
        self.assertEqual(h['location'],'http://test.url.com')
        del os.environ['HTTP_COOKIE']

        # enter with a session cookie AND "new". Start a new session.
        os.environ['QUERY_STRING'] = 'new=yes'
        os.environ['HTTP_COOKIE'] = http_cookie_anon2
        h = parse_session_launcher()
        self.assertEqual(h['status'],'303')
        self.assertEqual(h['location'],'http://test.url.com')
        del os.environ['QUERY_STRING']
        del os.environ['HTTP_COOKIE']

        # test SESSION_SCRIPT_MANAGE. First time in it starts
        # a completely new session. The next time it should call
        # the session starter script with the same sessionid it
        # generated on the first call and get the same link. Final
        # time we request a new session, so we should get a new
        # sessionid
        cadcSessionLauncher.SESSION_SCRIPT_MANAGE=True
        cadcSessionLauncher.SESSION_SCRIPT=script_test_manage
        os.environ['QUERY_STRING'] = 'new=yes'
        h = parse_session_launcher()
        sessionid = h['cookies']['sessionid']
        sessionlink='http://test.url.com?sessionid=%s' % sessionid
        self.assertEqual(h['status'],'303')
        self.assertEqual(h['location'],sessionlink)
        del os.environ['QUERY_STRING']

        cookie_next_visit = 'sessionlink="%s"; sessionid=%s' \
            % (sessionlink,sessionid)
        os.environ['HTTP_COOKIE'] = cookie_next_visit
        h = parse_session_launcher()
        self.assertEqual(h['cookies']['sessionid'],sessionid)
        self.assertEqual(h['status'],'303')
        self.assertEqual(h['location'],sessionlink)

        os.environ['QUERY_STRING'] = 'new=yes'
        h = parse_session_launcher()
        self.assertNotEqual(h['cookies']['sessionid'],sessionid)
        self.assertEqual(h['status'],'303')
        self.assertNotEqual(h['location'],sessionlink)

        del os.environ['QUERY_STRING']
        del os.environ['HTTP_COOKIE']
        cadcSessionLauncher.SESSION_SCRIPT_MANAGE=False
        cadcSessionLauncher.SESSION_SCRIPT=script_success


    # Session script failures
    def test_session_script(self):
        # Incorrect filename in settings, can't execute
        cadcSessionLauncher.SESSION_SCRIPT='junk_filename_87163487163487'
        h = parse_session_launcher()
        self.assertEqual(h['status'],'500')

        # Executes script but returns bad status
        cadcSessionLauncher.SESSION_SCRIPT=script_fail
        h = parse_session_launcher()
        self.assertEqual(h['status'],'502')

        cadcSessionLauncher.SESSION_SCRIPT=script_success

    # An authenticated user
    @patch('urllib2.build_opener')
    def test_auth(self,mock_build_opener):

        # First tests don't let the session script manage sessions
        cadcSessionLauncher.SESSION_SCRIPT_MANAGE=False

        # first time in no cookie, redirect to login page
        os.environ['QUERY_STRING'] = 'auth=yes'
        h = parse_session_launcher()
        self.assertEqual(h['status'],'303')
        self.assertEqual(h['location'],cadcSessionLauncher.LOGIN_PAGE)
        del os.environ['QUERY_STRING']

        # back from login page with token, create session/redirect
        os.environ['QUERY_STRING'] = 'auth=yes&token=abc123'
        h = parse_session_launcher()
        self.assertEqual(h['status'],'303')
        self.assertEqual(h['location'],'http://test.url.com?token=yes')
        del os.environ['QUERY_STRING']

        # second time in with a cookie, redirect to existing session
        os.environ['QUERY_STRING'] = 'auth=yes'
        os.environ['HTTP_COOKIE'] = http_cookie_auth
        h = parse_session_launcher()
        self.assertEqual(h['status'],'303')
        self.assertEqual(h['location'],'http://test.url.com?token=yes')
        del os.environ['HTTP_COOKIE']
        del os.environ['QUERY_STRING']

        # enter with a session cookie AND a token. User is re-authenticating.
        os.environ['QUERY_STRING'] = 'auth=yes&token=abc123'
        os.environ['HTTP_COOKIE'] = http_cookie_auth2
        h = parse_session_launcher()
        self.assertEqual(h['status'],'303')
        self.assertEqual(h['location'],'http://test.url.com?token=yes')
        del os.environ['QUERY_STRING']
        del os.environ['HTTP_COOKIE']

        # enter with an invalid cookie and no token, so start new session
        os.environ['QUERY_STRING'] = 'auth=yes'
        os.environ['HTTP_COOKIE'] = http_cookie_junk
        h = parse_session_launcher()
        self.assertEqual(h['status'],'303')
        self.assertEqual(h['location'],cadcSessionLauncher.LOGIN_PAGE)
        del os.environ['QUERY_STRING']
        del os.environ['HTTP_COOKIE']

        # previous session type was authenticated, but this time in
        # requesting an anonymous session, so we should end up with
        # a new anonymous session
        os.environ['HTTP_COOKIE'] = http_cookie_auth
        h = parse_session_launcher()
        self.assertEqual(h['status'],'303')
        self.assertEqual(h['location'],'http://test.url.com')
        del os.environ['HTTP_COOKIE']

        # test SESSION_SCRIPT_MANAGE. First time redirect is to login
        # page.  Next time (just back from login delegation page) it
        # starts a completely new session. The next time it should
        # call the session starter script with the same sessionid it
        # generated on the first call and get the same link.  Final
        # time we request a new session, so we should get a new
        # sessionid despite cookie.
        cadcSessionLauncher.SESSION_SCRIPT_MANAGE=True
        cadcSessionLauncher.SESSION_SCRIPT=script_test_manage

        os.environ['QUERY_STRING'] = 'new=yes&auth=yes'
        h = parse_session_launcher()
        self.assertEqual(h['status'],'303')
        self.assertEqual(h['location'],cadcSessionLauncher.LOGIN_PAGE)
        del os.environ['QUERY_STRING']

        os.environ['QUERY_STRING'] = 'auth=yes&token=abc123'
        h = parse_session_launcher()
        sessionid = h['cookies']['sessionid']
        sessionlink='http://test.url.com?token=yes&sessionid=%s' % sessionid
        self.assertEqual(h['status'],'303')
        self.assertEqual(h['location'],sessionlink)
        del os.environ['QUERY_STRING']

        cookie_next_visit = 'auth=yes; sessionlink="%s"; sessionid=%s; token=abc123' \
            % (sessionlink,sessionid)
        # The second time in we get redirected to same session
        os.environ['HTTP_COOKIE'] = cookie_next_visit
        os.environ['QUERY_STRING'] = 'auth=yes'
        h = parse_session_launcher()
        self.assertEqual(h['cookies']['sessionid'],sessionid)
        self.assertEqual(h['status'],'303')
        self.assertEqual(h['location'],sessionlink)

        os.environ['QUERY_STRING'] = 'auth=yes&token=abc123'
        h = parse_session_launcher()
        self.assertNotEqual(h['cookies']['sessionid'],sessionid)
        self.assertEqual(h['status'],'303')
        self.assertNotEqual(h['location'],sessionlink)

        del os.environ['QUERY_STRING']
        del os.environ['HTTP_COOKIE']
        cadcSessionLauncher.SESSION_SCRIPT_MANAGE=False
        cadcSessionLauncher.SESSION_SCRIPT=script_success

def run():
    suite = unittest.TestLoader().loadTestsFromTestCase(TestSessionLauncher)
    return unittest.TextTestRunner(verbosity=2).run(suite)

if __name__ == '__main__':
    run()
