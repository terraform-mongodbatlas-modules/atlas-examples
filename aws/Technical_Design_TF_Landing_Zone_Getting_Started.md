 # Technical Design: [TF] Landing Zone Getting Started (AWS)
 
 Status: Draft  
 Owners: TBD  
 Last Updated: 2026-02-04
 
 ## Overview
 This document defines the AWS landing-zone example for MongoDB Atlas integrations, mirroring the Azure example structure and validation VM flow. The example uses the `terraform-mongodbatlas-atlas-aws` module for Atlas-AWS integrations and reuses the existing `validate-atlas.sh` script to validate PrivateLink connectivity from a private client instance.
 
 ## Goals
 - Provide a complete AWS example that provisions Atlas + AWS integrations using Terraform.
 - Demonstrate PrivateLink connectivity, encryption at rest (KMS), and backup export (S3).
 - Include a validation VM pattern (EC2 in a private subnet) to verify DNS resolution, connectivity, and basic CRUD.
 - Keep parity with the Azure example in structure and user experience.
 
 ## Non-Goals
 - Production-hardening all AWS networking or security policies.
 - Building a full CI/CD pipeline.
 - Supporting every Atlas AWS integration option in the first iteration.
 
 ## Reference Module
 This example is built around the Atlas AWS module:  
 `terraform-mongodbatlas-atlas-aws`  
 Source: https://github.com/terraform-mongodbatlas-modules/terraform-mongodbatlas-atlas-aws
 
 ## Target Architecture
 ```mermaid
 flowchart LR
   user[Operator] --> tf[Terraform]
   tf --> atlas[MongoDB Atlas Project]
   tf --> aws[Amazon Web Services]
 
   atlas --> cluster[Atlas Cluster]
   aws --> vpc[VPC]
   vpc --> subnets[Private Subnets]
   vpc --> pl[PrivateLink Endpoints]
   vpc --> vm[Validation EC2]
   aws --> kms[KMS Key]
   aws --> s3[S3 Backup Bucket]
 
   cluster --> pl
   cluster --> s3
   cluster --> kms
   vm --> pl
 ```
 
 ## Terraform Composition
 The AWS example mirrors the Azure layout:
 - Root example module (new `aws/` example) that wires Atlas project + cluster + Atlas AWS integrations.
 - Validation VM submodule (new `aws/modules/validation-vm/`) that runs `validate-atlas.sh` inside a private subnet.
 
 Expected root-level modules:
 - Atlas project module (`terraform-mongodbatlas-modules/project/mongodbatlas`)
 - Atlas cluster module (`terraform-mongodbatlas-modules/cluster/mongodbatlas`)
 - Atlas AWS integration module (`terraform-mongodbatlas-atlas-aws`)
 
 ## AWS Integrations (Atlas AWS Module)
 This section maps to the AWS module capabilities and will be reflected in the example:
 
 - **Cloud Provider Access**: IAM role used by Atlas to manage AWS resources on your behalf.
 - **Encryption at Rest (KMS)**: Use existing KMS key or allow the module to create one.
 - **PrivateLink**: Configure one or more VPC endpoints; supports multi-region or single-region patterns.
 - **Backup Export (S3)**: Configure existing bucket or let the module create a secure bucket.
 
 The module supports optional defaults and BYO patterns for each integration.
 
 ## Networking Design
 - Create or use an existing VPC with at least one private subnet per region.
 - Configure security groups to allow the validation VM to reach the PrivateLink endpoint ports.
 - Use private DNS so Atlas PrivateLink hostnames resolve to private IPs from the VPC.
 
 Notes:
 - If Private DNS is managed outside Terraform, document the existing hosted zone and VPC associations.
 - For validation VM access, prefer AWS SSM Session Manager to avoid public IPs or inbound SSH.
 
 ## Validation VM (AWS)
 The validation VM should re-use the existing `validate-atlas.sh` script from the Azure module. The AWS version will:
 - Launch a small EC2 instance (Ubuntu 22.04 or similar) in a private subnet.
 - Use cloud-init/user-data to install:
   - `mongosh`
   - Atlas CLI (optional, for backup validation)
   - `validate-atlas.sh` and a pre-rendered connection string file
 - Create a temporary Atlas database user with `readWriteAnyDatabase` on `admin`.
 
 Access patterns:
 - **Recommended**: AWS SSM Session Manager (no public IP, no inbound SSH).
 - **Optional**: Bastion + SSH if your network requires it.
 
 ## Inputs (Root Example)
 Expected input shape (aligns with Azure example):
 - `atlas_org_id`, `project_name`, `cluster_name`
 - `regions` (Atlas region + AWS subnet/VPC mapping)
 - `ip_access_list` (optional, default empty for PrivateLink-only)
 - `tags`
 - `enable_validation_vm`
 - `validation_vm_ssh_key` (optional; if using Bastion)
 
 The AWS example will map region definitions to:
 - `privatelink_endpoints` and/or `privatelink_endpoints_single_region`
 - KMS configuration for encryption-at-rest
 - S3 configuration for backup export
 
 ## Outputs (Root Example)
 Expected outputs:
 - Atlas project ID, cluster ID
 - Private endpoint connection string (prefer private endpoint SRV)
 - Backup export configuration
 - Validation VM access hints and password/SSM details (if enabled)
 
 ## Deployment Flow
 1. Configure `terraform.tfvars` with Atlas org/project/cluster inputs and AWS networking info.
 2. `terraform apply` provisions Atlas project, AWS integrations, and cluster.
 3. PrivateLink endpoints are created and DNS is configured.
 4. Validation VM is created and cloud-init installs tooling.
 5. Run `./validate-atlas` on the VM.
 
 ## Validation Steps
 - **DNS**: All Atlas hosts resolve to private IPs from the validation VM.
 - **Connectivity**: `mongosh` connects over PrivateLink.
 - **CRUD**: Basic insert/read/update/delete succeeds.
 - **Backup (Optional)**: `atlas backups snapshots list` works if API keys are provided.
 
 ## Security Considerations
 - Keep validation VM private (no public IP).
 - Use SSM Session Manager or a tightly controlled Bastion host.
 - Restrict security groups to the minimum required ports.
 - Store Atlas API keys securely (only set them at runtime on the VM).
 
 ## Cost Considerations
 - EC2 instance costs for validation VM.
 - PrivateLink endpoint hourly costs and data processing.
 - KMS key costs if created by the module.
 - S3 storage costs for backup exports.
 
 ## Risks and Mitigations
 - **DNS misconfiguration**: validate private DNS zone associations with the VPC.
 - **PrivateLink propagation delays**: re-read connection strings via data source.
 - **SSM not available**: ensure VPC endpoints or NAT allow SSM traffic.
 
 ## Troubleshooting
 - If DNS resolves public IPs, verify the Private DNS zone and VPC association.
 - If `mongosh` fails, ensure the cluster is not paused and PrivateLink is `AVAILABLE`.
 - Check cloud-init logs on the VM for tool installation issues.
 
 ## Next Steps
 - Implement the AWS example folder (`aws/`) mirroring Azure layout.
 - Add `aws/modules/validation-vm/` using the same `validate-atlas.sh`.
 - Document required AWS prerequisites (VPC, subnets, IAM).
