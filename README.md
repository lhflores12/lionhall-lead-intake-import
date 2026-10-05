# lionhall-lead-intake-import

Terraform that absorbs the **original, hand-built** `lionhall-lead-intake` AWS
resources (created via the AWS Console on Oct 1, 2026, before any Terraform
existed in this account) into Terraform state — without destroying or
recreating anything.

This is a different exercise from `lionhall-lead-intake-iac`, which
deliberately deploys a **parallel**, Terraform-native copy of this same
pattern (`lionhall-lead-intake-tf`) to avoid any risk to the live demoed
project. This project does the opposite, and harder, thing: writing HCL
that matches infrastructure someone *else* already built by hand, then
running `terraform import` resource by resource until `terraform plan`
shows zero drift.

This is a real, common on-the-job scenario: inheriting infrastructure
nobody wrote as code, and bringing it under management without an outage
or a rebuild.

## What's being imported

| Resource | Real AWS identifier |
|---|---|
| `aws_iam_role.lead_intake` | `lionhall-lead-intake-role-80t9ar4w` |
| `aws_iam_policy.lead_intake_basic_execution` | `arn:aws:iam::438456517866:policy/service-role/AWSLambdaBasicExecutionRole-d43b399f-6c92-43b6-a645-25094817ec42` |
| `aws_iam_role_policy_attachment.lead_intake_basic_execution` | role + policy ARN |
| `aws_iam_role_policy.lead_intake_dynamodb_putitem` | inline policy `LeadIntake-DynamoDB-PutItem` |
| `aws_dynamodb_table.lead_intake` | table `LeadIntake` |
| `aws_lambda_function.lead_intake` | function `lionhall-lead-intake` |

**Note: no API Gateway here.** The original Oct 1 API Gateway trigger
(`lionhall-lead-intake-api`, endpoint `kz3u0lfj0h...`) no longer exists in
the account — only the Terraform-managed `lionhall-lead-intake-tf-api` from
the separate IaC project does. So this import is narrower than the full
original stack: it's the Lambda, its IAM role, and the DynamoDB table —
not a full API-fronted service. That's a realistic shape for this kind of
work: you often inherit partial infrastructure, not a complete matching
system.

## Setup: build the deployment package

The Lambda source code itself already exists and is version-controlled in
the sibling repo `lionhall-serverless-lead-intake` (the same code that's
live and deployed right now). Rather than duplicate that source here, pull
it in at build time:

```bash
mkdir -p build
cp ~/Projects/lionhall-serverless-lead-intake/src/lambda_function.py build/
cp ~/Projects/lionhall-serverless-lead-intake/src/validation.py build/
cd build && zip lambda.zip lambda_function.py validation.py && cd ..
```

## Running the import

```bash
terraform init

terraform import aws_iam_role.lead_intake lionhall-lead-intake-role-80t9ar4w

terraform import aws_iam_policy.lead_intake_basic_execution \
  arn:aws:iam::438456517866:policy/service-role/AWSLambdaBasicExecutionRole-d43b399f-6c92-43b6-a645-25094817ec42

terraform import aws_iam_role_policy_attachment.lead_intake_basic_execution \
  lionhall-lead-intake-role-80t9ar4w/arn:aws:iam::438456517866:policy/service-role/AWSLambdaBasicExecutionRole-d43b399f-6c92-43b6-a645-25094817ec42

terraform import aws_iam_role_policy.lead_intake_dynamodb_putitem \
  lionhall-lead-intake-role-80t9ar4w:LeadIntake-DynamoDB-PutItem

terraform import aws_dynamodb_table.lead_intake LeadIntake

terraform import aws_lambda_function.lead_intake lionhall-lead-intake

terraform plan
```

The goal is a `terraform plan` with **no changes**. If something is still
different, that's the real exercise: read the diff, decide whether the HCL
is wrong (fix it to match reality) or the live resource should actually
change (apply it), and iterate until `plan` is clean.

## A drift to expect, and why

`terraform plan` will very likely flag `source_code_hash` on
`aws_lambda_function.lead_intake` as changed, even though the code is
functionally identical to what's deployed. This isn't a mistake — it's a
well-known Terraform/Lambda nuance: AWS stores the deployed ZIP internally
and Terraform's `source_code_hash` is computed from *your local* ZIP file.
Unless that ZIP is byte-for-byte identical to the one AWS built (same
compression, same file order, same timestamps), the hash won't match, even
when every line of source code is the same.

Two reasonable ways to handle it, your call once you see the real plan
output:
1. **Apply it anyway.** It redeploys the exact same source as a new
   version — functionally a no-op, just a new `$LATEST` revision.
2. **Add a `lifecycle { ignore_changes = [source_code_hash] }` block** to
   the resource if you'd rather Terraform stop flagging it and treat code
   deploys as something that happens outside this particular `apply`
   (reasonable if `lionhall-serverless-lead-intake`'s own Git workflow
   stays the real deployment path for this function going forward).

Either is a legitimate, documented answer. Neither is a sign something
went wrong.
