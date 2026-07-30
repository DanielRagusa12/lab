# Proxmox Homelab

Infrastructure-as-code and operations repo for a small Proxmox-based homelab. The goal of this project is to treat a home environment like production infrastructure: reproducible provisioning, segmented services, explicit firewall policy, remote access controls, monitoring, backups, and recovery automation.

This repository is public as a portfolio project, so secrets, tokens, credentials, payment/session data, and local-only environment files are intentionally excluded.

## What This Lab Demonstrates

- Proxmox VE infrastructure managed with Terraform using the `bpg/proxmox` provider.
- Configuration management and application deployment with Ansible.
- A split architecture of lightweight infrastructure containers and heavier workload VMs.
- Default-deny Proxmox firewall rules with narrowly scoped service access.
- Private remote administration through Tailscale subnet routing.
- Public application ingress through Cloudflare Tunnel and Cloudflare Zero Trust Access.
- Monitoring with Prometheus, Grafana, Alertmanager, node exporter, and cAdvisor.
- Container management with Docker, Docker Compose, and Portainer.
- Game server automation with Docker Compose, RCON, Restic backups, restore tooling, and scheduled maintenance.

## Architecture Overview

The lab runs on a single Proxmox node with Terraform-managed guests. Infrastructure services are separated from workload services so networking, ingress, monitoring, and application hosts can be managed independently.

| Layer | Role | Implementation |
| --- | --- | --- |
| Hypervisor | Virtualization platform | Proxmox VE |
| Provisioning | Guest lifecycle, images, cloud-init, firewall | Terraform |
| Configuration | Host setup and application deployment | Ansible |
| Remote access | Private admin path into the LAN | Tailscale subnet router LXC |
| Public ingress | Authenticated web access without inbound port forwarding | Cloudflare Tunnel and Zero Trust |
| Workloads | Application and game server hosts | Ubuntu and Debian VMs |
| Observability | Metrics, dashboards, and alerting | Prometheus, Grafana, Alertmanager |
| Backups | Game data snapshots and restore flow | Restic over SSH/SFTP |

## Provisioned Systems

Terraform currently defines these Proxmox guests:

| Guest | Type | Purpose |
| --- | --- | --- |
| `vpn-gateway` | Ubuntu LXC | Tailscale subnet router for private administration |
| `cloudflared` | Ubuntu LXC | Cloudflare Tunnel connector for externally reachable apps |
| `playit-client` | Ubuntu LXC | Playit.gg tunnel client for game traffic |
| `monitor-server` | Ubuntu LXC | Dedicated monitoring host |
| `microservice-host` | Ubuntu VM | Docker workload host for dashboards, bots, automation, and service experiments |
| `game-server` | Debian VM | Docker workload host for the Minecraft server and related agents |

Images and templates are downloaded by Terraform from upstream Ubuntu and Debian cloud image sources, then initialized with cloud-init snippets.

## Networking And Firewalling

The Proxmox firewall is managed in Terraform and enabled per guest. Guest ingress defaults to `DROP`; explicit rules allow only the traffic needed for each service.

Current policy highlights:

- SSH and ICMP are limited to the management workstation and the private VPN gateway.
- Monitoring ports are limited to the monitoring host or trusted admin paths.
- cAdvisor and node exporter are reachable only from the monitoring server.
- The microservice dashboard endpoint is reachable only through the Cloudflare Tunnel container.
- Game server ports are limited by source, separating local LAN access, tunnel traffic, RCON, and management access.
- Portainer agent access is scoped to the microservice host.

This gives the lab a practical zero-trust style posture: no broad administrative exposure, public access routed through identity-aware controls, and service-to-service flows documented as code.

## Cloudflare Zero Trust

The Terraform Cloudflare module can create and manage:

- A shared remotely managed Cloudflare Tunnel.
- Tunnel ingress config from a map of applications.
- DNS records pointing app hostnames at the tunnel.
- Cloudflare Access applications and allow policies.
- Google identity provider enforcement for protected apps.

