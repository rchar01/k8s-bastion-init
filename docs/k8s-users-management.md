# 📘 README — Kubernetes User Access via Short-Lived Certificates

## Overview

This system provides secure Kubernetes access using:

* **Host (bastion) groups** as the source of truth
* **Short-lived client certificates** (default: 7 days)
* Kubernetes **CSR API** for certificate issuance
* Kubernetes **RBAC** bound to groups
* User self-service certificate renewal (no sudo required)

Access is granted automatically based on Linux groups beginning with:

```
k8s-*
```

Example:

```
k8s-gopher-dev
k8s-batman
k8s-admin
```

These groups become Kubernetes RBAC groups via the certificate `O=` field.

---

## Access Flow

Kubernetes access is granted through short-lived client certificates derived from host group membership.

The lifecycle of user access is shown below:

```
Admin bootstrap (once)
        ↓
User runs bastion-kube-renew
        ↓
CSR created (unprivileged request)
        ↓
Approver validates username and host groups
        ↓
Certificate issued (default: 7 days)
        ↓
Kubernetes RBAC grants access via certificate groups (O=)
        ↓
Certificate expires automatically
```

**Host groups define identity; Kubernetes RBAC defines permissions.**

### Step Summary

1. **Admin bootstrap**

   * Administrator installs a minimal kubeconfig allowing CSR requests.
   * Done once per user.

2. **User renewal**

   * User runs `bastion-kube-renew`.
   * Script derives Kubernetes groups from host groups (`k8s-*`).

3. **CSR creation**

   * A CertificateSigningRequest is submitted without elevated privileges.

4. **Approval automation**

   * Admin automation validates CSR identity and group membership.

5. **Certificate issuance**

   * Kubernetes signs and returns a short-lived client certificate.

6. **RBAC authorization**

   * Certificate `O=` fields map directly to Kubernetes RBAC groups.

7. **Automatic expiration**

   * Access is revoked automatically when the certificate expires.

No manual certificate revocation or user management inside Kubernetes is required.

---

## Architecture

```
Host User
   ↓
Linux groups (k8s-*)
   ↓
CSR request (user script)
   ↓
Admin approval automation
   ↓
Short-lived certificate
   ↓
Kubernetes RBAC (RoleBindings)
```

Kubernetes does **not manage users directly**.
Authentication comes from certificates; authorization comes from RBAC.

---

## Components

### Policy Configuration

```
/etc/kubernetes/access-policy.yaml
```

Single source of truth defining:

* certificate TTL
* allowed group prefix
* cluster connection info
* namespace contexts
* desired user → group mapping

---

### Scripts

| Script                      | Role                                        |
| --------------------------- | ------------------------------------------- |
| `bastion-bootstrap-kubeconfig` | Admin: initial kubeconfig bootstrap         |
| `bastion-kube-renew`        | User: request & install new certificate     |
| `bastion-csr-approver`      | Admin automation: validates & approves CSRs |
| `bastion-csr-cleanup`       | Admin automation: removes old CSR objects   |

---

## Access Flow

### 1️⃣ Admin bootstrap (once per user)

Admin prepares minimal kubeconfig:

```
bastion-bootstrap-kubeconfig --user <username>
```

This installs:

```
~/.kube/bootstrap
```

The bootstrap config allows only CSR creation.

---

### 2️⃣ User certificate renewal

User runs:

```
bastion-kube-renew
```

The script:

1. Reads host groups (`k8s-*`)
2. Creates CSR with:

   * CN = username
   * O = groups
3. Waits for admin approval
4. Writes new kubeconfig:

```
~/.kube/config
```

Previous config is backed up automatically.

---

### 3️⃣ Admin approval automation

Periodic job runs:

```
bastion-csr-approver
```

It verifies:

* CSR username matches requester
* Requested groups match host groups
* Policy rules are respected

If valid → CSR approved.

---

### 4️⃣ Certificate lifecycle

Certificates are short-lived.

| Action     | Result                |
| ---------- | --------------------- |
| Renew      | new cert issued       |
| Old cert   | expires automatically |
| Revocation | handled by expiration |

No manual certificate deletion required.

---

### 5️⃣ Cleanup automation

Periodic cleanup removes old CSR objects:

```
bastion-csr-cleanup
```

