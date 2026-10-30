#!/usr/bin/env python3
# bwrap wrapper for building Flatpaks inside an unprivileged incus container
# without security.nesting: a fresh /proc can be mounted in a new PID namespace
# only from the container's own user namespace, not a nested one. Flatpak always
# asks for --unshare-user, so drop it (and the options that require it) and run
# the build sandbox as the container's root. Flatpak passes most options via
# "--args <fd>" (NUL-separated); those are read, filtered and inlined.
# Used only via FLATPAK_BWRAP for flatpak-builder on this host.
import os, sys
drop_flag = {"--unshare-user", "--unshare-user-try", "--disable-userns", "--assert-userns-disabled"}
drop_with_arg = {"--uid", "--gid", "--userns", "--userns2"}

def expand(args):
    out = []
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--args" and i + 1 < len(args):
            fd = int(args[i + 1])
            data = b""
            while True:
                chunk = os.read(fd, 65536)
                if not chunk:
                    break
                data += chunk
            os.close(fd)
            parts = data.split(b"\0")
            if parts and parts[-1] == b"":
                parts = parts[:-1]  # trailing NUL terminator; keep empty values
            inner = [s.decode() for s in parts]
            out.extend(expand(inner))
            i += 2
            continue
        out.append(a)
        i += 1
    return out

def filt(args):
    # These flags never appear as values of other options, so remove them
    # wherever they occur; --uid/--gid only exist alongside --unshare-user.
    out = []
    i = 0
    while i < len(args):
        a = args[i]
        if a in drop_flag:
            i += 1; continue
        if a in drop_with_arg:
            i += 2; continue
        out.append(a); i += 1
    return out

final = filt(expand(sys.argv[1:]))
os.execv("/usr/bin/bwrap", ["bwrap"] + final)
