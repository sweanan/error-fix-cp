if [[ ! -d clusters ]] || [[ -z "$(ls -A clusters/*.yaml)" ]]; then exit 0; fi
echo "Flux bootstrap.sh"

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

    echo "Flux bootstrap with AKS"
    flux bootstrap github --owner="$GITOPS_REPO_OWNER" \
        --repository="$GITOPS_REPO" \
        --branch=main \
        --path=clusters/dev \
        --personal \
        --network-policy=false
done