This keeps the cluster tidy but does not affect issued certificates.

---

## Security Model

Users:

* ✅ may request certificates
* ❌ cannot approve certificates
* ❌ cannot choose arbitrary groups

Admins/automation:

* validate CSR contents
* enforce policy

Security enforcement occurs during **approval**, not request.

---

## Backup Behavior

Each renewal creates:

```
~/.kube/config.bak.TIMESTAMP
```

Only a few backups should be retained (rotation handled by scripts).

---

## Adding Access

To grant access:

1. Add user to host group:

```
usermod -aG k8s-gopher-dev <user>
```

2. Ensure RoleBinding exists for that group.

3. User runs:

```
bastion-kube-renew
```

Access updates automatically.

---

## Removing Access

1. Remove user from host group.
2. User's certificate expires automatically (≤7 days).

No RBAC or certificate cleanup required.
Great 👍 — here is a **clean Troubleshooting section** you can add to the README.
This is the part future-you (and other admins) will use the most.

Place it near the end of the README, after **Security Model** or **Operations**.

---

# 🔧 Troubleshooting

This section helps diagnose why a user cannot access Kubernetes.

Always debug access in the following order:

```
User → Host Groups → Certificate → CSR → RBAC → Namespace
```

---

## Quick Diagnostic Flow

```text
User cannot access cluster
        ↓
Is certificate valid?
        ↓
Does cert contain correct groups (O=)?
        ↓
Do RoleBindings reference those groups?
        ↓
Does RBAC allow requested action?
```

---

## 1️⃣ Verify Host Group Membership (Source of Truth)

On bastion:

```bash
id -nG <username>
```

Expected:

```
k8s-gopher-dev k8s-batman
```

If missing:

✅ Fix host groups first — Kubernetes is not the problem.

```bash
usermod -aG k8s-gopher-dev <username>
```

User must renew certificate afterward.

---

## 2️⃣ Check Certificate Identity

User runs:

```bash
kubectl auth whoami -o yaml
```

Example output:

```yaml
username: <user>
groups:
- k8s-gopher-dev
- k8s-batman
```

### Problems

| Problem        | Cause                     |
| -------------- | ------------------------- |
| wrong username | CSR generated incorrectly |
| missing group  | user didn’t renew cert    |
| no output      | cert expired              |

Fix:

```bash
bastion-kube-renew
```

---

## 3️⃣ Check CSR Status

Admin:

```bash
kubectl get csr
```

Common states:

| Status   | Meaning               |
| -------- | --------------------- |
| Pending  | waiting for approver  |
| Approved | waiting for issuance  |
| Issued   | ready                 |
| Missing  | request never created |

Inspect CSR:

```bash
kubectl describe csr <name>
```

---

## 4️⃣ Verify RBAC Binding

Check RoleBindings referencing group:

```bash
kubectl get rolebindings -A | grep k8s-gopher-dev
```

Or detailed:

```bash
kubectl get rolebinding -n <ns> -o yaml
```

Look for:

```yaml
subjects:
- kind: Group
  name: k8s-gopher-dev
```

If missing → RBAC configuration issue.

---

## 5️⃣ Test Effective Permissions

Impersonate user/group:

```bash
kubectl auth can-i get pods \
  --as=<user> \
  --as-group=k8s-gopher-dev \
  -n team-gopher-dev
```

Result:

```
yes
```

If `no` → RBAC rules insufficient.

---

## 6️⃣ Check Certificate Expiration

User:

```bash
kubectl config view --raw \
| grep client-certificate-data -A1
```

or:

```bash
openssl x509 -noout -dates -in <(kubectl config view --raw \
  -o jsonpath='{.users[0].user.client-certificate-data}' | base64 -d)
```

If expired:

```bash
bastion-kube-renew
```

---

## 7️⃣ Common Issues

| Symptom                    | Fix                     |
| -------------------------- | ----------------------- |
| `Unauthorized`             | cert expired or invalid |
| `Forbidden`                | RBAC missing            |
| CSR never approved         | approver not running    |
| Groups missing             | user not in host group  |
| Works yesterday, not today | cert expired            |

---

## Golden Rule

> Kubernetes never assigns users to groups.
> Groups come only from the certificate.

If groups are wrong → regenerate certificate.
