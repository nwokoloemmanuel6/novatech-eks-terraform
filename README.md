# 🚀 NovaTech Kubernetes Platform on AWS

Production-ready Amazon EKS cluster built with Terraform.

## Prerequisites

- [Terraform](https://www.terraform.io/downloads.html) >= 1.0
- [AWS CLI](https://aws.amazon.com/cli/) configured with appropriate credentials
- [kubectl](https://kubernetes.io/docs/tasks/tools/)

## Project Structure

```
eks-terraform-project/
├── backend-setup/          # S3 + DynamoDB for remote state
├── modules/
│   ├── eks/                # Custom EKS cluster module
│   └── node_group/         # Custom node group module
├── k8s/                    # Sample Kubernetes manifests
├── main.tf                 # Root module
├── provider.tf             # AWS provider config
├── backend.tf              # Remote state config
├── variables.tf            # Input variables
├── outputs.tf              # Output values
└── terraform.tfvars        # Variable values
```

## Quick Start

```bash
cd "EKS Cluster Setup"
terraform init
terraform apply
```

That's it! This will create:
- VPC with 2 public subnets across 2 AZs
- EKS cluster with logging enabled
- Managed node group (t3.micro, auto-scaling 1-3 nodes)
- IAM roles and policies
- Admin user for CI/CD

### Configure kubectl

This will create:
- VPC with 2 public subnets across 2 AZs
- EKS cluster with logging enabled
- Managed node group (t3.micro, auto-scaling 1-3 nodes)
- IAM roles and policies
- Admin user for CI/CD

### Step 4: Configure kubectl

```bash
aws eks update-kubeconfig --region us-east-1 --name novatech-dev-cluster
```

### Step 5: Verify Cluster Access

```bash
kubectl get nodes
```

### Step 6: Deploy Sample Workload

```bash
kubectl apply -f k8s/
kubectl get pods
kubectl get svc nginx-demo
```

## Terraform State Commands

```bash
# List all resources in state
terraform state list

# Show details of a specific resource
terraform state show module.vpc.aws_vpc.this[0]
terraform state show module.eks.aws_eks_cluster.this
```

## Cleanup

```bash
# Remove Kubernetes resources
kubectl delete -f k8s/

# Destroy EKS infrastructure
terraform destroy

# Destroy backend (optional)
cd backend-setup && terraform destroy
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `region` | `us-east-1` | AWS region |
| `project_name` | `novatech` | Project identifier |
| `environment` | `dev` | Environment name |
| `cluster_version` | `1.29` | Kubernetes version |
| `node_instance_types` | `["t3.micro"]` | Node instance types |
| `node_desired_size` | `2` | Desired node count |
| `node_min_size` | `1` | Minimum nodes |
| `node_max_size` | `3` | Maximum nodes |

## IRSA (IAM Roles for Service Accounts)

To allow Kubernetes workloads to assume AWS IAM roles:

1. Create an IAM role with a trust policy for the OIDC provider
2. Annotate Kubernetes service account with the role ARN
3. Configure pods to use the service account

Example service account:
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/MyAppRole
```

## Cost Estimate

| Resource | Monthly Cost |
|----------|-------------|
| EKS Control Plane | ~$73 |
| t3.micro nodes | Free tier eligible |
| **Total** | **~$73/month** |

> ⚠️ **Tip**: Destroy resources when not in use to minimize costs.
