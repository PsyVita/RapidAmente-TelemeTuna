# Networking: default VPC + subnet lookups and the instance security group.

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# First default subnet + its AZ (the data volume must live in the same AZ).
data "aws_subnet" "selected" {
  id = tolist(data.aws_subnets.default.ids)[0]
}

# --- Firewall (security group) ----------------------------------------------
# No SSH (22): shell access is via SSM Session Manager.
resource "aws_security_group" "telemetuna" {
  name        = "${var.project}-${var.environment}-sg"
  description = "TelemeTuna server firewall"
  vpc_id      = data.aws_vpc.default.id

  tags = {
    Name = "${var.project}-${var.environment}-sg"
  }
}

# Grafana dashboards — host port 3001 (container 3000).
resource "aws_vpc_security_group_ingress_rule" "grafana" {
  security_group_id = aws_security_group.telemetuna.id
  description       = "Grafana UI (admin only)"
  cidr_ipv4         = var.admin_cidr
  from_port         = 3001
  to_port           = 3001
  ip_protocol       = "tcp"

  tags = {
    Name = "${var.project}-${var.environment}-grafana-in"
  }
}

# MQTT broker — host port 1884 (container 1883).
resource "aws_vpc_security_group_ingress_rule" "mqtt" {
  security_group_id = aws_security_group.telemetuna.id
  description       = "MQTT broker (admin only during setup)"
  cidr_ipv4         = var.admin_cidr
  from_port         = 1884
  to_port           = 1884
  ip_protocol       = "tcp"

  tags = {
    Name = "${var.project}-${var.environment}-mqtt-in"
  }
}

# Allow all outbound (Docker pulls, OS updates, SSM agent).
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.telemetuna.id
  description       = "All outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"

  tags = {
    Name = "${var.project}-${var.environment}-egress"
  }
}
