### EFS
### EFS Security Group
resource "aws_security_group" "efs-sg" {
  name        = "terraform-efs"
  description = "Allow EFS Traffic from the Private Subnet"
  vpc_id      = var.vpc_id

  lifecycle {
    create_before_destroy = true
  }

  ingress {
    from_port   = "2049"
    to_port     = "2049"
    protocol    = "tcp"
    cidr_blocks = var.private_subnet_cidr
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

### EFS Filesystem
resource "aws_efs_file_system" "efs" {
  encrypted = true

  tags = {
    Name = "autoscale-efs"
  }
}

### EFS Mount Target
resource "aws_efs_mount_target" "efs" {
  file_system_id  = aws_efs_file_system.efs.id
  count           = var.az_count
  subnet_id       = element(var.private_subnet_ids, count.index)
  security_groups = [aws_security_group.efs-sg.id]
}
