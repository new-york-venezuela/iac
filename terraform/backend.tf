terraform {
  # B2 backend config — uses B2's S3-compatible API
  # Requires environment vars: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
  # Region defaults to us-west-002; adjust if using different B2 region
  backend "s3" {
    bucket         = "" # Set via -backend-config at init
    key            = "terraform.tfstate"
    region         = "us-west-002"
    endpoint       = "https://s3.us-west-002.backblazeb2.com"
    skip_region_validation = true
    skip_credentials_validation = true
    skip_requesting_account_id = true
    skip_metadata_api_check = true
    use_path_style = true
  }
}
