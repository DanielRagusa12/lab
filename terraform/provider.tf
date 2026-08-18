# =============================================================================
#  TERRAFORM & PROVIDER CONFIGURATION
# =============================================================================
terraform {
  cloud {
    organization = "daniel-home-lab"

    workspaces {
      name = "proxmox-home-lab"
    }
  }

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5"
    }

    proxmox = {
      source  = "bpg/proxmox"
      version = "0.97.1"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
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
