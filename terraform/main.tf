# =============================================================================
#  TERRAFORM & PROVIDER CONFIGURATION
# =============================================================================
terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.94.0" 
    }
  }
}

provider "proxmox" {
  endpoint  = var.pve_endpoint
  insecure  = true
  username  = var.pve_username
  password  = var.pve_password

  ssh {
    agent    = true
    username = "root"
  }
}

# =============================================================================
#  SHARED RESOURCES (Templates, Cloud-Init, Security Groups)
# =============================================================================

# --- OS Templates & Images ---
resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = "pve"
  url          = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  file_name    = "ubuntu-24.04-cloud-image.img"
}

resource "proxmox_virtual_environment_download_file" "ubuntu_lxc_template" {
  content_type = "vztmpl"
  datastore_id = "local"
  node_name    = "pve"
  url          = "http://download.proxmox.com/images/system/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
  file_name    = "ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
}

resource "proxmox_virtual_environment_download_file" "debian_cloud_image" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = "pve"
  url          = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
  file_name    = "debian-12-generic-amd64.img"
}

# --- Cloud-Init Configurations ---
resource "proxmox_virtual_environment_file" "microservice_user_data_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"
  source_raw {
    file_name = "user-init-data.yaml"
    data = templatefile("${path.module}/host-init-ms.tftpl", {
      hostname = "microservice-host"
      username = "ubuntu"
      ssh_key  = trimspace(file("~/.ssh/proxmox.pub"))
    })
  }
}

resource "proxmox_virtual_environment_file" "gameserver_user_data_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"
  source_raw {
    file_name = "user-data-game-server.yaml"
    data = templatefile("${path.module}/host-init-mc.tftpl", {
      hostname = "game-server"
      username = "debian"
      ssh_key  = trimspace(file("~/.ssh/proxmox.pub"))
    })
  }
}



# =============================================================================
#  COMPUTE RESOURCES (Containers & VMs)
# =============================================================================

# --- Networking & VPN ---
resource "proxmox_virtual_environment_container" "vpn_gateway" {
  node_name    = "pve"
  vm_id        = 100
  unprivileged = true
  initialization {
    hostname = "vpn-gateway"
    user_account {
      password = var.vpn_lxc_password
      keys     = [trimspace(file("~/.ssh/proxmox.pub"))]
    }
    ip_config {
      ipv4 {
        address = var.vpn_lxc_ipv4_address
        gateway = var.ipv4_gateway
      }
    }
  }
  network_interface {
    name   = "veth0"
    bridge = "vmbr0"
    firewall = true
  }
  operating_system {
    template_file_id = proxmox_virtual_environment_download_file.ubuntu_lxc_template.id
    type             = "ubuntu"
  }
  features {
    nesting = true
    keyctl  = true
  }
  device_passthrough { path = "/dev/net/tun" }
  memory { dedicated = 512 }
  disk {
    datastore_id = "local-zfs"
    size         = 8
  }
}

resource "proxmox_virtual_environment_container" "cloudflare_tunnel" {
  node_name    = "pve"
  vm_id        = 101
  unprivileged = true
  initialization {
    hostname = "cloudflared"
    user_account {
      password = var.tunnel_lxc_password
      keys     = [trimspace(file("~/.ssh/proxmox.pub"))]
    }
    ip_config {
      ipv4 {
        address = var.tunnel_lxc_ipv4_address
        gateway = var.ipv4_gateway
      }
    }
  }
  network_interface {
    name   = "veth0"
    bridge = "vmbr0"
    firewall = true
  }
  operating_system {
    template_file_id = proxmox_virtual_environment_download_file.ubuntu_lxc_template.id
    type             = "ubuntu"
  }
  features { nesting = true }
  memory { dedicated = 512 }
  disk {
    datastore_id = "local-zfs"
    size         = 8
  }
}

