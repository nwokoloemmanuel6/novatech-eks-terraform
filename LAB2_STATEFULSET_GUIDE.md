# 🔥 Lab 2: PostgreSQL with ConfigMaps, Secrets & StatefulSet

**Scenario: QuickCart Order Database**

QuickCart needs a PostgreSQL database with configurable settings, secure password storage, persistent disk, and stable network identity.

```
ConfigMap → Non-sensitive config (DB name, user)
Secret → Database password (base64 encoded)
Headless Service → Stable DNS per pod
StatefulSet → PostgreSQL Pod with stable identity
volumeClaimTemplates → Auto-provisioned PVC per replica
```

> [!IMPORTANT]
> This lab assumes you already have a running EKS cluster from Lab 1 with the EBS CSI driver installed and the `quickcart-sc` StorageClass created. If not, follow the Lab 1 guide first (`DEPLOYMENT_GUIDE.md`).

---

## PHASE 1 — Verify Fresh Cluster

**What we're doing:** Confirming the EKS cluster from Lab 1 is healthy and all prerequisites from the previous lab are in place.

### Step 1.1 — Check nodes

```bash
kubectl get nodes
```

> Lists all worker nodes in the cluster and their current status. All should show `Ready`.

All nodes should show `STATUS: Ready`. If not, check your kubeconfig:

```bash
aws eks update-kubeconfig --region us-east-1 --name novatech-dev-cluster
```

> Downloads the cluster credentials and writes them to your `~/.kube/config` file so `kubectl` can authenticate with your EKS cluster.

### Step 1.2 — Check StorageClass exists

```bash
kubectl get sc
```

> Lists all StorageClasses available in the cluster. `sc` is short for `storageclass`.

You should see `quickcart-sc` in the list. This is the StorageClass we created in Lab 1 that uses the EBS CSI driver to dynamically provision gp3 volumes.

### Step 1.3 — Check EBS CSI driver is working

```bash
kubectl get csidrivers
```

> Lists all Container Storage Interface (CSI) drivers installed. The EBS CSI driver allows Kubernetes to dynamically create AWS EBS volumes.

You should see `ebs.csi.aws.com`. If not, refer to Lab 1 Part 3 for CSI driver installation steps.

All three checks pass? Proceed. ✅

---

## PHASE 2 — Create ConfigMap

**What is a ConfigMap?**

A ConfigMap is a Kubernetes object that stores **non-sensitive configuration data** as key-value pairs. Instead of hardcoding values like database names or usernames inside your container image, you externalize them into a ConfigMap. This means:

- You can change config **without rebuilding your image**
- The same image can run in dev, staging, and production with **different configs**
- Configuration is **version-controlled** separately from application code

**What we're storing:** The PostgreSQL database name (`quickcartdb`) and the database user (`quickcartuser`). These are not sensitive — anyone can know them.

### Step 2.1 — Apply the ConfigMap

```bash
kubectl apply -f k8s/lab2-statefulset/postgres-config.yaml
```

> Creates the ConfigMap resource in the cluster from the YAML file. `apply` creates the resource if it doesn't exist, or updates it if it does.

### Step 2.2 — Verify

```bash
kubectl get configmap
```

> Lists all ConfigMaps in the current namespace. You should see `postgres-config` alongside any default ones.

You should see `postgres-config` in the list.

### Step 2.3 — Inspect the data

```bash
kubectl describe configmap postgres-config
```

> Shows the full details of the ConfigMap including all its key-value data pairs, labels, and metadata.

You'll see the key-value pairs in plain text:

```
Data
====
POSTGRES_DB:    quickcartdb
POSTGRES_USER:  quickcartuser
```

This is expected — ConfigMaps store data in **plain text** because they're for non-sensitive configuration. Later, when we create the StatefulSet, Kubernetes will inject these as environment variables into the PostgreSQL container.

---

## PHASE 3 — Create Secret

**What is a Secret?**

A Secret is similar to a ConfigMap, but designed for **sensitive data** like passwords, API keys, and tokens. Key differences from ConfigMaps:

- Values are **base64-encoded** (not encrypted by default, but hidden from casual viewing)
- Kubernetes can restrict access via RBAC so only authorized pods/users can read them
- They can be optionally **encrypted at rest** with additional configuration
- They're transmitted over encrypted connections between API server and nodes

