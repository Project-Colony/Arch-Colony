#!/usr/bin/env python3
"""Boot an Arch Colony image in QEMU with no window, and drive it blind.

    tools/vm-headless.py start [install|base] [--offline]   boot the newest ISO of that profile on a fresh disk
    tools/vm-headless.py installed [--offline]              boot the disk the last install wrote
    tools/vm-headless.py stop
    tools/vm-headless.py shot NAME              screenshot -> NAME.png (prints the size)
    tools/vm-headless.py key K [K ...]          QEMU key names: ret, tab, spc, alt-n, ctrl-alt-f2 ...
    tools/vm-headless.py type TEXT              letters, digits, space, dot, dash; capitals via shift
    tools/vm-headless.py exec CMD [ARG ...]     run a command in the guest, exit with its status
    tools/vm-headless.py check-firewall         fail unless the firewall is running in the guest
    tools/vm-headless.py autoinstall            install on the VM `start` booted, then power it off
    tools/vm-headless.py smoke ISO              boot ISO on a serial console, check the live system, power off

--offline boots with no network card at all, so an install has no network
whatever the answer to "Activer le réseau": the offline path, which has to
install the firewall from the medium. After its first boot, `check-firewall`
asserts what that path promises: the table, the daemon and the default rules
active, the kernel object on disk, and `colonyctl status` saying so.

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

`autoinstall` does the above unattended, which is how the release workflow
installs: it reads the console for the network question, steps through the
pages, watching the installer's step list move on, and waits for the
installer's log to report the result. The partition page is the exception: a
radio button the keyboard cannot reach reliably, so it preselects "Erase disk"
in the live session's partition.conf before the installer starts.

`exec` and `check-firewall` go through the QEMU guest agent, which both the
live image and an installed system carry (qemu-guest-agent, started by udev when
the virtio port below appears), so they read the guest without a screen.

Needs qemu-desktop, edk2-ovmf and pyside6 (for the PPM -> PNG conversion).
Only `shot` needs pyside6, and qemu-base with qemu-hw-display-virtio-vga is
enough for the rest.

`smoke` is the release workflow's boot test and needs neither a screen nor Qt.
It boots the kernel, initramfs and command line of the image's own default
boot entry, adds a serial console, logs in there and runs SMOKE_CHECKS: the
same live system a user boots, read as text. It exits non-zero when the image
does not reach a login prompt or a check fails.
"""

import base64
import json
import os
import re
import select
import shutil
import socket
import subprocess
import sys
import tempfile
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
QGA = SOCK.with_name("arch-colony-qga.sock")
FIREWALL_UNITS = ("colony-firewall-nft.service", "colony-firewalld.service",
                  "colony-firewall-seed.service")


def fail(msg):
    print(f"vm-headless: {msg}", file=sys.stderr)
    sys.exit(1)


class AgentError(Exception):
    """The guest agent is not reachable, or not answering yet."""


def monitor(cmd, wait=0.3):
    """Send one HMP command and return what the monitor printed."""
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        s.connect(str(SOCK))
    except OSError:
        fail(f"no VM listening on {SOCK} - start one first")
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


def guest(command, arguments=None, timeout=10):
    """One guest agent command; returns its "return" value."""
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        s.connect(str(QGA))
    except OSError:
        raise AgentError(f"no VM listening on {QGA} - start one first") from None
    s.settimeout(timeout)
    f = s.makefile("rwb")

    def ask(execute, args):
        msg = {"execute": execute}
        if args is not None:
            msg["arguments"] = args
        f.write(json.dumps(msg).encode() + b"\n")
        f.flush()

    # guest-sync first: an earlier client may have left a reply in the channel,
    # and only the one carrying our id says the next line is ours.
    sync = int(time.time() * 1000) % 2**31
    try:
        ask("guest-sync", {"id": sync})
        while json.loads(f.readline()).get("return") != sync:
            pass
        ask(command, arguments)
        reply = json.loads(f.readline())
    except (OSError, json.JSONDecodeError):
        raise AgentError("the guest agent does not answer - is the guest still booting?") from None
    finally:
        s.close()
    if "error" in reply:
        fail(f"{command}: {reply['error'].get('desc', reply['error'])}")
    return reply["return"]


