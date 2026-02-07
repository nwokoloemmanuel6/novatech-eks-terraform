output "node_group_names" {
  description = "Names of the node groups"
  value       = { for k, v in aws_eks_node_group.this : k => v.node_group_name }
}

output "node_group_arns" {
  description = "ARNs of the node groups"
  value       = { for k, v in aws_eks_node_group.this : k => v.arn }
}

output "node_role_arn" {
  description = "ARN of the node IAM role"
  value       = aws_iam_role.node.arn
}
