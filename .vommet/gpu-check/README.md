# Nightly GPU widget check

GitHub and Forgejo CI machines have no GPU. Under software rendering WebKitGTK
falls back to shared memory frames, which hid a real bug: on Wayland with a GPU,
a popped out docked widget was an all-black window. This check runs the released
Linux build on a real GPU (Intel Iris Xe) every night.

It runs in the `vommet-gpu-test` container on cubuntu. That container is for tests
only; it is not a CI runner.

## What it checks

`nightly.sh` fetches the newest `testing-*` release that has a Linux x64 tarball and
verifies the tarball's sha256. It then runs `probe-run.sh` twice, once under Wayland
and once under X11 (Xwayland). Both use weston headless with the GL renderer on the
GPU.

`dockprobe.so` is loaded into the real `vommet` binary with `LD_PRELOAD`. It catches
the `vommet/widget_dock` method channel that the runner registers at startup, then
drives the shipped dock code with a local test page (`page.html`):

- dock the page
- pop it out
- dock it back
- full screen while docked, then leave (Esc on X11, the page itself on Wayland)
- full screen while popped out, then the window manager leaves it
- destroy while in full screen

Each step is checked by counting pixel colours in a compositor screenshot, so a black
window fails.

The app runs offline (`unshare -n`) with a throwaway home directory. It never signs in
and never opens a real room.

The result is posted as the commit status `widgets-gpu / linux (cubuntu igpu)` on the
release tag's commit. Screenshots and logs are kept for two weeks in
`/var/lib/vommet-gpu-check/runs`.

## Schedule and CI courtesy

The timer runs at 03:15 America/New_York. That is after the 06:55 UTC nightly and
between the 2-hourly sync cuts at :47.

forgejo-runner shares the host with this container. Before starting, the check looks
at `nether/vommet` and `nether/nether-voicebridge` for running or waiting Actions
tasks. These light bookkeeping workflows are ignored: `pr-github`, `github-copy`,
`nightly` and `upstream-sync`. While real jobs run, it waits in 5 minute steps for up
to 70 minutes, then skips the night.

The service runs with `Nice=10`.

## Install or update (inside vommet-gpu-test, as root)

1. Install the packages:

   ```
   apt-get install --no-install-recommends gcc pkg-config libgtk-3-dev \
     libwebkit2gtk-4.1-0 libkeybinder-3.0-0 libmpv2 weston xwayland xdotool \
     dbus python3 curl ca-certificates
   ```

2. Install the scripts and build the probe:

   ```
   install -d /opt/vommet-gpu-check
   install -m 755 nightly.sh probe-run.sh /opt/vommet-gpu-check/
   install -m 644 dockprobe.c page.html /opt/vommet-gpu-check/
   gcc -O1 -shared -fPIC -o /opt/vommet-gpu-check/dockprobe.so /opt/vommet-gpu-check/dockprobe.c \
     $(pkg-config --cflags --libs gtk+-3.0 gdk-wayland-3.0) -ldl
   ```

3. Enable the timer:

   ```
   install -m 644 vommet-gpu-check.service vommet-gpu-check.timer /etc/systemd/system/
   systemctl daemon-reload && systemctl enable --now vommet-gpu-check.timer
   ```

To run a check now: `systemctl start vommet-gpu-check`. Follow it with
`journalctl -u vommet-gpu-check`.

To try one build by hand, unpack its tarball and run:

```
./probe-run.sh <bundle dir> wayland|x11 <label> <out dir>
```

## Token

The status is posted with a dedicated Forgejo token in
`/etc/vommet-gpu-check/forgejo-token`. Keep it root-only (`0600`) and never print it.

The token needs the `write:repository` scope, which Forgejo requires for commit
statuses. Forgejo tokens can't be limited to a single repository, so use an account
that can write only where it needs to.

Forgejo won't mint a token from another token. An account owner or an admin must
create it.
