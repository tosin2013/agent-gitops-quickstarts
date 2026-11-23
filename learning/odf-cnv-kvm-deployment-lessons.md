# Deploying ODF + CNV on KVM: Lessons Learned

**Date**: November 2026  
**Environment**: OCP 5.0.1, IBM Cloud KVM, 9-node cluster (3M+6W), workers have 8 vCPUs / 38GB RAM  
**Cluster**: cnv-5-0 on sandbox2401.opentlc.com

---

## Architecture Overview

```
KVM Host (377GB RAM, 48 CPU, /dev/vdb 1.2TB)
├── 3 control plane VMs (12 vCPU, 32GB)
├── 3 ODF worker VMs (8 vCPU, 38GB) + 400GB ODF disk each ← workers 0-2
└── 3 app worker VMs (8 vCPU, 38GB) ← workers 3-5
```

Network: bond0 (802.3ad) + VLAN 1924 (192.168.50.0/24) via VyOS router

---

## Problem 1: ODF Workers Undersized for Combined Workloads

**Symptom**: Load average 20-28 on ODF workers during Ceph initialization. kube-apiserver crashes (`context deadline exceeded`). All operators degrade.

**Root cause**: ODF base services require **10 CPU per node minimum** (30 CPU total across 3 nodes per docs). Our workers only had 8 vCPUs. Combined with Prometheus, OVN, and kubelet, the nodes were oversubscribed.

**Ref**: [ODF 5.0 Resource Requirements](https://docs.redhat.com/en/documentation/red_hat_openshift_data_foundation/5.0/html/planning_your_deployment/infrastructure-requirements_rhodf)

**Fix 1: Move monitoring off ODF nodes**

Label non-ODF workers and configure `ClusterMonitoring`:
```bash
oc label node lab-worker-3 lab-worker-4 lab-worker-5 monitoring-node=true
```

Create `cluster-monitoring-config` ConfigMap in `openshift-monitoring`:
```yaml
prometheusK8s:
  nodeSelector:
    monitoring-node: "true"
  resources:
    limits:
      cpu: 4000m
      memory: 8Gi
  retention: 24h
  retentionSize: 20GB
```

**Fix 2: Increase ODF worker vCPUs** (requires VM restart)

```bash
# For each ODF worker (0-2):
sudo virsh shutdown lab-worker-0
sudo virsh setvcpus lab-worker-0 12 --config --maximum
sudo virsh setvcpus lab-worker-0 12 --config
sudo virsh start lab-worker-0
```

This matches ODF's 10 CPU/node requirement with headroom.

---

## Problem 2: Prometheus Runaway (242% CPU, 932h CPU time)

**Symptom**: Single Prometheus pod consuming 242% CPU for 6+ hours during ODF + CNV simultaneous installation, causing all other workloads to starve.

**Root cause**: Prometheus scraped a large volume of new metrics from ODF, CNV, Pipelines, ArgoCD all installing simultaneously. Without CPU limits, it ran unconstrained.

**Fix**: Resource limits in `ClusterMonitoring` configmap (see Fix 1 above) + node affinity to place Prometheus on lightly-loaded workers.

**Detection**: 
```bash
ssh core@<worker-node> "ps aux --sort=-%cpu | head -5"
```

---

## Problem 3: Incorrect ArgoCD Sync Wave Ordering Caused Cascading Failures

**Original (broken) order:**
- Wave 1: LSO instance + ODF operator + CNV operator (all simultaneously)
- ODF operator started before LSO had provisioned block devices
- ODF console plugin job needed image registry (which was `Removed`)

**Fixed order:**
```
Wave 0: LSO operator
Wave 1: LSO instance + Image registry (emptyDir) + Monitoring config
Wave 2: ODF operator + CNV operator + Pipelines  
Wave 3: ODF instance (StorageCluster)
Wave 4: Image registry with ODF CephFS (100Gi, ReadWriteMany)
Wave 5: CNV instance (HyperConverged)
```

**Key dependency discovered**: On baremetal, the image registry is `Removed` by default. The ODF console plugin job pulls from the internal registry. Enable the registry with `emptyDir` **before** ODF operator installs.

Ref: [OCP 5.0 — Configuring registry for bare metal](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/registry/setting-up-and-configuring-the-registry)

---

## Problem 4: ArgoCD Health Checks Missing — Waves Advance Too Early

**Fix**: Add Lua health checks to the ArgoCD CR so waves only advance when operators are truly healthy, not just created:

```yaml
resourceCustomizations: |
  ocs.openshift.io/StorageCluster:
    health.lua: |
      -- Healthy only when phase == Ready
  hco.kubevirt.io/HyperConverged:
    health.lua: |
      -- Healthy only when Available == True
  local.storage.openshift.io/LocalVolumeSet:
    health.lua: |
      -- Healthy when devices provisioned > 0
```

---

## Expectations When Deploying VMs on this Cluster

Once ODF + CNV are healthy, the cluster can run VMs. Key considerations:

1. **Storage for VMs**: Use `ocs-storagecluster-ceph-rbd` (Block, ReadWriteMany) for VM disks — required for live migration. CephFS is for shared file access, not optimal for VM disks.

2. **Windows VMs**: Requires a dedicated storage class per CNV docs: *"you must create a dedicated storage class for Windows virtual machine disks"*

3. **Live migration**: Requires `ReadWriteMany` PVC access mode. Ceph RBD with RWX is preferred over CephFS for VM disks (better IOPS).

4. **Worker node separation**: Workers 0-2 run ODF Ceph. Workers 3-5 are available for VM workloads. Use node affinity or tolerations to control VM placement.

5. **Resource contention**: Ceph OSDs are CPU-intensive during initial setup. After the cluster stabilizes (~1-2 hours after `StorageCluster` creation), load normalizes to 2-4 on ODF workers.

---

## GitOps Configuration Applied

All fixes are in [agent-gitops-quickstarts](https://github.com/tosin2013/agent-gitops-quickstarts):

| Config | Wave | File |
|---|---|---|
| Monitoring pinned to workers 3-5 | 1 | `gitops/cluster-config/openshift-monitoring/` |
| Image registry (emptyDir) | 1 | `gitops/cluster-config/openshift-image-registry/overlays/emptydir/` |
| ODF operator | 2 | `gitops/cluster-config/apps/kvm-ocp-virt/openshift-data-foundation-operator.yaml` |
| ODF instance (StorageCluster) | 3 | `gitops/cluster-config/apps/kvm-ocp-virt/openshift-data-foundation-instance.yaml` |
| Image registry with ODF CephFS | 4 | `gitops/cluster-config/openshift-image-registry/overlays/odf-cephfs/` |
| HyperConverged (CNV instance) | 5 | `gitops/cluster-config/apps/kvm-ocp-virt/openshift-virtualization-instance.yaml` |
