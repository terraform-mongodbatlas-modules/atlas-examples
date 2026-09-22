# HTTP edge (ALB + CloudFront + WAF).

# --- HTTP edge (ALB + CloudFront + WAF) ---------------------------------------
module "http_edge" {
  for_each = local.http_edges

  source              = "./modules/http_edge"
  aws_region          = each.value.aws_region
  name                = "${var.default_resource_name_prefix}-${each.key}"
  security_group_name = "${var.default_resource_name_prefix}-alb-${each.key}"
  vpc_id              = local.app_network[each.value.aws_region].vpc_id
  public_subnet_ids   = local.app_network[each.value.aws_region].public_subnet_ids
  aliases             = each.value.aliases
  acm_certificate_arn = each.value.acm_certificate_arn
  idle_timeout        = each.value.idle_timeout
  waf                 = each.value.waf
  tags                = var.tags
}
