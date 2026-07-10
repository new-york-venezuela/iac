output "server_ip" {
  description = "Public IPv4 address of the mailcow server."
  value       = hcloud_server.mailcow.ipv4_address
}

output "server_ipv6" {
  description = "Public IPv6 address of the mailcow server."
  value       = hcloud_server.mailcow.ipv6_address
}

output "server_name" {
  description = "Hetzner server resource name."
  value       = hcloud_server.mailcow.name
}

output "volume_id" {
  description = "Hetzner volume ID."
  value       = hcloud_volume.mailcow_data.id
}

output "volume_linux_device" {
  description = "Block device path on the server (passed to Ansible for formatting/mounting)."
  value       = hcloud_volume.mailcow_data.linux_device
}

output "ansible_inventory_path" {
  description = "Path to the auto-generated Ansible inventory file."
  value       = local_file.ansible_inventory.filename
}

output "post_apply_dns_notice" {
  description = "Reminder: point DNS A records at the server IP before running Ansible."
  value = <<-EOT
    =====================================================================
    DNS RECORDS REQUIRED BEFORE RUNNING ANSIBLE
    =====================================================================
    Point these A records to: ${hcloud_server.mailcow.ipv4_address}

      ${var.domain}       A  ${hcloud_server.mailcow.ipv4_address}
      www.${var.domain}   A  ${hcloud_server.mailcow.ipv4_address}
      mail.${var.domain}  A  ${hcloud_server.mailcow.ipv4_address}

    MX record:
      ${var.domain}  MX  10  mail.${var.domain}
    =====================================================================
  EOT
}
