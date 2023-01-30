# Istio Service

**Author:** Marshall Bentley
**Date:** 11/29/2022

This template exposes parameters needed for App Teams to deploy an application which is integrated into the Istio service mesh.

## Configuration

Applications will be integrated into the Istio service mesh and will automatically have an Envoy proxy sidecar installed in the pod alongside the application.  A service is created for the application with the name set to the value of the `versionIndependentName` parameter.

This template provides the option to configure the application as a canary deployment by setting the parameter `canary: true`.  Custom environment variables can be configured using the `config` parameter.

## Required Values

These values are required and should be provided regardless of the value of the `canary` parameter:

- name - The application's name.
- versionIndependentName - The application's name, independent of versioning.  The value should be the same for all deployed versions of an app.  For example, if you deploy two versions of the same app, `app-v1` and `app-v2`, the version independent name might be `app`.  This parameter is used to refer to all versions of an application when configuring service mesh routing.
- version - The application's version.
- image - The image specification including tag of the container image to use.
- port - The port on the container where the app can be accessed

## Optional Values

These parameters are optional and should only be provided if needed / used:

- imagePullSecret: Boolean variable which indicates whether an imagePullSecret should be configured.  If enabled, these secrets should be configured by following instructions in the [Configuring ImagePullSecrets section](#configuring-imagepullsecrets).
- secrets: Boolean variable which indicates whether SOPS encrypted secrets will be provided to the control-plane.  If enabled, these secrets should be configured by following instructions in the [Configuring Secrets section](#configuring-secrets).
- config: Environment variables to set on the deployment listed as a single string.  The format is shown in the examples section.

## Canary Values

In addition to the standard required values, these values are required for canary deployments where `canary: true`:

- canary - A boolean flag which which set to true, indicates this version as a canary deployment.
- version - The canary application's version.  For example: `version: "v2"`.
- currentVersion - The original application's version.  For example: `version: "v1"`.
- weight - The percentage of traffic that should be directed to this application and version.
- currentWeight - The percentage of traffic that should be directed to the original application and version.  For example, if this canary version is `weight: 25`, currentWeight might be `currentWeight: 75`.  This would configure 75% of traffic to the current version and 25% to the canary.

## Configuring Secrets

This template supports injecting user defined secrets into the application deployment using secret yaml files stored in Azure Key Vault (AKV).  Secrets are passed to the application / deployment in the form of environment variables.  To enable and configure secrets, follow the steps described below.

### Application Secrets Conventions

### Enable Secret Deployment / Injection via app.yaml

The first step is to enable secret deployment using the `secrets: true` flag in the application's `app.yaml` file.  An example app.yaml enabling secrets might look like:

```yaml
template: istio-service
deployments:
  current:
    target: current
    clusters: 1
    values:
      name: app-v1
      versionIndependentName: dotnet-app
      version: "v1"
      image: ghcr.io/testuser/dotnet-app:main
      port: 5000
      imagePullSecret: true
      secrets: true
      config: "VALIDATION_DIRECTORY: '/var/data/validation'\n  RABBITMQ_HOSTNAME: 'rabbitmq'\n  RABBITMQ_USERNAME: 'rabbit'"
```

### Create Azure Key Vault Secrets

Next, create Kubernetes secret yaml files and store them in AKV.  Several conventions must be followed when creating secret files:

1. If the secret is an application secret, the AKV secret must be named in the format `<application name>-secrets`
2. If the secret is an imagePullSecret, the AKV secret must be named in the format `<application name>-image-pull-secret`
3. If the secret is an application secret, the k8s secret's name must be defined as `name: "{{name}}-secrets"`.
4. If the secret is an imagePullSecret, the k8s secret's name must be defined as `name: "{{name}}-image-pull-secret"`.
5. The k8s secret's namespace must be defined as `namespace: "{{coral.workspace}}-{{coral.app}}"`.
6. The secret must be base64 encoded into a single line string (no newlines) using the steps [here](../../docs/design-decisions/secret-management.md#base64-encoding-secrets)
7. When deploying multiple versions of an application or utilizing canary deployments, AKV secrets should be created for each version.  Each secret should use the value of the name parameter for that deployment defined in app.yaml.  For example, if an app.yaml defines deployments of both `app-v1` and `app-v2`, AKV secrets `app-v1-secrets` and `app-v2-secrets` should be created.

For example, a secret file for the application `app-v1` might look like:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: "{{name}}-secrets"
  namespace: "{{coral.workspace}}-{{coral.app}}"
stringData:
  DB_CONNECTION_STRING: <your pw>
  SQL_SERVER_PASSWORD: <your pw>
  RABBITMQ_PASSWORD: <your pw>
  azurestorageaccountkey: <access-key>
  azurestorageaccountname: <storage-account-name>
```

Values defined in `stringData` are passed to the application deployment in the form on environment variables.  Applications should define any combination of secret keys and values here.  For example:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: "{{name}}-secrets"
  namespace: "{{coral.workspace}}-{{coral.app}}"
stringData:
  DB_CONNECTION_STRING: test-db-connection-string
  SQL_SERVER_PASSWORD: test-sql-server-pw
  RABBITMQ_PASSWORD: test-rabbitmq-pw
  azurestorageaccountkey: <access-key>
  azurestorageaccountname: teststorageaccount
  ...
```

### Create Empty / Placeholder Yaml Files

Next, create an empty yaml file in the control-plane under `templates/istio-service/deploy/` following these conventions:

1. If the secret is an application secret, the placeholder file should be in the format `<application name>-secrets.enc.yaml`.  For example, if the app.yaml defines the application's name as `app-v1`, the placeholder file should be named `templates/istio-service/deploy/app-v1-secrets.enc.yaml`.
2. If the secret is an imagePullSecret, the placeholder file should be in the format `<application name>-image-pull-secret.enc.yaml` suffix.  For example, if the app.yaml defines the application's name as `app-v1`, the placeholder file should be named `templates/istio-service/deploy/app-v1-image-pull-secret.enc.yaml`.
3. When deploying multiple versions of an application or utilizing canary deployments, an empty / placeholder file should be created for each version.  Each placeholder file should use the value of the name parameter for that deployment defined in app.yaml.  For example, if an app.yaml defines deployments of both `app-v1` and `app-v2`, placeholder files `templates/istio-service/deploy/app-v1-secrets.enc.yaml` and `templates/istio-service/deploy/app-v2-secrets.enc.yaml` should be created.

When the CI / CD pipeline runs, the raw secret value will be retrieved from AKV, encrypted, copied into these files and deployed.

### Configuring ImagePullSecrets

Before using this template, determine whether your application requires credentials to pull down its image from your container registry.  If it doesn't, you can skip this section.

In order to deploy your application, an imagePullSecret will need to be created to authenticate to the container registry.  Create your secret and store it in a yaml file, the following is an example creating an imagePullSecret for the GitHub container registry:

```bash
kubectl create secret docker-registry --dry-run=client '{{name}}-image-pull-secret' \
  --namespace='{{coral.workspace}}-{{coral.app}}' \
  --docker-server=ghcr.io \
  --docker-username='testuser' \
  --docker-password='test-pw' \
  --docker-email=testemail -o yaml > image-pull-secret.yaml
```

Next, follow the imagePullSecret version of the steps in the [Configuring Secrets section](#configuring-secrets) to add your ImagePullSecret to AKV and automatically encrypt and deploy it using the CI / CD pipeline.

### Dedicated Application Secrets / Canary Secrets

This template provides a dedicated secret for each application using it.  Secrets are not shared among multiple applications using the same template.  This also applies to multiple versions of the same application (such as when using canary deployments).  When configuring secrets, applications implementing canary deployments should create an empty / placeholder file for both current and canary versions.

## Examples

The following is an example configuring two versions of the `dotnet-app` to be deployed, `app-v1` and `app-v2`.  In this example, `app-v1` is the current version and is deployed from the main branch.  `app-v1` is the canary version and is deployed from the feature branch.  75% of traffic is routed to `app-v1` while 25% is routed to the canary deployment, `app-v2`.

```yaml
template: istio-service
deployments:
  current:
    target: current
    clusters: 1
    values:
      name: app-v1
      versionIndependentName: dotnet-app
      version: "v1"
      image: ghcr.io/testuser/app-v1:main
      port: 5000
      imagePullSecret: true
      secrets: true
      config: "VALIDATION_DIRECTORY: '/var/data/validation'\n  RABBITMQ_HOSTNAME: 'rabbitmq'\n  RABBITMQ_USERNAME: 'rabbit'"
  canary:
    target: canary
    clusters: 1
    values:
      canary: true
      name: app-v2
      versionIndependentName: dotnet-app
      version: "v2"
      weight: 25
      currentVersion: "v1"
      currentWeight: 75
      image: ghcr.io/testuser/app-v1:feature
      port: 5000
      imagePullSecret: true
      secrets: true
      config: "VALIDATION_DIRECTORY: '/var/data/validation'\n  RABBITMQ_HOSTNAME: 'rabbitmq'\n  RABBITMQ_USERNAME: 'rabbit'"
```
