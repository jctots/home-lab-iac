#!/usr/bin/env bash
# Setup script for home-lab-iac on Debian
# Installs: SOPS, age

set -e

SOPS_VERSION=$(curl -s https://api.github.com/repos/getsops/sops/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
AGE_VERSION=$(curl -s https://api.github.com/repos/FiloSottile/age/releases/latest | grep '"tag_name"' | cut -d'"' -f4)

echo "Installing sops ${SOPS_VERSION}..."
curl -Lo /usr/local/bin/sops "https://github.com/getsops/sops/releases/download/${SOPS_VERSION}/sops-${SOPS_VERSION}.linux.amd64"
chmod +x /usr/local/bin/sops

echo "Installing age ${AGE_VERSION}..."
curl -Lo /tmp/age.tar.gz "https://github.com/FiloSottile/age/releases/download/${AGE_VERSION}/age-${AGE_VERSION}-linux-amd64.tar.gz"
tar -xzf /tmp/age.tar.gz -C /tmp
mv /tmp/age/age /usr/local/bin/age
mv /tmp/age/age-keygen /usr/local/bin/age-keygen
rm -rf /tmp/age.tar.gz /tmp/age

echo ""
echo "Installed: sops $(sops --version), age $(age --version)"
echo "Next: generate an age key with 'age-keygen -o key.txt', store it securely."
