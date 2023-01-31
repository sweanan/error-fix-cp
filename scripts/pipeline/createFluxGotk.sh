cd gitops
echo "createFluxGotk.sh"

for cluster in clusters/*/; do
    echo "cluster: $cluster"
    # cluster: clusters/dev.yaml
    # cluster_name=$(yq '.metadata.labels.aksClusterName' "$cluster")
    # echo "cluster_name: $cluster_name"

    mkdir -p $cluster/flux-system
    if [[ -f $cluster/flux-system/gotk-components.yaml ]] || [[ -f $cluster/flux-system/gotk-sync.yaml ]] || [[ -f $cluster/flux-system/kustomization.yaml ]]; then exit 0; fi
    echo "flux kustomization files not fund, creating..."
    touch $cluster/flux-system/gotk-components.yaml 
    touch $cluster/flux-system/gotk-sync.yaml
    touch $cluster/flux-system/kustomization.yaml
done