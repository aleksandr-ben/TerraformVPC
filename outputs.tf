output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "nat_gateway_ips" {
  description = "Elastic IPs assigned to NAT Gateways"
  value       = aws_eip.natEIP[*].public_ip
}

output "vpc_flow_logs_bucket" {
  description = "S3 bucket for VPC Flow Logs"
  value       = aws_s3_bucket.logsVPC.id
}

output "instance_public_ip" {
  description = "Public IP address of the apache servers"
  value       = aws_instance.apache_server[*].public_ip
}

output "instance_private_ip" {
  description = "Private IP address of the private servers"
  value       = aws_instance.private_server[*].private_ip
}

