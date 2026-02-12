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
    name     = "veth0"
    bridge   = "vmbr0"
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
    name     = "veth0"
    bridge   = "vmbr0"
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