def guest_exec(argv, timeout=120):
    """Run argv in the guest; returns (status, stdout, stderr)."""
    pid = guest("guest-exec", {"path": argv[0], "arg": argv[1:], "capture-output": True})["pid"]
    deadline = time.monotonic() + timeout
    while not (st := guest("guest-exec-status", {"pid": pid}))["exited"]:
        if time.monotonic() > deadline:
            fail(f"{argv[0]} still running after {timeout} s")
        time.sleep(0.5)
    out, err = (base64.b64decode(st.get(k, "")).decode(errors="replace")
                for k in ("out-data", "err-data"))
    return st.get("exitcode", 1), out, err


def wait_for_agent(timeout):
    """Wait until the guest agent answers, which is once the guest has booted."""
    deadline = time.monotonic() + timeout
    while True:
        try:
            return guest("guest-ping", timeout=5)
        except AgentError:
            if time.monotonic() > deadline:
                raise
            time.sleep(3)


def exec_in_guest(argv):
    status, out, err = guest_exec(argv)
    sys.stdout.write(out)
    sys.stderr.write(err)
    sys.exit(status)


def check_firewall():
    wait_for_agent(600)
    # Boot finished, so that "inactive" means the unit did not start, not that
    # it has not started yet. Printed, not asserted: what it says about
    # anything but the firewall is not this check's business.
    _, state, _ = guest_exec(["/usr/bin/systemctl", "is-system-running", "--wait"], timeout=600)
    print(f"{'system':32} {state.strip()}")
    _, states, _ = guest_exec(["/usr/bin/systemctl", "is-active", *FIREWALL_UNITS])
    states = states.split()
    for unit, state in zip(FIREWALL_UNITS, states):
        print(f"{unit:32} {state}")
    obj, _, _ = guest_exec(["/usr/bin/test", "-f", "/usr/lib/colony-firewall/cfc-ebpf.o"])
    print(f"{'kernel object':32} {'present' if obj == 0 else 'MISSING'}")
    _, status, _ = guest_exec(["/usr/bin/colonyctl", "status"])
    print(status)
    if states != ["active"] * len(FIREWALL_UNITS) or obj != 0:
        fail("the firewall is not running as installed")
    print("PASS - the firewall runs on the installed system")


def qemu(extra, offline=False):
    for tool in ("qemu-system-x86_64", "qemu-img"):
        if subprocess.run(["which", tool], capture_output=True).returncode:
            fail(f"{tool} missing: pacman -S qemu-desktop")
    if not CODE.is_file():
        fail("OVMF missing: pacman -S edk2-ovmf")
    STATE.mkdir(parents=True, exist_ok=True)
    SOCK.unlink(missing_ok=True)
    QGA.unlink(missing_ok=True)
    PIDFILE.unlink(missing_ok=True)
    args = [
        "qemu-system-x86_64", "-enable-kvm", "-cpu", "host", "-m", "4G", "-smp", "4",
        "-drive", f"file={DISK},format=qcow2,if=virtio",
        *(["-nic", "none"] if offline else ["-nic", "user,model=virtio-net-pci"]),
        "-device", "usb-ehci", "-device", "usb-tablet",
        "-vga", "virtio", "-display", "none",
        "-drive", f"if=pflash,format=raw,readonly=on,file={CODE}",
        "-drive", f"if=pflash,format=raw,file={VARS}",
        "-monitor", f"unix:{SOCK},server,nowait",
        "-chardev", f"socket,id=qga0,path={QGA},server=on,wait=off",
        "-device", "virtio-serial",
        "-device", "virtserialport,chardev=qga0,name=org.qemu.guest_agent.0",
        "-daemonize", "-pidfile", str(PIDFILE),
        *extra,
    ]
    subprocess.run(args, check=True)
    print(f"started, pid {PIDFILE.read_text().strip()}; monitor at {SOCK}")


