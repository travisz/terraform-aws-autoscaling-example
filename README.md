# About
Terraform example to create an Auto-Scaling Group (ASG) with an Application Load Balancer (ALB) an Elastic File System (EFS)

## Creates
This example creates:
* Network Resources: VPC / Subnet(s) / IGW / NAT Gateway(s)
* EC2 Resources: Autoscaling Group, Application Load Balancer, EC2 Instances, Security Groups
* Cloudwatch Resources: CloudWatch Alarms

# Usage
Create a vars file (ex: `vars`) with the following (customized as needed):
```
region = "us-east-1"
vpc_cidr = "172.50.0.0/16"
vpc_name = "my-test-vpc"
environment = "development"
asg_name = "my-test-asg"
asg_max_size = "4"
asg_desired_capacity = "1"
key_name = "my-key"
instance_type = "t3.small"
```

**NOTES**:
* Make sure to update `key_name` to an existing key on the AWS account.
* Review the `variables.tf` as there are some default values defined.

Validate and Plan
```
terraform validate -var-file=vars
terraform plan -var-file=vars
```

Apply
```
terraform apply -var-file=vars
```

**NOTE**: This uses local state. If you want to define a remote state create the bucket and assign a `terraform backend` seciton in `main.tf`

# Outputs
* `alb_hostname`
