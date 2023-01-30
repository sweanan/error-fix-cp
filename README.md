# Introduction

This control-plane seed provides the "dial tone" infrastructure services to support the Network Observability solution, however, it can be repurposed for use with other Kubernetes-based solutions.  It is built on the [Coral](https://github.com/microsoft/coral) platform and largely follows patterns established there.

## Overview

- `.github/workflows` - Runs a workflow on each push to transform Coral entities into cluster gitops repo YAML to be processed by Flux
- `applications`
  - `<workspace-name>`
    - `ApplicationRegistrations` - defines the `ApplicationRegistrations` for a given workspace ([sample](https://github.com/microsoft/coral/blob/main/docs/samples/ApplicationRegistration.yaml))
    - `ManifestDeployments` - defines the `ManifestDeployments` (dialtone services) for a given workspace
- `assignments` - holds the application:cluster assignments after Coral processes the repo
- `clusters` - defines the `Clusters` in your platform ([sample](https://github.com/microsoft/coral/blob/main/docs/samples/Cluster.yaml))
- `manifests` - holds Kubernetes YAML for use with `ManifestDeployments`
- `templates` - defines the available `ApplicationTemplates` in your platform ([sample](https://github.com/microsoft/coral/blob/main/docs/samples/ApplicationTemplate.yaml))
- `workspaces` - defines the `Workspaces` in your platform ([sample](https://github.com/microsoft/coral/blob/main/docs/samples/Workspace.yaml))

## Getting Started

To get started, see the [platform setup instructions](https://github.com/microsoft/coral/blob/main/docs/platform-setup.md) in the main Coral repo.

Before getting started, please review the official Coral docs.  In particular the docs for [platform setup](https://github.com/microsoft/coral/blob/main/docs/platform-setup.md) and [registering a Kubernetes cluster](https://github.com/microsoft/coral/blob/main/docs/cluster-registration.md).

### Create an Azure Service Principal

The control-plane's CI / CD pipelines uses a service principal to authenticate to Azure to manage SOPS keys in Azure Key Vault and query cluster credentials to deploy those keys.

Create a service principal:

```bash
az ad sp create-for-rbac --name "<your service principal name>" --role contributor \
      --scopes /subscriptions/<your subscription id>/resourceGroups/<your resource group> \
      --sdk-auth
```

For example:

```bash
$ az ad sp create-for-rbac --name "github-actions" --role contributor \
        --scopes /subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/mission-cloud \
        --sdk-auth
{
  "clientId": "22222222-2222-2222-2222-222222222222",
  "clientSecret": "",
  "subscriptionId": "",
  "tenantId": "",
  "activeDirectoryEndpointUrl": "https://login.microsoftonline.us",
  "resourceManagerEndpointUrl": "https://management.usgovcloudapi.net/",
  "activeDirectoryGraphResourceId": "https://graph.windows.net/",
  "sqlManagementEndpointUrl": "https://management.core.usgovcloudapi.net:8443/",
  "galleryEndpointUrl": "https://gallery.usgovcloudapi.net/",
  "managementEndpointUrl": "https://management.core.usgovcloudapi.net/"
}
```

Save the object produced by this command as it will be used to populate the `AZURE_CREDENTIALS` environment variable in the GitHub / GitLab repository.

Note: The SP and the AKS cluster (that will be created in the next steps) should be created under the same resource group

### Create an Azure Key Vault Access Policy

Next, assign this service principal permissions to work with secrets on your Azure Key Vault instance.

```bash
az keyvault set-policy --name <your AKV name> \
                       --resource-group <your resource group> \
                       --spn <your service principal clientId> \
                       --key-permissions all \
                       --secret-permissions all
```

For example, using the service principal created above:

```bash
az keyvault set-policy --name mission-cloud-kv \
                       --resource-group mission-cloud \
                       --spn 22222222-2222-2222-2222-222222222222 \
                       --key-permissions all \
                       --secret-permissions all
```

### Configure Repository Environment Variables

The following environment variables need to be configured on the control-plane repository.

Secrets can be created by following the below steps:

<details>
  <summary>GitHub</summary>

- [GitHub Manual Way](https://docs.github.com/en/actions/security-guides/encrypted-secrets#creating-encrypted-secrets-for-a-repository) Or
- By using [gh secret CLI](https://cli.github.com/manual/gh_secret_set) and `env` file as below
  - Installation details for [gh secret](https://github.com/cli/cli/blob/trunk/docs/install_linux.md#debian-ubuntu-linux-raspberry-pi-os-apt)
  - Create a .envgh in your local with all the env variables. Sample can be found [here](./.envgh.example)
  - Run the command to generate the secrets for your repository `gh secret set -f .envgh -R <githubrepourl>`

</details>

<details>
  <summary>GitLab</summary>

- [GitLab Manual Way](https://docs.gitlab.com/ee/ci/variables/#for-a-project) Or
- By using a [GitLab Rest API](https://docs.gitlab.com/ee/api/project_level_variables.html#create-a-variable)

</details>

NAME | REQUIRED (Y/N) | PURPOSE / EXAMPLE VALUES
--- | --- | ---
AZURE_CLOUD | Y | The Azure cloud environment in which you Key Vault instance is deployed (AzureCloud, AzureUSGovernment, etc.).
AZURE_CREDENTIALS | Y | The service principal credentials created in the [Create an Azure Service Principal](#create-an-azure-service-principal) section which have access to the Azure Key Vault instance. The entire JSON object produced by the `az ad sp create-for-rbac` should be assigned.
AKV_NAME | Y | The name of your Azure Key Vault instance.
SOPS_KEY_NAME | Y | The name of the AKV secret containing the SOPS key.  The reccomended value is `sops-age`, but any desired name can be used.  This secret does not need to exist in AKV.  If it doesn't exist, it will be created with the name configured with this name when the pipeline runs.
SOPS_PUBLIC_KEY | Y | The AGE public key string used encrypt SOPS secrets.  This value is generated when creating an AGE key pair.
SS_PUBLIC_KEY | Y | The public key certificate used to encrypt Sealed Secrets using kubeseal.  This is either generated automatically by the sealed-secrets-controller or is an existing public / private key pair used when deploying Sealed Secrets.
GITOPS_PAT | Y | Your PAT with access to the GitOps repository.  This should have been automatically created by Coral.

### Register Cluster

After deploying this control-plane, the first step to get started is to register a cluster.  Clusters are registered by creating a `kind: Cluster` object as a yaml file in the [clusters directory](./clusters/)  The following labels should be included in the cluster registration:

- aksClusterName: The name of the AKS cluster in which this cluster will run.  This is used to query connection info and credentials when deploying SOPS keys.
- aksClusterResourceGroup: The resource group containing the AKS cluster in which this cluster will run.  This is used to query connection info and credentials when deploying SOPS keys. The yaml file must match the desired cluster name.

For example, if the cluster is named as `usgovvirginia-1`, its registration might look like:

```bash
cat <<EOF > clusters/usgovvirginia-1.yaml
kind: Cluster
metadata:
  name: usgovvirginia-1
  labels:
    cloud: azure
    region: usgovvirginia
    aksClusterName: mission-cloud-aks
    aksClusterResourceGroup: mission-cloud
spec:
  environments:
    - dev
    - prod
EOF
```

After committing these changes, the corresponding files will be created in the gitops repo.  More info can be found in the Coral docs on [registering a cluster](https://github.com/microsoft/coral/blob/main/docs/cluster-registration.md#register-a-cluster).

> **Note:** The pipeline will fail after committing these changes.  That's ok, we havent' finished setting things up.  It will succeed after setup is complete

### Create flux-system Namespace

The `flux-system` namespace needs to be created so SOPS secrets can be deployed and available before Flux attempts to bootstrap the cluster.  Create the `flux-system` namespace:

```bash
kubectl create namespace flux-system
```

### Set Environment Variables

Before proceeding, we need to setup environment variables.  The main list of [required variables](https://github.com/microsoft/coral/blob/main/docs/cluster-registration.md) is in the Coral docs and should take precedence over any listed here.

```bash
export GITHUB_TOKEN="github-token"  # (eg. ghp_ZsPfZbeefLyeCa8deadEmFVupxAZYT285CjY)
export GITHUB_OWNER="username"      # (eg. contoso)
export GITOPS_REPO="repo-name"      # (eg. cluster-gitops)
export CLUSTER_NAME="cluster-name"  # (eg. azure-eastus2-1) note: will install flux-system to your new cluster
```

### Generate Istio Inter-Cluster Certificates

Next, we need to generate Istio certificates for securing both inter-cluster communications.  Instructions can be found in the [Inter-Cluster Certificate Management docs](./docs/design-decisions/certificate-management.md#istio-inter-cluster-certificate-management).

### Generate Istio Gateway Certificates

Next, we need to generate Istio certificates for securing gateway communications.  Instructions can be found in the [Gateway Certificate Management docs](./docs/design-decisions/certificate-management.md#istio-gateway-certificate-management).

### Bootstrap Kubernetes Cluster

The next step is to bootstrap your Kubernetes cluster to sync Flux with your source control repository.

```bash
flux bootstrap github --owner=$GITHUB_OWNER \
  --repository=$GITOPS_REPO \
  --branch=main \
  --path=clusters/$CLUSTER_NAME \
  --personal \
  --network-policy=false
```

## Deployment workflows

<details>
  <summary>GitHub</summary>

### Workflow file

- `.github/workflows` - Runs a workflow for github on each push to transform Coral entities into cluster gitops repo YAML to be processed by Flux
- Initially when the new repo is created by `coral init` using this Network-observability-control-plane-seed, during the repo creation process the CI-CD variable `GITOPS_PAT` gets created which will be used for the github workflow.

</details>

<details>
  <summary>GitLab</summary>

### Workflow file

- `.gitlab-ci.yml` - Runs a workflow for gitlab on each push to transform Coral entities into cluster gitops repo YAML to be processed by Flux

> **Note:**  Workflow for gitlab requires a gitlab runner to be configured. For more info on configuring GitLab Runner, please refer to the [GitLab Runner](./docs/design-decisions/gitlab-runner.md) docs.

### Group Access Token

- Create a Access Token under Group Level under group Setting -> Access Token
- Next use this token value for the ACCESS_TOKEN variable under group Setting -> CI/CD -> Variables `ACESS_TOKEN:value`
- Note: Only group Owner will have permission to perform this action
- This variable will be automatically inherited by all the projects created under this group and can be viewed at Setting -> CICD -> Variables -> Group Variables (inherited)

### In repository's CI/CD setting, add the below variables

Repo action secrets can be modified at Repo -> Settings -> Secrets -> Actions -> New repository secret

NAME | REQUIRED (Y/N) | PURPOSE / EXAMPLE VALUES
--- | --- | ---
GITOPS_REPO_NASME | Y | repo name of the control plane created / `test-control-plane`

</details>

## Dial Tone Services

### Centralized Logging

Centralized logging is an important component of any production-grade infrastructure, but it is especially critical in a containerized architecture. If you’re using Kubernetes to run your workloads, there’s no easy way to find the correct log “files” on one of the many worker nodes in your cluster. Kubernetes will reschedule your pods between different physical servers or cloud instances. Pod logs can be lost or, if a pod crashes, the logs may also get deleted from disk. Without a centralized logging solution, it is practically impossible to find a particular log file located somewhere on one of the hundreds or thousands of worker nodes. For this reason, any production-grade cluster should have its log collector agents configured on all nodes and use a centralized storage.

This control-plane leverages the following components to implement centralized logging:

- [Fluentbit](manifests/fluentbit): Log collection and aggregation
- [Elasticsearch](manifests/elasticsearch): Log storage and search capabilities
- [Kibana](manifests/kibana): Log visualizations

Each component is implemented as a Flux HelmRelease and values are applied via [Coral patches](https://github.com/microsoft/coral/blob/main/docs/platform-patch-manifest.md).

For more info, please refer to the [Centralized Logging](./docs/design-decisions/centralized-logging.md) docs.

### Service Mesh

In order to implement traffic management features such as canary and a / b deployments, the Network Observability control-plane plans to leverage a Service Mesh. A service mesh is a dedicated infrastructure layer that you can add to your applications. It allows you to transparently add capabilities like observability, traffic management, and security, without adding them to your own code. Due to its large number of features and widespread industry adoption, our initial choice is Istio. This spike evaluates Istio, provides an overview of its features and configuration and compares it to other popular technologies such as Linkerd.

This control-plane leverages Istio to implement service mesh using the following components:

- [istio-base](manifests/istio/istio-base-release.yaml): Installs and configures Istio CRDs
- [istiod](manifests/istio/istiod-release.yaml): Installs and configures Istio control-plane
- [istio-gateway](manifests/istio/istio-gateway-release.yaml): Installs and configures Istio ingress gateway

Each component is implemented as a Flux HelmRelease and values are applied via [Coral patches](https://github.com/microsoft/coral/blob/main/docs/platform-patch-manifest.md).

For more info, please refer to the [Service Mesh](./docs/design-decisions/istio-service-mesh.md) docs.

### Observability and Monitoring

This control-plane leverages Prometheus, Grafana, Istio and Zipkin to implement observability.

- [Prometheus](manifests/prometheus): Metric collection and persistence
- [Grafana](manifests/grafana): Metric visualization and dashboards
- [Istio](manifests/istio): Service Mesh and distributed tracing metrics
- [Zipkin](manifests/zipkin): Distributed tracing monitoring and visualizations

Each component is implemented as a Flux HelmRelease and values are applied via [Coral patches](https://github.com/microsoft/coral/blob/main/docs/platform-patch-manifest.md).

For more info, please refer to the [Observability and Monitoring](./docs/design-decisions/observability-monitoring.md) docs.

## Secret Management

For more info, please refer to the [Secret Management](./docs/design-decisions/secret-management.md) docs.

## Certificate Management

In order to use the control-plane, gateway certificates need to be created and deployed to the cluster.

For more info, please refer to the [Certificate Management](./docs/design-decisions/certificate-management.md) docs.

## Service Specific Dashboard Configuration for Grafana

The Platform team(Network Observability control-plane) could be contacted by the Service/App team(net-obs-stats-generator app service) to get the network-observability dashboard configured for them in the control-plane.

Only when the platform team recieves any such requests, the platform team needs to configure the service specific dashboards for the App team. In order to configure the service specific dashboards for App team please do refer to [Configure Service Dashboards](./docs/design-decisions/service-specific-dashboard-configuration.md) docs.

## Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us the rights to use your contribution. For details, visit <https://cla.opensource.microsoft.com>.

When you submit a pull request, a CLA bot will automatically determine whether you need to provide a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions provided by the bot.  You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft trademarks or logos is subject to and must follow [Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks/usage/general).  Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.  Any use of third-party trademarks or logos are subject to those third-party's policies.
