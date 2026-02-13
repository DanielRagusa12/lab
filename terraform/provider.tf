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
  endpoint = var.pve_endpoint
  insecure = var.pve_tls_insecure
  username = var.pve_username
  password = var.pve_password

  ssh {
    agent    = true
    username = "root"
  }
}