**What we're storing:** The PostgreSQL password (`supersecurepassword`).

> [!WARNING]
> Base64 encoding is **not encryption** — it's just encoding. Anyone with access to the Secret can decode it. In production, you'd enable encryption at rest and use tools like AWS Secrets Manager or Vault.

### Step 3.1 — Apply the Secret

```bash
kubectl apply -f k8s/lab2-statefulset/postgres-secret.yaml
```

> Creates the Secret resource in the cluster. Kubernetes automatically base64-encodes the `stringData` values when storing them.

### Step 3.2 — Verify

```bash
kubectl get secrets
```

> Lists all Secrets in the current namespace. Shows name, type, number of data keys, and age.

You should see `postgres-secret` with type `Opaque`.

### Step 3.3 — Inspect the encoding

```bash
kubectl get secret postgres-secret -o yaml
```

> Outputs the full Secret as YAML. The `-o yaml` flag shows the raw object including the base64-encoded data values.

Notice the password field shows a base64-encoded string — not the plain text. You can decode it to prove it's just encoding:

```bash
kubectl get secret postgres-secret -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 --decode
```

> Extracts just the password field using JSONPath, then pipes it to `base64 --decode` to show the original plain text value.

Output: `supersecurepassword` — proving base64 is encoding, not encryption.

---

## PHASE 4 — Create Headless Service

**What is a Headless Service?**

A normal Kubernetes Service gets a `clusterIP` — a single virtual IP that load-balances across all pods. A Headless Service sets `clusterIP: None`, which means:

- **No load balancing** — DNS returns the direct pod IPs instead
- Each pod gets its own **stable DNS name**: `<pod-name>.<service-name>.<namespace>.svc.cluster.local`
- For our setup: `postgres-0.postgres.default.svc.cluster.local`

**Why StatefulSets need it:** StatefulSets give pods stable identities (`postgres-0`, `postgres-1`, etc.). The Headless Service creates matching DNS entries so clients can connect to a **specific pod** by name, not just any random pod. This is critical for databases — you need to know exactly which instance you're talking to.

### Step 4.1 — Apply the Headless Service

```bash
kubectl apply -f k8s/lab2-statefulset/postgres-headless.yaml
```

> Creates the Headless Service. This gives each StatefulSet pod a unique, stable DNS name instead of a single load-balanced IP.

### Step 4.2 — Verify

```bash
kubectl get svc postgres
```

> Shows the details of the `postgres` Service. `svc` is short for `service`. The `CLUSTER-IP: None` confirms it's headless.

You should see:

```
NAME       TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)    AGE
postgres   ClusterIP   None         <none>        5432/TCP   10s
```

Notice `CLUSTER-IP: None` — that's the signature of a Headless Service. ✅

---

## PHASE 5 — Create StatefulSet

**What is a StatefulSet?**

A StatefulSet is like a Deployment, but for **workloads that need stable identity**. Key differences:

| Feature | Deployment | StatefulSet |
|---------|-----------|-------------|
| Pod names | Random hash (`nginx-7d4f8b6c9-xk2pq`) | Ordered index (`postgres-0`, `postgres-1`) |
| Startup order | All at once (parallel) | One at a time (sequential: 0 → 1 → 2) |
| Storage | All pods share PVC or use `emptyDir` | Each pod gets **its own PVC** via `volumeClaimTemplates` |
| DNS | Requires normal Service | Requires **Headless Service** |
| Delete behavior | PVCs are NOT auto-deleted | PVCs persist even after StatefulSet deletion |

**Why use it for databases?** PostgreSQL stores data on disk. If a pod restarts, it must reconnect to the **same disk** with the **same data**. A Deployment can't guarantee this — StatefulSet can.

**What `volumeClaimTemplates` does:** Instead of manually creating PVCs, the StatefulSet template automatically creates one PVC per replica. Pod `postgres-0` gets PVC `postgres-storage-postgres-0`, pod `postgres-1` gets `postgres-storage-postgres-1`, etc.

**How ConfigMap and Secret connect:** The `envFrom` field injects all key-value pairs from both the ConfigMap and Secret as environment variables into the container. PostgreSQL's official Docker image reads `POSTGRES_DB`, `POSTGRES_USER`, and `POSTGRES_PASSWORD` from environment variables to auto-configure the database on first boot.

### Step 5.1 — Apply the StatefulSet

