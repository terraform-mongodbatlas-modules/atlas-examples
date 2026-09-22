resource "aws_ecr_repository" "this" {
  for_each = local.ecr_repositories

  region               = each.value.region
  name                 = each.value.name
  image_tag_mutability = each.value.image_tag_mutability
  force_delete         = each.value.force_delete

  image_scanning_configuration {
    scan_on_push = each.value.scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = var.tags
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = local.ecr_lifecycle_policies

  region     = local.ecr_repositories[each.key].region
  repository = aws_ecr_repository.this[each.key].name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last ${each.value} images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = each.value
      }
      action = { type = "expire" }
    }]
  })
}