def start(profile, offline):
    pattern = {"base": "archcolony-base-*.iso", "install": "archcolony-2*.iso"}.get(
        profile, f"archcolony-{profile}-*.iso")
    isos = sorted((ROOT / "iso/out").glob(pattern), key=lambda p: p.stat().st_mtime)
    if not isos:
        fail(f"no ISO matching {pattern} in iso/out - run iso/build.sh first")
    iso = isos[-1]
    STATE.mkdir(parents=True, exist_ok=True)
    DISK.unlink(missing_ok=True)
    subprocess.run(["qemu-img", "create", "-f", "qcow2", str(DISK), DISK_SIZE],
                   check=True, stdout=subprocess.DEVNULL)
    subprocess.run(["cp", "-f", "/usr/share/edk2/x64/OVMF_VARS.4m.fd", str(VARS)], check=True)
    print(f"fresh disk {DISK} ({DISK_SIZE}); booting {iso.name}" + (", offline" if offline else ""))
    qemu(["-cdrom", str(iso), "-boot", "d"], offline)


def installed(offline):
    if not DISK.is_file():
        fail(f"no disk at {DISK} - nothing was installed yet")
    if not VARS.is_file():
        subprocess.run(["cp", "-f", "/usr/share/edk2/x64/OVMF_VARS.4m.fd", str(VARS)], check=True)
    print(f"booting {DISK}" + (", offline" if offline else ""))
    qemu(["-boot", "c"], offline)


def stop():
    if PIDFILE.is_file():
        pid = PIDFILE.read_text().strip()
        subprocess.run(["kill", pid], capture_output=True)
        PIDFILE.unlink(missing_ok=True)
        print(f"stopped pid {pid}")
    else:
        print("no headless VM running")
    SOCK.unlink(missing_ok=True)
    QGA.unlink(missing_ok=True)


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


def keys(names, pause=0.25):
    for k in names:
        monitor("sendkey " + k)
        time.sleep(pause)


def type_text(text):
    special = {" ": "spc", ".": "dot", "-": "minus", "_": "shift-minus", "/": "slash", "@": "shift-2"}
    names = [special.get(c) or (f"shift-{c.lower()}" if c.isupper() else c) for c in text]
    # One monitor session, ~80 ms apart: inside Qt's type-ahead window.
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        s.connect(str(SOCK))
    except OSError:
        fail(f"no VM listening on {SOCK} - start one first")
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


# What autoinstall types on the Users page. A throwaway machine: the disk is
# wiped by the next `start`, and nothing logs in with these.
INSTALL_LOGIN = "colony"
INSTALL_PASSWORD = "colony-smoke-test"
# The left margin of the installer's step list, where only the highlight of
# the current step is bright.
SIDEBAR_X = 10


def screendump(path):
    """The screen as (width, height, RGB bytes), saved to path as a PPM."""
    path.unlink(missing_ok=True)
    monitor(f"screendump {path}", wait=0.5)
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        data = path.read_bytes() if path.is_file() else b""
        head = re.match(rb"P6\s+(\d+)\s+(\d+)\s+255\s", data)
        if head and len(data) >= head.end() + int(head[1]) * int(head[2]) * 3:
            return int(head[1]), int(head[2]), data[head.end():]
        time.sleep(0.2)
    fail(f"screendump to {path} failed")


def current_step(path):
    """The height of the step the installer highlights, or None before it shows.

    The highlight is a bright band some 40 rows tall. Anything shorter, such as
    the console text the screen shows before the installer, is not it.
    """
    width, height, px = screendump(path)
    bright = [sum(px[(y * width + SIDEBAR_X) * 3:(y * width + SIDEBAR_X) * 3 + 3]) > 384
              for y in range(height)]
    band, top = None, None
    for y, lit in enumerate(bright + [False]):
        if lit and top is None:
            top = y
        elif not lit and top is not None:
            if y - top >= 20:
                band = (top + y - 1) / 2
            top = None
    return band


def wait_until(what, probe, timeout, interval=3, failure=fail):
    """Poll probe() until it returns something truthy; failure() after timeout."""
    deadline = time.monotonic() + timeout
    while not (found := probe()):
        if time.monotonic() > deadline:
            failure(f"timed out after {timeout} s waiting for {what}")
        time.sleep(interval)
    return found


