if [[ ! -d clusters ]] || [[ -z "$(ls -A clusters/*.yaml)" ]]; then exit 0; fi
echo "Flux bootstrap.sh"

for cluster in clusters/*.yaml; do
    echo "cluster: $cluster"
    cluster_name=$(yq '.metadata.labels.aksClusterName' "$cluster")
    cluster_rg=$(yq '.metadata.labels.aksClusterResourceGroup' "$cluster")
    cluster_info=$(yq '.metadata.name' "$cluster")
    echo "cluster_info: $cluster_info"


    # Get cluster's k8s credentials
    cluster_creds=$(az aks get-credentials --name "$cluster_name" --resource-group "$cluster_rg" -f -)
    if [[ -z "$cluster_creds" ]]; then
        echo "K8s cluster credentials for $cluster_name in resource group $cluster_rg not found, skipping..."
        continue
    fi

    # Setup kubeconfig for cluster
    echo "$cluster_creds" >cluster_creds
    export KUBECONFIG=cluster_creds

    if [[ -z ${1:-} ]]; then
        echo "Error: No source control parameter passed!"
        echo "Expected either --github or --gitlab"
        exit 1
    else
        source_control=$1
    fi

    echo "Flux bootstrap with AKS"
    if [[ $source_control = "--github" ]]; then
        flux bootstrap github --owner="$GITOPS_REPO_OWNER" \
            --repository="$GITOPS_REPO" \
            --branch=main \
            --path=clusters/$cluster_info \
            --personal \
            --network-policy=false
    elif [[ $source_control = "--gitlab" ]]; then
        flux bootstrap gitlab --hostname="$GITLAB_HOST" \
            --token-auth \
            --owner="$GITOPS_REPO_OWNER" \
            --repository="$GITOPS_REPO_NAME" \
            --branch=main \
            --namespace=flux-system \
            --path=clusters/$cluster_info
    fi
done