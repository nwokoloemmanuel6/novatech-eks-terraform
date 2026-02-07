#!/bin/bash

# =============================================================================
# Prerequisites Installation Script
# Installs: AWS CLI, Terraform, kubectl
# Tested on: Ubuntu/Debian
# =============================================================================

set -e  # Exit on any error

echo "🚀 Installing prerequisites for EKS Terraform project..."
echo "==========================================================="

# Update package list
echo ""
echo "📦 Updating package list..."
sudo apt-get update -y

# Install required dependencies
echo ""
echo "🔧 Installing required dependencies..."
sudo apt-get install -y curl unzip wget gnupg lsb-release

# -----------------------------------------------------------------------------
# Install AWS CLI v2
# -----------------------------------------------------------------------------
echo ""
echo "☁️  Installing AWS CLI v2..."

if command -v aws &> /dev/null; then
    echo "   AWS CLI already installed: $(aws --version)"
else
    curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -q awscliv2.zip
    sudo ./aws/install
    rm -rf awscliv2.zip aws/
    echo "   ✅ AWS CLI installed: $(aws --version)"
fi

# -----------------------------------------------------------------------------
# Install Terraform
# -----------------------------------------------------------------------------
echo ""
echo "🏗️  Installing Terraform..."

if command -v terraform &> /dev/null; then
    echo "   Terraform already installed: $(terraform --version | head -n1)"
else
    # Add HashiCorp GPG key
    wget -qO- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    
    # Add HashiCorp repo
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
    
    # Install Terraform
    sudo apt-get update -y
    sudo apt-get install -y terraform
    echo "   ✅ Terraform installed: $(terraform --version | head -n1)"
fi

# -----------------------------------------------------------------------------
# Install kubectl
# -----------------------------------------------------------------------------
echo ""
echo "☸️  Installing kubectl..."

if command -v kubectl &> /dev/null; then
    echo "   kubectl already installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
else
    # Download latest stable kubectl
    curl -sLO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    
    # Install kubectl
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl
    echo "   ✅ kubectl installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
fi

# -----------------------------------------------------------------------------
# Verify installations
# -----------------------------------------------------------------------------
echo ""
echo "==========================================================="
echo "✅ Installation complete! Versions installed:"
echo ""
echo "   AWS CLI:    $(aws --version 2>/dev/null || echo 'Not found')"
echo "   Terraform:  $(terraform --version 2>/dev/null | head -n1 || echo 'Not found')"
echo "   kubectl:    $(kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null | head -n1 || echo 'Not found')"
echo ""
echo "📝 Next steps:"
echo "   1. Configure AWS: aws configure"
echo "   2. Deploy EKS:    terraform init && terraform apply"
echo "   3. Get kubeconfig: aws eks update-kubeconfig --region us-east-1 --name novatech-dev-cluster"
echo ""