def autoinstall():
    """Install on the VM `start` booted, through the installer's own pages."""
    STATE.mkdir(parents=True, exist_ok=True)
    screen = STATE / "autoinstall-screen.ppm"
    log = STATE / "calamares-session.log"

    def fetch_log():
        _, out, _ = guest_exec(["/usr/bin/cat", "/root/.cache/calamares/session.log"])
        log.write_text(out)

    def failed(msg):
        try:
            screendump(screen)
            fetch_log()
        except AgentError:
            pass
        fail(f"{msg}; the screen is in {screen}, the installer log in {log}")

    def advance(press, page, timeout=120, pause=0.25):
        """Press keys until the highlight leaves the current step, once retried."""
        before = current_step(screen)
        if before is None:
            failed(f"the installer shows no current step before {page}")
        for _ in range(2):
            keys(press, pause)
            deadline = time.monotonic() + timeout / 2
            while time.monotonic() < deadline:
                now = current_step(screen)
                if now is not None and now > before + 10:
                    print(f"    {page}")
                    return
                time.sleep(2)
        failed(f"the installer did not move on to {page}")

    wait_for_agent(600)
    # The question .zlogin asks before it starts the installer, read off the
    # first console. A key sent before it is asked could be lost.
    wait_until("the live session's network question",
               lambda: "[o/N]" in guest_exec(["/usr/bin/cat", "/dev/vcs1"])[1], 300)
    # The one change to the medium: "Erase disk" preselected, which is the
    # click a person makes on that page. Without a mouse, the radio button
    # cannot be reached reliably by keyboard; every page and every job is
    # otherwise exactly what a person installs with.
    conf = "/etc/calamares/modules/partition.conf"
    guest_exec(["/usr/bin/sed", "-i", "s/^initialPartitioningChoice: .*/initialPartitioningChoice: erase/", conf])
    if guest_exec(["/usr/bin/grep", "-qx", "initialPartitioningChoice: erase", conf])[0]:
        fail(f"could not preselect the erase choice in {conf}")
    print("==> the network stays off; starting the installer")
    keys(["n"])
    # cage falls back to software rendering after a failed first start, which
    # takes a while on a VM without a GPU.
    wait_until("the installer's first page", lambda: current_step(screen) is not None, 600,
               failure=failed)
    print("==> through the installer's pages")
    for page in ("Location", "Keyboard", "Partitions", "Software", "Users"):
        advance(["alt-n"], page)
    # Name, login and hostname follow from the name; one password for the
    # user and, ticked last, for the administrator.
    type_text(INSTALL_LOGIN)
    keys(["tab", "tab", "tab"])
    type_text(INSTALL_PASSWORD)
    keys(["tab"])
    type_text(INSTALL_PASSWORD)
    keys(["tab", "spc"])
    advance(["alt-n"], "Summary")
    # Install, then Install Now once the confirmation is up.
    advance(["alt-i", "alt-i"], "Install", pause=3)

    print("==> installing")
    pattern = re.compile(r"completion: (succeeded|failed)|Installation failed:.*")
    found = wait_until("the installation to finish", lambda: pattern.search(
        guest_exec(["/usr/bin/cat", "/root/.cache/calamares/session.log"])[1]), 2700, interval=10,
        failure=failed)
    fetch_log()
    if found.group(1) != "succeeded":
        failed(f"the installation failed: {found.group(0)}")
    print(f"    finished; the installer log is in {log}")

    # The power button, so that the live system shuts down cleanly.
    pid = int(PIDFILE.read_text())
    monitor("system_powerdown")
    try:
        wait_until("the live system to power off", lambda: not Path(f"/proc/{pid}").exists(), 300, 2)
    finally:
        stop()


# Run as root on the live image, in bash. Each line is one check; the first
# that exits non-zero fails the smoke test.
SMOKE_CHECKS = [
    # Booted all the way, with no failed unit. "degraded" means one failed.
    "systemctl is-system-running --wait",
    # The image says what it is, and runs the kernel it is meant to.
    ". /etc/os-release && echo \"$PRETTY_NAME\" && test \"$ID\" = archcolony",
    "uname -r | grep -- -hardened$",
    # The [colony] packages the installer copies onto every disk.
    "pacman -Q calamares colony-keyring colony-mirrorlist colony-mkinitcpio colony-release colonyctl",
    # pacman-init populated the keyring with the Colony key, and trusts it.
    "pacman-key --list-keys 5CD2FCA13E691C65A354780D80C118F774E6C43F",
    "colonyctl status",
]


