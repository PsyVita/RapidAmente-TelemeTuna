# eip.tf
# The Elastic IP is allocated OUTSIDE Terraform (manually, tagged Name=telemetuna-eip),
# so `terraform destroy` cannot release it and the IP stays stable across rebuilds.
# Terraform only LOOKS IT UP and ATTACHES it to the instance.

# Find the manually-created EIP by its Name tag. Expects exactly one match.
data "aws_eip" "telemetuna" {
  tags = {
    Name = "telemetuna-eip"
  }
}

# Attach that EIP to the instance. `destroy` removes only this association,
# never the underlying address.
resource "aws_eip_association" "telemetuna" {
  instance_id   = aws_instance.telemetuna.id
  allocation_id = data.aws_eip.telemetuna.id
}