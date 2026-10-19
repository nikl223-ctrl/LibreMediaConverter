#!/usr/bin/env python3
"""Read-only performance diagnostics for an Ubuntu Sunshine/Moonlight gateway.

This does not measure Moonlight's client-side frame timing or input-to-photon
latency. Use Moonlight's performance overlay for those metrics.
"""
import argparse
import ipaddress
import math
from pathlib import Path
import re
import statistics
import subprocess
import time

INTERFACE_RE = re.compile(r"^[A-Za-z0-9_.:-]{1,32}$")
CPU_FIELDS_TO_EXCLUDE = (3, 4)  # idle and iowait

def cpu_sample(contents):
    line = next((x for x in contents.splitlines() if x.startswith("cpu ")), None)
    if not line:
        raise ValueError("No aggregate /proc/stat CPU record")
    nums = [int(part) for part in line.split()[1:]]
    if len(nums) < 5:
        raise ValueError("Incomplete CPU record")
    total = sum(nums)
    idle = nums[3] + nums[4]
    return total, idle

def cpu_percentage(start, end):
    total = end[0] - start[0]
    idle = end[1] - start[1]
    if total <= 0:
        return 0.0
    return max(0.0, min(100.0, 100.0 * (total - idle) / total))

def network_sample(contents, interface):
    for line in contents.splitlines()[2:]:
        name, sep, data = line.rpartition(":")
        if sep and name.strip() == interface:
            values = [int(s) for s in data.strip().split()]
            if len(values) < 16:
                raise ValueError("Incomplete /proc/net/dev interface record")
            return {
                "rx_bytes": values[0], "rx_errs": values[2], "rx_drops": values[3],
                "tx_bytes": values[8], "tx_errs": values[10], "tx_drops": values[11]
            }
    raise ValueError(f"Network interface {interface!r} not found in /proc/net/dev")

def diff_counters(start, end):
    return {key: max(0, end[key] - start[key]) for key in start}

def parse_ping_ms(raw):
    """Return ICMP round-trip time, or None if blocked / unavailable."""
    match = re.search(r"\btime[=<]([0-9]+(?:\.[0-9]+)?)\s*ms\b", raw)
    return float(match.group(1)) if match else None

def one_ping(ip):
    try:
        p = subprocess.run(
            ["ping", "-n", "-c", "1", "-W", "1", ip],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
            timeout=3, check=False
        )
        return parse_ping_ms(p.stdout)
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None

def percentile(values, q):
    if not values:
        return None
    a = sorted(values)
    rank = math.ceil(q * len(a)) - 1
    return a[max(rank, 0)]

def read_cpu():
    return cpu_sample(Path("/proc/stat").read_text())

def read_network(interface):
    return network_sample(Path("/proc/net/dev").read_text(), interface)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--interface", required=True, help="Gateway ingress or WireGuard interface")
    parser.add_argument("--seconds", type=int, default=60, help="Sample duration (5 to 600 seconds)")
    parser.add_argument("--ping-ip", help="Optional authorized WireGuard peer IP for ICMP RTT")
    args = parser.parse_args()
    if not INTERFACE_RE.fullmatch(args.interface) or args.interface.startswith("-"):
        parser.error("Invalid interface name")
    if not 5 <= args.seconds <= 600:
        parser.error("--seconds must be between 5 and 600")
    if args.ping_ip:
        try:
            addr = ipaddress.ip_address(args.ping_ip)
            if addr.is_multicast or addr.is_unspecified or addr.is_loopback:
                raise ValueError("Invalid target")
        except ValueError:
            parser.error("--ping-ip requires a valid unicast address")

    begin = time.monotonic()
    previous_cpu = read_cpu()
    previous_net = read_network(args.interface)
    max_seconds = float(args.seconds)
    cpu_pct, rtt = [], []
    cumulative = {key: 0 for key in previous_net}
    samples = 0
    print(f"Gateway health: {args.interface}, {args.seconds}s; read-only, no game rendering")
    while time.monotonic() - begin < max_seconds:
        time.sleep(min(1.0, max_seconds - (time.monotonic() - begin)))
        current_cpu = read_cpu()
        current_net = read_network(args.interface)
        cpu_pct.append(cpu_percentage(previous_cpu, current_cpu))
        for key, delta in diff_counters(previous_net, current_net).items():
            cumulative[key] += delta
        previous_cpu, previous_net = current_cpu, current_net
        samples += 1
        if args.ping_ip:
            v = one_ping(args.ping_ip)
            if v is not None:
                rtt.append(v)
    print(f"Samples: {samples}")
    if cpu_pct:
        print(f"Gateway CPU: avg {statistics.mean(cpu_pct):.1f}% / max {max(cpu_pct):.1f}%")
    print(f"Traffic on {args.interface}: RX {cumulative['rx_bytes']/1e6:.1f} MB, TX {cumulative['tx_bytes']/1e6:.1f} MB")
    print(f"Interface errors/drops: RX {cumulative['rx_errs']}/{cumulative['rx_drops']}; TX {cumulative['tx_errs']}/{cumulative['tx_drops']}")
    if args.ping_ip:
        if rtt:
            print(f"WireGuard peer ICMP RTT: median {statistics.median(rtt):.2f} ms; p95 {percentile(rtt, .95):.2f} ms; max {max(rtt):.2f} ms; replies {len(rtt)}/{samples}")
        else:
            print("ICMP RTT unavailable; ping may be blocked or missing")
    print("60 FPS, frame pacing, A/V sync and controller lag MUST be verified in Moonlight client statistics.")

if __name__ == "__main__":
    main()
