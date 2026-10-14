terraform {
  backend "s3" {
    bucket       = "aws-multi-region-dr-platform-620306387033"
    key          = "terraform/lab/terraform.tfstate"
    region       = "ap-southeast-1"
    encrypt      = true
    use_lockfile = true
  }
}
