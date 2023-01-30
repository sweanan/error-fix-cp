# Secret Management

**Author:** Marshall Bentley
**Date:** 10/25/2022

## Overview

This control plane follows GitOps principles which rely on infrastructure as code (IaC) and elevate source / version control as the single source of truth.  Ideally, all resources are defined in the source code repository and commits are used as the driver of change.  This philosophy begins to break down however, when it comes to secret management as secrets cannot traditionally be stored in source control without being compromised.  We are able to overcome this issue by encrypting secrets and storing the encrypted files in source control.  Doing this preserves alignment with GitOps as all resources, including secrets, are maintained in source control.

The following secret management documentation is specific to the Cloud Native control-plane implementation which can operate in connected cloud, edge, disconnected and air-gapped environments.

## Mozilla SOPS

Mozilla [SOPS](https://github.com/mozilla/sops) (Secrets OPerationS) is a command line application that supports encrypting and decrypting files as well as specific values within those files.  We use it, along with the [AGE](https://github.com/FiloSottile/age) encryption library, to encrypt secret files before placing them under source control as well to decrypt them after they're deployed to the Kubernetes cluster.

## SOPS and Flux

This control-plane configures Flux to use SOPS as its decryption provider.  Doing this allows Flux to automatically detect and decrypt encrypted secrets when deployed to the cluster.  The following config is only shown for understanding.  It is applied and ready to use out of the box.

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1beta2
kind: Kustomization
metadata:
  name: flux-system
spec:
  decryption:
    provider: sops
    secretRef:
      name: sops-age
```

## Bitnami Sealed Secrets

The disconnected deployment scenario using Zarf does not include Flux.  Since SOPS depends on Flux to provide automatic in-cluster decryption functionality, the disconnected scenario instead uses Bitnami Sealed Secrets for secret management.  Sealed Secrets (SS) and SOPS have similar workflows.  Both use asymmetric certs / keys to provide encryption functionality, provide a command line tool which performs file encryption and perform automatic secret in-cluster decryption.  The main difference is SOPS depends on Flux for in-cluster decryption, while SS uses a controller pod installed in the cluster using a [Helm chart](../../manifests/sealed-secrets).

Sealed Secrets 

## Automatic Secret Encryption using Azure Key Vault and CI / CD Pipeline

### Overview / Workflow

This control-plane uses Azure Key Vault (AKV) to store and manage all encryption / decryption keys and secret / sensitive values.  Pipeline access to AKV is obtained via Service Principal credentials stored in the `AZURE_CREDENTIALS` pipeline secret variable.  This approach establishes conventions which must be followed to function correctly.  After creating AKV, a Service Principal with correct permissions and entering credentials into the `AZURE_CREDENTIALS` pipeline secret variable, the high level automatic encryption workflow is as follows:

1. Empty secret placeholder files are created and committed where needed in the control-plane.  These files should be named following the convention `<secret name>.enc.yaml`, for example `mysecret.enc.yaml`.
2. Raw / unencrypted Kubernetes secret yaml files are created, base64 encoded and stored in AKV secrets with names matching their correspoinding secret.enc.yaml files in the control plane but without the `.enc.yaml` extension.  For example, if an empty / placeholder file `mysecret.enc.yaml` is created in the control-plane, a secret with the name `mysecret` must be created in the configured AKV instance.
3. The CI / CD pipeline is triggered.
4. The pipeline finds all placeholder files in the control plane with a `.enc.yaml` suffix and retrieves the AKV secrets with matching names (hence the importance of the naming convention).  If no such files are found, the secret management flow stops.
5. The pipeline replaces the contents of each placeholder `.enc.yaml` file with the secret value obtained from AKV.
6. The pipeline runs Coral on the control-plane replacing Coral / Mustache variables.
7. The pipeline retrieves the encryption / decryption keys from AKV.
8. The pipeline encrypts each secret `.enc.yaml` file (which now contains the raw secret and has been processed by Coral) and overwrites its raw contents with the encrypted result.
9. The pipeline commits the encrypted files to the GitOps repository.

### File and AKV Secret Naming Conventions

As stated in the Overview / Workflow section, the following naming conventions apply and must be followed.

1. Each empty / placeholder file created in the control-plane must have a `.enc.yaml` extension and be in the format `<secret name>.enc.yaml`, for example `mysecret.enc.yaml`.
2. Each empty / placeholder file created in the control-plane must have a matching secret in AKV where the AKV secret name matches the control-plane's filename without the `.enc.yaml` extension.  For example, if the control-plane secret is `mysecret.enc.yaml`, the AKV would be `mysecret`.

### Base64 Encoding Secrets

All raw secret values stored in AKV must first be base64 encoded.  Base64 encoded secrets should be a single string value, without newlines.  The following command can be used to base64 encode a file without newlines:

```bash
base64 <secret file> -w 0
```

For example, encoding the secret file `templates/istio-service/deploy/secrets.enc.yaml`:

```bash
base64 templates/istio-service/deploy/secrets.enc.yaml -w 0
```

This command generates a base64 encoded string which should then be entered as the AKV secret's value.

## Secret Variables in CI / CD Pipelines

This control plane uses two secrets in the CI / CD pipeline, `GITOPS_PAT` and `AZURE_CREDENTIALS`.  `GITOPS_PAT` is used by Flux to update the cluster-gitops repository.  `AZURE_CREDENTIALS` is used to connect to Azure Key Vault to manage encryption / decryption keys, control-plane / application secrets and query Kubernetes cluster connection info and credentials used for deploying SOPS keys.

Although not reccomended, it is possible users of this seed might wish to add additional secret variables to extend the pipline.  To achieve this, the reccomended approach is to use the source control platform's implementation to create, manage and reference secrets.  For GitHub, this would be [encrypted-secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets), and for GitLab [secrets](https://docs.gitlab.com/charts/installation/secrets.html).

## Manual Secret Management (Informational Only)

### Manually Collecting SOPS Keys from Azure Key Vault

A SOPS key pair is created as part of the CI / CD pipeline and uploaded to Azure Key Vault.  This AKV secret is created with the name provided in the `SOPS_KEY_NAME` environment variable.  In order to perform cryptographic operations, we need to retrieve that secret and extract the public key from its contents.  The secret's contents will look like:

```bash
# created: 2022-12-20T17:07:50Z
# public key: age1qyytj3h4z0w39h8t5cfd6089607p04smnxw58jmkwa2m8jxcmpcqjqg9jq
AGE-SECRET-KEY-<private key data>
```

First, install sops by running the script from [here](https://github.com/benc-uk/tools-install/blob/master/sops.sh).

For SOPS encryption operations, the value of the `--age` parameter should be the value of the `public key:` line from this secret.  In this example, the value will be `age1qyytj3h4z0w39h8t5cfd6089607p04smnxw58jmkwa2m8jxcmpcqjqg9jq`.

For example, encrypting a secret using with SOPS using this public key:

```bash
sops --encrypt --age 'age1qyytj3h4z0w39h8t5cfd6089607p04smnxw58jmkwa2m8jxcmpcqjqg9jq' --encrypted-regex '^(data|stringData)$' cacerts.yaml > cacerts.enc.yaml
```

### Manually Creating and Deploying Encrypted Secrets

This section describes how to manually perform secret / file encryption and deploy the encrypted resulting files to the cluster.  These steps are provided for information purposes only as secrets are automatically detected and encrypted by the CI / CD pipeline.

After the SOPS keys have been created and deployed to the cluster, we're ready to start creating and encrypting secrets.  The first stop is to create a regular, unencrypted, Kubernetes secret.  For example:

```bash
cat <<EOF > secret.yaml
apiVersion: v1
data:
  username: user1
  password: abc123
kind: Secret
metadata:
  creationTimestamp: null
  name: test-secret
  namespace: my-app
EOF
```

Kubernetes secrets are only accessible within a single namespace.  The namespace specified when creating the secret should be the one containing the apps / resources which will use it.  For example, if you're creating a secret to be used by apps / resources in the `my-app` namespace, the secret should also specify that namespace.

SOPS provides a CLI to encrypt and decrypt files. We will use this CLI going forward to encrypt raw secret files. Install the CLI using instructions [here](https://github.com/mozilla/sops#download).

Next, we will encrypt secret.yaml using SOPS and the public key we created earlier.  Encryption is performed using AGE as indicated by the `--age` flag

```bash
sops --encrypt --verbose --age '<your age public key>' --encrypted-regex '^(data|stringData)$' secrets.yaml > secrets.enc.yaml
```

For example:

```bash
sops --encrypt --verbose --age 'age1qyytj3h4z0w39h8t5cfd6089607p04smnxw58jmkwa2m8jxcmpcqjqg9jq' --encrypted-regex '^(data|stringData)$' secrets.yaml > secrets.enc.yaml
```

The inclusion of the `--encrypted-regex '^(data|stringData)$'` parameter configures SOPS to encrypt only objects under `data` and / or `stringData`, leaving the rest of the object as plain text which can be templated by Coral.

This produces the encrypted file `secret.enc.yaml`:

```yaml
cat secret.enc.yaml
apiVersion: v1
data:
    username: ENC[AES256_GCM,data:eR04eWg=,iv:Yv1jC6LKA9Q4Oi7bPJChiI6s6sdkEhrYwmJH0P85FI4=,tag:DduqeCGvenFhGfa6OTh71w==,type:str]
    password: ENC[AES256_GCM,data:SfeQzbWO,iv:rcQqGLtfdEeYpbcLMog9EOjmWvHPnsbh5Brxdj0zoo0=,tag:TpuJubOX2jef0ErkIpiZKQ==,type:str]
kind: Secret
metadata:
    creationTimestamp: null
    name: test-secret
    namespace: my-app
sops:
    kms: []
    gcp_kms: []
    azure_kv: []
    hc_vault: []
    age:
        - recipient: age1qyytj3h4z0w39h8t5cfd6089607p04smnxw58jmkwa2m8jxcmpcqjqg9jq
          enc: |
            -----BEGIN AGE ENCRYPTED FILE-----
            YWdlLWVuY3J5cHRpb24ub3JnL3YxCi0+IFgyNTUxOSBzbFc3dCtqdnp5cldlZGQy
            SjVtUTBydmpZVys0bXdOeDEzbDJlOTZDZFJRCm5Dd0xMd3RVUkUrYlZxb0pWbUky
            Y1NHdlgwMndSV0xRODk4M1F2a2FlVFkKLS0tIEJTOGRoZjFLQUtZa0c0NlVZUzRQ
            VXJOdlM0anp4ZkwySUJIL1lHdk5CMk0KT7+rcVRC/5HtFMPTrbeJw07w1MQKAEDR
            o+d38DIxFg6sAvhvWcS0MYAxBqXKmaA9KwAgYwk5qWLqlbKdN6fi2g==
            -----END AGE ENCRYPTED FILE-----
    lastmodified: "2022-12-20T17:58:36Z"
    mac: ENC[AES256_GCM,data:4PR3TPWBJkp9t/52bSRoLj0mLheJxiDEu8WiTu6QIUgrMuQGWmNKwFlEE9oIc4OgjPhW6KtJhnnVUZfY4GxEr8DsLuuJLK6VJ5q9r2L3mU2bMJPu/7GhRya00NmzbQ+iquOP5LG3cRDcRrG0jRlMcXgEgn4LtztMgjLuLFJZKNI=,iv:7TkroDIrQqOjjjN0f568Qokd2k0ZIi+BUrZKOTnJ3bk=,tag:BGiSrVI2siVr/mjOHlxxJw==,type:str]
    pgp: []
    encrypted_regex: ^(data|stringData)$
    version: 3.7.3
```

This file can now be committed to the control-plane where it will be deployed to the cluster using Flux.  The control-plane provides the `manifests/secrets` directory to store encrypted secrets.  To deploy the `secret.enc.yaml` file from our example above, copy this file into the `manifests/secrets` directory, then add it to the kustomization.yaml file like so:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ghcr-credentials.enc.yaml
  - secret.enc.yaml
```

Next, commit your changes.  The secret will be deployed to the cluster and automatically decrypted.

> **Warning: Remember to delete the raw / unencrypted `secrets.yaml` file!**

## Deploying Applications

The above example shows secret deployment flow for dialtone services. To deploy application secrets, first follow the same sops workflow above to encrypt secrets, then commit the encrypted file at [templates/istio-service/deploy/secrets.enc.yaml](../../templates/istio-service/deploy/secrets.enc.yaml). More info is available in the istio-service template's [README](../../templates/istio-service/README.md#enable-secret-deployment--injection-via-appyaml). Next, in the application seed, modify its `app.yaml` to turn on secret usage, such as:

```yaml
template: istio-service
deployments:
  dev:
    target: dev
    clusters: 1
    values:
      name: app-name
      versionIndependentName: dotnet-app
      version: v1
      image: xxx
      port: 5000
      secrets: true
      config: |-
        MY_CONFIG: xxx
```

Note the `secrets: true` flag.
