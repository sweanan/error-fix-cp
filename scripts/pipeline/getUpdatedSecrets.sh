#!/usr/bin/env bash

# Get all secret files (now updated by Coral)
secret_files=($(find gitops -iname '*.enc.yaml'))

if [[ -z "$secret_files" ]]; then
    echo "No secrets found to encrypt, stopping..."
    exit 0
fi

declare -A secrets_map
for secret_file in "${secret_files[@]}"; do
    echo "Updating secret: $secret_file"
    secrets_map["$secret_file"]=$(cat "$secret_file")
done

# Serialize secret map
declare -p secrets_map > akv_secrets_map
