if [[ ! -d clusters ]] || [[ -z "$(ls -A clusters/*.yaml)" ]]; then exit 0; fi
echo "createFluxGotk.sh"

for cluster in clusters/*.yaml; do
    echo "cluster: $cluster"
    cluster_name=$(yq '.metadata.labels.aksClusterName' "$cluster")
    cluster_rg=$(yq '.metadata.labels.aksClusterResourceGroup' "$cluster")

    mkdir -p clusters/$cluster/flux-system
    if [[ -f clusters/$cluster/flux-system/gotk-components.yaml ]] || [[ -f clusters/$cluster/flux-system/gotk-sync.yaml ]] || [[ -f clusters/$cluster/flux-system/kustomization.yaml ]]; then exit 0; fi
    echo "flux kustomization files not fund, creating..."
    touch clusters/$cluster/flux-system/gotk-components.yaml \    
        clusters/$cluster/flux-system/gotk-sync.yaml \
        clusters/$cluster/flux-system/kustomization.yaml
done