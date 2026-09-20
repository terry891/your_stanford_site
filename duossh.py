#!/usr/bin/env python3
"""
Open a cached SSH master connection to a Stanford host with a clean Duo prompt.

Stanford's Duo shows its whole menu again after sending SMS codes, which reads
as if nothing happened. This wrapper hides the menu, picks the SMS option for
you, and then asks one question:  Enter SMS passcode:

Nothing is written to disk. On success an authenticated SSH control socket is
left open so later runs need no password at all.
"""
import argparse
import getpass
import os
import pty
import re
import select
import shlex
import sys
import time

SENTINEL = "__DUOSSH_AUTH_OK__"

RE_DUO_Q   = re.compile(r"Passcode or option \((\d+)-(\d+)\):\s*$")
RE_PW_Q    = re.compile(r"[Pp]assword:\s*$")
RE_ITEM    = re.compile(r"^\s*(\d+)\.\s+(.+?)\s*$")
RE_MENUHDR = re.compile(r"^\s*Enter a passcode or select one of the following options:\s*$")
RE_DUOHDR  = re.compile(r"^\s*Duo two-factor login for \S+\s*$")
RE_SENT    = re.compile(r"(New SMS passcodes sent|next code starts with)", re.I)
RE_FAIL    = re.compile(r"(Permission denied|Authentication failed|Access denied"
                        r"|Too many authentication failures|Login incorrect)", re.I)
RE_PHONE   = re.compile(r"(X{2,}[-. ]X{2,}[-. ]\d{2,}|\+?\d[\d\-.() ]{6,}\d)")
RE_PROMPTY = re.compile(r"[:?]\s*$")


def note(msg):
    print(f"    {msg}", flush=True)


class Session:
    def __init__(self, fd, method):
        self.fd = fd
        self.method = method
        self.menu = {}
        self.phone = None
        self.code_requested = False
        self.pw_attempts = 0
        self.authed = False
        self.failed = False
        self.last_sent = None
        self._echo = None     # compared against remote echo, never printed

    def send(self, text, secret=False):
        self.last_sent = None if secret else text
        self._echo = text
        os.write(self.fd, (text + "\n").encode())

    # ---- line classification -------------------------------------------
    def emit(self, raw):
        line = raw.rstrip("\r")
        if SENTINEL in line:
            self.authed = True
            return
        if RE_MENUHDR.match(line) or RE_DUOHDR.match(line):
            return
        m = RE_ITEM.match(line)
        if m:                                    # a Duo menu entry
            self.menu[int(m.group(1))] = m.group(2)
            if "sms" in m.group(2).lower():
                ph = RE_PHONE.search(m.group(2))
                if ph:
                    self.phone = ph.group(1)
            return
        if RE_SENT.search(line):                 # we print our own version
            return
        if self._echo is not None and line.strip() == self._echo:
            self._echo = None
            return                               # remote echo of our own reply
        if not line.strip():
            return
        if RE_FAIL.search(line):
            self.failed = True
        note(line.strip())

    # ---- prompt handlers -----------------------------------------------
    def pick_option(self):
        want = {"sms": "sms", "push": "push", "call": "phone call"}[self.method]
        for num, label in sorted(self.menu.items()):
            if want in label.lower():
                return num
        return None

    def answer_duo(self):
        if self.method == "ask" or (not self.code_requested and not self.menu):
            for num, label in sorted(self.menu.items()):
                note(f"{num}. {label}")
            self.send(input("    Passcode or option: ").strip())
            self.code_requested = True
            return

        if not self.code_requested:
            opt = self.pick_option()
            if opt is None:
                note(f"no {self.method} option offered by Duo; showing the menu")
                for num, label in sorted(self.menu.items()):
                    note(f"{num}. {label}")
                self.send(input("    Passcode or option: ").strip())
            else:
                where = f" to {self.phone}" if self.phone else ""
                note(f"Duo: requesting {self.method.upper()} passcode{where} ...")
                self.send(str(opt))
            self.code_requested = True
            return

        # Codes are already on their way. This is the only question we ask.
        label = {"sms": "Enter SMS passcode: ",
                 "call": "Enter the passcode read to you: "}.get(self.method, "Enter passcode: ")
        while True:
            code = input("    " + label).strip()
            if code:
                self.send(code)
                return
            note("(a passcode is required)")

    def answer_password(self):
        self.pw_attempts += 1
        label = "    SUNet password: " if self.pw_attempts == 1 \
                else f"    SUNet password (attempt {self.pw_attempts}): "
        self.send(getpass.getpass(label), secret=True)

    # ---- stream processing ----------------------------------------------
    def feed(self, buf):
        *lines, tail = buf.split("\n")
        for line in lines:
            self.emit(line)
            if self.authed:
                return ""
        if RE_DUO_Q.search(tail):
            self.answer_duo()
            return ""
        if RE_PW_Q.search(tail):
            self.answer_password()
            return ""
        return tail

    def unknown_prompt(self, tail):
        """Fallback so an unexpected question can never strand the user."""
        text = tail.strip()
        if not text:
            return
        note(f"(unrecognised prompt) {text}")
        self.send(input("    > "))


def main():
    ap = argparse.ArgumentParser(description="SSH to a Stanford host with clean Duo prompts.")
    ap.add_argument("target", help="user@host")
    ap.add_argument("--control-path", required=True)
    ap.add_argument("--persist", default="8h", help="how long the cached session stays open")
    ap.add_argument("--method", default="sms", choices=["sms", "push", "call", "ask"])
    args = ap.parse_args()

    ssh_bin = shlex.split(os.environ.get("DUOSSH_SSH", "ssh"))
    cmd = [
        *ssh_bin, "-M",
        "-o", f"ControlPath={args.control_path}",
        "-o", f"ControlPersist={args.persist}",
        "-o", "StrictHostKeyChecking=accept-new",
        "-o", "NumberOfPasswordPrompts=3",
        args.target, f"echo {SENTINEL}",
    ]

    pid, fd = pty.fork()
    if pid == 0:
        os.execvp(cmd[0], cmd)
        os._exit(127)

    sess = Session(fd, args.method)
    buf = ""
    last_read = time.time()
    try:
        while True:
            ready, _, _ = select.select([fd], [], [], 0.4)
            if ready:
                try:
                    chunk = os.read(fd, 4096)
                except OSError:
                    break
                if not chunk:
                    break
                buf += chunk.decode("utf-8", "replace")
                last_read = time.time()
                buf = sess.feed(buf)
                if sess.authed:
                    break
            elif buf.strip() and RE_PROMPTY.search(buf) and time.time() - last_read > 2.5:
                sess.unknown_prompt(buf)
                buf = ""
    except KeyboardInterrupt:
        note("cancelled")
        return 130
    finally:
        try:
            os.close(fd)
        except OSError:
            pass

    if sess.authed:
        note(f"authenticated, session cached for {args.persist}")
        return 0
    note("authentication did not complete")
    return 1


if __name__ == "__main__":
    sys.exit(main())
