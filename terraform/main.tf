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
  api_token = var.pve_api_token
  insecure  = true
  ssh {
    agent    = true
    username = "root"
  }
}

resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = "pve"
  url          = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  file_name    = "ubuntu-24.04-cloud-image.img"
}

# Cloud-Init
resource "proxmox_virtual_environment_file" "user_data_cloud_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

  source_raw {
    data = <<EOF
#cloud-config
hostname: docker-main
manage_etc_hosts: true
users:
  - default
  - name: ubuntu
    groups: sudo
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    ssh_authorized_keys:
      - ${trimspace(file("~/.ssh/proxmox.pub"))}

package_update: true
packages:
  - qemu-guest-agent

runcmd:
  - systemctl enable --now qemu-guest-agent
EOF
    file_name = "user-data-docker-main.yaml"
  }
}

# Build the VM
resource "proxmox_virtual_environment_vm" "docker_host" {
  name      = "docker-main"
  node_name = "pve"
  vm_id     = 200
  agent { enabled = true }

  cpu {
    cores = 2
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 4096
  }

  initialization {
    user_data_file_id = proxmox_virtual_environment_file.user_data_cloud_config.id
    datastore_id      = "local-zfs"

    ip_config {
      ipv4 {
        # Swapped hardcoded IP and Gateway for variables
        address = var.vm_ipv4_address
        gateway = var.vm_ipv4_gateway
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