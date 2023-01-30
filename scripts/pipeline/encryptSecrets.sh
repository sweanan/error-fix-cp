#!/usr/bin/env bash

ss=false
encryption_key="$SOPS_PUBLIC_KEY"
no_secrets_error_msg="No secrets found to encrypt, stopping..."

if [[ ! -f ./akv_secrets_map ]]; then
    echo "$no_secrets_error_msg"
    exit 0
fi

source ./akv_secrets_map

if [[ "${#secrets_map[@]}" -eq 0 ]]; then
    echo "$no_secrets_error_msg"
    exit 0
fi

if [[ "$#" -gt 0 ]] && [[ "$1" == "ss" ]]; then
    ss=true
    encryption_key="$SS_PUBLIC_KEY"

    # Install kubeseal
    echo "Installing kubeseal..."
    current_dir=$(pwd)
    mkdir tmp_kubeseal \
        && cd tmp_kubeseal \
        && wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.19.3/kubeseal-0.19.3-linux-arm64.tar.gz \
        && tar xf kubeseal-0.19.3-linux-arm64.tar.gz \
        && mv kubeseal $HOME/.local/bin/kubeseal \
        && chmod +x kubeseal $HOME/.local/bin/kubeseal
    cd "$current_dir"
    rm -rf tmp_kubeseal
fi

if [[ -z "$encryption_key" ]]; then
    echo "Encryption key missing, stopping..."
    exit -1
fi

for secret_file in "${!secrets_map[@]}"; do
    raw_secret="${secrets_map[$secret_file]}"

    # Write raw secret to file
    echo "$raw_secret" > "$secret_file"

    echo "Encrypting secret file: $secret_file"

    if [[ "$ss" == "true" ]]; then
        # Encrypt with Sealed Secrets
        output=$(echo "$encryption_key" | kubeseal --format=yaml --cert=/dev/stdin < "$secret_file")
    else
        # Encrypt with SOPS
        output=$(sops --encrypt --verbose --age "$encryption_key" --encrypted-regex '^(data|stringData)$' "$secret_file")
    fi

    echo "$output" > "$secret_file"
done
