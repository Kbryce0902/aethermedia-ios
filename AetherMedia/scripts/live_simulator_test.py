#!/usr/bin/env python3
"""Opt-in live iOS integration runner. Never publish raw XCTest logs or private grants."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def private_dir():
    folder = Path(os.environ["RUNNER_TEMP"]) / "aether-live-rd"
    folder.mkdir(mode=0o700, parents=True, exist_ok=True)
    folder.chmod(0o700)
    return folder


def output_dir():
    folder = ROOT / "build" / "LiveReports"
    folder.mkdir(mode=0o700, parents=True, exist_ok=True)
    return folder


def run_json(*args):
    return json.loads(subprocess.check_output(args, text=True))


def validate_code_card(value):
    expected = {"status", "verification_url", "user_code", "expires_at", "approval_wait_seconds", "real_network"}
    if set(value) != expected or value["status"] != "awaiting_approval":
        raise ValueError("Invalid authorization card")
    if value["verification_url"] != "https://real-debrid.com/device":
        raise ValueError("Unexpected verification endpoint")
    if not re.fullmatch(r"[A-Za-z0-9-]{4,40}", value["user_code"]):
        raise ValueError("Invalid display-code shape")
    if not isinstance(value["approval_wait_seconds"], int) or not 0 < value["approval_wait_seconds"] <= 1200:
        raise ValueError("Invalid approval interval")
    return value


def prepare():
    if sys.platform != "darwin":
        raise SystemExit("A Mac with Xcode is required.")
    folder = private_dir()
    devices = run_json("xcrun", "simctl", "list", "devices", "available", "--json")["devices"]
    candidates = [(runtime, device) for runtime, entries in devices.items() if "iOS" in runtime
                  for device in entries if device.get("isAvailable") and device["name"].startswith("iPhone")]
    if not candidates:
        raise SystemExit("No available iPhone simulator runtime.")
    runtime, phone = candidates[-1]
    types = run_json("xcrun", "simctl", "list", "devicetypes", "--json")["devicetypes"]
    phone_type = next(item["identifier"] for item in types if item["name"] == phone["name"])
    simulator = subprocess.check_output(["xcrun", "simctl", "create", "AetherMedia-Live-" + os.environ.get("GITHUB_RUN_ID", "local"), phone_type, runtime], text=True).strip()
    state = {"simulator": simulator, "phone": phone["name"], "runtime": runtime}
    (folder / "state.json").write_text(json.dumps(state))
    subprocess.run(["xcrun", "simctl", "boot", simulator], check=True, stdout=subprocess.DEVNULL)
    subprocess.run(["xcrun", "simctl", "bootstatus", simulator, "-b"], check=True, stdout=subprocess.DEVNULL)
    derived = ROOT / "build" / "LiveDerivedData"
    command = ["xcodebuild", "-project", "AetherMedia.xcodeproj", "-scheme", "AetherMedia", "-configuration", "Debug",
               "-destination", "id=" + simulator, "-derivedDataPath", str(derived), "CODE_SIGNING_ALLOWED=NO", "build-for-testing"]
    with (folder / "build.log").open("w") as log:
        result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        # No account authorization has started; compiler output cannot contain live credentials.
        print("\n".join((folder / "build.log").read_text(errors="replace").splitlines()[-100:]))
        raise SystemExit(result.returncode)
    original = next((derived / "Build" / "Products").glob("*.xctestrun"))
    with original.open("rb") as source:
        payload = plistlib.load(source)
    env = {"AETHERMEDIA_UNIT_TESTING": "1", "AETHER_LIVE_RD": "1",
           "AETHER_LIVE_GRANT_PATH": str(folder / "pending-grant.json"),
           "AETHER_LIVE_PUBLIC_CODE_PATH": str(output_dir() / "authorize.json"),
           "AETHER_LIVE_REPORT_PATH": str(output_dir() / "report.json")}
    targets = 0

    def inject(node):
        nonlocal targets
        if isinstance(node, dict):
            if "TestBundlePath" in node:
                node.setdefault("EnvironmentVariables", {}).update(env)
                targets += 1
            for child in list(node.values()):
                inject(child)
        elif isinstance(node, list):
            for child in node:
                inject(child)

    inject(payload)
    if targets != 1:
        raise SystemExit("Unexpected hosted-test target layout; refusing to start authorization.")
    # Keep the xctestrun beside the original: __TESTROOT__ is relative to this directory.
    configured = original.with_name("LiveRealDebrid.xctestrun")
    with configured.open("wb") as dest:
        plistlib.dump(payload, dest)
    state["xctestrun"] = str(configured)
    (folder / "state.json").write_text(json.dumps(state))
    print(json.dumps({"status": "built", "phone": phone["name"], "runtime": runtime, "live_credentials_requested": False}))


def execute(method):
    folder = private_dir()
    state = json.loads((folder / "state.json").read_text())
    command = ["xcodebuild", "test-without-building", "-xctestrun", state["xctestrun"],
               "-destination", "id=" + state["simulator"], "-parallel-testing-enabled", "NO", "-test-timeouts-enabled", "NO",
               "-only-testing:AetherMediaTests/LiveRealDebridTests/" + method]
    # VLC and OS diagnostics may contain a signed URL. These logs never go to Actions output/artifacts.
    with (folder / (method + ".log")).open("w") as log:
        result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    if method == "test00RequestAuthorization" and result.returncode == 0:
        card = validate_code_card(json.loads((output_dir() / "authorize.json").read_text()))
        print(json.dumps(card, sort_keys=True))
    elif (output_dir() / "report.json").exists():
        print((output_dir() / "report.json").read_text())
    else:
        print(json.dumps({"status": "live_test_failed_without_report", "method": method}))
    raise SystemExit(result.returncode)


def cleanup():
    folder = private_dir()
    state_path = folder / "state.json"
    if state_path.exists():
        state = json.loads(state_path.read_text())
        simulator = state.get("simulator")
        if simulator:
            subprocess.run(["xcrun", "simctl", "shutdown", simulator], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run(["xcrun", "simctl", "delete", simulator], check=True, stdout=subprocess.DEVNULL)
    import shutil
    shutil.rmtree(folder, ignore_errors=True)
    shutil.rmtree(ROOT / "build" / "LiveDerivedData", ignore_errors=True)
    print("Temporary simulator, pending grant, raw test logs and test build removed.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["prepare", "request", "test", "cleanup"])
    action = parser.parse_args().action
    if action == "prepare":
        prepare()
    elif action == "request":
        execute("test00RequestAuthorization")
    elif action == "test":
        execute("test10LiveAccountCloudAndPublicVideo")
    else:
        cleanup()
