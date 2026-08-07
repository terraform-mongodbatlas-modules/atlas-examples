output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnets" {
  value = module.vpc.private_subnets
}

output "vpc_cidr_block" {
  value = module.vpc.vpc_cidr_block
}

output "private_route_table_ids" {
  value = module.vpc.private_route_table_ids
}

output "natgw_ids" {
  value = module.vpc.natgw_ids
}
