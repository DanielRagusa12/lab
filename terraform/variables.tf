variable "pve_api_token" {
  description = "The API token for Proxmox"
  type        = string
  sensitive   = true
}

variable "pve_ssh_key" {
  description = "Path to the private SSH key"
  type        = string
  default     = "~/.ssh/proxmox"
}

variable "pve_endpoint" {
  description = "The URL for the Proxmox API"
  type        = string
}

variable "vm_ipv4_address" {
  description = "The static IP address for the VM in CIDR notation"
  type        = string
}

variable "vm_ipv4_gateway" {
  description = "The default gateway for the VM"
  type        = string
}