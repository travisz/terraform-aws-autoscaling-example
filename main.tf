### AutoScaling EC2 Instances

provider "aws" {
  region = var.region
}

### Grab the Region
data "aws_region" "current" {}

### Define the AMI to use (Aamzon Linux 2)
data "aws_ami" "autoscale_ami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*-x86_64-gp2"]
  }
}

### Networking

### Grab the currently available AZs for the region
data "aws_availability_zones" "available" {}

# Create the VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true

  tags = {
    Name        = var.vpc_name
    Environment = var.environment
  }
}

### Private Subnets based on az_count variable
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  count             = var.az_count
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name        = "${format("${var.vpc_name}-${var.environment}-private-%03d", count.index + 1)}"
    Environment = var.environment
  }
}

### Publc Subnets based on az_count variable
resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  count             = var.az_count
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, var.az_count + count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name        = "${format("${var.vpc_name}-${var.environment}-public-%03d", count.index + 1)}"
    Environment = var.environment
  }
}

### IGW for the public subnet
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "${var.vpc_name}-{var.environment}-IGW"
    Environment = var.environment
  }
}

### Route table entry for public subnet traffic to the IGW
resource "aws_route" "public" {
  route_table_id         = aws_vpc.main.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw.id
}

### EIP for NAT Gateway
resource "aws_eip" "nat-gw" {
  count      = var.az_count
  vpc        = true
  depends_on = [aws_internet_gateway.gw]
}

### NAT Gateway, one per AZ for the private subnet to have internet access
resource "aws_nat_gateway" "nat-gw" {
  count         = var.az_count
  subnet_id     = element(aws_subnet.public.*.id, count.index)
  allocation_id = element(aws_eip.nat-gw.*.id, count.index)
}

### Route table for the private subnets
resource "aws_route_table" "private" {
  count  = var.az_count
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = element(aws_nat_gateway.nat-gw.*.id, count.index)
  }
}

### Associate the route tables to the private subnets
resource "aws_route_table_association" "private" {
  count          =  var.az_count
  subnet_id      = element(aws_subnet.private.*.id, count.index)
  route_table_id = element(aws_route_table.private.*.id, count.index)
}

### Create the AutoScaling Group
resource "aws_autoscaling_group" "asg" {
  name                 = var.asg_name
  vpc_zone_identifier  = aws_subnet.private.*.id
  min_size             = var.asg_min_size
  max_size             = var.asg_max_size
  desired_capacity     = var.asg_desired_capacity
  launch_configuration = aws_launch_configuration.launch_config.name
  target_group_arns    = [aws_alb_target_group.app.arn]

  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupTotalInstances"
  ]

  metrics_granularity = "1Minute"

  lifecycle {
    ignore_changes = [
      desired_capacity
    ]
  }

  tags = [
    {
      key                 = "Name"
      value               = var.asg_name
      propagate_at_launch = true
    },
    {
      key                 = "Environment"
      value               = var.environment
      propagate_at_launch = true
    }
  ]

  depends_on = [
    module.efs-0.mount_target_ids
  ]
}

### Cloud-init for EC2 Instances
data "template_file" "cloud_config" {
  template = "${file("${path.module}/cloud-config.yml")}"

  vars = {
    aws_region         = data.aws_region.current.name
    efs_volume_id      = module.efs-0.volume_id
    mount_point_1      = "/mnt/efs"
  }
}

### Launch Configuration
resource "aws_launch_configuration" "launch_config" {
  security_groups = [
    aws_security_group.instance_sg.id,
    aws_security_group.alb.id
  ]

  name_prefix                 = var.asg_name
  key_name                    = var.key_name
  image_id                    = data.aws_ami.autoscale_ami.id
  instance_type               = var.instance_type
  user_data                   = data.template_file.cloud_config.rendered
  associate_public_ip_address = false

  lifecycle {
    create_before_destroy = true
  }
}

### Auto-Scaling Policy
### Policy - Scale Up
resource "aws_autoscaling_policy" "policy_up" {
  name                   = "autoscale_policy_up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.asg.name
}

### Alarm - Scale Up
resource "aws_cloudwatch_metric_alarm" "cpu_alarm_up" {
  alarm_name          = "autoscale_cpu_alarm_up"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "60"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.asg.name
  }

  alarm_description = "This metrics monitors EC2 instance CPU utilization"
  alarm_actions = [aws_autoscaling_policy.policy_up.arn]
}

### Policy - Scale Down
resource "aws_autoscaling_policy" "policy_down" {
  name                   = "autoscale_policy_down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.asg.name
}

### Alarm - Scale Down
resource "aws_cloudwatch_metric_alarm" "cpu_alarm_down" {
  alarm_name          = "autoscale_cpu_alarm_down"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "10"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.asg.name
  }

  alarm_description = "This metrics monitors EC2 instance CPU utilization"
  alarm_actions = [aws_autoscaling_policy.policy_down.arn]
}

### Security
### Application Load Balancer Security Group
### Modify this to allow ports for your application or to restrict access
resource "aws_security_group" "alb" {
  name        = "terraform-alb"
  description = "Controls Access to the ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

### Security Group - EC2 Instance Access
resource "aws_security_group" "instance_sg" {
  description = "controls direct access to application instances"
  vpc_id      = aws_vpc.main.id
  name        = "direct-ec2-instance-access"

  ingress {
    description = "Concat of the Public and Private subnet ranges"
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22

    cidr_blocks = concat(aws_subnet.private.*.cidr_block, aws_subnet.public.*.cidr_block)
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

### Restrict traffic to the Backend Servers, only allow it to come from the ALB
resource "aws_security_group" "backend" {
  name        = "terraform-backend"
  description = "Allow access from the ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    protocol        = "tcp"
    from_port       = 80
    to_port         = 80
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

### Application Load Balancer
resource "aws_alb" "main" {
  name            = "terraform-test"
  subnets         = aws_subnet.public.*.id
  security_groups = [aws_security_group.alb.id]
}

### Application Load Balancer Target Group
resource "aws_alb_target_group" "app" {
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "terraform-test"
  }
}

resource "aws_alb_listener" "app_front_end" {
  load_balancer_arn = aws_alb.main.id
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_alb_target_group.app.id
    type             = "forward"
  }
}

### EFS Module
# This needs to be declared separately due to the "depends_on" in the autoscale group resource.

module "efs-0" {
  source              = "./efs"
  private_subnet_cidr = aws_subnet.private.*.cidr_block
  private_subnet_ids  = aws_subnet.private.*.id
  vpc_id              = aws_vpc.main.id
  az_count            = var.az_count
}
