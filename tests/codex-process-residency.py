#!/usr/bin/env python3
"""Offline scripted native subagent residency test, with no model service.

One stock process, one fake MCP per resident thread; all Responses are literal
fixture events produced by an HTTP server thread in this process.

Usage: python3 tests/codex-process-residency.py /absolute/codex configured 24
Run from an owned evidence directory; receipts and disposable state go there.
Use 12 6 for the historical comparison; 1 4 --replace-roots for root retention
and explicit child unsubscribe. Requires Python 3.11+, macOS and 40 free user slots.
"""
import http.server
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import threading
import time
import tomllib
from codex_process_fixture import ROOT, Rpc, descendants, process_rows, stop_owned


class Provider(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        state = self.server.fixture
        state.setdefault("request_shapes", []).append({"keys": list(body), "model": body.get("model"), "tools": body.get("tools")})
        state["requests"] += 1
        n = state["requests"]
        tool = state.pop("next_tool", None)
        child_request = any(i.get("type") == "agent_message" and "Return fixture completion." in json.dumps(i)
                            for i in body.get("input", []))
        identity_called = any(i.get("type") == "function_call" and i.get("name") == "identity"
                              for i in body.get("input", []))
        if tool:
            tools = body.get("tools", [])
            state["tools"] = tools
            namespace = "collaboration"
            for entry in tools:
                if entry.get("type") == "namespace" and any(t.get("name") == "spawn_agent" for t in entry.get("tools", [])):
                    namespace = entry["name"]
            item = {"type": "function_call", "id": f"fc_{n}", "call_id": f"call_{n}",
                    "name": "spawn_agent", "arguments": json.dumps({"task_name": tool,
                    "message": "Return fixture completion.", "fork_turns": "none"})}
            if namespace:
                item["namespace"] = namespace
        elif child_request and not identity_called:
            item = {"type": "function_call", "id": f"fc_{n}", "call_id": f"call_{n}",
                    "namespace": "mcp__process_probe", "name": "identity", "arguments": "{}"}
        else:
            item = {"type": "message", "id": f"msg_{n}", "role": "assistant", "status": "completed",
                    "content": [{"type": "output_text", "text": "fixture-complete", "annotations": []}]}
        response = {"id": f"resp_{n}", "object": "response", "status": "completed", "output": [item],
                    "usage": {"input_tokens": 10, "output_tokens": 5, "total_tokens": 15}}
        events = [{"type": "response.created", "response": {**response, "status": "in_progress", "output": []}},
                  {"type": "response.output_item.added", "output_index": 0, "item": item},
                  {"type": "response.output_item.done", "output_index": 0, "item": item},
                  {"type": "response.completed", "response": response}]
        payload = "".join("data: " + json.dumps(e) + "\n\n" for e in events).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


def run(binary, capacity, cycles=6, replace_roots=False):
    if not 1 <= capacity <= 12 or not 1 <= cycles <= 24 or min(capacity, cycles) + 1 > 8:
        raise ValueError("Fixture must stay within eight descendants and 24 cycles")
    if replace_roots and (capacity != 1 or cycles > 4):
        raise ValueError("Root replacement probe requires capacity one and at most four cycles")
    rows = process_rows()
    limit = int(subprocess.run(["sysctl", "-n", "kern.maxprocperuid"], capture_output=True,
                              text=True, check=True).stdout)
    if limit - sum(u == os.getuid() for _, _, u in rows) < 40:
        raise RuntimeError("Need 40 free user process slots")
    receipt = {"started": time.time(), "replace_roots": replace_roots, "capacity": capacity, "samples": [], "complete": False}
    server = http.server.HTTPServer(("127.0.0.1", 0), Provider)
    server.fixture = {"requests": 0}
    worker = threading.Thread(target=server.serve_forever)
    worker.start()
    try:
        with tempfile.TemporaryDirectory(prefix="subagent-probe-", dir=ROOT) as directory:
            directory = Path(directory)
            config = f'''model = "gpt-5.6-sol"
model_provider = "fixture"
check_for_update_on_startup = false
approval_policy = "never"
sandbox_mode = "danger-full-access"
thread_unload_delay_secs = 0
[model_providers.fixture]
name = "Offline literal fixture"
base_url = "http://127.0.0.1:{server.server_port}/v1"
wire_api = "responses"
supports_websockets = false
[agents]
max_concurrent_threads_per_session = {capacity}
[features]
multi_agent_v2 = true
code_mode = false
collab = true
apps = false
plugins = false
remote_plugin = false
hooks = false
shell_snapshot = false
shell_snapshot_v2 = false
[analytics]
enabled = false
[mcp_servers.process_probe]
command = {json.dumps(sys.executable)}
args = {json.dumps([str(Path(__file__).with_name("codex_process_fixture.py")), "--fake-server"])}
required = true
'''
            (directory / "config.toml").write_text(config)
            env = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "CODEX_HOME": str(directory),
                   "TMPDIR": str(directory), "LANG": "en_US.UTF-8"}
            with (directory / "stderr.log").open("wb") as stderr:
                child = subprocess.Popen([binary, "app-server", "--listen", "stdio://"],
                                         cwd=directory, env=env, stdin=subprocess.PIPE,
                                         stdout=subprocess.PIPE, stderr=stderr, start_new_session=True)
                rpc = Rpc(child)
                try:
                    rpc.call("initialize", {"clientInfo": {"name": "offline_residency_probe", "version": "1"},
                                            "capabilities": {"experimentalApi": True}})
                    rpc.send({"method": "initialized", "params": {}})
                    root = rpc.call("thread/start", {"cwd": str(directory)})["thread"]["id"]
                    previous_pids = set()
                    for cycle in range(cycles):
                        server.fixture["next_tool"] = f"fixture_{cycle}"
                        turn = rpc.call("turn/start", {"threadId": root, "input": [{"type": "text", "text": "Fixture step"}]})["turn"]["id"]
                        deadline = time.monotonic() + 15
                        while time.monotonic() < deadline:
                            rpc.call("thread/loaded/list", {})
                            turns = [n["params"]["turn"] for n in rpc.notifications
                                     if n["method"] == "turn/completed" and n["params"]["turn"]["id"] == turn]
                            if turns:
                                receipt["last_turn"] = turns[-1]
                                break
                            time.sleep(0.1)
                        else:
                            raise TimeoutError("Fixture root did not complete")
                        # Let the literal child response complete before requesting another slot.
                        time.sleep(0.3)
                        loaded = rpc.call("thread/loaded/list", {})["data"]
                        deadline = time.monotonic() + 8
                        while time.monotonic() < deadline:
                            states = [rpc.call("thread/read", {"threadId": t})["thread"]["status"] for t in loaded]
                            if all(s.get("type") != "active" for s in states):
                                break
                            time.sleep(0.1)
                        else:
                            receipt["pending_requests"] = rpc.server_requests
                            raise TimeoutError("Fixture child still active")
                        rows = process_rows()
                        owned = descendants(rows, child.pid)
                        sample = {"cycle": cycle, "loaded": loaded, "descendants": owned,
                                  "requests": server.fixture["requests"]}
                        receipt["samples"].append(sample)
                        print(json.dumps(sample), flush=True)
                        if len(owned) > 8 or limit - sum(u == os.getuid() for _, _, u in rows) < 24:
                            raise RuntimeError("Process safety bound exceeded")
                        if len(loaded) < 2:
                            raise RuntimeError("Scripted native spawn did not create a child")
                        expected = min(cycle + 1, capacity) + 1
                        if replace_roots:
                            expected = cycle + 2
                        assert len(loaded) == len(owned) == expected, (sample, expected)
                        assert server.fixture["requests"] == (cycle + 1) * 4, "Spawn/tool/completion sequence failed"
                        alive = {p for p, _, _ in rows}
                        assert not ((previous_pids - set(owned)) & alive), "Evicted MCP process survived"
                        previous_pids = set(owned)
                        if replace_roots:
                            sample["unsubscribe"] = rpc.call("thread/unsubscribe", {"threadId": root})
                            deadline = time.monotonic() + 8
                            while time.monotonic() < deadline:
                                remaining = rpc.call("thread/loaded/list", {})["data"]
                                if root not in remaining:
                                    break
                                time.sleep(0.1)
                            else:
                                raise TimeoutError("Unsubscribed root remained loaded")
                            time.sleep(0.3)
                            sample["after_unsubscribe"] = {"loaded": remaining,
                                "descendants": descendants(process_rows(), child.pid)}
                            assert len(remaining) == len(sample["after_unsubscribe"]["descendants"]) == cycle + 1
                            print(json.dumps(sample["after_unsubscribe"]), flush=True)
                            if cycle + 1 < cycles:
                                root = rpc.call("thread/start", {"cwd": str(directory)})["thread"]["id"]
                    if replace_roots:
                        receipt["child_unsubscribe"] = {t: rpc.call("thread/unsubscribe", {"threadId": t})
                                                          for t in remaining}
                        deadline = time.monotonic() + 8
                        while time.monotonic() < deadline:
                            if not rpc.call("thread/loaded/list", {})["data"] and not descendants(process_rows(), child.pid):
                                break
                            time.sleep(0.1)
                        else:
                            raise TimeoutError("Explicit child unsubscribe did not release fixture threads/tools")
                        receipt["after_child_unsubscribe"] = {
                            "loaded": rpc.call("thread/loaded/list", {})["data"],
                            "descendants": descendants(process_rows(), child.pid)}
                        print(json.dumps({"child_unsubscribe": receipt["child_unsubscribe"],
                                          "after": receipt["after_child_unsubscribe"]}), flush=True)
                    receipt["complete"] = True
                finally:
                    rpc.close()
                    stop_owned(child)
                    receipt["child_exit"] = child.returncode
                    receipt["pending_requests"] = rpc.server_requests
                    receipt["stderr"] = (directory / "stderr.log").read_text()[-6000:]
    finally:
        server.shutdown()
        server.server_close()
        worker.join()
        receipt["ended"] = time.time()
        receipt["tool_names"] = [{"name": t.get("name"), "type": t.get("type")} for t in server.fixture.get("tools", [])]
        receipt["request_shapes"] = server.fixture.get("request_shapes")
        (ROOT / f"subagent-probe-{int(receipt['started'])}.json").write_text(json.dumps(receipt, indent=2))


if __name__ == "__main__":
    def expired(*_):
        raise TimeoutError("Three-minute fixture bound exceeded")
    signal.signal(signal.SIGALRM, expired)
    signal.alarm(180)
    capacity = (tomllib.loads((Path(__file__).resolve().parents[1] / "config/harnesses/codex.toml").read_text())
                ["agents"]["max_concurrent_threads_per_session"] if sys.argv[2] == "configured" else int(sys.argv[2]))
    run(str(Path(sys.argv[1]).resolve(strict=True)), capacity, int(sys.argv[3]) if len(sys.argv) > 3 else 6, "--replace-roots" in sys.argv[4:])
