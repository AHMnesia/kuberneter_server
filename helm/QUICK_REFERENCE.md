# 📋 Suma Platform - Quick Reference Card

## 🚀 Deployment Commands

| Task | Windows (PowerShell) | Linux/Mac (Bash) |
|------|---------------------|------------------|
| Deploy Dev | `.\deploy.ps1 dev` | `./deploy.sh dev` |
| Deploy Prod | `.\deploy.ps1 production` | `./deploy.sh production` |
| Skip Build | `.\deploy.ps1 dev -SkipBuild` | `./deploy.sh dev --skip-build` |
| Force Recreate | `.\deploy.ps1 dev -ForceRecreate` | `./deploy.sh dev --force-recreate` |
| Show Help | N/A | `./deploy.sh --help` |

## 🌐 Access URLs (Development)

| Service | URL | Port |
|---------|-----|------|
| Suma Android | http://suma-android.local | 8000 |
| Suma E-commerce | http://suma-ecommerce.local | 8000 |
| Suma Office | http://suma-office.local | 8000 |
| Suma PMO | http://suma-pmo.local | 8000 |
| Suma Chat | http://suma-chat.local | 4000 |
| Redis Cluster | redis-cluster.redis.svc.cluster.local | 6379 |
| Elasticsearch | http://search.suma-honda.local | 9200 |
| Kibana | http://kibana.suma-honda.local | 5601 |
| Grafana | http://monitoring.suma-honda.local | 3000 |
| API Gateway | http://api.suma-honda.id | - |

## 🔍 Quick Status Checks

```bash
# All pods
kubectl get pods -A

# Specific namespace
kubectl get pods -n suma-ecommerce

# Services
kubectl get svc -A

# Ingress
kubectl get ingress -A

# Certificates
kubectl get certificates -A

# Resource usage
kubectl top pods -A
kubectl top nodes
```

## 📊 Logs & Debugging

```bash
# View logs
kubectl logs -n suma-ecommerce <pod-name>

# Follow logs
kubectl logs -f -n suma-chat <pod-name>

# Previous logs (crashed pod)
kubectl logs -n suma-office <pod-name> --previous

# All containers
kubectl logs -n suma-ecommerce --all-containers=true -l app=suma-ecommerce

# Describe pod
kubectl describe pod -n suma-pmo <pod-name>

# Events
kubectl get events -n suma-android --sort-by='.lastTimestamp'
```

## 🔄 Common Operations

```bash
# Restart deployment
kubectl rollout restart deployment suma-ecommerce -n suma-ecommerce

# Scale deployment
kubectl scale deployment suma-office -n suma-office --replicas=3

# Update chart
helm upgrade suma-ecommerce ./charts/suma-ecommerce -n suma-ecommerce -f values-dev.yaml

# Rollback
helm rollback suma-ecommerce -n suma-ecommerce

# Uninstall
helm uninstall suma-ecommerce -n suma-ecommerce
```

## 📦 Namespaces

| Namespace | Component | Type |
|-----------|-----------|------|
| redis | Redis Cluster | Infrastructure |
| suma-android | Suma Android API | Application |
| suma-ecommerce | Suma E-commerce API | Application |
| suma-office | Suma Office API | Application |
| suma-pmo | Suma PMO API | Application |
| suma-chat | Suma Chat Service | Application |
| suma-webhook | Suma Webhook | Application |
| elasticsearch | Elasticsearch | Infrastructure |
| kibana | Kibana | Infrastructure |
| monitoring | Prometheus/Grafana | Infrastructure |

## 🔑 Hosts File Entries (Dev)

**Windows:** `C:\Windows\System32\drivers\etc\hosts`
**Linux/Mac:** `/etc/hosts`

```
127.0.0.1 suma-android.local suma-ecommerce.local suma-office.local
127.0.0.1 suma-pmo.local suma-chat.local
127.0.0.1 search.suma-honda.local kibana.suma-honda.local monitoring.suma-honda.local
127.0.0.1 api.suma-honda.id webhook.suma-honda.local
```

## 🐳 Docker Images

