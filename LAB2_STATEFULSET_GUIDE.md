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

All nodes should show `STATUS: Ready`. If not, check your kubeconfig:

```bash
aws eks update-kubeconfig --region us-east-1 --name novatech-dev-cluster
```

### Step 1.2 — Check StorageClass exists

```bash
kubectl get sc
```

You should see `quickcart-sc` in the list. This is the StorageClass we created in Lab 1 that uses the EBS CSI driver to dynamically provision gp3 volumes.

### Step 1.3 — Check EBS CSI driver is working

```bash
kubectl get csidrivers
```

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

### Step 2.2 — Verify

```bash
kubectl get configmap
```

You should see `postgres-config` in the list.

### Step 2.3 — Inspect the data

```bash
kubectl describe configmap postgres-config
```

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

### Step 3.2 — Verify

```bash
kubectl get secrets
```

You should see `postgres-secret` with type `Opaque`.

### Step 3.3 — Inspect the encoding

```bash
kubectl get secret postgres-secret -o yaml
```

Notice the password field shows a base64-encoded string — not the plain text. You can decode it to prove it's just encoding:

```bash
kubectl get secret postgres-secret -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 --decode
```

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

### Step 4.2 — Verify

```bash
kubectl get svc postgres
```

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

### Step 5.2 — Watch it come up

```bash
kubectl get pods -w
```

You'll see `postgres-0` go through: `Pending` → `ContainerCreating` → `Running`.

Press `Ctrl+C` to stop watching once it's `Running`.

---

## PHASE 6 — Observe Stateful Behavior

**What we're verifying:** That the StatefulSet creates pods with stable names and auto-provisions PVCs.

### Step 6.1 — Check pod names

```bash
kubectl get pods
```

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

This opens an interactive PostgreSQL shell. The credentials (`quickcartuser`, `quickcartdb`) came from the ConfigMap, and the password was handled by the Secret.

### Step 7.2 — Create test data

```sql
CREATE TABLE orders (id SERIAL PRIMARY KEY, product TEXT, quantity INT);
INSERT INTO orders (product, quantity) VALUES ('Laptop', 2);
INSERT INTO orders (product, quantity) VALUES ('Keyboard', 5);
SELECT * FROM orders;
```

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

### Step 7.3 — Delete the pod

```bash
kubectl delete pod postgres-0
```

The StatefulSet controller immediately notices the pod is gone and **recreates it** with the same name `postgres-0`, reattaching the same PVC.

### Step 7.4 — Wait and reconnect

```bash
kubectl get pods -w
```

Wait until `postgres-0` is `Running` again (`Ctrl+C` to stop). Then reconnect:

```bash
kubectl exec -it postgres-0 -- psql -U quickcartuser -d quickcartdb
```

### Step 7.5 — Verify data survived

```sql
SELECT * FROM orders;
```

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

### Step 8.2 — Watch the ordered startup

```bash
kubectl get pods -w
```

You'll see `postgres-1` appear **after** `postgres-0` is fully ready. StatefulSets start pods sequentially (0 → 1 → 2), never in parallel. Press `Ctrl+C` when `postgres-1` is Running.

### Step 8.3 — Check PVCs

```bash
kubectl get pvc
```

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

`postgres-1` is terminated, but its PVC (`postgres-storage-postgres-1`) is **NOT deleted**. Kubernetes preserves StatefulSet PVCs so you don't lose data accidentally. If you scale back up, `postgres-1` will reattach to the same PVC.

---

## PHASE 9 — DNS Demonstration

**What we're proving:** The Headless Service creates stable DNS entries that resolve to specific pod IPs.

### Step 9.1 — Launch a debug pod

```bash
kubectl run debug --image=busybox -it --rm -- sh
```

### Step 9.2 — Resolve the StatefulSet DNS

Inside the debug pod:

```bash
nslookup postgres-0.postgres
```

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

---

## 🧹 Cleanup

To remove all Lab 2 resources:

```bash
kubectl delete -f k8s/lab2-statefulset/

# Delete the auto-provisioned PVCs (not removed automatically)
kubectl delete pvc -l app=postgres
```

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
