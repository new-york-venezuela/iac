terraform {
  # B2 backend config — uses B2's S3-compatible API
  # Requires environment vars: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
  # Region defaults to us-west-002; adjust if using different B2 region
  backend "s3" {
    bucket         = "alimentos-new-york-terraform"
    key            = "terraform.tfstate"
    region         = "us-east-005"
    endpoints = {
      s3 = "https://s3.us-east-005.backblazeb2.com"
    }
    skip_region_validation = true
    skip_credentials_validation = true
    skip_requesting_account_id = true
    skip_metadata_api_check = true
    use_path_style = true
  }
}