```bash
kubectl apply -f k8s/lab2-statefulset/postgres-statefulset.yaml
```

> Creates the StatefulSet, which in turn creates the pod `postgres-0`, auto-provisions a PVC, and injects the ConfigMap + Secret as environment variables.

### Step 5.2 — Watch it come up

```bash
kubectl get pods -w
```

> Lists pods and watches for changes in real-time. The `-w` flag keeps the command running and streams updates as pod statuses change.

You'll see `postgres-0` go through: `Pending` → `ContainerCreating` → `Running`.

Press `Ctrl+C` to stop watching once it's `Running`.

---

## PHASE 6 — Observe Stateful Behavior

**What we're verifying:** That the StatefulSet creates pods with stable names and auto-provisions PVCs.

### Step 6.1 — Check pod names

```bash
kubectl get pods
```

> Lists all pods in the current namespace, showing their name, readiness, status, restart count, and age.

You will see:

```
NAME         READY   STATUS    RESTARTS   AGE
postgres-0   1/1     Running   0          2m
```

Notice: `postgres-0` — not a random hash like `postgres-7d4f8b6c9-xk2pq`. That's the **stable identity** a StatefulSet provides. If this pod is deleted, the replacement will also be named `postgres-0`.

### Step 6.2 — Check auto-provisioned PVC

```bash
kubectl get pvc
```

> Lists all PersistentVolumeClaims. Shows whether each PVC is `Bound` to a PV and which StorageClass provisioned it.

You'll see:

```
NAME                         STATUS   VOLUME        CAPACITY   ACCESS MODES   STORAGECLASS   AGE
postgres-storage-postgres-0  Bound    pvc-xxx...    5Gi        RWO            quickcart-sc   2m
```

This PVC was **not created manually** — the StatefulSet's `volumeClaimTemplates` created it automatically. The naming convention is `<template-name>-<pod-name>`.

---

## PHASE 7 — Test Persistence

**What we're proving:** That data survives pod deletion. The StatefulSet recreates the pod and reattaches it to the **same PVC**, so nothing is lost.

### Step 7.1 — Connect to PostgreSQL

```bash
kubectl exec -it postgres-0 -- psql -U quickcartuser -d quickcartdb
```

> Opens an interactive shell inside the `postgres-0` pod and runs the `psql` client. `-i` keeps stdin open, `-t` allocates a terminal. Everything after `--` is the command run inside the container.

This opens an interactive PostgreSQL shell. The credentials (`quickcartuser`, `quickcartdb`) came from the ConfigMap, and the password was handled by the Secret.

### Step 7.2 — Create test data

```sql
CREATE TABLE orders (id SERIAL PRIMARY KEY, product TEXT, quantity INT);
INSERT INTO orders (product, quantity) VALUES ('Laptop', 2);
INSERT INTO orders (product, quantity) VALUES ('Keyboard', 5);
SELECT * FROM orders;
```

> Creates a table called `orders`, inserts two rows, and queries them. `SERIAL` auto-increments the ID. This data is stored on the EBS volume via the PVC.

You should see:

```
 id | product  | quantity
----+----------+----------
  1 | Laptop   |        2
  2 | Keyboard |        5
```

Exit the shell:

```sql
\q
```

> Quits the `psql` interactive shell and returns you to your terminal.

### Step 7.3 — Delete the pod

```bash
kubectl delete pod postgres-0
```

> Forcefully deletes the pod. The StatefulSet controller detects this and automatically recreates a new `postgres-0` pod, reattaching it to the same PVC.

The StatefulSet controller immediately notices the pod is gone and **recreates it** with the same name `postgres-0`, reattaching the same PVC.

### Step 7.4 — Wait and reconnect

```bash
kubectl get pods -w
```

> Watches pods in real-time. You'll see the new `postgres-0` go from `Pending` → `Running`.

Wait until `postgres-0` is `Running` again (`Ctrl+C` to stop). Then reconnect:

```bash
kubectl exec -it postgres-0 -- psql -U quickcartuser -d quickcartdb
```

> Reconnects to the newly created pod. Same PVC means same data.

### Step 7.5 — Verify data survived

```sql
SELECT * FROM orders;
```

> Queries the `orders` table again. If the data is still there, persistence is confirmed.

🔥 **Data is still there.** Same rows, same values. The pod was destroyed and recreated, but the PVC kept the data on the EBS volume. That's real persistence.

