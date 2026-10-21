# Update existing LXC and VM guests

`update_guests.yml` updates Debian and Ubuntu OS packages over SSH using the existing inventory. It targets `infrastructure` and `workloads`, excluding `proxmox` and `macos`. An additional `/etc/pve` check refuses hypervisor updates even through another inventory alias.

The current targets are `vpn_gateway`, `cloudflare_tunnel`, `playit_client`, `monitor_server`, `microservice_host`, and `game_server`. This is inventory-based, not Proxmox API discovery. Add any other guests to the inventory before running it.

## Preview

Run from `ansible/`:

```bash
ansible-playbook -i inventory.yml update_guests.yml --list-hosts
ansible-playbook -i inventory.yml update_guests.yml
```

The default run refreshes APT metadata and prints `apt-get --simulate --no-remove dist-upgrade` output. It does not install or upgrade packages. It needs SSH access and root or sudo permissions. Add `--ask-become-pass` if sudo requires a password.

Before applying, review the proposed packages, versions, configured repositories, and relevant upstream advisories. APT upgrades execute package maintainer scripts as root and may restart services. The preview is not approval of those scripts or their download sources. Repositories can change between preview and apply.

## Apply

Take or verify backups first. Use a maintenance window, especially for the VPN gateway, tunnel clients, and Docker hosts. Run from the LAN or another management path that does not depend on the services being updated.

```bash
# Start with one guest.
ansible-playbook -i inventory.yml update_guests.yml \
  --limit microservice_host -e guest_update_apply=true

# Update every inventoried guest.
ansible-playbook -i inventory.yml update_guests.yml \
  -e guest_update_apply=true
```

The playbook processes one guest at a time and stops the rollout on failure. It performs a full APT upgrade within the configured release, allowing new dependencies but refusing package removals. It preserves Ansible's default handling of modified conffiles. It does not autoremove packages, change distribution releases, update Docker images, or reboot machines.

The final status reports `/var/run/reboot-required` when present. Its absence does not guarantee that a Debian guest needs no reboot or service restart. Schedule VM reboots separately. LXC guests share the hypervisor kernel, so guest updates cannot patch that kernel. Maintain and reboot Proxmox separately.

`--check` previews against available metadata without refreshing it. Neither preview mode verifies application health after updates, so check the affected services after applying.
