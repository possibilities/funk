#!/usr/bin/env python3
"""Offline MCP fixture and bounded stock-process test helpers."""
import json
import os
from pathlib import Path
import selectors
import signal
import subprocess
import sys
import time

ROOT = Path.cwd()


def fake_server():
    for line in sys.stdin:
        request = json.loads(line)
        if "id" not in request:
            continue
        method = request["method"]
        if method == "initialize":
            result = {"protocolVersion": request["params"]["protocolVersion"],
                      "capabilities": {"tools": {}},
                      "serverInfo": {"name": "owned-process-probe", "version": "1"}}
        elif method == "tools/list":
            result = {"tools": [{"name": "identity", "description": "Owned fixture PID",
                                 "inputSchema": {"type": "object", "properties": {}}}]}
        elif method == "tools/call":
            result = {"content": [{"type": "text", "text": str(os.getpid())}]}
        elif method in ("resources/list", "resources/templates/list", "prompts/list"):
            result = {"resources/list": {"resources": []},
                      "resources/templates/list": {"resourceTemplates": []},
                      "prompts/list": {"prompts": []}}[method]
        elif method == "ping":
            result = {}
        else:
            print(json.dumps({"jsonrpc": "2.0", "id": request["id"],
                              "error": {"code": -32601, "message": "Unsupported fixture method"}}), flush=True)
            continue
        print(json.dumps({"jsonrpc": "2.0", "id": request["id"], "result": result}), flush=True)


class Rpc:
    def __init__(self, child):
        self.child = child
        self.selector = selectors.DefaultSelector()
        self.selector.register(child.stdout, selectors.EVENT_READ)
        self.pending = b""
        self.serial = 0
        self.server_requests = []
        self.notifications = []

    def send(self, value):
        self.child.stdin.write(json.dumps(value).encode() + b"\n")
        self.child.stdin.flush()

    def call(self, method, params):
        self.serial += 1
        serial = self.serial
        self.send({"id": serial, "method": method, "params": params})
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            if b"\n" not in self.pending:
                if not self.selector.select(max(0, deadline - time.monotonic())):
                    raise TimeoutError(method)
                data = os.read(self.child.stdout.fileno(), 65536)
                if not data:
                    raise RuntimeError("Child ended during " + method)
                self.pending += data
                continue
            line, self.pending = self.pending.split(b"\n", 1)
            value = json.loads(line)
            if "method" in value and "id" in value:
                self.server_requests.append(value)
            elif "method" in value:
                self.notifications.append(value)
            if value.get("id") != serial or "method" in value:
                continue
            if "error" in value:
                raise RuntimeError(method + ": " + json.dumps(value["error"]))
            return value["result"]
        raise TimeoutError(method)

    def close(self):
        self.selector.close()


def process_rows():
    result = subprocess.run(["ps", "-axo", "pid=,ppid=,uid="],
                            capture_output=True, text=True, check=True, timeout=5)
    return [tuple(map(int, line.split())) for line in result.stdout.splitlines()]


def descendants(rows, pid):
    found = {pid}
    while True:
        updated = found | {p for p, parent, _ in rows if parent in found}
        if found == updated:
            return sorted(found - {pid})
        found = updated


def stop_owned(child):
    # This process group is created exclusively by this probe. Never name-match.
    if child.poll() is None:
        child.stdin.close()
        try:
            child.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(child.pid, signal.SIGTERM)
            try:
                child.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(child.pid, signal.SIGKILL)
                child.wait(timeout=3)
    # An owned descendant may survive its parent. A process group cannot be
    # reassigned while its members remain; this is our exclusive new group.
    try:
        os.killpg(child.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        try:
            os.killpg(child.pid, 0)
        except ProcessLookupError:
            return
        time.sleep(0.1)
    os.killpg(child.pid, signal.SIGKILL)


if __name__ == "__main__":
    if sys.argv[1:] != ["--fake-server"]:
        raise SystemExit("Only --fake-server is supported")
    fake_server()
