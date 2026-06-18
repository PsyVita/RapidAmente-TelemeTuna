# --- IAM role for the EC2 instance ------------------------------------------
# Lets the server: (1) be managed via SSM Session Manager (shell access, no
# SSH), and (2) read ONLY its three secrets from Parameter Store.

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2" {
  name               = "${var.project}-${var.environment}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

# AWS-managed policy that enables SSM Session Manager.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Allow reading (and decrypting) ONLY the three secrets this server needs.
data "aws_iam_policy_document" "read_secrets" {
  statement {
    sid     = "ReadOwnSecrets"
    actions = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = [
      aws_ssm_parameter.postgres_password.arn,
      aws_ssm_parameter.grafana_password.arn,
      aws_ssm_parameter.pgadmin_password.arn,
    ]
  }

  # SecureString values are encrypted with the AWS-managed SSM key; decrypting
  # them requires kms:Decrypt. Scoped to SSM use only via the condition.
  statement {
    sid       = "DecryptViaSsm"
    actions   = ["kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${var.aws_region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "read_secrets" {
  name   = "read-secrets"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.read_secrets.json
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project}-${var.environment}-ec2-profile"
  role = aws_iam_role.ec2.name
}