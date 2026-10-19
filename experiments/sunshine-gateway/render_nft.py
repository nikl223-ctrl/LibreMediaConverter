#!/usr/bin/env python3
"""Print safe-to-review nftables NAT rules for a remote Sunshine host.
This adds no CPU cores or RAM. No firewall changes are applied here.
"""
import argparse
import ipaddress
import re

TCP_PORTS = (47984, 47989, 48010)
UDP_PORTS = (47998, 47999, 48000, 48002, 48010)
IFACE_RE = re.compile(r"^[a-zA-Z0-9_.-]{1,15}$")

def interface_name(value):
    if not IFACE_RE.fullmatch(value) or value in (".", ".."):
        raise argparse.ArgumentTypeError("Invalid Linux interface name")
    return value

def ipv4_address(value):
    try:
        parsed = ipaddress.IPv4Address(value)
    except ipaddress.AddressValueError as exc:
        raise argparse.ArgumentTypeError(str(exc)) from exc
    if parsed.is_multicast or parsed.is_unspecified or parsed.is_loopback or parsed.is_link_local:
        raise argparse.ArgumentTypeError("Upstream must be a routed IPv4 unicast address")
    return str(parsed)

def ipv4_network(value):
    try:
        parsed = ipaddress.IPv4Network(value, strict=False)
    except (ipaddress.AddressValueError, ipaddress.NetmaskValueError) as exc:
        raise argparse.ArgumentTypeError(str(exc)) from exc
    return str(parsed)

def render_nft(ingress, egress, upstream, allowed_clients):
    if ingress == egress:
        raise ValueError("Ingress and WireGuard interfaces must differ")
    tcp = ', '.join(map(str, TCP_PORTS))
    udp = ', '.join(map(str, UDP_PORTS))
    return f'''# GENERATED PREVIEW. Requires WireGuard, IPv4 forwarding, and FORWARD firewall permissions.
# NAT only: no video decoding or encoding on the gateway.
# TCP 47990 Sunshine administration UI intentionally not forwarded.
table ip sunshine_gateway {{
  chain prerouting {{
    type nat hook prerouting priority dstnat; policy accept;
    iifname "{ingress}" ip saddr {allowed_clients} tcp dport {{ {tcp} }} dnat to {upstream}
    iifname "{ingress}" ip saddr {allowed_clients} udp dport {{ {udp} }} dnat to {upstream}
  }}
  chain postrouting {{
    type nat hook postrouting priority srcnat; policy accept;
    oifname "{egress}" ip daddr {upstream} tcp dport {{ {tcp} }} masquerade
    oifname "{egress}" ip daddr {upstream} udp dport {{ {udp} }} masquerade
  }}
}}
'''

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ingress", required=True, type=interface_name)
    parser.add_argument("--wireguard", required=True, type=interface_name)
    parser.add_argument("--upstream", required=True, type=ipv4_address)
    parser.add_argument("--allow-clients", required=True, type=ipv4_network)
    args = parser.parse_args()
    print(render_nft(args.ingress, args.wireguard, args.upstream, args.allow_clients), end="")

if __name__ == "__main__":
    main()
