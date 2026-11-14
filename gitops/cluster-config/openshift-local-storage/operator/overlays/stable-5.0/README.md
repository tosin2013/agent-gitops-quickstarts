# Local Storage Operator — stable-5.0 Overlay

Installs the OpenShift Local Storage Operator on **OpenShift Container Platform 5.0**.

## Channel

`stable-5.0`

## Usage

```bash
kustomize build gitops/cluster-config/openshift-local-storage/operator/overlays/stable-5.0 | oc apply -f -
```
