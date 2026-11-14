# RHACM Operator — stable-5.0 Overlay

Installs Red Hat Advanced Cluster Management (ACM) 5.0 on **OpenShift Container Platform 5.0**.

## Channel

`stable-5.0` — confirmed from ACM 5.0 release notes.

The legacy `release-5.0` channel is also supported for compatibility.

## Usage

```bash
kustomize build gitops/cluster-config/rhacm-operator/overlays/stable-5.0 | oc apply -f -
```

Then deploy the MultiClusterHub instance:

```bash
oc apply -k gitops/cluster-config/rhacm-instance/overlays/basic
```
