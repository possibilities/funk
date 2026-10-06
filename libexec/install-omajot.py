#!/usr/bin/env python3
"""Converge one private Omajot endpoint without changing unrelated Serve routes."""

import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import time
from urllib.error import HTTPError, URLError
from urllib.request import urlopen


LABEL = "io.arthack.funk.omajot-hub"
TARGET = "http://127.0.0.1:8799"
HTTPS_PORT = "8448"
LOCAL_TARGET = re.compile(r"^(?:https?://)?(?:127\.0\.0\.1|localhost|\[::1\]):8799(?:/|$)")


def fail(message):
    raise RuntimeError(message)


def read_json(command, description):
    result = subprocess.run(command, text=True, capture_output=True)
    if result.returncode:
        fail(f"cannot read {description}; refusing to change Omajot")
    try:
        value = json.loads(result.stdout)
    except ValueError:
        fail(f"invalid {description}; refusing to change Omajot")
    if not isinstance(value, dict):
        fail(f"invalid {description}; refusing to change Omajot")
    return value


def identity():
    status = read_json(["tailscale", "status", "--json"], "Tailscale identity")
    node = status.get("Self") or {}
    user = (status.get("User") or {}).get(str(node.get("UserID"))) or {}
    dns = (node.get("DNSName") or "").rstrip(".")
    login = user.get("LoginName") or ""
    if status.get("BackendState") != "Running" or not node.get("Online"):
        fail("Tailscale must be running and signed in; no unauthenticated fallback")
    if not dns.endswith(".ts.net") or not all(
        re.fullmatch(r"[a-z0-9](?:[a-z0-9-]*[a-z0-9])?", label) for label in dns.split(".")
    ):
        fail("Tailscale did not supply a valid machine DNS name")
    if not isinstance(login, str) or not login or any(ord(c) < 32 for c in login):
        fail("Tailscale did not supply an untagged user login")
    return f"{dns}:{HTTPS_PORT}", login


def route_state(serve, endpoint):
    tcp, web, funnel = (serve.get(key, {}) for key in ("TCP", "Web", "AllowFunnel"))
    if not all(isinstance(section, dict) for section in (tcp, web, funnel)):
        fail("invalid Tailscale route status")
    if funnel.get(endpoint):
        fail("Omajot's HTTPS port has Funnel enabled; refusing public access")
    for host, definition in web.items():
        if not isinstance(definition, dict) or not isinstance(definition.get("Handlers", {}), dict):
            fail("invalid Tailscale web route")
        for handler in definition.get("Handlers", {}).values():
            proxy = handler.get("Proxy", "") if isinstance(handler, dict) else ""
            if isinstance(proxy, str) and LOCAL_TARGET.search(proxy) and host != endpoint:
                fail("another Tailscale endpoint proxies the Omajot listener")
        if host.endswith(f":{HTTPS_PORT}") and host != endpoint:
            fail("Omajot's HTTPS port belongs to another endpoint")
    for definition in tcp.values():
        if not isinstance(definition, dict):
            fail("invalid Tailscale TCP route")
        forward = definition.get("TCPForward", "")
        if isinstance(forward, str) and LOCAL_TARGET.search(forward):
            fail("a raw TCP route bypasses Omajot's identity proxy")
    listener, website = tcp.get(HTTPS_PORT), web.get(endpoint)
    if listener is None and website is None:
        return False
    if listener != {"HTTPS": True} or website != {"Handlers": {"/": {"Proxy": TARGET}}}:
        fail("Omajot's HTTPS port is already in use; refusing to replace its routes")
    return True


def serve_status():
    return read_json(["tailscale", "serve", "status", "--json"], "Tailscale route status")


