# OpenShift Virtualization — stable-5.0 Overlay

Installs OpenShift Virtualization (CNV/KubeVirt) on **OpenShift Container Platform 5.0**.

## Channel

`stable` — OpenShift Virtualization uses a single `stable` channel that is not OCP-version-specific.
This overlay exists to identify the OCP 5.0–validated configuration.

## OCP 5.0 Notes

- This overlay is functionally equivalent to the base subscription with `stable` channel
- Hardware virtualization extensions (Intel VT-x / AMD-V) are still required on nodes
- Live migration across nodes works on multi-node clusters; not supported on SNO

## Usage

```bash
# For standard (multi-node) deployments on OCP 5.0:
kustomize build gitops/cluster-config/openshift-virtualization/operator/overlays/stable-5.0 | oc apply -f -

# Then apply the HyperConverged instance:
oc apply -f gitops/cluster-config/openshift-virtualization/instance/hyperconverged.yaml
```
