#!/usr/bin/env bash

# Check if SOPS secret exists
sops_secret_exists=$(az keyvault secret list --vault-name "$KEYVAULT_NAME" --query "contains([].name, '$SOPS_KEY_NAME')")

if [[ "$sops_secret_exists" == "true" ]]; then
    echo "SOPS keys already exist in AKV, skipping key generation..."
    exit 0
fi

# Generate AGE keys
wget -O age-keygen.tar.gz https://dl.filippo.io/age/v1.0.0?for=linux/amd64
tar -xf age-keygen.tar.gz
age/age-keygen -o age.agekey

# Store AGE private key in AKV as a secret
az keyvault secret set --name "$SOPS_KEY_NAME" --vault-name "$KEYVAULT_NAME" --encoding base64 --value "$(cat age.agekey)" >/dev/null
