output "instance_id" {
  description = "Jenkins EC2 instance ID"
  value       = aws_instance.jenkins.id
}

output "public_ip" {
  description = "Jenkins EC2 public IP address"
  value       = aws_instance.jenkins.public_ip
}

output "jenkins_url" {
  description = "Jenkins web UI URL"
  value       = "http://${aws_instance.jenkins.public_ip}:8080"
}

output "security_group_id" {
  description = "Jenkins security group ID"
  value       = aws_security_group.jenkins.id
}

output "iam_role_arn" {
  description = "IAM role ARN attached to the Jenkins instance"
  value       = aws_iam_role.jenkins.arn
}

output "ssh_key_file" {
  description = "Local path to the generated SSH private key"
  value       = local_file.jenkins_private_key.filename
}
