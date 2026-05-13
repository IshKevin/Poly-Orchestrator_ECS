output "address" {
  description = "Redis cluster hostname"
  value       = aws_elasticache_cluster.this.cache_nodes[0].address
}

output "port" {
  description = "Redis cluster port"
  value       = aws_elasticache_cluster.this.port
}
