# Terraform State Migration to Backblaze B2

Complete step-by-step guide to migrate tfstate from local storage to Backblaze B2.

---

## Overview

**Before:** Terraform state stored locally in `terraform/terraform.tfstate`  
**After:** Terraform state stored remotely in B2 bucket `mailcow-tfstate-{company_name}`

**Buckets created (both optional, tied to `TF_VAR_b2_enabled`):**
- `mailcow-backup-{company_name}` — Mailcow backups + logs
- `mailcow-tfstate-{company_name}` — Terraform state (NEW)

---

## Prerequisites

✅ B2 account with application keys (see Step 2b in INSTRUCTIONS.md)  
✅ `.env` file populated with B2 credentials  
✅ Local Terraform state exists (`terraform/terraform.tfstate`)  
✅ Terraform 1.5+ installed  

---

## Step 1: Verify Current State

Check that local state exists and is healthy:

```bash
cd terraform

# List all resources in current state
terraform state list

# Should output something like:
#   hcloud_firewall.mailcow
#   hcloud_firewall_attachment.mailcow
#   hcloud_server.mailcow
#   hcloud_volume.mailcow_data
#   local_file.ansible_inventory
```

If no resources listed, state may be corrupted. Stop here and recover from backup.

---

## Step 2: Load B2 Credentials

From repo root, source `.env`:

```bash
source .env
```

Verify credentials are loaded:

```bash
echo $AWS_ACCESS_KEY_ID
echo $AWS_SECRET_ACCESS_KEY
echo $TF_VAR_b2_enabled
```

**Expected output:**
```
<your-b2-key-id>
<your-b2-application-key>
true
```

If any are empty, edit `.env` and re-source.

---

## Step 3: Enable B2 Infrastructure (if not already done)

This creates both the backup bucket AND the tfstate bucket.

Still in repo root:

```bash
cd terraform

# Create the B2 buckets via Terraform provider
terraform apply
```

When prompted, review changes — should include:
```
  + resource "b2_bucket" "backup" { ... }
  + resource "b2_bucket" "tfstate" { ... }
```

Confirm with `yes`.

**Wait for completion.** Verify in Terraform output:
```
Outputs:

b2_bucket_name = "mailcow-backup-{company}"
b2_tfstate_bucket_name = "mailcow-tfstate-{company}"
```

---

## Step 4: Create Local Backup

Before migrating, always back up local state:

```bash
cd terraform

# Create timestamped backup
cp terraform.tfstate terraform.tfstate.backup.$(date +%s)

# Verify backup exists
ls -lh terraform.tfstate.backup.*
```

Example output:
```
-rw------- 1 user group 12K Jul 13 10:30 terraform.tfstate.backup.1720842600
```

**Keep this file safe.** If migration fails, restore from here.

---

## Step 5: Determine Target Bucket Name

The tfstate bucket name is auto-generated. Verify which one will be used:

```bash
# Check what Terraform will use
echo $TF_VAR_b2_tfstate_bucket_name

# If empty, the default is:
echo "mailcow-tfstate-${TF_VAR_company_name}"
```

Example:
```
mailcow-tfstate-acmecorp
```

**Note this name for Step 6.**

---

## Step 6: Migrate State to B2

Initialize the backend with state migration:

```bash
cd terraform

# Reinitialize Terraform, using B2 backend and migrating local state
terraform init \
  -migrate-state \
  -backend-config="bucket=mailcow-tfstate-${TF_VAR_company_name}"
```

**What happens:**
1. Terraform detects local state (`terraform.tfstate`)
2. Asks: "Do you want to copy existing state to the new backend?"
3. Migrates all resources to B2

**Expected output:**
```
Do you want to copy existing state to the new backend?
```

Type `yes` and press Enter.

When complete:
```
Successfully configured the backend "s3"!
Terraform will automatically use this backend in all future operations.
```

---

## Step 7: Verify Remote State

Confirm state is now in B2 and accessible:

```bash
cd terraform

# List resources from remote state
terraform state list

# Should show same resources as Step 1
#   hcloud_firewall.mailcow
#   hcloud_server.mailcow
#   ...
```

Spot-check a resource:

```bash
terraform state show hcloud_server.mailcow

# Should output resource attributes
```

---

## Step 8: Verify Backend Configuration

