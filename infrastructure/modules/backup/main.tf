# Backup: scheduled STANDARD-tier EBS snapshots of the Postgres data volume, with a
# Recycle Bin safety net for accidental/automated deletes.
#
# Standard-tier snapshots are INCREMENTAL: only blocks that changed since the previous
# snapshot are stored and billed (not the whole volume) — the right fit for frequent,
# short-retention, fast-restore backups. (Archiving, which stores a full snapshot with a
# 90-day minimum, was intentionally NOT used here.)
#
# Everything targets volumes BY TAG (Backup = postgres), so this module is decoupled from
# the compute module. Works on AWS provider 5.x (no v6 features used).

# --- IAM role the DLM service assumes to create/delete/tag snapshots --------
data "aws_iam_policy_document" "dlm_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["dlm.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "dlm" {
  name               = "${var.project}-${var.environment}-dlm-role"
  assume_role_policy = data.aws_iam_policy_document.dlm_assume.json
}

# AWS-managed policy scoped to exactly what DLM needs (snapshot create/delete/tag).
resource "aws_iam_role_policy_attachment" "dlm" {
  role       = aws_iam_role.dlm.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
}

# --- The snapshot lifecycle policy -----------------------------------------
resource "aws_dlm_lifecycle_policy" "postgres" {
  description        = "${var.project}-${var.environment} Postgres EBS snapshots - daily standard tier"
  execution_role_arn = aws_iam_role.dlm.arn
  state              = var.snapshot_state

  policy_details {
    resource_types = ["VOLUME"]

    # Only EBS volumes carrying this tag are snapshotted. The Postgres DATA volume has
    # Backup=postgres; the EC2 root/OS disk does NOT, so it is intentionally excluded.
    target_tags = {
      (var.backup_tag_key) = var.backup_tag_value
    }

    schedule {
      name = "daily-midnight-ict"

      # WHEN to snapshot. DLM cron is UTC; this fires at 17:00 UTC == 00:00 Asia/Bangkok.
      # Change var.snapshot_cron to adjust cadence (apply updates in place — no destroy).
      create_rule {
        cron_expression = var.snapshot_cron
      }

      # Keep the N most recent snapshots in the standard tier; older ones are deleted
      # (and then caught by the Recycle Bin rule below).
      retain_rule {
        count = var.standard_retain_count
      }

      # Copy the source volume's tags onto each snapshot, and stamp our own so the
      # Recycle Bin rule can match the snapshots even if copy_tags ever changes.
      copy_tags = true
      tags_to_add = {
        (var.backup_tag_key) = var.backup_tag_value
        SnapshotCreator      = "DLM"
      }
    }
  }
}

# --- Recycle Bin: keep DELETED snapshots recoverable for a window ----------
# Tag-level rule: if DLM (or a person) deletes a matching snapshot, it lands in the
# Recycle Bin instead of vanishing, recoverable for recycle_bin_retention_days.
resource "aws_rbin_rule" "snapshots" {
  description   = "${var.project}-${var.environment} Postgres snapshot recovery window"
  resource_type = "EBS_SNAPSHOT"

  resource_tags {
    resource_tag_key   = var.backup_tag_key
    resource_tag_value = var.backup_tag_value
  }

  retention_period {
    retention_period_value = var.recycle_bin_retention_days
    retention_period_unit  = "DAYS"
  }

  tags = {
    Name = "${var.project}-${var.environment}-snapshot-rbin"
  }
}