```sql
\q
```

---

## PHASE 8 — Scale StatefulSet

**What we're demonstrating:** StatefulSets scale in an **ordered, predictable** way, and each new replica gets its own independent PVC.

### Step 8.1 — Scale up

```bash
kubectl scale statefulset postgres --replicas=2
```

> Tells Kubernetes to scale the StatefulSet to 2 replicas. A new pod `postgres-1` will be created with its own PVC.

### Step 8.2 — Watch the ordered startup

```bash
kubectl get pods -w
```

> Watches pods scale up. `postgres-1` starts only after `postgres-0` is fully ready — that's ordered startup.

You'll see `postgres-1` appear **after** `postgres-0` is fully ready. StatefulSets start pods sequentially (0 → 1 → 2), never in parallel. Press `Ctrl+C` when `postgres-1` is Running.

### Step 8.3 — Check PVCs

```bash
kubectl get pvc
```

> Shows all PVCs. You'll now see two — one per replica, each with its own independent EBS volume.

```
NAME                         STATUS   STORAGECLASS   CAPACITY
postgres-storage-postgres-0  Bound    quickcart-sc   5Gi
postgres-storage-postgres-1  Bound    quickcart-sc   5Gi
```

Each replica got **its own independent PVC and EBS volume**. Data is NOT shared between replicas — each has its own disk. This is essential for databases.

### Step 8.4 — Scale back down

```bash
kubectl scale statefulset postgres --replicas=1
```

> Scales back to 1 replica. `postgres-1` is terminated but its PVC is preserved — Kubernetes never auto-deletes StatefulSet PVCs.

`postgres-1` is terminated, but its PVC (`postgres-storage-postgres-1`) is **NOT deleted**. Kubernetes preserves StatefulSet PVCs so you don't lose data accidentally. If you scale back up, `postgres-1` will reattach to the same PVC.

---

## PHASE 9 — DNS Demonstration

**What we're proving:** The Headless Service creates stable DNS entries that resolve to specific pod IPs.

### Step 9.1 — Launch a debug pod

```bash
kubectl run debug --image=busybox -it --rm -- sh
```

> Creates a temporary pod using the `busybox` image and opens an interactive shell. `--rm` auto-deletes the pod when you exit.

### Step 9.2 — Resolve the StatefulSet DNS

Inside the debug pod:

```bash
nslookup postgres-0.postgres
```

> Performs a DNS lookup for the StatefulSet pod. The Headless Service resolves this to the pod's direct IP address.

You'll see the DNS resolve to the pod's IP address:

```
Name:      postgres-0.postgres.default.svc.cluster.local
Address:   10.0.x.x
```

This is the **stable DNS identity** that the Headless Service + StatefulSet provide. Any application in the cluster can connect to PostgreSQL using `postgres-0.postgres` as the hostname — and it will always reach the correct pod.

Exit the debug pod:

```bash
exit
```

> Exits the debug pod's shell. The pod is automatically deleted because we used `--rm`.

---

## 🧹 Cleanup

To remove all Lab 2 resources:

```bash
kubectl delete -f k8s/lab2-statefulset/
```

> Deletes all resources defined in the YAML files inside the directory — the ConfigMap, Secret, Headless Service, and StatefulSet.

```bash
# Delete the auto-provisioned PVCs (not removed automatically)
kubectl delete pvc -l app=postgres
```

> Deletes PVCs that have the label `app=postgres`. The `-l` flag filters by label. StatefulSet PVCs must be deleted manually.

---

## 🎯 Summary — What This Lab Demonstrated

| Concept | What You Learned |
|---------|-----------------|
| **ConfigMap** | Externalizes non-sensitive config, decouples config from image |
| **Secret** | Stores sensitive data, base64-encoded (not encrypted by default) |
| **StatefulSet** | Stable pod identity, ordered deployment, per-replica storage |
| **Headless Service** | Enables stable DNS names for each StatefulSet pod |
| **volumeClaimTemplates** | Auto-provisions a PVC per replica |
| **Persistence** | Data survives pod deletion via PVC → PV → EBS |

### Architecture

```
ConfigMap (DB name, user) ──┐
                            ├──→ StatefulSet (postgres-0) ──→ PVC ──→ PV ──→ EBS Volume
Secret (DB password) ───────┘         ↑
                              Headless Service (stable DNS)
```
