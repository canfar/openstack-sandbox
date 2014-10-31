# CADC Session Launcher

**cadcSessionLauncher** is a CGI script, implemented in Python, that provides a mechanism for starting and redirecting the user to arbitrary web application sessions. These applications are initiated by a user-supplied launcher script. CADC authorization with access to a portion of a user's VOSpace is possible using scoped tokens.

To start an authenticated session provide ```auth=yes``` as a query parameter, otherwise an anonymous session is created.

Once a session has been launched, browser cookies are set, so that a user will be automatically redirected to their running sessions on subsequent visits to the CGI script.

If a user has a session cookie from a previous visit but you wish to start a new session set the ```new=yes``` query parameter.

## Installation

Copy ```test_session_launcher.py``` and ```settings.py``` to the location where your web server is configured to look for CGI scripts (e.g., ```/usr/local/apache2/cgi-bin```), and set world read/execute permissions. Edit ```settings.py```, primarily to ensure that the correct ```SESSION_SCRIPT``` is being launched (this file has in-line documentation). An example ```session_example.sh``` is provided.

## Tests

To run the unit tests:

```
$ ./rununittests
```

Line-by-line coverage is output to the cover/ subdirectory.
