# =============================================================================
#  FIREWALL ATTACHMENTS & OPTIONS
# =============================================================================

resource "proxmox_virtual_environment_cluster_firewall_security_group" "web_traffic" {
  name    = "web-traffic"
  comment = "Allow HTTP and HTTPS"
  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "80,443"
    comment = "Allow web traffic"
  }
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "management" {
  name    = "my_management"
  comment = "Allow SSH and ICMP ONLY from workstation"

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "22"
    source  = var.workstation_ipv4_address
    comment = "Workstation SSH Access"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "icmp"
    source  = var.workstation_ipv4_address
    comment = "Workstation Ping Access"
  }
}

# Rules applied to the physical Proxmox Node (Host)
resource "proxmox_virtual_environment_firewall_rules" "pve_host_fw" {
  node_name = "pve" # Your actual Proxmox node name

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "22" # Rsync uses SSH
    source  = split("/", var.game_vm_ipv4_address)[0]
    comment = "Allow Game Server Rsync Backups via SSH"
  }
}

# VPN Gateway (ID 100)
resource "proxmox_virtual_environment_firewall_rules" "vpn_fw" {
  node_name    = "pve"
  container_id = 100
  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.management.name
    enabled        = true
  }
}

# Cloudflare Tunnel (ID 101)
resource "proxmox_virtual_environment_firewall_rules" "cloudflare_fw" {
  node_name    = "pve"
  container_id = 101
  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.management.name
    enabled        = true
  }
}

# Playit Client (ID 102)
resource "proxmox_virtual_environment_firewall_rules" "playit_fw" {
  node_name    = "pve"
  container_id = 102
  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.management.name
    enabled        = true
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "25565"
    source  = split("/", var.game_vm_ipv4_address)[0]
    comment = "Allow Minecraft bridge traffic from Game Server"
  }
}

# NGINX Proxy (ID 103)
resource "proxmox_virtual_environment_firewall_rules" "nginx_fw" {
  node_name    = "pve"
  container_id = 103
  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.management.name
    enabled        = true
  }
  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.web_traffic.name
    enabled        = true
  }
}

# Microservice Host (ID 200)
resource "proxmox_virtual_environment_firewall_rules" "ms_host_fw" {
  node_name = "pve"
  vm_id     = 200
  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.management.name
    enabled        = true
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "5000"
    source  = split("/", var.tunnel_lxc_ipv4_address)[0]
    comment = "Allow Cloudflare Tunnel to dashboard endpoint"
  }
}

# Game Server (ID 201)
resource "proxmox_virtual_environment_firewall_rules" "game_server_fw" {
  node_name = "pve"
  vm_id     = 201
  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.management.name
    enabled        = true
  }
  # Allow RCON from Management/Microservice Host
  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "25575"
    source  = split("/", var.ms_vm_ipv4_address)[0]
    comment = "Allow RCON from Microservice Host"
  }

  # Allow RCON from Developer Workstation
  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "25575"
    source  = var.workstation_ipv4_address
    comment = "Allow RCON from Dev Workstation"
  }

  # Allow SSH from Microservice Host (For Remote Logs)
  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "22"
    source  = split("/", var.ms_vm_ipv4_address)[0]
    comment = "Allow Dashboard to fetch Logs via SSH"
  }

  # Allow Playit LXC to bridge traffic to Minecraft
  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "25565"
    source  = split("/", var.playit_lxc_ipv4_address)[0]
    comment = "Allow Playit Tunnel"
  }

  # Allow direct local workstation access to Minecraft
  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "25565"
    source  = var.workstation_ipv4_address
    comment = "Allow Minecraft from Dev Workstation"
  }

  # Allow direct local LAN access to Minecraft
  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "25565"
    source  = "192.168.1.0/24"
    comment = "Allow Minecraft from Local LAN"
  }

  # Allow Portainer (Microservice VM) to monitor Docker
  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "9001"
    source  = split("/", var.ms_vm_ipv4_address)[0]
    comment = "Allow Portainer Agent Monitoring"
  }
}

resource "proxmox_virtual_environment_firewall_options" "vpn_opts" {
  node_name    = "pve"
  container_id = 100
  enabled      = true
  ipfilter     = false # REQUIRED for Tailscale Subnet Routing
  input_policy = "DROP"
}

resource "proxmox_virtual_environment_firewall_options" "cf_opts" {
  node_name    = "pve"
  container_id = 101
  enabled      = true
  input_policy = "DROP"
}

resource "proxmox_virtual_environment_firewall_options" "playit_opts" {
  node_name    = "pve"
  container_id = 102
  enabled      = true
  input_policy = "DROP"
}

resource "proxmox_virtual_environment_firewall_options" "nginx_opts" {
  node_name    = "pve"
  container_id = 103
  enabled      = true
  input_policy = "DROP"
}

resource "proxmox_virtual_environment_firewall_options" "ms_opts" {
  node_name    = "pve"
  vm_id        = 200
  enabled      = true
  input_policy = "DROP"
}

resource "proxmox_virtual_environment_firewall_options" "game_opts" {
  node_name    = "pve"
  vm_id        = 201
  enabled      = true
  input_policy = "DROP"
}