resource "proxmox_virtual_environment_container" "playit_client" {
  node_name    = "pve"
  vm_id        = 102
  unprivileged = true
  initialization {
    hostname = "playit-client"
    user_account {
      password = var.playit_lxc_password
      keys     = [trimspace(file("~/.ssh/proxmox.pub"))]
    }
    ip_config {
      ipv4 {
        address = var.playit_lxc_ipv4_address
        gateway = var.ipv4_gateway
      }
    }
  }
  network_interface {
    name   = "veth0"
    bridge = "vmbr0"
    firewall = true
  }
  device_passthrough { path = "/dev/net/tun" }
  operating_system {
    template_file_id = proxmox_virtual_environment_download_file.ubuntu_lxc_template.id
    type             = "ubuntu"
  }
  features { nesting = true }
  memory { dedicated = 512 }
  disk {
    datastore_id = "local-zfs"
    size         = 8
  }
}

# --- Frontend / Proxy ---
resource "proxmox_virtual_environment_container" "nginx_proxy" {
  node_name    = "pve"
  vm_id        = 103
  unprivileged = true
  initialization {
    hostname = "nginx-proxy"
    user_account {
      password = var.nginx_lxc_password
      keys     = [trimspace(file("~/.ssh/proxmox.pub"))]
    }
    ip_config {
      ipv4 {
        address = var.nginx_lxc_ipv4_address
        gateway = var.ipv4_gateway
      }
    }
  }
  network_interface {
    name     = "veth0"
    bridge   = "vmbr0"
    firewall = true 
  }
  operating_system {
    template_file_id = proxmox_virtual_environment_download_file.ubuntu_lxc_template.id
    type             = "ubuntu"
  }
  features { nesting = true }
  memory { dedicated = 512 }
  disk {
    datastore_id = "local-zfs"
    size         = 8
  }
}

# --- Workload VMs ---
resource "proxmox_virtual_environment_vm" "microservice_host" {
  name      = "microservice-host"
  node_name = "pve"
  vm_id     = 200
  agent { enabled = true }
  cpu {
    cores = 2
    type  = "host"
  }
  memory { dedicated = 4096 }
  initialization {
    user_data_file_id = proxmox_virtual_environment_file.microservice_user_data_config.id
    datastore_id      = "local-zfs"
    ip_config {
      ipv4 {
        address = var.ms_vm_ipv4_address
        gateway = var.ipv4_gateway
      }
    }
  }
  disk {
    datastore_id = "local-zfs"
    interface    = "scsi0"
    size         = 32
    file_format  = "raw"
    file_id      = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
  }
  network_device {
    bridge   = "vmbr0"
    firewall = true 
  }
  operating_system { type = "l26" }
}

resource "proxmox_virtual_environment_vm" "game_server" {
  name      = "game-server"
  node_name = "pve"
  vm_id     = 201
  cpu {
    cores = 4
    type  = "host"
  }
  scsi_hardware = "virtio-scsi-pci"
  memory { dedicated = 12288 }
  serial_device {}
  vga { type = "serial0" }
  agent {
    enabled = true
    timeout = "15m"
  }
  initialization {
    user_data_file_id = proxmox_virtual_environment_file.gameserver_user_data_config.id
    datastore_id      = "local-zfs"
    ip_config {
      ipv4 {
        address = var.game_vm_ipv4_address
        gateway = var.ipv4_gateway
      }
    }
  }
  disk {
    datastore_id = "local-zfs"
    interface    = "scsi0"
    size         = 64
    file_format  = "raw"
    file_id      = proxmox_virtual_environment_download_file.debian_cloud_image.id
  }
  
  network_device {
    bridge   = "vmbr0"
    firewall = true
  }
  operating_system { type = "l26" }
}

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

resource "proxmox_virtual_environment_cluster_firewall_security_group" "minecraft" {
  name    = "minecraft-traffic"
  comment = "Allow Minecraft default port"
  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "25565"
    comment = "Allow MC Java"
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
    # Source is your Minecraft VM IP
    source  = split("/", var.game_vm_ipv4_address)[0]
    comment = "Allow return traffic from Minecraft Server"
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
}

# Game Server (ID 201)
resource "proxmox_virtual_environment_firewall_rules" "game_server_fw" {
  node_name = "pve"
  vm_id     = 201
  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.management.name
    enabled        = true
  }
  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.minecraft.name
    enabled        = true
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