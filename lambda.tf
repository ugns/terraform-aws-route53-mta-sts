resource "aws_iam_role" "lambda" {
  name_prefix        = "origin-response-"
  path               = "/service-role/"
  description        = "${local.sts_fqdn} origin-response secure header Lambda@Edge execution role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags = merge(
    var.additional_tags,
    {
      ManagedBy = "Terraform"
      Changed   = formatdate("YYYY-MM-DD hh:mm ZZZ", timestamp())
    },
  )
}

resource "aws_iam_role_policy" "lambda" {
  name_prefix = "origin-response-policy-"
  role        = aws_iam_role.lambda.id
  policy      = data.aws_iam_policy_document.lambda.json
}

resource "aws_lambda_function" "origin_response" {
  description      = "${local.sts_fqdn} origin-response secure headers"
  function_name    = format("%s-origin-response", replace(local.sts_fqdn, ".", "-"))
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  filename         = data.archive_file.lambda_archive.output_path
  source_code_hash = data.archive_file.lambda_archive.output_base64sha256
  role             = aws_iam_role.lambda.arn
  timeout          = 5
  publish          = true
  tags = merge(
    var.additional_tags,
    {
      ManagedBy = "Terraform"
      Changed   = formatdate("YYYY-MM-DD hh:mm ZZZ", timestamp())
    },
  )
}

data "archive_file" "lambda_archive" {
  type        = "zip"
  source_file = "${path.module}/lambda/index.js"
  output_path = "${path.module}/lambda/s-headers.zip"
}