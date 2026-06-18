# --- Compute: the TelemeTuna server -----------------------------------------

# Latest Ubuntu 22.04 image from Canonical (no hard-coded AMI IDs).
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Pick the first default subnet and learn its Availability Zone (the data
# volume must live in the same AZ as the instance).
data "aws_subnet" "selected" {
  id = tolist(data.aws_subnets.default.ids)[0]
}

# Dedicated EBS volume for Postgres data only — so snapshots target just the DB.
resource "aws_ebs_volume" "postgres_data" {
  availability_zone = data.aws_subnet.selected.availability_zone
  size              = var.data_volume_size
  type              = "gp3"
  encrypted         = true

  tags = {
    Name   = "${var.project}-${var.environment}-postgres-data"
    Backup = "postgres" # the snapshot policy (task 12) targets this tag
  }
}

resource "aws_instance" "telemetuna" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnet.selected.id
  vpc_security_group_ids = [aws_security_group.telemetuna.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  associate_public_ip_address = true

  metadata_options {
    http_tokens = "required" # enforce IMDSv2 (security best practice)
  }

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    aws_region  = var.aws_region
    project     = var.project
    environment = var.environment
    repo_url    = var.repo_url
  })

  tags = {
    Name = "${var.project}-${var.environment}"
  }
}

# Attach the dedicated data volume to the instance.
resource "aws_volume_attachment" "postgres_data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.postgres_data.id
  instance_id = aws_instance.telemetuna.id
}

