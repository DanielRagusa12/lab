terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">=0.60.0"
    }
  }
}

provider "proxmox" {
  endpoint  = var.pve_endpoint
  insecure  = true
  username = var.pve_username
  password = var.pve_password

  ssh {
    agent    = true
    username = "root"
  }
}

# =============================================================================
# TEMPLATES & IMAGES
# =============================================================================

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


# =============================================================================
# CLOUD INIT (UBUNTU NOBLE)
# =============================================================================
resource "proxmox_virtual_environment_file" "microservice_user_data_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

  source_raw {
    file_name = "user-init-data.yaml"
    
    data = templatefile("${path.module}/host-init.tftpl", {
      hostname = "microservice-host"
      username = "ubuntu"
      ssh_key  = trimspace(file("~/.ssh/proxmox.pub"))
    })
  }
}

# =============================================================================
# DOCKER MICROSERVICE VM (UBUNTU NOBLE)
# =============================================================================
resource "proxmox_virtual_environment_vm" "microservice_host" {
  name      = "microservice-host"
  node_name = "pve"
  vm_id     = 200
  agent { enabled = true }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 4096
  }

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
    bridge = "vmbr0"
  }
  
  operating_system {
    type = "l26"
  }
}


# =============================================================================
# TAILSCALE VPN GATEWAY (LXC)
# =============================================================================
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
  }

  operating_system {
    template_file_id = proxmox_virtual_environment_download_file.ubuntu_lxc_template.id
    type             = "ubuntu"
  }

  features {
    nesting = true
    keyctl = true
  }

  device_passthrough {
    path = "/dev/net/tun" # Required for VPN functionality
  }

  memory {
    dedicated = 512
  }

  disk {
    datastore_id = "local-zfs"
    size         = 8
  }
}


# =============================================================================
# CLOUDFLARE TUNNEL (LXC)
# =============================================================================


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
  }

  # USES THE SAME TEMPLATE AS VPN GATEWAY (Ubuntu 24.04)
  operating_system {
    template_file_id = proxmox_virtual_environment_download_file.ubuntu_lxc_template.id
    type             = "ubuntu"
  }

  features {
    nesting = true
  }

  memory {
    dedicated = 512 # Tunnels are lightweight
  }

  disk {
    datastore_id = "local-zfs"
    size         = 8
  }
}


# =============================================================================
# CLOUD INIT (DEBIAN)
# =============================================================================
resource "proxmox_virtual_environment_file" "gameserver_user_data_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

  source_raw {
    file_name = "user-data-game-server.yaml"
    
    
    data = templatefile("${path.module}/host-init.tftpl", {
      hostname = "game-server"
      username = "debian"
      ssh_key  = trimspace(file("~/.ssh/proxmox.pub"))
    })
  }
}


# =============================================================================
# GAME SERVER (DEBIAN)
# =============================================================================
resource "proxmox_virtual_environment_vm" "game_server" {
  name      = "game-server"
  node_name = "pve"
  vm_id     = 201

  
  cpu {
    cores = 4
    type  = "host" 
  }
  scsi_hardware = "virtio-scsi-pci" #

  memory { dedicated = 4096 }

  
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
    interface    = "scsi0" #
    size         = 64
    file_format  = "raw"
    file_id      = proxmox_virtual_environment_download_file.debian_cloud_image.id
  }

  network_device { bridge = "vmbr0" }
  operating_system { type = "l26" }
}