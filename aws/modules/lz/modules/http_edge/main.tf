data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

data "aws_ec2_managed_prefix_list" "cloudfront_origin" {
  region = var.aws_region
  name   = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "random_password" "origin_header" {
  length  = 32
  special = false
}

locals {
  origin_header_name  = "X-Origin-Verify"
  origin_header_value = random_password.origin_header.result
}

resource "aws_security_group" "alb" {
  region      = var.aws_region
  name_prefix = "${var.security_group_name}-"
  description = "HTTP edge ALB (CloudFront origin-facing only)"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTP from CloudFront"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront_origin.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = var.security_group_name })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb" "this" {
  region             = var.aws_region
  name               = var.name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids
  idle_timeout       = var.idle_timeout

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_lb_listener" "http" {
  region            = var.aws_region
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not found"
      status_code  = "404"
    }
  }
}

resource "aws_wafv2_web_acl" "this" {
  count       = var.waf.enabled ? 1 : 0
  region      = "us-east-1"
  name        = var.name
  description = "CloudFront WAF for ${var.name}"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "common"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = var.name
    sampled_requests_enabled   = true
  }

  tags = var.tags
}

resource "aws_cloudfront_distribution" "this" {
  enabled         = true
  price_class     = "PriceClass_100"
  is_ipv6_enabled = true
  aliases         = var.aliases
  web_acl_id      = var.waf.enabled ? aws_wafv2_web_acl.this[0].arn : null

  origin {
    domain_name = aws_lb.this.dns_name
    origin_id   = "alb"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
      # 120s is the CloudFront origin-read max without a quota increase. Matches ALB idle default.
      origin_read_timeout = 120
    }

    custom_header {
      name  = local.origin_header_name
      value = local.origin_header_value
    }
  }

  default_cache_behavior {
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    target_origin_id         = "alb"
    viewer_protocol_policy   = "redirect-to-https"
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  dynamic "viewer_certificate" {
    for_each = var.acm_certificate_arn != null ? [1] : []
    content {
      acm_certificate_arn      = var.acm_certificate_arn
      ssl_support_method       = "sni-only"
      minimum_protocol_version = "TLSv1.2_2021"
    }
  }

  dynamic "viewer_certificate" {
    for_each = var.acm_certificate_arn == null ? [1] : []
    content {
      cloudfront_default_certificate = true
    }
  }

  tags = var.tags
}
