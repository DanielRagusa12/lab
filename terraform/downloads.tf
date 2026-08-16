# =============================================================================
#  SHARED RESOURCES (Templates, Cloud-Init, Security Groups)
# =============================================================================

# --- OS Templates & Images ---
resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = "pve"
  overwrite    = false
  url          = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  file_name    = "ubuntu-24.04-cloud-image.img"
}

resource "proxmox_virtual_environment_download_file" "ubuntu_lxc_template" {
  content_type = "vztmpl"
  datastore_id = "local"
  node_name    = "pve"
  overwrite    = false
  url          = "http://download.proxmox.com/images/system/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
  file_name    = "ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
}

resource "proxmox_virtual_environment_download_file" "debian_cloud_image" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = "pve"
  overwrite    = false
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
      ssh_key  = trimspace(file(pathexpand("~/.ssh/proxmox.pub")))
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
      ssh_key  = trimspace(file(pathexpand("~/.ssh/proxmox.pub")))
    })
  }
}
