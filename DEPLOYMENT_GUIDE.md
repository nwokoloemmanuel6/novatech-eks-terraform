# 🚀 NovaTech EKS — Full Lab Deployment Guide

**Lab: Production-Style Ingress + Persistent Storage**
QuickCart File Upload Service on Amazon EKS.

```
Internet → LoadBalancer → NGINX Ingress → ClusterIP Service → Pod → PVC → PV → CSI → Cloud Disk
```

---

## PART 1 — Spin Up the EKS Cluster

### Step 1.1 — Prerequisites

| Tool | Check | Install |
|------|-------|---------|
| **AWS CLI v2** | `aws --version` | [Install](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) |
| **Terraform ≥ 1.0** | `terraform --version` | [Install](https://developer.hashicorp.com/terraform/install) |
| **kubectl** | `kubectl version --client` | [Install](https://kubernetes.io/docs/tasks/tools/) |
| **Helm** | `helm version` | [Install](https://helm.sh/docs/intro/install/) |

> [!TIP]
> On Ubuntu/Debian: `chmod +x install-prerequisites.sh && ./install-prerequisites.sh`

### Step 1.2 — Configure AWS Credentials

```bash
aws configure
```

> Launches the AWS CLI setup wizard to store your access key, secret key, default region, and output format in `~/.aws/credentials`.

| Prompt | Value |
|--------|-------|
| Access Key ID | Your IAM key |
| Secret Access Key | Your IAM secret |
| Region | `us-east-1` |
| Output format | `json` |

Verify: `aws sts get-caller-identity`

### Step 1.3 — Initialize & Deploy EKS

```bash
cd "EKS Cluster Setup"
terraform init
terraform plan
terraform apply
```

> `cd` navigates to the project directory. `terraform init` downloads provider plugins and modules. `terraform plan` previews what will be created. `terraform apply` creates all the AWS resources.

Type **`yes`** when prompted.

> [!IMPORTANT]
> Takes **10–15 minutes**. Do not interrupt.

### Step 1.4 — Configure kubectl

```bash
aws eks update-kubeconfig --region us-east-1 --name novatech-dev-cluster
```

> Downloads the cluster credentials and writes them to `~/.kube/config` so `kubectl` can authenticate with the EKS cluster.

### Step 1.5 — Verify cluster is ready

```bash
kubectl get nodes
```

> Lists all worker nodes in the cluster. All should show `STATUS: Ready` before proceeding.

If nodes appear in `Ready` status, proceed. ✅

---

## PART 2 — Install NGINX Ingress Controller

### Step 2.1 — Add Helm repo

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
```

> `helm repo add` registers the official NGINX Ingress Helm chart repository. `helm repo update` fetches the latest chart versions from all registered repos.

### Step 2.2 — Install NGINX Ingress

```bash
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace
```

> Installs the NGINX Ingress Controller into a dedicated `ingress-nginx` namespace. `--create-namespace` creates the namespace if it doesn't exist.

### Step 2.3 — Verify

```bash
kubectl get pods -n ingress-nginx
```

> Lists pods in the `ingress-nginx` namespace. The `-n` flag targets a specific namespace. The controller pod should be `Running`.

Then check the external LoadBalancer:

```bash
kubectl get svc -n ingress-nginx
```

> Lists services in the `ingress-nginx` namespace. Shows the LoadBalancer's `EXTERNAL-IP` — your cluster's entry point from the internet.

You should see `TYPE: LoadBalancer` with an `EXTERNAL-IP` (may show `<pending>` for 1-2 min, then a real hostname/IP). That external IP is your cluster entry point.

---

## PART 3 — Storage Setup (PVC + CSI)

### Step 3.1 — Verify CSI Driver

```bash
kubectl get csidrivers
```

> Lists all Container Storage Interface (CSI) drivers installed in the cluster. Look for `ebs.csi.aws.com`.

If you see `ebs.csi.aws.com` in the output, skip to **Step 3.2**. Otherwise, follow the steps below to install it.

### Step 3.1a — Create an IAM OIDC provider for the cluster

EBS CSI uses IAM Roles for Service Accounts (IRSA), which requires an OIDC provider:

```bash
eksctl utils associate-iam-oidc-provider \
  --region us-east-1 \
  --cluster novatech-dev-cluster \
  --approve
```

> Creates an IAM OIDC identity provider for the cluster. This allows Kubernetes service accounts to assume AWS IAM roles (IRSA), which the EBS CSI driver needs.

> [!NOTE]
> **If you don't have `eksctl`, install it first:**
>
> **Linux:**
> ```bash
> curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz"
> tar -xzf eksctl_Linux_amd64.tar.gz -C /tmp
> sudo mv /tmp/eksctl /usr/local/bin
> eksctl version
> ```
>
> **macOS (Homebrew):**
> ```bash
> brew tap weaveworks/tap
> brew install weaveworks/tap/eksctl
> eksctl version
> ```
>
> **Windows (PowerShell):**
> ```powershell
> choco install eksctl
> eksctl version
> ```

### Step 3.1b — Create the EBS CSI Driver IAM Role

```bash
eksctl create iamserviceaccount \
  --region us-east-1 \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --cluster novatech-dev-cluster \
  --role-name AmazonEKS_EBS_CSI_DriverRole \
  --role-only \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve
```

> Creates an IAM role with the `AmazonEBSCSIDriverPolicy` attached. This role allows the EBS CSI driver to create, attach, and delete EBS volumes on your behalf.

### Step 3.1c — Install the EBS CSI add-on

Get your AWS account ID first:

```bash
aws sts get-caller-identity --query Account --output text
```

> Returns just your 12-digit AWS account ID. You'll need this in the next command.

Then install the add-on (replace `<ACCOUNT_ID>` with your actual account ID):

```bash
aws eks create-addon \
  --cluster-name novatech-dev-cluster \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn arn:aws:iam::<ACCOUNT_ID>:role/AmazonEKS_EBS_CSI_DriverRole \
  --region us-east-1
```

> Installs the EBS CSI driver as a managed EKS add-on and links it to the IAM role so it has permissions to manage EBS volumes.

Wait a minute, then verify it's active:

```bash
aws eks describe-addon \
  --cluster-name novatech-dev-cluster \
  --addon-name aws-ebs-csi-driver \
  --region us-east-1 \
  --query "addon.status"
```

> Checks the installation status of the add-on. Should return `"ACTIVE"` when ready.

Should return `"ACTIVE"`. Now confirm the driver is present:

```bash
kubectl get csidrivers
```

> Confirms the CSI driver is now registered in the cluster.

You should see `ebs.csi.aws.com`. ✅

### Step 3.2 — Create StorageClass

```bash
kubectl apply -f k8s/StroageClass.yaml
```

> Creates a StorageClass named `quickcart-sc` that tells Kubernetes to use the EBS CSI driver and provision gp3 volumes.

This creates `quickcart-sc` using the EBS CSI driver with gp3 volumes.

### Step 3.3 — Create PersistentVolumeClaim

```bash
kubectl apply -f k8s/pvc.yaml
```

> Creates a PersistentVolumeClaim requesting 5Gi of storage from the `quickcart-sc` StorageClass.

Verify:

```bash
kubectl get pvc
```

> Lists all PersistentVolumeClaims and their current status (`Pending` or `Bound`).

You should see `STATUS: Pending` — this is normal! Because the StorageClass uses `volumeBindingMode: WaitForFirstConsumer`, the PV won't be provisioned until a Pod that uses the PVC is actually scheduled. It will become `Bound` after we deploy the app in Part 4.

---

## PART 4 — Deploy App with Volume Mount

### Step 4.1 — Apply deployment

```bash
kubectl apply -f k8s/nginx-mount.yaml
```

> Creates the Deployment that runs an NGINX container with the PVC mounted at `/usr/share/nginx/html/uploads` for file persistence.

This deploys `quickcart-app` with nginx, mounting the PVC at `/usr/share/nginx/html/uploads`.

### Step 4.2 — Verify PVC is now Bound

```bash
kubectl get pvc
```

> Checks PVC status again — now that a pod is using it, it should show `Bound`.

Now that a Pod is consuming the PVC, it should show `STATUS: Bound` — the PV was dynamically provisioned and a cloud disk was created by CSI. ✅

```bash
kubectl get pods
kubectl describe pod <pod-name>
```

> `get pods` lists all pods and their names. `describe` shows full details including volume mounts, events, and container status.

You'll see the volume attached in the output.

### Step 4.3 — Test persistence

```bash
# Exec into the pod
kubectl exec -it <pod-name> -- /bin/bash
```

> Opens an interactive bash shell inside the running pod.

```bash
# Create a test file
echo "Persistent file test" > /usr/share/nginx/html/uploads/test.txt
exit
```

> Creates a file on the persistent volume and exits the pod.

```bash
# Delete the pod (Deployment will recreate it)
kubectl delete pod <pod-name>
```

> Deletes the pod. The Deployment controller automatically recreates a new one and reattaches the same PVC.

```bash
# Wait for new pod, then check the file still exists
kubectl exec -it <new-pod-name> -- cat /usr/share/nginx/html/uploads/test.txt
```

> Reads the file from the new pod. If it prints the content, the data persisted across pod recreation.

🔥 File is still there — that's real persistence.

---

## PART 5 — Create ClusterIP Service

```bash
kubectl apply -f k8s/quickcart-service.yaml
```

> Creates a ClusterIP Service that routes internal cluster traffic to pods with the `quickcart` label on port 80.

This creates `quickcart-service` (ClusterIP) routing internal traffic to quickcart pods on port 80.

---

## PART 6 — Create Ingress Resource

```bash
kubectl apply -f k8s/ingress.yaml
```

> Creates an Ingress resource that routes external traffic from `quickcart.local` through the NGINX Ingress Controller to the ClusterIP service.

This routes traffic from `quickcart.local` through the NGINX Ingress Controller to the ClusterIP service.

---

## PART 7 — Access the App

### Step 7.1 — Get the external IP

```bash
kubectl get svc -n ingress-nginx
```

> Shows the NGINX Ingress Service with its `EXTERNAL-IP` — the AWS LoadBalancer hostname you'll use to access the app.

Copy the `EXTERNAL-IP` value.

### Step 7.2 — Update your hosts file

The `EXTERNAL-IP` from Step 7.1 is an AWS ELB hostname, but the hosts file requires an **IP address**. Resolve it first:

```bash
nslookup <EXTERNAL-IP-HOSTNAME>
```

> Resolves the AWS ELB hostname to an actual IP address, which is needed for the hosts file entry.

This will return one or more IP addresses. Pick any one of them.

Then add to your hosts file (`/etc/hosts` on Linux/Mac, `C:\Windows\System32\drivers\etc\hosts` on Windows):

```
<RESOLVED-IP>  quickcart.local
```

> [!WARNING]
> AWS ELB IPs can change over time. If `quickcart.local` stops working later, re-run `nslookup` and update the IP.

### Step 7.3 — Open in browser

```
http://quickcart.local
```

NGINX should load. 🎉

---

## 💸 Cost Awareness

| Resource | Monthly Cost |
|----------|-------------|
| EKS Control Plane | ~$73 |
| t3.micro nodes (×2) | Free tier eligible |
| EBS gp3 (5Gi) | ~$0.40 |
| Load Balancer (Ingress) | ~$16 |
| **Total** | **~$89/month** |

> [!TIP]
> Destroy everything when not in use to avoid charges.

---

## 🧹 Cleanup

```bash
# 1. Delete all K8s resources
kubectl delete -f k8s/
```

> Deletes all Kubernetes resources defined in the `k8s/` directory (Deployments, Services, PVCs, Ingress, etc.).

```bash
helm uninstall ingress-nginx -n ingress-nginx
```

> Removes the NGINX Ingress Controller and its associated AWS LoadBalancer.

```bash
# 2. Wait ~60 seconds for LB to deprovision

# 3. Destroy infrastructure
terraform destroy
```

> Destroys all AWS infrastructure created by Terraform (EKS cluster, VPC, subnets, IAM roles, node groups). Wait for the LB to deprovision first to avoid orphaned resources.

Type **`yes`** when prompted.

> [!CAUTION]
> Always delete the Ingress/LoadBalancer resources **before** `terraform destroy` to avoid orphaned AWS Load Balancers that keep incurring charges.