def iso_file(iso, path):
    """One file out of the image, without mounting it."""
    out = subprocess.run(["bsdtar", "-xOf", str(iso), path], capture_output=True)
    if out.returncode or not out.stdout:
        fail(f"{path} is not in {iso.name}")
    return out.stdout


def boot_entry(iso):
    """kernel, initrds and options of the entry systemd-boot starts by default."""
    loader = iso_file(iso, "loader/loader.conf").decode()
    default = re.search(r"^default\s+(\S+)", loader, re.M)
    if not default:
        fail("loader/loader.conf names no default entry")
    entry = {"initrd": []}
    for line in iso_file(iso, "loader/entries/" + default.group(1)).decode().splitlines():
        key, _, value = line.strip().partition(" ")
        if key == "initrd":
            entry["initrd"].append(value.strip().lstrip("/"))
        elif key in ("linux", "options"):
            entry[key] = value.strip().lstrip("/") if key == "linux" else value.strip()
    if "linux" not in entry or not entry["initrd"]:
        fail(f"the default entry {default.group(1)} has no linux or initrd line")
    return entry


class Serial:
    """The guest's serial console, as QEMU's stdin and stdout."""

    def __init__(self, proc, log):
        self.proc, self.log, self.buf = proc, log, ""

    def expect(self, pattern, timeout):
        """Read until pattern matches what arrived since the last match."""
        regex = re.compile(pattern)
        deadline = time.monotonic() + timeout
        while True:
            found = regex.search(self.buf)
            if found:
                self.buf = self.buf[found.end():]
                return found
            left = deadline - time.monotonic()
            if left <= 0 or self.proc.poll() is not None:
                return None
            ready, _, _ = select.select([self.proc.stdout], [], [], min(left, 1))
            if ready:
                chunk = os.read(self.proc.stdout.fileno(), 65536).decode(errors="replace")
                self.log.write(chunk)
                self.log.flush()
                self.buf += chunk

    def send(self, line):
        self.proc.stdin.write((line + "\n").encode())
        self.proc.stdin.flush()


