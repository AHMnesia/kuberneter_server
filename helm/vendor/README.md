# Vendor Dependencies

This folder contains Kubernetes vendor dependencies that are automatically installed during deployment.

## Files

### cert-manager.yaml
**Version:** v1.18.2  
**Purpose:** Certificate management for Kubernetes  
**Namespace:** cert-manager  
**Usage:** Automatically manages TLS certificates for Ingress resources

**Installation:**
```bash
kubectl apply -f cert-manager.yaml
kubectl wait --for=condition=ready pod --all -n cert-manager --timeout=180s
```

**Verification:**
```bash
kubectl get pods -n cert-manager
kubectl get clusterissuer
```

**Components:**
- cert-manager-controller
- cert-manager-webhook
- cert-manager-cainjector

### metrics-server.yaml
**Version:** Latest stable  
**Purpose:** Resource metrics for horizontal pod autoscaling  
**Namespace:** kube-system  
**Usage:** Provides CPU and memory metrics for pods and nodes

**Installation:**
```bash
kubectl apply -f metrics-server.yaml
kubectl wait --for=condition=available deployment/metrics-server -n kube-system --timeout=120s
```

**Verification:**
```bash
kubectl top nodes
kubectl top pods -A
```

**Note:** Metrics-server is optional but recommended for production environments.

## Automatic Installation

Both components are automatically installed by the deployment script:

```powershell
# Windows
.\deploy.ps1 dev

# Linux/Mac
./deploy.sh dev
```

The deployment script will:
1. Check if cert-manager namespace exists
2. Install cert-manager from local file if not found
3. Wait for all pods to be ready
4. Create ClusterIssuer for self-signed certificates
5. Install metrics-server (optional)
6. Continue with application deployment

## Manual Installation

If you need to install these components manually:

```bash
# Install cert-manager
kubectl apply -f vendor/cert-manager.yaml
kubectl wait --for=condition=ready pod --all -n cert-manager --timeout=180s

# Create ClusterIssuer
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-cluster-issuer
spec:
  selfSigned: {}
EOF

# Install metrics-server (optional)
kubectl apply -f vendor/metrics-server.yaml
kubectl wait --for=condition=available deployment/metrics-server -n kube-system --timeout=120s
```

## Updating

To update these files:

1. **cert-manager:**
   ```bash
   curl -o vendor/cert-manager.yaml https://github.com/cert-manager/cert-manager/releases/download/v1.18.2/cert-manager.yaml
   ```

2. **metrics-server:**
   ```bash
   curl -o vendor/metrics-server.yaml https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
   ```

## Troubleshooting

### cert-manager Issues

**Problem:** Pods not starting
```bash
kubectl describe pod -n cert-manager
kubectl logs -n cert-manager -l app=cert-manager
```

**Problem:** Certificate not issued
```bash
kubectl get certificate -A
kubectl describe certificate <name> -n <namespace>
kubectl get certificaterequest -A
```

### metrics-server Issues

**Problem:** "unable to fetch pod metrics"
```bash
kubectl logs -n kube-system deployment/metrics-server
```

**Solution:** Check if metrics-server has proper RBAC permissions:
```bash
kubectl get clusterrole system:metrics-server
kubectl get clusterrolebinding system:metrics-server
```

**Problem:** Connection refused errors (common in Docker Desktop)
- This is expected in development environments
- Metrics will work in production with proper network configuration

## Dependencies

These vendor files are required for:
- TLS/SSL certificate automation (cert-manager)
- Ingress certificate management (cert-manager)
- Horizontal Pod Autoscaling (metrics-server)
- Resource monitoring (metrics-server)

## See Also

- [Main Deployment Guide](../README.md)
- [Deployment Flow](../DEPLOYMENT_FLOW.md)
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [metrics-server Documentation](https://github.com/kubernetes-sigs/metrics-server)
