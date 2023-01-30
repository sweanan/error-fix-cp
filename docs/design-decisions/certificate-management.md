# Certificate Management for the Network Observability Solution - Cloud Native

**Author:** Marshall Bentley
**Date:** 12/5/2022

## Overview

This control-plane uses digitial certificates primarily to enable Istio security features.  Certificates are used to secure Istio service mesh communciations with HTTPS / TLS as well as to enable other identity and authentication features.  There are two main types of certificate mechanisms, inter-cluster and gateway.  Inter-cluster certificates are for workloads within the cluster are managed by the Istio Certificate Authority (CA).  A custom root certificate can be provisioned in this CA which is then used to sign all other certificates used within cluster workloads.  Gateway certificates are for securing ingress and egress gateway traffic and are created and deployed seperatly.

## Istio Inter-cluster Certificate Management

Many of Istio's security features rely on digital certificates.  An Istio installation includes its own certificate authority (CA) which runs within the Kubernetes cluster and is managed by Istio.  This CA performs certificate management tasks such as provisioning certificates and fulfilling certificate signing requests (CSR).  By default, the Istio CA generates self-signed root certificates during the first startup after initial deployment.  These root certs are then used to provision dedicated certs for each workload in the cluster which are used, among other things, to enable mTLS communication.

### Istio Custom Certificates

Istio provides several mechanisms to replace its self-signed root certificates with ones provided by an administrator.  Once replaced, these custom root certs are used to sign all other certs in the cluster.  This means that only the root certs need to be replaced to configure custom certs for the entire cluster.  