| Service | Image | Dev Tag | Prod Tag |
|---------|-------|---------|----------|
| Android | suma-android-api | latest | production |
| E-commerce | suma-ecommerce-api | latest | production |
| Office | suma-office-api | latest | production |
| PMO | suma-pmo-api | latest | production |
| Chat | suma-chat | latest | production |
| Webhook | suma-webhook | latest | production |

## 🛠️ Helm Commands

```bash
# List releases
helm list -A

# Status
helm status suma-ecommerce -n suma-ecommerce

# History
helm history suma-ecommerce -n suma-ecommerce

# Get values
helm get values suma-ecommerce -n suma-ecommerce

# Test
helm test suma-ecommerce -n suma-ecommerce

# Update dependencies
helm dependency update .

# Lint
helm lint ./charts/suma-ecommerce
```

## 🔐 Cert-Manager

```bash
# Check cert-manager
kubectl get pods -n cert-manager

# List ClusterIssuers
kubectl get clusterissuer

# List certificates
kubectl get certificates -A

# Describe certificate
kubectl describe certificate -n suma-ecommerce suma-ecommerce-tls

# Certificate events
kubectl get events -n suma-ecommerce --field-selector involvedObject.kind=Certificate
```

## 🌐 Ingress

```bash
# List ingress
kubectl get ingress -A

# Describe ingress
kubectl describe ingress -n suma-ecommerce suma-ecommerce-ingress

# Check ingress controller
kubectl get pods -n ingress-nginx

# Enable ingress (minikube)
minikube addons enable ingress
```

## 💾 Storage

```bash
# List PVCs
kubectl get pvc -A

# Describe PVC
kubectl describe pvc -n elasticsearch elasticsearch-data-0

# List PVs
kubectl get pv

# Storage classes
kubectl get storageclass
```

## ⚠️ Troubleshooting Checklist

- [ ] Cluster accessible: `kubectl cluster-info`
- [ ] All namespaces created: `kubectl get ns`
- [ ] Pods running: `kubectl get pods -A`
- [ ] Images built: `docker images | grep suma`
- [ ] Ingress controller running: `kubectl get pods -n ingress-nginx`
- [ ] Cert-manager running: `kubectl get pods -n cert-manager`
- [ ] Certificates issued: `kubectl get certificates -A`
- [ ] Hosts file updated: `cat /etc/hosts` or `type C:\Windows\System32\drivers\etc\hosts`
- [ ] Services accessible: `curl http://suma-ecommerce.local`

## 📚 Documentation

- **README.md** - Quick start guide
- **DEPLOYMENT.md** - Detailed deployment guide
- **MIGRATION_REPORT.md** - K8s to Helm migration info
- **CLEANUP_REPORT.md** - Cleanup & optimization
- **DEPLOYMENT_SCRIPT_IMPROVEMENTS.md** - Script improvements

## 🆘 Quick Fixes

### Pods in ImagePullBackOff
```bash
# Rebuild image
docker build -t suma-ecommerce-api:latest ../suma-ecommerce

# Load to cluster (minikube)
minikube image load suma-ecommerce-api:latest

# Restart deployment
kubectl rollout restart deployment suma-ecommerce -n suma-ecommerce
```

### Ingress Not Working
```bash
# Check ingress controller
kubectl get pods -n ingress-nginx

# Enable (minikube)
minikube addons enable ingress

# Get minikube IP
minikube ip

# Update hosts file with minikube IP
```

### Certificate Pending
```bash
# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager

# Check ClusterIssuer
kubectl describe clusterissuer selfsigned-cluster-issuer

# Delete and recreate certificate
kubectl delete certificate -n suma-ecommerce suma-ecommerce-tls
kubectl apply -f charts/suma-ecommerce/templates/certificate.yaml
```

### Pod Crash Loop
```bash
# Check logs
kubectl logs -n suma-ecommerce <pod-name>

# Check previous logs
kubectl logs -n suma-ecommerce <pod-name> --previous

# Check events
kubectl describe pod -n suma-ecommerce <pod-name>

# Check resources
kubectl top pods -n suma-ecommerce
```

---

**💡 Tip:** Simpan file ini untuk quick reference saat deployment atau troubleshooting!
