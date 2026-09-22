mock_provider "aws" {
  override_during = plan

  mock_data "aws_cloudfront_cache_policy" {
    defaults = { id = "cache-disabled" }
  }

  mock_data "aws_cloudfront_origin_request_policy" {
    defaults = { id = "origin-req" }
  }

  mock_data "aws_ec2_managed_prefix_list" {
    defaults = { id = "pl-cloudfront" }
  }
}

mock_provider "random" {
  override_during = plan

  mock_resource "random_password" {
    defaults = { result = "test-origin-header-value-32chars" }
  }
}

variables {
  aws_region          = "us-east-1"
  name                = "lz-main"
  security_group_name = "lz-alb-main"
  vpc_id              = "vpc-123"
  public_subnet_ids   = ["subnet-a", "subnet-b"]
}

run "alb_sg_uses_cloudfront_prefix_list" {
  command = plan

  assert {
    condition = alltrue([
      length(aws_security_group.alb.ingress) == 1,
      alltrue([
        for r in aws_security_group.alb.ingress :
        r.from_port == 80 && contains(r.prefix_list_ids, "pl-cloudfront") && (r.cidr_blocks == null || length(r.cidr_blocks) == 0)
      ]),
    ])
    error_message = "ALB SG ingress must be CloudFront origin-facing prefix list on port 80, not 0.0.0.0/0"
  }
}

run "alb_and_cloudfront_idle_read_timeout_120" {
  command = plan

  assert {
    condition = alltrue([
      aws_lb.this.idle_timeout == 120,
      alltrue([
        for o in aws_cloudfront_distribution.this.origin :
        o.custom_origin_config[0].origin_read_timeout == 120
      ]),
    ])
    error_message = "ALB idle_timeout and CloudFront origin_read_timeout should default to 120"
  }
}

run "waf_on_by_default" {
  command = plan

  assert {
    condition = alltrue([
      length(aws_wafv2_web_acl.this) == 1,
      aws_wafv2_web_acl.this[0].scope == "CLOUDFRONT",
      startswith(output.https_url, "https://"),
      length(flatten([
        for rule in aws_wafv2_web_acl.this[0].rule :
        try(rule.statement[0].managed_rule_group_statement[0].rule_action_override, [])
      ])) == 0,
    ])
    error_message = "WAF Common Rule Set should be attached with no CRS count overrides by default"
  }
}

run "waf_can_be_disabled" {
  command = plan

  variables {
    waf = { enabled = false }
  }

  assert {
    condition     = length(aws_wafv2_web_acl.this) == 0
    error_message = "waf.enabled = false should skip the Web ACL"
  }
}

run "waf_counts_named_crs_rules" {
  command = plan

  variables {
    waf = {
      common_rule_set_count_rules = ["SizeRestrictions_BODY", "CrossSiteScripting_BODY"]
    }
  }

  assert {
    condition = toset(flatten([
      for rule in aws_wafv2_web_acl.this[0].rule : [
        for o in try(rule.statement[0].managed_rule_group_statement[0].rule_action_override, []) : o.name
      ]
    ])) == toset(["SizeRestrictions_BODY", "CrossSiteScripting_BODY"])
    error_message = "common_rule_set_count_rules should count the named CRS rules"
  }
}