Istio supports integrating with third-party / external CAs as well as using certificate management frameworks such as [cert-manager](https://istio.io/latest/docs/ops/integrations/certmanager/).  However, due to its simplicity and the requirement of this control-plane to function in disconnected scenarios, we utilize the `cacerts` mechanism.  Istio continually monitors the cluster for a secret named `cacerts`.  This name is special and is hardcoded into Istio.  If a secret with this name is present, Istio abandons its default behavior of creating self-signed certificates and instead uses the certificates stored in this secret.  If the secret is absent, it will continue with the self-signed cert flow.  In order to provision custom certificates, administrators / users of this control-plane should populate the `cacerts` secret with their custom root cert.

### Creating Kubernetes Certificate Secrets

As this control-plane leverages SOPS for secret management, the `cacerts` secret should be created and encrypted as a yaml file and stored in source control.  Flux continually synchronizes the source control repo and will automatically decrypt this secret and deploy it to the cluster.  The data contanted in a `cacerts` secret is as follows:

- ca-cert.pem: the generated intermediate certificates
- ca-key.pem: the generated intermediate key
- cert-chain.pem: the generated certificate chain which is used by istiod
- root-cert.pem: the root certificate

The following is an example of configuring this control-plane to use a custom certificate.

Optional: Create test certificates

```bash
# Create certs dir to store cert files
mkdir certs
cd certs

# Create test root certs
make -f ../scripts/Makefile.selfsigned.mk root-ca

# Create test intermediate certs
make -f ../scripts/Makefile.selfsigned.mk cluster1-cacerts

# Return to parent dir
cd ..
```

Create `cacerts` secret:

```bash
kubectl create secret generic cacerts -n infrastructure --dry-run=client \
    --from-file=ca-cert.pem \
    --from-file=ca-key.pem \
    --from-file=root-cert.pem \
    --from-file=cert-chain.pem \
    -o yaml > cacerts.yaml
```

If you used the optional section to generate test certs, the command would be:

```bash
kubectl create secret generic cacerts -n infrastructure --dry-run=client \
    --from-file=certs/cluster1/ca-cert.pem \
    --from-file=certs/cluster1/ca-key.pem \
    --from-file=certs/cluster1/root-cert.pem \
    --from-file=certs/cluster1/cert-chain.pem \
    -o yaml > cacerts.yaml
```

**Warning: If you created certs, make sure to delete them so they're not accidentally committed to source control!**

### Encrypting Kubernetes Certificate Secrets

You now have the `cacerts` Kubernetes secret containing your custom certs, stored as the yaml file `cacerts.yaml`.  The next step is to encrypt this file using SOPS.

Before performing these steps, collect your SOPS key data using the steps in the [Collecting SOPS Keys from Azure Key Vault doc](./secret-management.md#collecting-sops-keys-from-azure-key-vault).

```bash
sops --encrypt --age '<your SOPS public key>' --encrypted-regex '^(data|stringData)$' cacerts.yaml > cacerts.enc.yaml
```

For example:

```bash
sops --encrypt --age 'age1qyytj3h4z0w39h8t5cfd6089607p04smnxw58jmkwa2m8jxcmpcqjqg9jq' --encrypted-regex '^(data|stringData)$' cacerts.yaml > cacerts.enc.yaml
```

The resulting encrypted secret file `cacerts.enc.yaml` is now ready to be stored in source control.  Move this file to the [manifests/secrets](../../manifests/secrets/) directoy.  The control-plane seed already has a placeholder file at this location.  The encrypted contents can be copied into that file or it can be overwritten with the following:

```bash
mv -f cacerts.enc.yaml manifests/secrets
```

The control-plane should already include this file in the Kustomization but verify it is and add it if needed:

```bash
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - cacerts.enc.yaml
```

Wait a minute for so for Flux to synchronize your changes and deploy the secret to the cluster.  You should eventually see the deployed secret.  If you are following the getting started doc, you will not have deployed yet and this can be ignored.

```bash
kubectl get secret cacerts -n infrastructure
NAME      TYPE     DATA   AGE
cacerts   Opaque   4      1m
```

## Istio Gateway Certificate Management

Istio gateway certificates are used to secure ingress and egress traffic flowing through the cluster gateway.  This section describes how to create and deploy self-signed certificates and assign them to the cluster gateway.  Administrators wishing to use their own certificates my skip creating the self-signed certs and instead substitute their own.

### Creating Self-signed Gateway Certificates

First, create a directory to store the new certificates

```bash
mkdir gw_certs
```

Next, create a self-signed root certificate and key for the Network Observability control-plane.

```bash
openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -subj '/O=Network Observability control-plane/CN=no-control-plane.com' -keyout gw_certs/no-control-plane.com.key -out gw_certs/no-control-plane.com.crt
```

Next, use the root cert to create a certificate and key for the gateway.  Since these are self-signed / test certificates, the gateway will have a different external IP address for each deployment.  Thus, a wildcard certificate is created.

```bash
openssl req -out gw_certs/wildcard.csr -newkey rsa:2048 -nodes -keyout gw_certs/wildcard.key -subj "/CN=*/O=Network Observability control-plane"
openssl x509 -req -sha256 -days 365 -CA gw_certs/no-control-plane.com.crt -CAkey gw_certs/no-control-plane.com.key -set_serial 0 -in gw_certs/wildcard.csr -out gw_certs/wildcard.crt
```

Next, create a Kubernetes TLS secret using the generated wildcard cert and store it in yaml file.

```bash
kubectl create -n infrastructure secret tls gateway-cert --dry-run=client \
  --key=gw_certs/wildcard.key \
  --cert=gw_certs/wildcard.crt \
  -o yaml > gateway-cert.yaml
```

Next, encrypt this yaml secret file with SOPS.  More information on secret management can be found in the [secret management docs](./secret-management.md)

```bash
sops --encrypt --verbose --age 'age1qyytj3h4z0w39h8t5cfd6089607p04smnxw58jmkwa2m8jxcmpcqjqg9jq' --encrypted-regex '^(data|stringData)$' gateway-cert.yaml > gateway-cert.enc.yaml
```

This encrypted `gateway-cert.enc.yaml` file should now be committed to source control in [gateway-cert.enc.yaml](../../manifests/secrets/gateway-cert.enc.yaml) where it will be synchronized to the cluster by Flux, decrypted and used to generate a Kubernetes secret.  A placeholder [gateway-cert.enc.yaml](../../manifests/secrets/gateway-cert.enc.yaml) file already exists in the control plane.  Either paste your file's contents into the existing file or copy over it with your own.  The Istio gateway is already configured to use the `gateway-cert` secret to secure ingress and egress traffic.