def require_auth():
    deadline = time.monotonic() + 8
    while True:
        try:
            with urlopen(TARGET + "/api/whoami", timeout=1) as response:
                fail(f"local API returned {response.status}; refusing to proxy an unauthenticated hub")
        except HTTPError as error:
            if error.code == 403:
                return
            fail(f"local API returned {error.code}; authentication could not be verified")
        except (URLError, TimeoutError):
            if time.monotonic() >= deadline:
                fail("authenticated hub did not become ready; no Serve route was added")
            time.sleep(0.1)


def unrelated(serve, endpoint):
    """Only our exact listener/root handler may differ after publication."""
    result = json.loads(json.dumps(serve))
    for section, key in (("TCP", HTTPS_PORT), ("Web", endpoint)):
        result.get(section, {}).pop(key, None)
        if not result.get(section):
            result.pop(section, None)
    # An explicit false is equivalent to an absent Funnel grant.
    if result.get("AllowFunnel", {}).get(endpoint) is False:
        result["AllowFunnel"].pop(endpoint)
        if not result["AllowFunnel"]:
            result.pop("AllowFunnel")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("binary")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    home = Path.home()
    data = home / "omajot-data"
    if data.is_symlink():
        fail("refusing a symlinked hub data directory")
    endpoint, login = identity()
    url = f"https://{endpoint}"
    route_state(serve_status(), endpoint)
    client = ["/usr/bin/python3", str(args.root / "libexec/configure-omajot-client.py"), url, "--login", login]
    subprocess.run([*client, "--check"], check=True)
    template = args.root / "launchd" / f"{LABEL}.plist.in"
    with template.open("rb") as handle:
        rendered = plistlib.load(handle)
    substitutions = {"__OMAJOT_BINARY__": args.binary, "__OMAJOT_DATA__": str(data),
                     "__OMAJOT_LOGIN__": login, "__OMAJOT_URL__": url}
    rendered["ProgramArguments"] = [substitutions.get(arg, arg) for arg in rendered["ProgramArguments"]]
    rendered["EnvironmentVariables"]["HOME"] = str(home)
    logs = home / "Library/Logs/Funk"
    rendered["StandardOutPath"] = rendered["StandardErrorPath"] = str(logs / "omajot-hub.log")
    if args.check:
        print("Omajot authenticated hub, client configuration and private Serve route validate.")
        return
    agent = home / "Library/LaunchAgents" / f"{LABEL}.plist"
    launchctl = os.environ.get("FUNK_LAUNCHCTL_BIN", "/bin/launchctl")
    running = subprocess.run([launchctl, "print", f"gui/{os.getuid()}/{LABEL}"],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
    same = agent.is_file() and not agent.is_symlink() and agent.read_bytes() == plistlib.dumps(rendered)
    if running and not same:
        fail("hub configuration changed while running; stop the hub explicitly before reinstalling")
    subprocess.run(client, check=True)
    if not running:
        data.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="funk-omajot-") as temporary:
            path = Path(temporary) / f"{LABEL}.plist"
            path.write_bytes(plistlib.dumps(rendered))
            subprocess.run([str(args.root / "libexec/install-user-launchagent"), LABEL,
                            "com.arthack.funk.omajot-hub", str(path), str(logs)], check=True)
    # Never publish until the actual listener rejects unauthenticated requests.
    require_auth()
    before = serve_status()
    if not route_state(before, endpoint):
        subprocess.run(["tailscale", "serve", "--bg", f"--https={HTTPS_PORT}", TARGET],
                       check=True, stdout=subprocess.DEVNULL)
        after = serve_status()
        if not route_state(after, endpoint) or unrelated(before, endpoint) != unrelated(after, endpoint):
            fail("Serve publication did not preserve its private route boundary; inspect Tailscale routes")
    print(f"Omajot TUI and Android PWA: {url}/")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, subprocess.CalledProcessError) as error:
        # Do not echo arguments containing the operator's generated login.
        detail = str(error) if isinstance(error, RuntimeError) else "installation failed; inspect the preceding diagnostic"
        raise SystemExit(f"funk install-omajot: {detail}")
