#!/bin/bash
set -eo pipefail

readonly state_file=controlplane/infrastructure/state

if [[ -f $state_file ]]; then
    state_rg=$(awk '/RESOURCE_GROUP_NAME/  { print $2 }' $state_file)
    state_staccnt=$(awk '/STORAGE_ACCOUNT_NAME/  { print $2 }' $state_file)
    state_acr=$(awk '/ACR_NAME/  { print $2 }' $state_file)
fi

readonly resource_group_name=${RESOURCE_GROUP_NAME:-$state_rg}
readonly staccnt_name=${STORAGE_ACCOUNT:-$state_staccnt}
readonly acr_name=${ACR_NAME:-$state_acr}

declare storage_container_name="zarf-container-local"
declare script_deploy=""

########
# Usage:
# * Create the following $HOME/.env file locally or via the pipeline variables for the script to run
#   * Name: CONTAINER_REGISTRY_URL
#   * Value: Container registry URL eg. <acrname>.azurecr.us
#   * Name: CONTAINER_REGISTRY_ACCESS_TOKEN
#   * Value: Container registry Access Token (Local only)
#   * Name: CONTAINER_REGISTRY_USER
#   * Value: Container registry username eg. <acrname>
#   * Name: RESOURCE_GROUP_NAME
#   * Value: Azure Storage Account Resource Group
#   * Name: STORAGE_ACCOUNT
#   * Value: Azure Storage Account Name in the Resouce Group above
#   * Name: GITOPS_REPO
#   * Value: GitOps repo initialized with this Control Plane
#   * Name: GITHUB_USER
#   * Value: GitHub user with access to the GitOps repo
#   * Name: GITHUB_TOKEN
#   * Value: GitHub user PAT with access to the GitOps repo
########


init () {
    if [[ -z "$GITHUB_SHA" ]]; then
        # Local execution - $HOME/.env required
        export $(grep -v '^#' $HOME/.env | xargs)
    else 
        # Pipeline execution
        repo=$(sed "s/\//\-/g" <<<"${GITHUB_REPOSITORY}")
        storage_container_name="zarf-$repo-$GITHUB_RUN_NUMBER"
        echo $storage_container_name

        # Copy zarf folders from the GitOps repo into the zarf folder (cloned to gitops folder via the pipeline)
        find gitops -type f -name zarf.yaml | while read item; do
            folder=$(echo "${item/$(basename ${item})/""}"    )
            destination="controlplane/zarf/$(echo $(sed "s/ /-/g"  <<<$(echo $folder | awk -F "/" '{print $3,$5,$6}')))"
            mkdir -p $destination && cp -r ${folder}* $destination
        done
        
        # Reanining operations are in the Control Plane repo (cloned to controlplane folder via the pipeline)
        cd controlplane

        echo "ls zarf"
        ls zarf
    fi    
}

login_container_registry () {
    # Zarf login to the Container Registry for private images such as the application build images
    if [[ -z "$acr_name" ]]; then
        if [[ -n "$CONTAINER_REGISTRY_USER" ]] && [[ -n "$CONTAINER_REGISTRY_USER" ]] && [[ -n "$CONTAINER_REGISTRY_USER" ]]; then
            echo "Logging into environment supplied Container Registry $CONTAINER_REGISTRY_URL"
            zarf tools registry login -u ${CONTAINER_REGISTRY_USER} -p ${CONTAINER_REGISTRY_ACCESS_TOKEN} ${CONTAINER_REGISTRY_URL}
        else
            warn="Warning: "
            [[ -n "$GITHUB_SHA" ]] && warn="<span class='CheckStep-warning-text'>Warning: </span>"
            echo "${warn}No container registry information supplied for Zarf images."
        fi
    else
        echo "Logging into Azure Container Registry $acr_name using the SP context"
        az acr login --name $acr_name
    fi
}

set_storage_account_connection_string () {
    # Uses the SP via the pipeline or az login locally, creating a connection to the storage account
    export AZURE_STORAGE_CONNECTION_STRING=$(az storage account show-connection-string -g $resource_group_name  -n $staccnt_name -o tsv)
}

create_blob_container () {
    # Create the Storage Account Container
    echo "Creating Blob Container"
    az storage container create -n ${storage_container_name}
}

clone_gitops_zarf_assets () {
    # Local only, clone the GitOps repo and move Zarf assets to the Zarf folder
    rm -rf gitops
    run_cmd "git clone https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/$GITOPS_REPO.git gitops"
    find gitops -type f -name zarf.yaml | while read item; do
        folder=$(echo "${item/$(basename ${item})/""}"    )
        destination="zarf/gitops-$(echo $(sed "s/ /-/g"  <<<$(echo $folder | awk -F "/" '{print $3,$5,$6}')))"
        mkdir -p $destination && cp -r ${folder}* $destination
    done
    rm -rf gitops    
}

zarf_package_upload () {
    # Creates an individual Zarf package and uploads it to the Storage Account
    local folder=$1
    zarf tools clear-cache
    zarf package create $folder -o $folder --confirm
    package=$(ls $folder | grep tar.zst)
    az storage blob upload -f $folder/$package -c ${storage_container_name} --overwrite true
}

create_upload_zarf_packages () {
    local parallel_create=""

    # Local clone of GitOps assets to Zarf folder
    [[ -z "$GITHUB_SHA" ]] && clone_gitops_zarf_assets

    for folder in ./zarf/*; do
        if [ -d "$folder" ]; then
            if [ -f "$folder/zarf.yaml" ]; then
                echo "Processing Zarf folder $folder"

                if [[ -z "$GITHUB_SHA" ]]; then
                    parallel_create="zarf package create $folder -o $folder --confirm & $parallel_create"
                else
                    # Pipeline creation of individual Zarf packages
                    zarf_package_upload $folder
                fi
            else
                echo "Zarf file in $folder not found!"
            fi
        fi
    done

    # Local parallel creation of Zarf packages
    [[ -z "$GITHUB_SHA" ]] && run_cmd "$parallel_create wait"  

    find zarf -type f -name *.tar.zst | while read item; do
        parallal_upload="az storage blob upload -f $item -c ${storage_container_name} --overwrite true & $parallal_upload"
        echo "${parallal_upload}wait" >./zarf/upload.sh
        file=$(echo "$item" | awk -F"/" '{print $NF}')
        script_deploy=$(echo -e "zarf package deploy $file --no-progress --confirm & \n$script_deploy")
        echo "${script_deploy}wait" >./zarf/deploy.sh
    done    

    [[ -z "$GITHUB_SHA" ]] && run_cmd "$(cat ./zarf/upload.sh)"

    # Helper log output
    echo -e "\nPACKAGES CREATED:"
    find zarf -type f -name *.tar.zst | awk -F"/" '{print $NF}' | sort

    echo -e "\nPACKAGES BATCH DOWNLOAD:"
    echo -e "az storage blob download-batch -d . --pattern *.zst -s $storage_container_name --account-name <replace-with-your-storage-account-name> --account-key <replace-with-your-storage-account-key> --dryrun"

    echo -e "\nDEPLOYMENT SCRIPT:"
    cat ./zarf/deploy.sh

    rm -rf zarf/gitops-*
}

run_cmd() {
  local command=$1
  echo -e "$command \n"
  output=$(eval "$command")
}

init
login_container_registry
set_storage_account_connection_string
create_blob_container
create_upload_zarf_packages