Check Terraform is using B2 backend:

```bash
cd terraform

# Show which backend is active
cat .terraform/terraform.tfstate

# Should contain:
#   "backend": {
#     "type": "s3",
#     "config": {
#       "bucket": "mailcow-tfstate-..."
```

Or simpler:

```bash
terraform backend show

# Output should show S3 backend details
```

---

## Step 9: Delete Local State (Optional)

Once verified, local state files are no longer needed. Backup already created in Step 4.

```bash
cd terraform

# Delete local state files
rm -f terraform.tfstate terraform.tfstate.backup

# Verify they're gone
ls terraform.tfstate* 2>/dev/null || echo "Local state deleted"
```

**⚠️ Important:** Keep the backup from Step 4 for at least 7 days before permanently deleting.

---

## Step 10: Smoke Test

Verify workflow still works after migration:

```bash
cd terraform

# Plan (should show no changes if infra hasn't changed)
terraform plan

# Output should be:
#   No changes. Infrastructure is up-to-date.
```

If there are unexpected changes, **DO NOT APPLY**. Investigate first.

---

## Verification Checklist

- [ ] Local state backed up (Step 4)
- [ ] B2 buckets created (Step 3)
- [ ] `.env` sourced with B2 credentials (Step 2)
- [ ] `terraform init -migrate-state` completed successfully (Step 6)
- [ ] `terraform state list` shows all resources (Step 7)
- [ ] `terraform plan` shows no unexpected changes (Step 10)
- [ ] Local `terraform.tfstate*` files deleted (Step 9, optional)

---

## Troubleshooting

### Error: "access denied" during `terraform init`

**Cause:** AWS credentials not exported or invalid  
**Fix:**
```bash
# Re-source .env
source .env

# Verify credentials
echo $AWS_ACCESS_KEY_ID $AWS_SECRET_ACCESS_KEY

# Retry terraform init
terraform init -migrate-state -backend-config="bucket=..."
```

---

### Error: "NoSuchBucket"

**Cause:** B2 tfstate bucket doesn't exist yet  
**Fix:**
```bash
# Go back to Step 3 and run terraform apply
cd terraform
terraform apply

# Once buckets are created, retry Step 6
terraform init -migrate-state -backend-config="bucket=..."
```

---

### Error: "bucket already exists with different settings"

**Cause:** Bucket exists but backend config mismatch  
**Fix:**
```bash
# Check what bucket name terraform expects
echo "mailcow-tfstate-${TF_VAR_company_name}"

# If you used a custom name:
echo $TF_VAR_b2_tfstate_bucket_name

# Use the correct name in the backend-config flag
```

---

### State file lost, need to restore

If local state was deleted and remote migration failed:

```bash
# Restore from backup created in Step 4
cd terraform
cp terraform.tfstate.backup.1720842600 terraform.tfstate

# Re-run migration
terraform init -migrate-state -backend-config="bucket=..."
```

---

### How to verify state is in B2 (via Backblaze console)

1. Log into [Backblaze](https://secure.backblaze.com/)
2. Go to **B2 Cloud Storage → Buckets**
3. Click bucket `mailcow-tfstate-{company_name}`
4. Should see object: `terraform.tfstate` (~10-20 KB)

---

## After Migration

**Future `terraform apply` runs:**
- State is automatically fetched from B2 at start
- State is automatically pushed to B2 after changes
- No manual backup needed (but highly recommended after major changes)

**Manual state backup to B2 (optional):**
```bash
# If you want an extra copy in B2
rclone copy terraform/terraform.tfstate b2:mailcow-tfstate-{company_name}/backups/
```

---

## Rollback (if needed)

If something goes wrong during migration, you can revert to local state:

```bash
cd terraform

# Restore local state from backup
cp terraform.tfstate.backup.1720842600 terraform.tfstate

# Reinitialize to local backend
terraform init

# When prompted about migrating, choose "no"
```

Then investigate the issue before retrying.

---

## Questions?

Refer to:
- **Step 2b** in `INSTRUCTIONS.md` for B2 setup details
- **AWS/B2 docs:** [B2 S3-Compatible API](https://www.backblaze.com/docs/cloud-storage-s3-compatible-api)
- **Terraform docs:** [S3 Backend](https://developer.hashicorp.com/terraform/language/settings/backends/s3)
