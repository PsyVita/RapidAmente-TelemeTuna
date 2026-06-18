# --- Networking -------------------------------------------------------------
# Use the account's default VPC and its subnets.

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# --- Firewall (security group) ----------------------------------------------
# The group itself holds no rules; each rule is a separate, named resource below
# These are inbound rules which control who can access the instance. Outbound rules are at the bottom of this file.
# No SSH (22): shell access is via SSM Session Manager.

resource "aws_security_group" "telemetuna" {
  name        = "${var.project}-${var.environment}-sg"
  description = "TelemeTuna server firewall"
  vpc_id      = data.aws_vpc.default.id

  tags = {
    Name = "${var.project}-${var.environment}-sg"
  }
}

# Grafana dashboards — host port 3001 (container 3000), admin IP only.
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

# MQTT broker — host port 1884 (container 1883). Admin-only during setup;
# opened to the internet (with auth + TLS) in the hardening step.
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
# Allowing all outbounds means the instance can send info out to anywhere on the internet.
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.telemetuna.id
  description       = "All outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"

  tags = {
    Name = "${var.project}-${var.environment}-egress"
  }
}