# OpenShift Pipelines Operator — latest-5.0 Overlay

Installs OpenShift Pipelines (Tekton) on **OpenShift Container Platform 5.0**.

## Channel

`latest` — OpenShift Pipelines uses named channels (`latest`, `stable`, `pipelines-X.Y`)
rather than OCP-version-specific channels. The `latest` channel tracks the most recent
Pipelines release compatible with the installed OCP version.

## Usage

```bash
kustomize build gitops/cluster-config/openshift-pipelines-operator/overlays/latest-5.0 | oc apply -f -
```
