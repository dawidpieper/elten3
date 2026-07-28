#!/usr/bin/env python3
"""Probe a speech-dispatcher output module for broken SSML index-mark support.

Some output modules accept SSML, start speaking, and then never report anything
again: no index marks, no end notification. The message stays in the module for
good, CANCEL does not remove it, and every later message - from every client on
the machine, screen reader included - queues behind it. Only restarting
speech-dispatcher clears that.

This tool reproduces the failure in isolation and prints exactly what the module
reports, so the behaviour can be shown to the module's authors.

Run it twice on the same file to get the comparison that makes the bug obvious:

    ./ssml_probe.py text.txt --module rhvoice --voice Natan --plain
    ./ssml_probe.py text.txt --module rhvoice --voice Natan

A working module reports index marks as it goes and ends with 702 in both runs.
A broken one completes the --plain run and hangs on the SSML one.

WARNING: if the module is broken, the SSML run will leave speech-dispatcher
unable to speak at all until it is restarted:

    systemctl --user restart speech-dispatcher.service   # or: killall speech-dispatcher
"""

import argparse
import os
import re
import select
import socket
import sys
import time

# SSIP reply codes for asynchronous notifications.
INDEX_MARK, BEGIN, END, CANCEL, PAUSE, RESUME = "700", "701", "702", "703", "704", "705"
NOTIFICATIONS = {INDEX_MARK, BEGIN, END, CANCEL, PAUSE, RESUME}
NAMES = {INDEX_MARK: "INDEX MARK", BEGIN: "BEGIN", END: "END", CANCEL: "CANCEL",
         PAUSE: "PAUSE", RESUME: "RESUME"}


def socket_path():
    candidates = []
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if runtime:
        candidates.append(os.path.join(runtime, "speech-dispatcher", "speechd.sock"))
    candidates.append("/run/user/%d/speech-dispatcher/speechd.sock" % os.getuid())
    candidates.append(os.path.expanduser("~/.cache/speech-dispatcher/speechd.sock"))
    for path in candidates:
        if os.path.exists(path):
            return path
    sys.exit("speech-dispatcher socket not found; tried:\n  " + "\n  ".join(candidates))


class Ssip:
    def __init__(self, path, verbose=False):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(path)
        self.buffer = b""
        self.verbose = verbose
        self.started = time.monotonic()

    def stamp(self):
        return "%7.2fs" % (time.monotonic() - self.started)

    def line(self, blocking=True, timeout=0.5):
        """One protocol line, or None when nothing arrives in time."""
        while b"\n" not in self.buffer:
            if not blocking and not select.select([self.sock], [], [], 0)[0]:
                return None
            if blocking and not select.select([self.sock], [], [], timeout)[0]:
                return None
            chunk = self.sock.recv(8192)
            if not chunk:
                raise ConnectionError("speech-dispatcher closed the connection")
            self.buffer += chunk
        raw, self.buffer = self.buffer.split(b"\n", 1)
        return raw.decode("utf-8", "replace").rstrip("\r")

    def reply(self, on_event=None):
        """Reads one command reply, routing notifications to on_event."""
        collected = []
        while True:
            line = self.line()
            if line is None:
                return collected
            if line[:3] in NOTIFICATIONS:
                self.event(line, on_event)
                continue
            collected.append(line)
            if len(line) > 3 and line[3] == " ":
                return collected

    def event(self, line, on_event):
        """Notifications arrive as NNN-field lines closed by a final NNN line."""
        code, sep, rest = line[:3], line[3:4], line[4:]
        if sep == "-":
            self.pending = getattr(self, "pending", [])
            self.pending.append(rest)
            return
        fields = getattr(self, "pending", [])
        self.pending = []
        if on_event:
            on_event(code, fields)

    def command(self, text, on_event=None):
        if self.verbose:
            print("%s >> %s" % (self.stamp(), text))
        self.sock.sendall((text + "\r\n").encode("utf-8"))
        reply = self.reply(on_event)
        if self.verbose and reply:
            print("%s << %s" % (self.stamp(), " | ".join(reply)))
        return reply

    def speak(self, data, on_event=None):
        reply = self.command("SPEAK", on_event)
        if not reply or not reply[-1].startswith("2"):
            sys.exit("SPEAK refused: %s" % reply)
        # A line consisting of a single dot ends the block, so leading dots double.
        body = "\r\n".join("." + l if l.startswith(".") else l
                           for l in data.replace("\r\n", "\n").split("\n"))
        if self.verbose:
            print("%s >> [%d bytes of %s]" % (self.stamp(), len(data.encode()),
                                              "SSML" if "<mark" in data else "text"))
        self.sock.sendall((body + "\r\n.\r\n").encode("utf-8"))
        return self.reply(on_event)

    def pump(self, on_event):
        while True:
            line = self.line(blocking=False)
            if line is None:
                return
            if line[:3] in NOTIFICATIONS:
                self.event(line, on_event)


