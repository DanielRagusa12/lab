# =============================================================================
#  FIREWALL ATTACHMENTS & OPTIONS
# =============================================================================

resource "proxmox_virtual_environment_cluster_firewall_security_group" "management" {
  name    = "my_management"
  comment = "Allow SSH and ICMP from workstation and VPN gateway"

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

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "22"
    source  = split("/", var.vpn_lxc_ipv4_address)[0]
    comment = "VPN Gateway SSH Access"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "icmp"
    source  = split("/", var.vpn_lxc_ipv4_address)[0]
    comment = "VPN Gateway Ping Access"
  }
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "monitoring" {
  name    = "monitoring"
  comment = "Allow monitoring UIs from workstation and VPN gateway"

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "3000,9090,9093"
    source  = var.workstation_ipv4_address
    comment = "Workstation monitoring access"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "3000,9090,9093"
    source  = split("/", var.vpn_lxc_ipv4_address)[0]
    comment = "VPN Gateway monitoring access"
  }
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "node_exporter" {
  name    = "node-exporter"
  comment = "Allow Prometheus scrapes from monitor server"

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "9100"
    source  = split("/", var.monitor_lxc_ipv4_address)[0]
    comment = "Allow node exporter scrape from monitor server"
  }
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "cadvisor" {
  name    = "cadvisor"
  comment = "Allow cAdvisor scrapes from monitor server"

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "8080"
    source  = split("/", var.monitor_lxc_ipv4_address)[0]
    comment = "Allow cAdvisor scrape from monitor server"
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
  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.node_exporter.name
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
  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.node_exporter.name
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

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.node_exporter.name
    enabled        = true
  }

}

# Monitor Server (ID 103)
resource "proxmox_virtual_environment_firewall_rules" "monitor_fw" {
  node_name    = "pve"
  container_id = 103
  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.management.name
    enabled        = true
  }
  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.monitoring.name
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
    dport   = "6969"
    source  = split("/", var.tunnel_lxc_ipv4_address)[0]
    comment = "Allow Cloudflare Tunnel lxc to dashboard endpoint on ms host"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "5902,5903"
    source  = var.workstation_ipv4_address
    comment = "Allow VNC from Dev Workstation"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "6969"
    source  = var.workstation_ipv4_address
    comment = "Allow web application from Dev Workstation"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "6969"
    source  = split("/", var.vpn_lxc_ipv4_address)[0]
    comment = "Allow web application from Tailscale LXC"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.node_exporter.name
    enabled        = true
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.cadvisor.name
    enabled        = true
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

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.node_exporter.name
    enabled        = true
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.cadvisor.name
    enabled        = true
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

resource "proxmox_virtual_environment_firewall_options" "monitor_opts" {
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
