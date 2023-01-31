if [[ ! -d clusters ]] || [[ -z "$(ls -A clusters/*.yaml)" ]]; then exit 0; fi
echo "createFluxGotk.sh"

for cluster in clusters/*/; do
    echo "cluster: $cluster"
    # cluster: clusters/dev.yaml
    
    mkdir -p ./gitops/clusters/$cluster/flux-system
    if [[ -f ./gitops/clusters/$cluster/flux-system/gotk-components.yaml ]] || [[ -f ./gitops/clusters/$cluster/flux-system/gotk-sync.yaml ]] || [[ -f ./gitops/clusters/$cluster/flux-system/kustomization.yaml ]]; then exit 0; fi
    echo "flux kustomization files not fund, creating..."
    touch ./gitops/clusters/$cluster/flux-system/gotk-components.yaml 
    touch ./gitops/clusters/$cluster/flux-system/gotk-sync.yaml
    touch ./gitops/clusters/$cluster/flux-system/kustomization.yaml
done