def smoke(iso):
    iso = Path(iso).resolve()
    if not iso.is_file():
        fail(f"no such image: {iso}")
    for tool in ("qemu-system-x86_64", "bsdtar"):
        if not shutil.which(tool):
            fail(f"{tool} missing: pacman -S qemu-base libarchive")
    if not CODE.is_file():
        fail("OVMF missing: pacman -S edk2-ovmf")
    if not os.access("/dev/kvm", os.R_OK | os.W_OK):
        fail("/dev/kvm is not usable here; without KVM the boot takes too long to test")

    entry = boot_entry(iso)
    with tempfile.TemporaryDirectory(prefix="colony-smoke.") as tmp:
        tmp = Path(tmp)
        kernel = tmp / "vmlinuz"
        kernel.write_bytes(iso_file(iso, entry["linux"]))
        # Several initrds are cpio archives the kernel unpacks in turn, which is
        # what one concatenated file is too.
        initrd = tmp / "initrd"
        initrd.write_bytes(b"".join(iso_file(iso, i) for i in entry["initrd"]))
        shutil.copy("/usr/share/edk2/x64/OVMF_VARS.4m.fd", tmp / "vars.fd")
        append = entry.get("options", "") + " console=ttyS0,115200"
        print(f"booting {iso.name}: {entry['linux']} {append}", flush=True)

        proc = subprocess.Popen([
            # q35: on the default i440fx machine a directly booted kernel never
            # sees the IDE CD-ROM, and the initramfs drops to a rescue shell
            # waiting for the image. The SATA one q35 has is found at once.
            "qemu-system-x86_64", "-machine", "q35", "-enable-kvm", "-cpu", "host",
            "-m", "4G", "-smp", "4",
            "-drive", f"if=pflash,format=raw,readonly=on,file={CODE}",
            "-drive", f"if=pflash,format=raw,file={tmp / 'vars.fd'}",
            "-cdrom", str(iso), "-kernel", str(kernel), "-initrd", str(initrd),
            "-append", append,
            # Offline, as an install from the medium is by default.
            # std VGA: built into qemu-system-x86, where virtio-vga is a
            # separate package a headless runner does not install.
            "-nic", "none", "-vga", "std", "-display", "none",
            "-monitor", "none", "-serial", "stdio",
        ], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        console = Serial(proc, sys.stdout)
        try:
            ok = run_checks(console)
            console.send("poweroff")
            try:
                proc.wait(timeout=120)
            except subprocess.TimeoutExpired:
                print("\nvm-headless: the guest did not power off; killing it", file=sys.stderr)
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait()
    if not ok:
        fail("smoke test failed")
    print("\nsmoke test passed")


def run_checks(console):
    if not console.expect(r"login: ", timeout=600):
        print("\nvm-headless: no login prompt on the serial console", file=sys.stderr)
        return False
    # root has no password on the live image.
    console.send("root")
    if not console.expect(r"#\s", timeout=120):
        print("\nvm-headless: no shell prompt after logging in", file=sys.stderr)
        return False
    # A plain shell with no prompt and no echo, so that what comes back is only
    # what the checks print.
    console.send("exec bash --norc --noprofile --noediting")
    # Each line only once the shell before it is listening: zsh throws away
    # what was typed ahead while it hands over to bash.
    if not console.expect(r"bash-[\d.]+# ", timeout=60):
        print("\nvm-headless: bash did not start", file=sys.stderr)
        return False
    # dmesg -n 1: kernel messages on this console would land in the middle
    # of what the checks print.
    # The sum, not a literal: the terminal echoes the command line back
    # before stty takes effect, and that echo must not count as the answer.
    console.send("stty -echo; PS1=; dmesg -n 1; echo ready-for-$((1 + 1))")
    if not console.expect(r"ready-for-2", timeout=60):
        print("\nvm-headless: no bash after logging in", file=sys.stderr)
        return False
    ok = True
    for check in SMOKE_CHECKS:
        print(f"\n==> {check}", flush=True)
        console.send(f"( {check} ) 2>&1; echo \"check-exit=$?\"")
        found = console.expect(r"check-exit=(\d+)", timeout=600)
        if not found or found.group(1) != "0":
            print(f"\nvm-headless: FAILED: {check}", file=sys.stderr)
            if check.startswith("systemctl is-system-running"):
                console.send("systemctl --failed --no-pager; echo listed-failed-units")
                console.expect(r"listed-failed-units", timeout=60)
            ok = False
    return ok


def main(argv):
    # Progress as it happens, in CI's log too, where stdout is a pipe.
    sys.stdout.reconfigure(line_buffering=True)
    try:
        run(argv)
    except AgentError as e:
        fail(str(e))


def run(argv):
    if len(argv) < 2:
        fail(__doc__.split("\n\n")[1])
    verb, rest = argv[1], argv[2:]
    if verb in ("start", "installed"):
        offline = "--offline" in rest
        rest = [a for a in rest if a != "--offline"]
    if verb == "start" and len(rest) <= 1:
        start(rest[0] if rest else "install", offline)
    elif verb == "installed" and not rest:
        installed(offline)
    elif verb == "stop":
        stop()
    elif verb == "shot" and len(rest) == 1:
        shot(rest[0])
    elif verb == "key" and rest:
        keys(rest)
    elif verb == "type" and len(rest) == 1:
        type_text(rest[0])
    elif verb == "exec" and rest:
        exec_in_guest(rest)
    elif verb == "check-firewall" and not rest:
        check_firewall()
    elif verb == "autoinstall" and not rest:
        autoinstall()
    elif verb == "smoke" and len(rest) == 1:
        smoke(rest[0])
    else:
        fail(__doc__.split("\n\n")[1])


if __name__ == "__main__":
    main(sys.argv)
