#!/usr/bin/env python3
"""Aqua-session regression: an idle MCP server must not swallow normal app opening.

Build an isolated signed fixture with automation_ui_probe.py --root ...noindex
--bundle-id local.dd.mcplaunch...qa first. Never accepts the installed app identity.
"""
import argparse, json, os, plistlib, select, signal, subprocess, tempfile, time
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("app", type=Path)
parser.add_argument("--report", type=Path)
args = parser.parse_args()
app = args.app.resolve()
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
identity = info["CFBundleIdentifier"]
assert identity.startswith("local.dd.mcplaunch") and identity.endswith("qa"), "Disposable launch QA identities only"
project = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(suffix=".noindex") as folder:
    helper = Path(folder) / "inspect"
    subprocess.run(["xcrun", "swiftc", str(project / "Tests/Fixtures/AutomationLaunchInspection.swift"), "-o", str(helper)], check=True, timeout=60)
    def applications():
        return json.loads(subprocess.check_output([str(helper), identity], text=True, timeout=10))
    assert not applications(), "The QA identity is already running"
    with (Path(folder) / "stderr.log").open("w") as errors:
        process = subprocess.Popen([str(app / "Contents/MacOS/DayDistance"), "--cli", "mcp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=errors, text=True)
        def rpc(identifier, method, params=None):
            process.stdin.write(json.dumps({"jsonrpc": "2.0", "id": identifier, "method": method, "params": params or {}}) + "\n")
            process.stdin.flush()
            assert select.select([process.stdout], [], [], 10)[0], "MCP did not reply before stdin EOF"
            reply = json.loads(process.stdout.readline())
            assert reply["id"] == identifier
            return reply
        report = {"mcpPID": process.pid, "opens": []}
        try:
            assert rpc(1, "initialize", {"protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": {"name": "launch-regression", "version": "1"}})["result"]["protocolVersion"] == "2025-11-25"
            report["beforeOpen"] = applications()
            gui_pid = None
            for attempt in range(3):
                subprocess.run(["/usr/bin/open", str(app)], check=True, timeout=15)
                deadline = time.monotonic() + 10
                while time.monotonic() < deadline:
                    running = applications()
                    gui = [item for item in running if item["policy"] == 0 and item["pid"] != process.pid and item["finished"]]
                    if gui:
                        break
                    time.sleep(0.2)
                report["opens"].append(running)
                assert len(gui) == 1, "Normal opening was swallowed by MCP or created duplicate GUI instances"
                if gui_pid is None:
                    gui_pid = gui[0]["pid"]
                assert gui[0]["pid"] == gui_pid, "Repeated normal opening must reuse the GUI"
                assert process.poll() is None
                assert len(rpc(2 + attempt, "tools/list")["result"]["tools"]) == 10
            report["passed"] = True
            print("MCP_NORMAL_LAUNCH_PASS: normal opening, repeated opens reuse one GUI, MCP connection and 10 tools remain available")
        finally:
            if args.report:
                args.report.write_text(json.dumps(report, indent=2) + "\n")
            if process.poll() is None:
                process.stdin.close()
                try:
                    process.wait(timeout=6)
                except subprocess.TimeoutExpired:
                    process.terminate()
                    process.wait(timeout=6)
            for item in applications():
                if item["pid"] != process.pid:
                    try:
                        os.kill(item["pid"], signal.SIGTERM)
                    except ProcessLookupError:
                        pass
