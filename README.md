# Homelab IaC (Proxmox + Terraform + Ansible)

This repository provisions and configures a Proxmox homelab stack for:

- Core infrastructure nodes (LXC): VPN gateway, Cloudflare tunnel, Playit client, NGINX proxy
- Workload VMs: microservice host and game server
- Services: Minecraft (NeoForge), Portainer, Discord bot, backup/restore automation

## Layout

- `terraform/`: infrastructure provisioning and Proxmox firewall rules
- `ansible/`: post-provision configuration and service deployment

## Terraform Flow

Run from `terraform/`:

```bash
terraform init
terraform validate
terraform plan
terraform apply
```

Configuration is split by responsibility:

- `provider.tf`: Terraform + Proxmox provider config
- `downloads.tf`: cloud images, templates, cloud-init snippets
- `compute.tf`: LXC and VM definitions
- `firewall.tf`: security groups, firewall rules, firewall options
- `variables.tf`: input variables

Provider TLS verification is enabled by default. Use `pve_tls_insecure = true` only as a temporary bootstrap fallback.

## Ansible Flow

Run from `ansible/` with `inventory.yml`:

```bash
ansible-playbook -i inventory.yml install_docker.yml
ansible-playbook -i inventory.yml minecraft-deploy.yml
```

`ansible/ansible.cfg` enforces SSH host key checking for playbook runs.

Common playbooks:

- `install_docker.yml`: installs Docker engine and dependencies on workload hosts
- `minecraft-deploy.yml`: deploys Minecraft server, NeoForge install, restic backup scripts, cron jobs
- `deploy_tailscale.yml`: configures VPN gateway as Tailscale subnet router
- `deploy_cloudflare_tunnel.yml`: installs cloudflared, provisions/updates tunnel via API, and manages optional hostname DNS
- `install_playit.yml` + `start_playit.yml`: installs and starts Playit agent
- `deploy_portainer.yml`: deploys Portainer UI on microservice host
- `deploy_portainer_agent.yml`: deploys Portainer agent on game server
- `deploy_discord_bot.yml`: ships and runs Discord bot container on microservice host

## Validation

Run from each directory:

```bash
# Terraform
terraform validate

# Ansible syntax checks
ansible-playbook -i inventory.yml install_docker.yml --syntax-check
ansible-playbook -i inventory.yml minecraft-deploy.yml --syntax-check
ansible-playbook -i inventory.yml deploy_tailscale.yml --syntax-check
ansible-playbook -i inventory.yml deploy_cloudflare_tunnel.yml --syntax-check
ansible-playbook -i inventory.yml install_playit.yml --syntax-check
ansible-playbook -i inventory.yml start_playit.yml --syntax-check
ansible-playbook -i inventory.yml deploy_portainer.yml --syntax-check
ansible-playbook -i inventory.yml deploy_portainer_agent.yml --syntax-check
ansible-playbook -i inventory.yml deploy_discord_bot.yml --syntax-check
```

## Secrets

Secrets are intentionally user-managed and should not be committed.
Terraform secrets should stay in ignored files such as `terraform.tfvars`.

For Ansible secrets, use `ansible/vault.yml` encrypted with Ansible Vault:

```bash
cp ansible/vault.example.yml ansible/vault.yml
ansible-vault encrypt ansible/vault.yml
ansible-playbook -i ansible/inventory.yml ansible/minecraft-deploy.yml --ask-vault-pass
```

Playbooks that need secrets now load `vault.yml` first, then fall back to legacy `env.yml` for compatibility.

## Network posture

- Minecraft ingress is scoped for Playit forwarding (`playit-client -> game-server:25565`) instead of globally exposing `25565`.
- Management access remains workstation-scoped for SSH/ICMP via Proxmox firewall groups.
