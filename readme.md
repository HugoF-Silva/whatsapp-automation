# My Chatbot on AWS

This monorepo contains three services:

1. **evolution-api**: WhatsApp event listener & router (fixed desired count)
2. **n8n**: Workflow engine (autoscale on CPU >70%)
3. **redis**: Message queue (autoscale on CPU >70%)

All are deployed to AWS Fargate via ECS, behind an ALB.

## Getting Started
1. Fill in `terraform/variables.tf` with your subnets, AZs, and credentials.
2. Run:
   ```bash
   cd terraform
   terraform init && terraform apply