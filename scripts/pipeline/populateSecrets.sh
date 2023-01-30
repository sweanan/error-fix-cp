#!/usr/bin/env bash

# Get all secret files
secret_files=($(find controlplane -iname '*.enc.yaml'))

if [[ -z "$secret_files" ]]; then
    echo "No secrets found to encrypt, stopping..."
    exit 0
fi

for secret_file in "${secret_files[@]}"; do
    secret_name=$(basename "$secret_file" ".enc.yaml")

    # Get matching secret from AKV
    akv_secret_value=$(az keyvault secret show --name "$secret_name" --vault-name "$KEYVAULT_NAME" --query 'value' -o tsv)
    if [[ -z "$akv_secret_value" ]]; then
        echo "No AKV secret matching $secret_name, stopping..."
        exit -1
    fi

    # Write AKV secret value to matching file
    echo "Populating secret: $secret_file"
    echo "$akv_secret_value" | base64 --decode > "$secret_file"
done
