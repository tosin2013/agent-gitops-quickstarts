# ODF Operator — stable-5.0 Overlay

Installs OpenShift Data Foundation on **OpenShift Container Platform 5.0**.

## OCP 5.0 Requirements

- **RHCOS 10** nodes are required (automatically used with OCP 5.0)
- **x86-64-v3+** CPU microarchitecture required for ODF storage nodes
  - Verify: `grep -m1 avx512 /proc/cpuinfo` on each storage node
- Minimum 3 storage nodes with dedicated unformatted disks
- OLM v1 (`ClusterExtension`) is the preferred API in OCP 5.0, but classic
  `Subscription` (used here) remains supported for backward compatibility

## Channel

`stable-5.0`

## Usage

Applied via ArgoCD Application or directly:

```bash
kustomize build gitops/cluster-config/openshift-data-foundation-operator/operator/overlays/stable-5.0 | oc apply -f -
```
