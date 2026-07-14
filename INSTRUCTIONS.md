# Deployment Instructions

Complete runbook for deploying and maintaining a Mailcow + Caddy stack on Hetzner Cloud.

---

## Prerequisites

### Local machine

| Tool | Min version | Install |
|---|---|---|
| Terraform | 1.5 | `brew install terraform` or [terraform.io](https://developer.hashicorp.com/terraform/install) |
| Ansible | 9.x | via uv (see below) |
| uv | latest | `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| rsync | any | pre-installed on macOS/Linux |
| git | any | pre-installed |

### Hetzner Cloud

1. Create a Hetzner Cloud project at console.hetzner.cloud
2. Generate an **API token** (Read & Write)
3. Upload your SSH public key: **Project → Security → SSH Keys → Add SSH Key**
   - Note the exact name you give it — this goes into `TF_VAR_ssh_key_name`

---

## Step 1 — Python Environment

```bash
# From repo root
uv sync                          # Provisions Python 3.13 (pinned) and installs ansible + ansible-lint + netaddr
source .venv/bin/activate        # Activate

# Install Ansible Galaxy collections + the official mailcow role
ansible-galaxy install -r ansible/requirements.yml
```

---

## Step 2 — Configure Secrets

```bash
cp .env.example .env
```

Edit `.env` and fill in every value:

```bash
export HCLOUD_TOKEN="..."          # Hetzner API token
export TF_VAR_company_name="..."   # Short slug, e.g. acmecorp
export TF_VAR_domain="..."         # e.g. acmecorp.com
export TF_VAR_admin_email="..."    # For Caddy ACME registration
export TF_VAR_ssh_key_name="..."   # Must match name in Hetzner console
export TF_VAR_server_location="fsn1"
export TF_VAR_timezone="Europe/Berlin"
```

Then source it:

```bash
source .env
```

> **Never commit `.env`.** It is in `.gitignore`. Verify with `git status` before pushing.

---

## Step 2b — Backblaze B2 (optional offsite backup)

If you want automated offsite backups to Backblaze B2:

1. Create a Backblaze account at [backblaze.com](https://www.backblaze.com/)
2. Go to **Account → App Keys → Add a New Application Key**
   - Give it a name (e.g. `mailcow-backup`)
   - Allow access to **All Buckets** (so Terraform can create the bucket), or scope to a specific bucket after creation
   - Enable **Read and Write** on Files and Buckets
3. Copy the Key ID and Application Key into `.env`:
   ```bash
   export B2_APPLICATION_KEY_ID="..."
   export B2_APPLICATION_KEY="..."
   export TF_VAR_b2_enabled="true"
   ```
4. Re-source `.env` and re-run Terraform — it will create the bucket
5. Re-run Ansible — it will configure rclone and the daily offsite sync cron

> **Bucket naming:** B2 bucket names are globally unique across all B2 accounts. The default `mailcow-backup-{company_name}` may already be taken. Set `TF_VAR_b2_bucket_name` to a unique name if needed.

---

## Step 3 — Terraform (provision infrastructure)

```bash
cd terraform

terraform init          # Download providers (hcloud + local)
terraform validate      # Syntax check
terraform plan          # Preview — review carefully before proceeding

# When satisfied:
terraform apply         # Provisions server, volume, firewall, writes ansible/inventory.ini
```

After `apply` completes:

- Check the **DNS notice** in the Terraform output
- Add the A records and MX record shown before running Ansible
- Wait for DNS propagation (use `dig mail.yourdomain.com` to confirm)

> Caddy's automatic TLS will fail if DNS is not pointing at the server when Ansible runs.

---

## Step 4 — Ansible (configure server)

```bash
cd ..   # Back to repo root

# Verify connectivity first
ansible -i ansible/inventory.ini mailserver -m ping

# Run the full playbook
ansible-playbook -i ansible/inventory.ini ansible/playbook.yml \
  -e domain="${TF_VAR_domain}" \
  -e admin_email="${TF_VAR_admin_email}" \
  -e timezone="${TF_VAR_timezone}" \
  -e b2_key_id="${B2_APPLICATION_KEY_ID}" \
  -e b2_application_key="${B2_APPLICATION_KEY}"
```

The playbook is **fully idempotent** — safe to re-run. Tags let you target specific blocks:

```bash
# Re-deploy only the website
ansible-playbook ... --tags web

# Re-apply Caddy config after Caddyfile edit
ansible-playbook ... --tags caddy

# Re-run the mailcow role only (config patches + start/update stack)
ansible-playbook ... --tags mailcow
```

---

## Step 5 — Post-deployment Setup

### Mailcow Admin UI

1. Navigate to `https://mail.yourdomain.com` in your browser
2. Log in with default credentials: **admin / moohoo**
3. **Change the admin password immediately**
4. Create your first domain: **Configuration → Mail Setup → Domains → Add domain**
5. Create mailboxes and aliases as needed

### DNS Records for Email Delivery

After the mail domain is configured in Mailcow, add these DNS records:

```
# SPF
yourdomain.com  TXT  "v=spf1 mx ~all"

# DKIM — retrieve the public key from Mailcow UI:
# Configuration → Mail Setup → Domains → DKIM
dkim._domainkey.yourdomain.com  TXT  "v=DKIM1; k=rsa; p=<key from UI>"

# DMARC
_dmarc.yourdomain.com  TXT  "v=DMARC1; p=none; rua=mailto:dmarc@yourdomain.com"
```

### Verify TLS

```bash
# Check Caddy issued certs
curl -I https://yourdomain.com
curl -I https://mail.yourdomain.com

# Check mail TLS (Dovecot/Postfix)
openssl s_client -connect mail.yourdomain.com:993 -quiet
openssl s_client -connect mail.yourdomain.com:465 -quiet
```

---

## Backup Guide

### Automated Daily Backup

Ansible installs a cron job that runs at **02:30 UTC daily**:

```bash
MAILCOW_BACKUP_LOCATION=/mnt/mailcow-data/backups \
  /opt/mailcow-dockerized/helper-scripts/backup_and_restore.sh backup all
```

Backups older than 7 days are pruned automatically (Sunday 04:00 UTC cron).

**Monitor:**
```bash
tail -f /var/log/mailcow-backup.log
ls -lh /mnt/mailcow-data/backups/
```

### Offsite Push with Backblaze B2 (automated)

When `b2_enabled = true` in Terraform, Ansible automatically:

1. Writes `/root/.config/rclone/rclone.conf` with B2 credentials (mode 0600)
2. Installs a daily cron at **05:00 UTC** that syncs to B2:

```
rclone sync /mnt/mailcow-data/backups b2:<bucket>/mailcow/
```

Logs go to `/var/log/rclone-backup.log`.

**Monitor:**
```bash
tail -f /var/log/rclone-backup.log
rclone lsd b2:<bucket-name>/mailcow/
```

**Verify remote contents:**
```bash
rclone ls b2:<bucket-name>/mailcow/
```

**Terraform state backup** (manual, run after each `terraform apply`):
```bash
rclone copy terraform/terraform.tfstate b2:<bucket-name>/tfstate/
```

### Backup Restoration

```bash
# SSH into server
ssh root@<server-ip>

# List available backups
ls /mnt/mailcow-data/backups/

# Restore a specific backup
MAILCOW_BACKUP_LOCATION=/mnt/mailcow-data/backups \
  /opt/mailcow-dockerized/helper-scripts/backup_and_restore.sh restore

# Follow the interactive prompts to select backup date and components
```

> **Test restores regularly.** A backup never tested is not a backup.

---

## Maintenance

### Updating Mailcow

Re-running the playbook applies updates automatically: the `mailcow.mailcow`
role runs mailcow's official `update.sh` when the stack is already running
(`mailcow__install_updates: true`).

```bash
ansible-playbook -i ansible/inventory.ini ansible/playbook.yml \
  -e domain="${TF_VAR_domain}" --tags mailcow
```

Manual alternative:

```bash
ssh root@<server-ip>
cd /opt/mailcow-dockerized
./update.sh
```

### Updating Caddy

Caddy is managed via apt; it updates with `unattended-upgrades`. To force:

```bash
ssh root@<server-ip>
apt update && apt upgrade caddy
systemctl reload caddy
```

### Scaling the Volume

If `/mnt/mailcow-data` fills up:

1. In Hetzner console: resize the volume (online resize supported)
2. On the server:
   ```bash
   resize2fs /dev/disk/by-id/scsi-0HC_Volume_<id>
   df -h /mnt/mailcow-data   # Verify new size
   ```

### Updating the Static Website

```bash
# Build your site into dist/ locally, then:
ansible-playbook -i ansible/inventory.ini ansible/playbook.yml \
  -e domain="${TF_VAR_domain}" \
  -e admin_email="${TF_VAR_admin_email}" \
  --tags web
```

---

## Replicating for a New Company

1. Clone this repo into a new directory (or use a new git branch)
2. Copy `.env.example` → `.env`, set all `TF_VAR_company_name`, `TF_VAR_domain`, etc.
3. Upload a new SSH key to Hetzner for this client
4. `source .env && cd terraform && terraform init && terraform apply`
5. Point DNS A records at new server IP
6. Run `ansible-playbook` with the client's domain and email
7. Configure Mailcow admin UI
8. Add SPF / DKIM / DMARC records

Each deployment is fully isolated: different Hetzner project, different server, different volume.
