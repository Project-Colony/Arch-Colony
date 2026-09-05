#!/usr/bin/env python3
"""Boot an Arch Colony image in QEMU with no window, and drive it blind.

    tools/vm-headless.py start [install|base]   boot the newest ISO of that profile on a fresh disk
    tools/vm-headless.py installed              boot the disk the last install wrote
    tools/vm-headless.py stop
    tools/vm-headless.py shot NAME              screenshot -> NAME.png (prints the size)
    tools/vm-headless.py key K [K ...]          QEMU key names: ret, tab, spc, alt-n, ctrl-alt-f2 ...
    tools/vm-headless.py type TEXT              letters, digits, space, dot, dash; capitals via shift

Same machine as tools/run-iso.sh and the same disk (colony-target.qcow2 under
~/.cache/arch-colony), so a headless install can be opened in a window afterwards
with tools/run-installed.sh. `start` wipes that disk, exactly as run-iso.sh does.

Why no window: a validation that pops a QEMU window steals focus and keyboard
from whoever is working on the machine, and cannot run from a script. Here the
screen is read through QEMU's monitor (screendump) and input is sent the same way.

What was learned driving Calamares this way (2026-09-05):
  - The live session stops at "Activer le réseau ? [o/N]" before starting the
    installer: `key o ret`, then ~30 s until the welcome page.
  - The mouse is dead: neither the HID tablet nor vmmouse reach cage through
    the monitor, and a QMP input-send-event crashed QEMU 11.1. Keyboard only.
  - Calamares is fully keyboard-driven: alt-n Next, alt-b Back, alt-i Install
    and again alt-i on the confirmation. On the partition page, Tab then Space
    repeatedly until the "Erase disk" radio takes it (4 rounds from a fresh page).
  - On the Software page the package tree has focus on arrival. `type hypr`
    is a type-ahead search that lands on Hyprland; Space toggles the row.
    Keys must arrive within Qt's 400 ms window, which `type` guarantees.
  - Compare screenshot regions to detect page changes; convert to RGB32 first
    (QImage.copy() leaves row padding uninitialised, so raw bytes hash randomly).

Needs qemu-desktop, edk2-ovmf and pyside6 (for the PPM -> PNG conversion).
"""

import os
import socket
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STATE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "arch-colony"
DISK = Path(os.environ.get("COLONY_TEST_DISK", STATE / "colony-target.qcow2"))
DISK_SIZE = os.environ.get("COLONY_TEST_DISK_SIZE", "20G")
VARS = STATE / "colony-OVMF_VARS.fd"
CODE = Path("/usr/share/edk2/x64/OVMF_CODE.4m.fd")
PIDFILE = STATE / "colony-headless.pid"
# UNIX socket paths are capped at 108 bytes; the runtime dir is short and per-user.
SOCK = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "arch-colony-vm.sock"


def fail(msg):
    print(f"vm-headless: {msg}", file=sys.stderr)
    sys.exit(1)


def monitor(cmd, wait=0.3):
    """Send one HMP command and return what the monitor printed."""
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        s.connect(str(SOCK))
    except OSError:
        fail(f"no VM listening on {SOCK} — start one first")
    s.settimeout(2)
    time.sleep(0.15)
    try:
        s.recv(4096)  # banner
    except socket.timeout:
        pass
    s.sendall((cmd + "\n").encode())
    time.sleep(wait)
    out = b""
    try:
        while True:
            chunk = s.recv(65536)
            if not chunk:
                break
            out += chunk
            if b"(qemu)" in chunk:
                break
    except socket.timeout:
        pass
    s.close()
    return out.decode(errors="replace")


def qemu(extra):
    for tool in ("qemu-system-x86_64", "qemu-img"):
        if subprocess.run(["which", tool], capture_output=True).returncode:
            fail(f"{tool} missing: pacman -S qemu-desktop")
    if not CODE.is_file():
        fail("OVMF missing: pacman -S edk2-ovmf")
    STATE.mkdir(parents=True, exist_ok=True)
    SOCK.unlink(missing_ok=True)
    PIDFILE.unlink(missing_ok=True)
    args = [
        "qemu-system-x86_64", "-enable-kvm", "-cpu", "host", "-m", "4G", "-smp", "4",
        "-drive", f"file={DISK},format=qcow2,if=virtio",
        "-nic", "user,model=virtio-net-pci",
        "-device", "usb-ehci", "-device", "usb-tablet",
        "-vga", "virtio", "-display", "none",
        "-drive", f"if=pflash,format=raw,readonly=on,file={CODE}",
        "-drive", f"if=pflash,format=raw,file={VARS}",
        "-monitor", f"unix:{SOCK},server,nowait",
        "-daemonize", "-pidfile", str(PIDFILE),
        *extra,
    ]
    subprocess.run(args, check=True)
    print(f"started, pid {PIDFILE.read_text().strip()}; monitor at {SOCK}")


