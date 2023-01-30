#!/usr/bin/env bash

if [[ ! -d clusters ]] || [[ -z "$(ls -A clusters/*.yaml)" ]]; then exit 0; fi

# Install yq
wget https://github.com/mikefarah/yq/releases/download/v4.30.6/yq_linux_amd64 -O $HOME/.local/bin/yq &&\
    chmod +x $HOME/.local/bin/yq

# Get SOPS key
sops_key=$(az keyvault secret show --name "$SOPS_KEY_NAME" --vault-name "$KEYVAULT_NAME" --query 'value' -o tsv)
if [[ -z "$sops_key" ]]; then
    echo "SOPS key does not exist in AKV, stopping..."
    exit
fi

for cluster in clusters/*.yaml; do
    cluster_name=$(yq '.metadata.labels.aksClusterName' "$cluster")
    cluster_rg=$(yq '.metadata.labels.aksClusterResourceGroup' "$cluster")

    # Get cluster's k8s credentials
    cluster_creds=$(az aks get-credentials --name "$cluster_name" --resource-group "$cluster_rg" -f -)
    if [[ -z "$cluster_creds" ]]; then
        echo "K8s cluster credentials for $cluster_name in resource group $cluster_rg not found, skipping..."
        continue
    fi

    # Setup kubeconfig for cluster
    echo "$cluster_creds" >cluster_creds
    export KUBECONFIG=cluster_creds

    sops_key_exists=$(kubectl get secret --namespace flux-system sops-age --output name --ignore-not-found=true | wc -l)
    if [[ "$sops_key_exists" -gt "0" ]]; then
        echo "SOPS key secret already exists on cluster ${cluster_name}, skipping secret deployment..."
        continue
    fi

    kubectl delete secret --namespace flux-system --ignore-not-found=true sops-age

    echo "$sops_key" |
        kubectl create secret generic sops-age \
            --namespace=flux-system \
            --from-file=age.agekey=/dev/stdin
done
