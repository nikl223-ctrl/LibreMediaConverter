#!/usr/bin/env python3
"""Control an authorized external Sunshine machine via SSH from the lightweight gateway.

This script never transfers passwords, cookies or browser profiles. A remote
user-systemd unit keeps persistent login data on the remote compute host.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys

HOST_RE = re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9.-]{0,251}$")
USER_RE = re.compile(r"^[a-z_][a-z0-9_-]{0,31}$")
COMMANDS = ("start", "stop", "status", "logs")

def load_config(path):
    with Path(path).expanduser().open(encoding="utf-8") as stream:
        value = json.load(stream)
    if not isinstance(value, dict):
        raise ValueError("Configuration must be a JSON object")
    host = value.get("remote_host")
    user = value.get("remote_user")
    key = value.get("ssh_key")
    port = value.get("ssh_port", 22)
    if not isinstance(host, str) or not HOST_RE.fullmatch(host) or ".." in host:
        raise ValueError("remote_host must be a valid hostname or IPv4 address")
    if not isinstance(user, str) or not USER_RE.fullmatch(user):
        raise ValueError("Invalid remote_user")
    if not isinstance(key, str) or not key.strip():
        raise ValueError("ssh_key must specify an existing SSH private key")
    if not isinstance(port, int) or isinstance(port, bool) or not (1 <= port <= 65535):
        raise ValueError("ssh_port must be between 1 and 65535")
    identity = Path(key).expanduser()
    if not identity.is_file():
        raise ValueError("SSH private key does not exist: " + str(identity))
    return {"host": host, "user": user, "identity": str(identity), "port": port}

def ssh_argv(config, command):
    if command not in COMMANDS:
        raise ValueError("Unknown command")
    return [
        "ssh", "-n",
        "-o", "BatchMode=yes",
        "-o", "StrictHostKeyChecking=yes",
        "-o", "ConnectTimeout=8",
        "-i", config["identity"],
        "-p", str(config["port"]),
        "--", config["user"] + "@" + config["host"],
        "cloudgaming-remote-control", command,
    ]

def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=COMMANDS)
    parser.add_argument("--config", default=os.environ.get(
        "CLOUDGAMING_CONFIG", "~/.config/cloudgaming-gateway/config.json"))
    parser.add_argument("--dry-run", action="store_true",
                        help="Display remote target and command, without connecting")
    args = parser.parse_args(argv)
    try:
        config = load_config(args.config)
        command = ssh_argv(config, args.command)
        if args.dry_run:
            print("DRY RUN: would send", args.command, "to",
                  config["user"] + "@" + config["host"])
            return 0
        result = subprocess.run(command, check=False, timeout=35)
        return result.returncode
    except (ValueError, OSError, subprocess.TimeoutExpired) as exc:
        print("cloudgamingctl:", exc, file=sys.stderr)
        return 2

if __name__ == "__main__":
    raise SystemExit(main())