def start(profile):
    pattern = {"base": "archcolony-base-*.iso", "install": "archcolony-2*.iso"}.get(
        profile, f"archcolony-{profile}-*.iso")
    isos = sorted((ROOT / "iso/out").glob(pattern), key=lambda p: p.stat().st_mtime)
    if not isos:
        fail(f"no ISO matching {pattern} in iso/out — run iso/build.sh first")
    iso = isos[-1]
    STATE.mkdir(parents=True, exist_ok=True)
    DISK.unlink(missing_ok=True)
    subprocess.run(["qemu-img", "create", "-f", "qcow2", str(DISK), DISK_SIZE],
                   check=True, stdout=subprocess.DEVNULL)
    subprocess.run(["cp", "-f", "/usr/share/edk2/x64/OVMF_VARS.4m.fd", str(VARS)], check=True)
    print(f"fresh disk {DISK} ({DISK_SIZE}); booting {iso.name}")
    qemu(["-cdrom", str(iso), "-boot", "d"])


def installed():
    if not DISK.is_file():
        fail(f"no disk at {DISK} — nothing was installed yet")
    if not VARS.is_file():
        subprocess.run(["cp", "-f", "/usr/share/edk2/x64/OVMF_VARS.4m.fd", str(VARS)], check=True)
    print(f"booting {DISK}")
    qemu(["-boot", "c"])


def stop():
    if PIDFILE.is_file():
        pid = PIDFILE.read_text().strip()
        subprocess.run(["kill", pid], capture_output=True)
        PIDFILE.unlink(missing_ok=True)
        print(f"stopped pid {pid}")
    else:
        print("no headless VM running")
    SOCK.unlink(missing_ok=True)


def shot(name):
    from PySide6.QtGui import QImage  # only here: the other verbs need no Qt
    ppm = Path(name + ".ppm").resolve()
    png = Path(name + ".png").resolve()
    monitor(f"screendump {ppm}", wait=1.5)
    img = QImage(str(ppm))
    if img.isNull() or not img.save(str(png)):
        fail(f"screendump failed (is the VM running? see {SOCK})")
    ppm.unlink(missing_ok=True)
    print(f"{png}  {img.width()}x{img.height()}")


def keys(names):
    for k in names:
        monitor("sendkey " + k)
        time.sleep(0.25)


def type_text(text):
    special = {" ": "spc", ".": "dot", "-": "minus", "_": "shift-minus", "/": "slash", "@": "shift-2"}
    names = [special.get(c) or (f"shift-{c.lower()}" if c.isupper() else c) for c in text]
    # One monitor session, ~80 ms apart: inside Qt's type-ahead window.
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        s.connect(str(SOCK))
    except OSError:
        fail(f"no VM listening on {SOCK} — start one first")
    s.settimeout(1)
    time.sleep(0.15)
    try:
        s.recv(4096)
    except socket.timeout:
        pass
    for k in names:
        s.sendall(f"sendkey {k}\n".encode())
        time.sleep(0.08)
    time.sleep(0.3)
    s.close()


def main(argv):
    if len(argv) < 2:
        fail(__doc__.split("\n\n")[1])
    verb, rest = argv[1], argv[2:]
    if verb == "start":
        start(rest[0] if rest else "install")
    elif verb == "installed":
        installed()
    elif verb == "stop":
        stop()
    elif verb == "shot" and len(rest) == 1:
        shot(rest[0])
    elif verb == "key" and rest:
        keys(rest)
    elif verb == "type" and len(rest) == 1:
        type_text(rest[0])
    else:
        fail(__doc__.split("\n\n")[1])


if __name__ == "__main__":
    main(sys.argv)
