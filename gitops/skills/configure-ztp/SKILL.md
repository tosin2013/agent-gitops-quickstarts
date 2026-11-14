---
name: configure-ztp
description: Configure Zero Touch Provisioning (ZTP) spoke clusters via RHACM hub and SiteConfig
version: "1.0"
compatibility:
  ocp: ">=4.9"
  tools: ["oc", "kustomize"]
triggers:
  - "ZTP"
  - "spoke cluster"
  - "zero touch provisioning"
  - "provision spoke"
  - "add managed cluster"
  - "configure ZTP"
  - "site config"
---

# configure-ztp

## Overview

Configures Zero Touch Provisioning (ZTP) to provision bare-metal spoke clusters from a
RHACM hub. ZTP uses the Assisted Installer service on the hub, combined with SiteConfig
CRs, to fully automate bare-metal cluster provisioning from DHCP boot to Day 2 config.

This skill covers SNO spokes (`spoke-sno-ztp`) and 3-node compact spokes (`spoke-3nodes-ztp`).

## Prerequisites

- RHACM hub installed: [[install-acm]] completed
- Hub cluster has network access to spoke bare-metal nodes (IPMI/BMC)
- DNS and DHCP configured for spoke nodes
- Pull secret available in hub cluster
- Spoke nodes meet minimum hardware requirements

## Quick Diagnostics

```bash
# Check RHACM and Assisted Service
oc get mch -n open-cluster-management
oc get agentserviceconfig -n assisted-installer 2>/dev/null || echo "Assisted Installer not configured"

# Check existing spokes
oc get agentclusterinstall -A
oc get clusterdeployment -A
oc get infraenv -A
oc get managedcluster

# Check ZTP agent status for a spoke
oc get agent -A
oc get baremetalhost -A

# Check spoke cluster status
oc get clusterdeployment -A -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.conditions[-1].type}{"\t"}{.status.conditions[-1].reason}{"\n"}{end}'
```

## Steps

### Step 1: Configure the Assisted Installer service

```bash
# Apply the agent-service-config (connected or disconnected)
# Connected (internet access):
oc apply -k gitops/cluster-config/agent-service-config/overlays/connected

# Disconnected (air-gapped):
oc apply -k gitops/cluster-config/agent-service-config/overlays/disconnected
```

### Step 2: Configure spoke manifests

For an SNO spoke, edit the files in `gitops/cluster-config/spoke-sno-ztp/`:

| File | What to configure |
|---|---|
| `AgentClusterInstall.yaml` | Cluster name, API VIP, SSH key, OCP version |
| `ClusterDeployment.yaml` | Pull secret ref, cluster name, base domain |
| `InfraEnv.yaml` | NMState network config, SSH key |
| `BareMetalHost.yaml` | BMC address, credentials, MAC address |
| `NMStateConfig.yaml` | NIC names, IP, gateway, DNS |

For 3-node compact, use `gitops/cluster-config/spoke-3nodes-ztp/` with the same pattern.

### Step 3: Apply the spoke ZTP manifests

```bash
# SNO spoke
oc apply -k gitops/cluster-config/spoke-sno-ztp/

# 3-node compact spoke
oc apply -k gitops/cluster-config/spoke-3nodes-ztp/
```

### Step 4: Monitor provisioning

```bash
# Watch agent registration (node must boot from ISO)
watch oc get agent -A

# Watch ClusterDeployment progress
watch oc get clusterdeployment -A

# Watch AgentClusterInstall conditions
oc describe agentclusterinstall -n <spoke-namespace> <spoke-name>
```

### Step 5: Retrieve kubeconfig after installation completes

```bash
oc get secret -n <spoke-namespace> <spoke-name>-admin-kubeconfig -o jsonpath='{.data.kubeconfig}' | base64 -d > /tmp/spoke-kubeconfig
export KUBECONFIG=/tmp/spoke-kubeconfig
oc get nodes
```

## Verification

```bash
# ClusterDeployment should show Installed: true
oc get clusterdeployment -A -o wide

# ManagedCluster should show Available: true
oc get managedcluster

# Check spoke cluster from hub
oc get managedclusterinfo -A
```

## Common Failure Modes

| Symptom | Root Cause | Fix |
|---|---|---|
| Agent not registering | Spoke node not booting from ISO | Check DHCP lease for spoke MAC; verify ISO URL accessible from spoke |
| `BareMetalHost` in `ProvisioningError` | Invalid BMC credentials or network | Verify: `oc describe baremetalhost -n <ns> <name>` |
| `AgentClusterInstall` validation failure | Wrong number of agents or unmatched MAC | `oc describe agentclusterinstall -A` → check ValidationsFailing field |
| Installation times out | Cluster rendezvous IP unreachable | Check InfraEnv NMState: static IP must route to hub API |
| `ClusterDeployment` stuck at 0% | Assisted Installer pod not running | `oc get pods -n assisted-installer`; check image pull |
| Pull secret invalid | Expired or wrong pull secret | Update secret: `oc create secret generic pull-secret -n <ns> --from-file=.dockerconfigjson=<file>` |
| OCP version mismatch | Requested OCP version not in catalog | Check available versions: `oc get clusterimagesets` |

## Related Skills

- [[install-acm]] — Must be completed first
- [[bootstrap-gitops]] — Foundation for all skills
- [[troubleshoot-argocd]] — If Day 2 config via GitOps fails on spoke
