# Offsite Backup Strategy: Backblaze B2

**Date:** 2026-07-13  
**Status:** Approved  
**Owner:** Eugenio Doñaque

---

## Overview

Implement automated offsite backups to Backblaze B2 for all critical data: Mailcow backups, ERP database snapshots, and Terraform state. This provides geographic diversity against Hetzner Frankfurt regional failure while maintaining minimal cost ($0.12/month baseline storage).

---

## Goals

1. **Safe from day one** — backups stored offsite, outside Hetzner Frankfurt region
2. **Cost-optimized** — B2 at $0.006/GB/month storage, cheap egress ($0.01/GB on restore)
3. **Low operational burden** — automated via rclone + cron, integrated into existing playbook
4. **Future-proof** — structure allows adding secondary provider (S3, etc.) later without refactoring

---

## What We're Backing Up

| Data | Source | Frequency | Retention |
|------|--------|-----------|-----------|
| Mailcow (SQL + files) | `/mnt/mailcow-data/backups/` | Daily @ 02:30 UTC | 7 days local, indefinite in B2 |
| ERP Database | TBD (user provides path) | TBD (weekly assumed) | 30 days rolling |
| Terraform State | `/terraform/terraform.tfstate` | On-demand (after each `apply`) | All versions (B2 versioning) |

---

## Architecture

### Storage

**Backblaze B2:**
- Single bucket: `mailcow-backup-{company_slug}`
- Regions: B2 distributes across US/EU automatically (geographic diversity)
- Versioning enabled (recover tfstate rollbacks, accident scenarios)
- Lifecycle policy: Keep all versions, no auto-delete (user manages retention)

### Sync Strategy

**Mailcow + ERP backups:**
- rclone daemon on server, cron job pushes `/mnt/mailcow-data/backups/` → B2 daily
- `--delete-during` not used (preserves older backups for retention window)
- Local pruning (7-day retention) still active; B2 keeps indefinite archive

**Terraform state:**
- Manual: `rclone copy terraform/terraform.tfstate b2:mailcow-backup-{company_slug}/tfstate/`
- Integrated as part of deployment checklist or hook (user decides on automation level)
- B2 versioning provides history

### Recovery

**RTO: ~30–60 minutes**
- Download from B2 via rclone (`rclone copy b2:... /mnt/restore/`)
- Restore via mailcow's `backup_and_restore.sh`
- ERP restore: user-dependent (assumed < 1 hour for 500 MB)

Meets 1-hour RTO requirement for regional failure scenario.

---

## Implementation

### Prerequisites

- B2 account and API credentials (generated in B2 console)
- rclone already installed by prep tag

### Changes to Playbook

1. **Backup tag expansion:**
   - Update rclone.conf template to include B2 remote example
   - Add daily cron: `rclone sync /mnt/mailcow-data/backups b2:mailcow-backup-{company_slug}/mailcow/`
   - Add daily cron: ERP backup sync (path TBD by user)
   - Add log rotation for rclone sync

2. **Terraform state backup:**
   - Document manual copy command in INSTRUCTIONS.md
   - Optional: Add pre-deployment hook or remind user in CI/CD

3. **Monitoring:**
   - Log rclone output to `/var/log/rclone-backup.log`
   - User can check via: `tail -f /var/log/rclone-backup.log` or `rclone lsd b2:mailcow-backup-{company_slug}/`

---

## Cost

| Component | Cost/Month |
|-----------|-----------|
| Storage (20 GB @ $0.006/GB) | $0.12 |
| API requests | ~$0.01 |
| Egress on restore (if needed) | $0.20 (20 GB download) |
| **Total (baseline, no restore)** | **$0.13/month** |
| **Total (if 1 restore/month)** | **$0.33/month** |

Negligible; scales linearly with data volume.

---

## Security & Secrets

- B2 credentials stored in `/root/.config/rclone/rclone.conf` (mode 0600, root-only)
- Credentials injected via Ansible variable (user provides via `.env` or secrets manager)
- rclone config never committed to git (already in playbook as templated, user fills in)

---

## Testing & Validation

- **Initial:** After playbook runs, check `ls /mnt/mailcow-data/backups/` and `rclone lsd b2:...` to verify sync
- **Monthly:** Download a backup via rclone and test restore to verify RTO
- **Ongoing:** Monitor `/var/log/rclone-backup.log` for sync errors

---

## Future Enhancements

- Add S3 secondary backup for true redundancy (if mailserver becomes business-critical)
- Automate Terraform state upload via pre-commit hook or CI/CD
- Implement monitoring/alerting if rclone sync fails (e.g., via systemd timer + mail alert)

---

## Open Questions for User

1. **ERP Database Path:** Where is the ERP SQL backup file located, and how often should it sync?
2. **Terraform State:** Should tfstate backup be manual or automated (pre-apply hook)?
3. **B2 Bucket Naming:** Confirm bucket name scheme (`mailcow-backup-{company_slug}` vs other)?

