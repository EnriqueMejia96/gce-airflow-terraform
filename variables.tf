variable "project" {
  description = "The project ID"
  type        = string
}

variable "region" {
  description = "The region for the resources"
  type        = string
}

variable "machine_type" {
  description = "The machine type for the Compute Engine instance"
  type        = string
}

variable "bucket_name" {
  description = "The name of the GCS bucket to store Airflow DAGs"
  type        = string
}

variable "user_email" {
    description = "The default email for the user"
    type        = string
}

variable "disk_size" {
  description = "Size of the boot disk in GB"
  type        = number
}
