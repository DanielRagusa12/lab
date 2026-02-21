# =============================================================================
# PVE
# =============================================================================


variable "pve_ssh_key" {
  description = "Path to the private SSH key"
  type        = string
  default     = "~/.ssh/proxmox"
}

variable "pve_username" {
  description = "The Proxmox user (must be root@pam for device passthrough)"
  type        = string
  default     = "root@pam"
}

variable "pve_password" {
  description = "The password for the Proxmox user"
  type        = string
  sensitive   = true
}

variable "pve_endpoint" {
  description = "The URL for the Proxmox API"
  type        = string
}

variable "pve_tls_insecure" {
  description = "Allow insecure TLS to Proxmox API (set true only for temporary/self-signed lab bootstrap)"
  type        = bool
  default     = false
}

# =============================================================================
# NODES
# =============================================================================


variable "ipv4_gateway" {
  description = "The default gateway for the network"
  type        = string
}

variable "ms_vm_ipv4_address" {
  description = "The static IP address for the microservice VM in CIDR notation"
  type        = string
}

variable "game_vm_ipv4_address" {
  description = "IP address for the Game Server VM (CIDR)"
  type        = string
}

variable "vpn_lxc_ipv4_address" {
  description = "IP address for the Tailscale LXC (CIDR)"
  type        = string
}


variable "vpn_lxc_password" {
  description = "Root password for the tailscale LXC container"
  type        = string
  sensitive   = true
}

variable "tunnel_lxc_ipv4_address" {
  description = "IP address for the Cloudflare Tunnel LXC (CIDR)"
  type        = string
}

variable "tunnel_lxc_password" {
  description = "Root password for the tailscale LXC container"
  type        = string
  sensitive   = true
}

variable "playit_lxc_ipv4_address" {
  description = "IP address for the Playit.gg LXC (CIDR)"
  type        = string
}

variable "playit_lxc_password" {
  description = "Root password for the Playit LXC container"
  type        = string
  sensitive   = true
}

variable "nginx_lxc_ipv4_address" {
  description = "IP address for the NGINX Reverse Proxy LXC (CIDR)"
  type        = string
}

variable "nginx_lxc_password" {
  description = "Root password for the NGINX LXC container"
  type        = string
  sensitive   = true
}

# =============================================================================
# NODES
# =============================================================================
variable "workstation_ipv4_address" {
  description = "local IP of management workstation (CIDR format)"
  type        = string
}

# =============================================================================
# CLOUDFLARE ZERO TRUST
# =============================================================================

variable "enable_cloudflare_zero_trust" {
  description = "Manage Cloudflare Tunnel, DNS, and Access resources from Terraform"
  type        = bool
  default     = false
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID for Zero Trust resources"
  type        = string
  default     = ""

  validation {
    condition = (
      !var.enable_cloudflare_zero_trust ||
      length(trimspace(var.cloudflare_account_id)) > 0
    )
    error_message = "Set cloudflare_account_id when enable_cloudflare_zero_trust is true."
  }
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token used by Terraform provider"
  type        = string
  default     = ""
  sensitive   = true

  validation {
    condition = (
      !var.enable_cloudflare_zero_trust ||
      length(trimspace(var.cloudflare_api_token)) > 0
    )
    error_message = "Set cloudflare_api_token when enable_cloudflare_zero_trust is true."
  }
}

variable "cloudflare_zone_id" {
  description = "Cloudflare DNS zone ID for app hostnames"
  type        = string
  default     = ""

  validation {
    condition = (
      !var.enable_cloudflare_zero_trust ||
      length(trimspace(var.cloudflare_zone_id)) > 0
    )
    error_message = "Set cloudflare_zone_id when enable_cloudflare_zero_trust is true."
  }
}

variable "cloudflare_domain" {
  description = "Base DNS domain used for Cloudflare Tunnel app hostnames"
  type        = string
  default     = ""

  validation {
    condition = (
      !var.enable_cloudflare_zero_trust ||
      length(trimspace(var.cloudflare_domain)) > 0
    )
    error_message = "Set cloudflare_domain when enable_cloudflare_zero_trust is true."
  }
}

variable "cloudflare_tunnel_name" {
  description = "Name for the shared remotely-managed Cloudflare tunnel"
  type        = string
  default     = "homelab-shared-tunnel"
}

variable "cloudflare_google_identity_provider_id" {
  description = "Access identity provider ID for Google login method"
  type        = string
  default     = ""

  validation {
    condition = (
      !var.enable_cloudflare_zero_trust ||
      length(trimspace(var.cloudflare_google_identity_provider_id)) > 0
    )
    error_message = "Set cloudflare_google_identity_provider_id when enable_cloudflare_zero_trust is true."
  }
}

variable "cloudflare_access_default_session_duration" {
  description = "Default Access session duration for self-hosted apps"
  type        = string
  default     = "24h"
}

variable "cloudflare_tunnel_apps" {
  description = "Map of Cloudflare Tunnel applications keyed by app name"
  type = map(object({
    subdomain             = string
    service               = string
    access_enabled        = optional(bool, true)
    session_duration      = optional(string)
    app_launcher_visible  = optional(bool, false)
    allowed_emails        = optional(list(string), [])
    allowed_email_domains = optional(list(string), [])
  }))
  default = {}

  validation {
    condition = (
      !var.enable_cloudflare_zero_trust ||
      length(var.cloudflare_tunnel_apps) > 0
    )
    error_message = "Define at least one cloudflare_tunnel_apps entry when enable_cloudflare_zero_trust is true."
  }

  validation {
    condition = alltrue([
      for _, app in var.cloudflare_tunnel_apps : (
        length(trimspace(app.subdomain)) > 0 &&
        length(trimspace(app.service)) > 0
      )
    ])
    error_message = "Each cloudflare_tunnel_apps item must define non-empty subdomain and service values."
  }

  validation {
    condition = (
      length(distinct([
        for _, app in var.cloudflare_tunnel_apps : lower(trimspace(app.subdomain))
      ])) == length(var.cloudflare_tunnel_apps)
    )
    error_message = "Each cloudflare_tunnel_apps entry must use a unique subdomain."
  }

  validation {
    condition = alltrue([
      for _, app in var.cloudflare_tunnel_apps : (
        !app.access_enabled ||
        length(app.allowed_emails) > 0 ||
        length(app.allowed_email_domains) > 0
      )
    ])
    error_message = "For access_enabled apps, set at least one allowed_emails or allowed_email_domains entry."
  }
}
