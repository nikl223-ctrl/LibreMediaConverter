# Sunshine / Moonlight remote compute gateway — experiment

This is a **real network forwarding configuration**, not a way to append external RAM or vCPUs to an existing virtual machine.

## What this solves

Keep the existing small Linux server's public/VPN entry point for Moonlight, while a **separately authorized compute server** runs the cloud-gaming browser and Sunshine (capture and encoding). Linux kernel NAT on the small server relays Sunshine's TCP/UDP traffic through WireGuard. There is **no video decode/encode on the small server**, reducing its CPU load.

**Important:** This DOES NOT keep the game/browser process running on the small server; it must run on the remote compute server. A local Sunshine process is not magically accelerated. After changing the host, Moonlight typically must be paired to the remote Sunshine instance. This is NOT a tested live Moonlight session.

## Before using

Prerequisites: Ubuntu Linux gateway, existing working authenticated WireGuard tunnel, a remote compute host with Sunshine + browser + functional encoder, and a client network address range you control. Run only after verifying routes and having console access. No secrets or passwords belong in GitHub.

Generate a **preview only** (does not alter firewall or server):

```bash
cd experiments/sunshine-gateway
python3 -m unittest -v test_render_nft.py
python3 render_nft.py --ingress eth0 --wireguard wg0 --upstream 10.77.0.2 --allow-clients 10.66.0.0/24 > sunshine-gateway.nft
```

Addresses and interface names above are EXAMPLES. The allowed-client CIDR is required to avoid accidentally forwarding traffic from unknown hosts.

Optional pre-apply validation: `sudo nft -c -f sunshine-gateway.nft`. Inspect existing firewall rules with `sudo nft list ruleset` and have rollback/console access. You must deliberately enable `net.ipv4.ip_forward=1` and ensure existing FORWARD firewall chains allow traffic between ingress and WireGuard peer. Do not disable a firewall globally.

If you knowingly choose to apply the generated dedicated NAT table: `sudo nft -f sunshine-gateway.nft`. Rollback: `sudo nft delete table ip sunshine_gateway`. Neither apply nor rollback is performed by the generator, tests or GitHub Actions.

Ports: TCP 47984, 47989, 48010; UDP 47998, 47999, 48000, 48002, 48010. Sunshine admin Web UI TCP 47990 is intentionally **not** forwarded. Ports can differ if Sunshine was customized.

## Why the 20 GitHub workers cannot add CPU/RAM to this host

Linux schedules native Sunshine and Chromium processes on the vCPUs allocated to the VM by its hypervisor. Remote CPUs cannot be merged into the VM's local CPU topology by exchanging TCP packets. Distributed compute works for software that is explicitly designed to delegate work. Remote swap does not behave like low-latency real RAM. Video-encoding offload could be researched by changing Sunshine's capture/encoding code but would require an actual tested, low-latency streaming protocol and cannot be assumed to improve frames.

GitHub-hosted Actions may test this project's software, but are not a permitted general-purpose cloud-gaming host or compute capacity supplier.
