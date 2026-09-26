#!/usr/bin/env python3
"""Does a booting Tart guest's agent answer? (#149) Used by e2e.sh and golden.sh.

    python3 agent-probe.py TART_HOME/vms/<vm>/control.sock

Exit 0: the agent answers through tart's control socket; 1: tart closed the connection or it
stayed silent (the agent is not up yet); 2: no socket yet.

A plain connection, not `tart exec`: a client that goes away before tart has accepted it kills
tart 2.38's control socket for good (NIOFcntlFailedError), and a `tart exec` probe against a
booting guest is such a client. This one leaves only after data or a 3 s timeout, never before
tart has accepted it.
"""
import os
import socket
import sys

d, name = os.path.split(sys.argv[1])
try:
    os.chdir(d)   # a relative path: AF_UNIX paths are capped at 104 bytes
except OSError:
    sys.exit(2)
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(3)
try:
    s.connect(name)
except OSError:
    sys.exit(2)
try:
    # tart accepts, then dials the guest for this connection: it hangs up if nothing listens, and
    # while the guest boots the dial can simply hang. Only the agent speaks first (its HTTP/2
    # SETTINGS frame, within ~0.1 s), so data is the one sign it is up.
    sys.exit(0 if s.recv(1) else 1)
except (socket.timeout, OSError):
    sys.exit(1)
finally:
    s.close()
