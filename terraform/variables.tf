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
