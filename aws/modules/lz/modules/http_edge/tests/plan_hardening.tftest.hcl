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

run "waf_on_by_default" {
  command = plan

  assert {
    condition = alltrue([
      length(aws_wafv2_web_acl.this) == 1,
      aws_wafv2_web_acl.this[0].scope == "CLOUDFRONT",
      startswith(output.https_url, "https://"),
    ])
    error_message = "WAF Common Rule Set should be attached and https_url should be CloudFront HTTPS"
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
