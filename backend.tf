terraform {
  backend "s3" {
    bucket         = "terraform-tradebotpy-state"
    key            = "terraform.tfstate"
    region         = "eu-south-2"
    dynamodb_table = "terraform-tradebotpy-lock"
  }
}