def split_units(text, mode):
    if mode == "word":
        return [u for u in re.split(r"(?<=\s)", text) if u.strip()]
    if mode == "line":
        return [u for u in text.splitlines(keepends=True) if u.strip()]
    return [u for u in re.split(r"(?<=[.!?])\s+", text) if u.strip()]


def escape(text):
    return (text.replace("&", "&amp;").replace("<", "&lt;")
                .replace(">", "&gt;").replace('"', "&quot;"))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("file", help="text file to speak")
    ap.add_argument("--module", help="output module, e.g. espeak-ng or rhvoice")
    ap.add_argument("--voice", help="synthesis voice, e.g. Natan")
    ap.add_argument("--unit", choices=["sentence", "word", "line"], default="sentence",
                    help="what one index mark covers (default: sentence)")
    ap.add_argument("--plain", action="store_true",
                    help="send the same text with no markup, for comparison")
    ap.add_argument("--rate", type=int, default=0, help="SSIP rate, -100..100")
    ap.add_argument("--stall", type=float, default=5.0,
                    help="seconds without any notification before declaring a stall")
    ap.add_argument("--wait", type=float, default=120.0, help="overall time limit")
    ap.add_argument("--verbose", action="store_true", help="show the raw protocol")
    args = ap.parse_args()

    with open(args.file, encoding="utf-8", errors="replace") as handle:
        text = handle.read()
    units = split_units(text, args.unit)
    if not units:
        sys.exit("nothing to speak in %s" % args.file)

    ssip = Ssip(socket_path(), args.verbose)
    ssip.command("SET self CLIENT_NAME probe:probe:main")
    ssip.command("SET self NOTIFICATION ALL on")
    if args.module:
        ssip.command("SET self OUTPUT_MODULE %s" % args.module)
    if args.voice:
        ssip.command("SET self SYNTHESIS_VOICE %s" % args.voice)
    ssip.command("SET self RATE %d" % args.rate)

    state = {"begin": False, "end": False, "marks": 0, "last": time.monotonic()}

    def on_event(code, fields):
        state["last"] = time.monotonic()
        name = NAMES.get(code, code)
        if code == INDEX_MARK:
            state["marks"] += 1
            mark = fields[2] if len(fields) > 2 else "?"
            index = int(mark) if mark.isdigit() else None
            where = units[index][:60].replace("\n", " ") if index is not None and index < len(units) else "?"
            print("%s  %-10s mark %-5s unit %s/%d  %r"
                  % (ssip.stamp(), name, mark, mark, len(units), where))
        else:
            if code == BEGIN:
                state["begin"] = True
            if code in (END, CANCEL):
                state["end"] = True
            print("%s  %-10s %s" % (ssip.stamp(), name, fields))

    print("file      : %s (%d bytes, %d %ss)" % (args.file, len(text.encode()), len(units), args.unit))
    print("module    : %s   voice: %s" % (args.module or "(daemon default)", args.voice or "(default)"))
    print("mode      : %s" % ("PLAIN TEXT (no markup)" if args.plain else "SSML with one <mark> per %s" % args.unit))
    print("-" * 72)

    if args.plain:
        ssip.command("SET self SSML_MODE off", on_event)
        payload = " ".join(u.strip() for u in units)
    else:
        ssip.command("SET self SSML_MODE on", on_event)
        payload = "".join('<mark name="%d"/>%s ' % (i, escape(u.strip()))
                          for i, u in enumerate(units))
    ssip.speak(payload, on_event)

    deadline = time.monotonic() + args.wait
    stalled = False
    while time.monotonic() < deadline:
        try:
            ssip.pump(on_event)
        except ConnectionError as error:
            print("\n%s  the daemon closed the connection: %s" % (ssip.stamp(), error))
            print("VERDICT: inconclusive - speech-dispatcher went away mid-run.")
            return 3
        if state["end"]:
            break
        if state["begin"] and time.monotonic() - state["last"] > args.stall:
            stalled = True
            break
        time.sleep(0.05)

    print("-" * 72)
    print("began: %s   index marks: %d/%d   ended: %s"
          % (state["begin"], state["marks"], 0 if args.plain else len(units), state["end"]))

    if state["end"]:
        print("VERDICT: OK - the module reported completion.")
        return 0
    if not state["begin"]:
        print("VERDICT: the module never even started speaking.")
        return 2
    print("VERDICT: STUCK - it started and then reported nothing for %.1fs." % args.stall)
    print("         The message is still held by the module. Expect every later")
    print("         message, from any client, to queue behind it until")
    print("         speech-dispatcher is restarted.")
    if not args.plain:
        print("         Re-run with --plain: if that one completes, the module's")
        print("         SSML handling is at fault, not the text.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
