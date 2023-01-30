if [[ ! -d clusters ]] || [[ -z "$(ls -A clusters/*.yaml)" ]]; then exit 0; fi
echo "createFluxGotk.sh"

for cluster in clusters/*.yaml; do
    echo "cluster: $cluster"
    # cluster: clusters/dev.yaml
    cluster_name=$(yq '.metadata.labels.aksClusterName' "$cluster")
    cluster_rg=$(yq '.metadata.labels.aksClusterResourceGroup' "$cluster")

    mkdir -p clusters/dev/flux-system
    if [[ -f clusters/dev/flux-system/gotk-components.yaml ]] || [[ -f clusters/dev/flux-system/gotk-sync.yaml ]] || [[ -f clusters/dev/flux-system/kustomization.yaml ]]; then exit 0; fi
    echo "flux kustomization files not fund, creating..."
    touch clusters/dev/flux-system/gotk-components.yaml \    
        clusters/dev/flux-system/gotk-sync.yaml \
        clusters/dev/flux-system/kustomization.yaml
done