variable "hcloud_token" {
  description = "Hetzner Cloud API token. Set via TF_VAR_hcloud_token or terraform.tfvars."
  type        = string
  sensitive   = true
}

variable "company_name" {
  description = "Slug-safe company identifier used in resource naming (e.g. acmecorp)."
  type        = string
}

variable "domain" {
  description = "Primary domain (e.g. acmecorp.com). Used for DNS references in docs."
  type        = string
}

variable "admin_email" {
  description = "Admin email for Caddy ACME registration and system alerts."
  type        = string
}

variable "ssh_key_name" {
  description = "Name of the SSH public key already uploaded to Hetzner Cloud."
  type        = string
}

variable "server_name" {
  description = "Hetzner server resource name."
  type        = string
  default     = "mailcow-server"
}

variable "server_type" {
  description = "Hetzner server type. cx22 = 2 vCPU / 4 GB RAM."
  type        = string
  default     = "cx22"
}

variable "server_location" {
  description = "Hetzner datacenter location. fsn1 = Falkenstein (EU), ash = Ashburn (US)."
  type        = string
  default     = "fsn1"

  validation {
    condition     = contains(["fsn1", "nbg1", "hel1", "ash", "hil", "sin"], var.server_location)
    error_message = "Must be a valid Hetzner location: fsn1, nbg1, hel1, ash, hil, sin."
  }
}

variable "server_image" {
  description = "Base OS image."
  type        = string
  default     = "ubuntu-24.04"
}

variable "volume_size_gb" {
  description = "Size in GB for the block storage volume holding all mailcow/Docker data."
  type        = number
  default     = 50
}

variable "timezone" {
  description = "Server and mailcow timezone (IANA format, e.g. Europe/Berlin)."
  type        = string
  default     = "UTC"
}

variable "skip_clamd" {
  description = "Disable ClamAV antivirus to stay within 4 GB RAM budget."
  type        = bool
  default     = true
}

variable "allowed_ssh_cidrs" {
  description = "CIDR ranges permitted inbound on SSH port 22. Restrict in production."
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"]
}

# ---------------------------------------------------------------------------
# Backblaze B2 (optional offsite backup storage)
# ---------------------------------------------------------------------------
variable "b2_enabled" {
  description = "Create a Backblaze B2 bucket for offsite backups. Requires b2_key_id and b2_application_key."
  type        = bool
  default     = false
}

variable "b2_key_id" {
  description = "Backblaze B2 application key ID. Set via TF_VAR_b2_key_id or .env."
  type        = string
  sensitive   = true
  default     = ""
}

variable "b2_application_key" {
  description = "Backblaze B2 application key. Set via TF_VAR_b2_application_key or .env."
  type        = string
  sensitive   = true
  default     = ""
}

variable "b2_bucket_name" {
  description = "B2 bucket name. Defaults to mailcow-backup-{company_name} if empty. Must be globally unique across all B2 accounts."
  type        = string
  default     = ""
}
