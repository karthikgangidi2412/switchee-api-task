terraform {
  backend "s3" {
    bucket = "weather-request-data"
    key    = "terraform.tfstate"
    region = "eu-north-1"
  }
}