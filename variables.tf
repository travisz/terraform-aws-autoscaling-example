variable "region" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "vpc_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "az_count" {
  description = "Number of AZs in the given AWS region"
  default     = "2"
}

variable "asg_name" {
  description = "Name for the auto-scaling group"
}

variable "asg_min_size" {
  type    = string
  default = "1"
}

variable "asg_max_size" {
  type = string
}

variable "asg_desired_capacity" {
  type = string
}

variable "key_name" {
  type = string
}

variable "instance_type" {
  type = string
}
