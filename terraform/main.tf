terraform {
  required_version = ">= 1.5.0"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.48"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

# ---------------------------------------------------------------------------
# SSH key (must be pre-uploaded to Hetzner Cloud)
# ---------------------------------------------------------------------------
data "hcloud_ssh_key" "deployer" {
  name = var.ssh_key_name
}

# ---------------------------------------------------------------------------
# Block storage volume — all mailcow/Docker data lives here
# ---------------------------------------------------------------------------
resource "hcloud_volume" "mailcow_data" {
  name      = "${var.company_name}-mailcow-data"
  size      = var.volume_size_gb
  location  = var.server_location
  format    = "ext4"

  labels = {
    managed-by = "terraform"
    company    = var.company_name
    role       = "mailcow-data"
  }
}

# ---------------------------------------------------------------------------
# Server
# ---------------------------------------------------------------------------
resource "hcloud_server" "mailcow" {
  name        = "${var.company_name}-${var.server_name}"
  server_type = var.server_type
  image       = var.server_image
  location    = var.server_location
  ssh_keys    = [data.hcloud_ssh_key.deployer.id]

  # Attach the block volume at provisioning time so the device is stable
  # before Ansible touches the filesystem.
  volumes = [hcloud_volume.mailcow_data.id]

  user_data = <<-EOT
    #cloud-config
    hostname: ${var.company_name}-mail
    manage_etc_hosts: true
    package_update: false
  EOT

  labels = {
    managed-by = "terraform"
    company    = var.company_name
    role       = "mailcow"
  }
}

# Attach firewall to server (separate resource keeps the graph clean)
resource "hcloud_firewall_attachment" "mailcow" {
  firewall_id = hcloud_firewall.mailcow.id
  server_ids  = [hcloud_server.mailcow.id]
}

# ---------------------------------------------------------------------------
# Firewall — principle of least privilege; only necessary ports
# ---------------------------------------------------------------------------
resource "hcloud_firewall" "mailcow" {
  name = "${var.company_name}-mailcow-fw"

  # SSH — intentionally parameterised so you can lock this to office IPs
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = var.allowed_ssh_cidrs
    description = "SSH"
  }

  # Web — HTTP (redirected to HTTPS by Caddy)
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "80"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "HTTP (Caddy redirect)"
  }

  # Web — HTTPS (served by Caddy)
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "443"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "HTTPS (Caddy TLS)"
  }

  # Mail — SMTP (MX delivery, port 25)
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "25"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "SMTP MX"
  }

  # Mail — SMTPS (port 465, legacy TLS)
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "465"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "SMTPS"
  }

  # Mail — Submission (port 587, STARTTLS)
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "587"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "SMTP Submission"
  }

  # Mail — IMAPS (port 993)
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "993"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "IMAPS"
  }

  labels = {
    managed-by = "terraform"
    company    = var.company_name
  }
}

# ---------------------------------------------------------------------------
# Ansible inventory — generated after server IP is known
# ---------------------------------------------------------------------------
resource "local_file" "ansible_inventory" {
  content = <<-EOT
    [mailserver]
    ${hcloud_server.mailcow.ipv4_address} ansible_user=root volume_device=${hcloud_volume.mailcow_data.linux_device}
  EOT
  filename        = "${path.module}/../ansible/inventory.ini"
  file_permission = "0600"

  depends_on = [hcloud_server.mailcow, hcloud_volume.mailcow_data]
}
