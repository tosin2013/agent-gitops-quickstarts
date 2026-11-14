# Local Storage Instance — demo-redhat Overlay (Template)

This overlay was originally created for Red Hat Labs environments with nodes named
`lab-worker-0`, `lab-worker-1`, and `lab-worker-2`. The node names are hardcoded in
`kustomization.yaml`.

## To use this for a different cluster

1. Copy this directory to a new overlay name matching your environment:
   ```bash
   cp -r overlays/demo-redhat overlays/my-cluster
   ```

2. Edit `overlays/my-cluster/kustomization.yaml` and replace the node name values:
   ```yaml
   values:
     - lab-worker-0    # ← change to your node names
     - lab-worker-1
     - lab-worker-2
   ```

3. Apply with: `oc apply -k overlays/my-cluster`

## Automatic overlay generation

`configure-redhat-labs.sh` generates a temporary overlay at runtime based on the
actual node names (detected via `oc get nodes` or supplied via `--nodes`). You don't
need to create a permanent overlay unless you want to commit it to the repo.

After a successful run with `--learn`, the **learn-environment** agent will automatically
create a named overlay for your node naming pattern and commit it.