Zero Trust management is feature-flagged with `enable_cloudflare_zero_trust` so the Proxmox lab can be managed independently from Cloudflare when needed.

## Ansible Automation

The `ansible/` directory contains playbooks for post-provisioning setup and service deployment:

- `install_docker.yml` installs Docker Engine and Compose support on workload VMs.
- `deploy_tailscale.yml` configures the Tailscale subnet router, IP forwarding, and UFW hardening.
- `deploy_cloudflare_tunnel.yml` installs and runs `cloudflared` as a system service.
- `deploy_portainer.yml` deploys Portainer CE on the microservice host.
- `deploy_portainer_agent.yml` deploys the Portainer agent on the game server.
- `install_node_exporter.yml` installs node exporter and verifies local metrics endpoints.
- `install_cadvisor.yml` runs cAdvisor containers for Docker visibility.
- `deploy_discord_bot.yml` builds and deploys a Discord music bot container.
- `deploy_proxmox_network_watchdog.yml` installs a systemd watchdog for sustained host network failures.
- `mc/minecraft-deploy.yml` deploys and maintains the Minecraft server stack.

Secrets are loaded through Ansible variable files but are not committed to the public repository.

## Monitoring Stack

The monitoring stack is maintained in its own repository and included here as part of the lab deployment context. It provides:

- Prometheus scrape configuration for node exporter and cAdvisor targets.
- Alertmanager configuration.
- Grafana provisioning for datasources, dashboards, plugins, and alerting.
- Dashboards for host and container visibility.

The stack is designed to observe both infrastructure containers and workload VMs while keeping monitoring surfaces scoped behind firewall policy and admin access paths.

## Workloads

### Microservice Host

The microservice VM is the general-purpose Docker application host. Current and in-progress workloads include:

- Portainer CE for Docker management.
- A Discord music bot deployment pipeline.
- Automation and browser-backed service experiments.
- Application endpoints exposed through Cloudflare Tunnel where appropriate.

### Game Server

The game server VM runs a containerized Minecraft server stack. The deployment includes:

- Docker Compose-based Minecraft service management.
- NeoForge server installation.
- RCON configuration for administrative automation.
- Playit.gg tunnel integration for game traffic.
- Restic backups to Proxmox-hosted storage.
- Hourly automated backups, daily retention maintenance, manual checkpoints, and interactive restore scripts.
- Portainer agent support for remote container management.

## Operations

The lab includes a Proxmox network watchdog deployed through Ansible. It checks gateway and external reachability on a timer and can reboot the host after sustained network failure, reducing manual recovery needs for known network lockup scenarios.

## Repository Layout

```text
.
|-- ansible/          # Configuration management and service deployment playbooks
|-- monitor-stack/    # Monitoring stack maintained in a separate repository
`-- terraform/        # Proxmox, firewall, image, cloud-init, and Cloudflare IaC
```

## Current Status

Implemented so far:

- Terraform-managed Proxmox containers and VMs.
- Cloud-init based VM initialization.
- Proxmox firewall attachments, security groups, and default-deny guest policy.
- Tailscale subnet router for private access.
- Cloudflare Tunnel connector and optional Zero Trust application management.
- Docker installation and application deployment playbooks.
- Portainer and Portainer Agent deployment.
- Prometheus/Grafana monitoring assets and exporter installation playbooks.
- Minecraft server deployment with automated backup and restore workflows.
- Host network watchdog automation.

Planned or ongoing work:

- Continue expanding dashboards and alert coverage.
- Tighten backup verification and restore testing.
- Refine public/private service boundaries as new workloads are added.
- Keep application experiments isolated from core infrastructure.

## Notes For Reviewers

This is a real working lab, not a static demo. Some inventory values and local paths reflect the physical environment, but the important patterns are portable: declarative infrastructure, least-privilege firewalling, automated configuration, observable services, and documented operational recovery.
