# Codex Cloud server access

When the user asks to work on `berlin-server` or `proxy-server` from the
`Linux-Server-SSH` cloud environment:

1. Before the first network-dependent shell command in each new Cloud turn,
   request network access with `request_permissions` using
   `{"permissions":{"network":{"enabled":true}}}`. The Cloud shell sandbox
   otherwise rejects its internal proxy and SSH stalls during the banner
   exchange, even when the environment's Internet access is enabled.
2. Connect with the prepared aliases using the explicit configuration:
   `ssh -F "$HOME/.ssh/config" -o BatchMode=yes berlin-server` or
   `ssh -F "$HOME/.ssh/config" -o BatchMode=yes proxy-server`.
3. Before changing a server, verify `hostname` and `id`. Never print SSH
   private keys or the values of `SSH_KEY_BERLIN` and `SSH_KEY_PROXY`.
   Preserve running services unless the user's request calls for a change.

If network permission is unavailable or denied, report that specific blocker
instead of changing server firewall or SSH settings.
