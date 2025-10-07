# Suma Webhook Chart

## Overview

Chart ini **TIDAK** men-deploy container webhook ke Kubernetes. Webhook berjalan di **HOST** (bare metal/VM).

Chart ini hanya membuat:
- **Namespace** - `suma-webhook`
- **Service** - Headless service tanpa selector
- **Endpoints** - Manual endpoints yang mengarah ke webhook di host
- **Ingress** - Route traffic dari domain ke webhook
- **Certificate** - TLS certificate untuk ingress

## Arsitektur

```
┌─────────────────────────────────────────────────────────┐
│  Kubernetes Cluster                                     │
│                                                          │
│  ┌────────────────────────────────────────────────┐    │
│  │ Ingress (webhook.suma-honda.local)             │    │
│  │  - Routes HTTP/HTTPS traffic                   │    │
│  └──────────────┬─────────────────────────────────┘    │
│                 │                                        │
│  ┌──────────────▼─────────────────────────────────┐    │
│  │ Service (suma-webhook)                         │    │
│  │  - Type: ClusterIP None (headless)             │    │
│  │  - Port: 5000                                  │    │
│  │  - No selector (manual endpoints)              │    │
│  └──────────────┬─────────────────────────────────┘    │
│                 │                                        │
│  ┌──────────────▼─────────────────────────────────┐    │
│  │ Endpoints                                      │    │
│  │  - IP: 192.168.1.125 (host IP)                │    │
│  │  - Port: 5000                                  │    │
│  └────────────────────────────────────────────────┘    │
│                 │                                        │
└─────────────────┼────────────────────────────────────────┘
                  │
                  │ Routes to external host
                  ▼
         ┌────────────────────┐
         │  Host Machine      │
         │  IP: 192.168.1.125 │
         │                    │
         │  ┌──────────────┐  │
         │  │ webhook.js   │  │
         │  │ Port: 5000   │  │
         │  │ (Task        │  │
         │  │  Scheduler)  │  │
         │  └──────────────┘  │
         └────────────────────┘
```

## Configuration

### values.yaml

```yaml
# Deployment disabled - webhook runs on host
deployment:
  enabled: false

namespace: suma-webhook

# Service configuration - headless service with manual endpoints
service:
  type: ClusterIP
  port: 5000  # Port on host where webhook is running

# Endpoints configuration - points to webhook running on host
endpoints:
  enabled: true
  name: suma-webhook
  ip: 192.168.1.125  # Host IP where webhook is running
  port: 5000         # Port where webhook listens on host

# Ingress
ingress:
  enabled: true
  className: nginx
  hosts:
    - host: webhook.suma-honda.local  # Dev
      # or webhook.suma-honda.id for production
      paths:
        - path: /
          pathType: Prefix
```

### Environment-Specific Values

**Development (values-dev.yaml):**
```yaml
suma-webhook:
  endpoints:
    ip: 192.168.1.125  # Local host IP
    port: 5000
  ingress:
    hosts:
      - host: webhook.suma-honda.local
```

**Production (values-production.yaml):**
```yaml
suma-webhook:
  endpoints:
    ip: <PRODUCTION_HOST_IP>  # Production server IP
    port: 5000
  ingress:
    hosts:
      - host: webhook.suma-honda.id
```

## Templates

### service.yaml
Creates a **headless service** (ClusterIP: None) without selector. This allows manual endpoint configuration.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: suma-webhook
spec:
  clusterIP: None
  ports:
    - port: 5000
  # No selector - endpoints defined manually
```

### endpoints.yaml
Defines manual endpoints pointing to the host where webhook runs.

```yaml
apiVersion: v1
kind: Endpoints
metadata:
  name: suma-webhook
subsets:
  - addresses:
      - ip: 192.168.1.125  # Host IP
    ports:
      - port: 5000
```

### deployment.yaml
**Disabled by default** (`deployment.enabled: false`). If you need to run webhook in K8s for some reason, set to `true`.

### ingress.yaml
Routes external traffic to the webhook service.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: suma-webhook
spec:
  ingressClassName: nginx
  rules:
    - host: webhook.suma-honda.local
      http:
        paths:
          - path: /
            backend:
              service:
                name: suma-webhook
                port: 5000
```

## Deployment

Chart ini di-deploy bersama chart lain:

```powershell
# Deploy ke development
.\deploy.ps1 dev

# Deploy ke production
.\deploy.ps1 production
```

Chart akan:
1. Create namespace `suma-webhook`
2. Create service dengan manual endpoints
3. Create ingress untuk routing
4. Setup TLS certificate

**TIDAK** akan:
- Build Docker image
- Create Deployment/Pod
- Schedule container di K8s

## Webhook Setup on Host

Webhook di-setup di host menggunakan script di `helm/perintah/`:

**Windows:**
```powershell
# Setup Task Scheduler
.\helm\perintah\setup-webhook-scheduler.ps1
```

**Linux:**
```bash
# Setup systemd service
sudo ./helm/perintah/setup-webhook-scheduler.sh install
```

Lihat [perintah/README.md](../../perintah/README.md) untuk detail setup webhook di host.

## Access

### Development
- **Direct access**: `http://192.168.1.125:5000`
- **Via Kubernetes**: `http://webhook.suma-honda.local`
- **From pods**: `http://suma-webhook.suma-webhook.svc.cluster.local:5000`

### Production
- **Direct access**: `https://<HOST_IP>:5000`
- **Via Kubernetes**: `https://webhook.suma-honda.id`
- **From pods**: `http://suma-webhook.suma-webhook.svc.cluster.local:5000`

## Testing

### Test from outside cluster:
```bash
# Development
curl http://webhook.suma-honda.local/health

# Production
curl https://webhook.suma-honda.id/health
```

### Test from inside cluster:
```bash
# From any pod in cluster
kubectl run test --rm -it --image=curlimages/curl -- sh
curl http://suma-webhook.suma-webhook.svc.cluster.local:5000/health
```

### Verify service and endpoints:
```bash
# Check service
kubectl get svc -n suma-webhook

# Check endpoints (should show host IP)
kubectl get endpoints -n suma-webhook

# Check ingress
kubectl get ingress -n suma-webhook
```

## Troubleshooting

### Endpoints not showing host IP

**Check:**
```bash
kubectl get endpoints suma-webhook -n suma-webhook -o yaml
```

**Should see:**
```yaml
subsets:
  - addresses:
      - ip: 192.168.1.125
    ports:
      - port: 5000
```

**Fix:**
1. Check `values.yaml` has correct `endpoints.ip`
2. Redeploy: `helm upgrade suma-webhook ./charts/suma-webhook -n suma-webhook -f values-dev.yaml`

### Cannot access webhook via ingress

**Check:**
1. Ingress created: `kubectl get ingress -n suma-webhook`
2. Ingress controller running: `kubectl get pods -n ingress-nginx`
3. DNS/hosts file configured for webhook.suma-honda.local
4. Webhook running on host: `curl http://192.168.1.125:5000`

### Webhook not running on host

**Check:**
```powershell
# Windows
Get-NetTCPConnection -LocalPort 5000
Get-ScheduledTask -TaskName "SumaWebhookService"

# Linux
sudo netstat -tlnp | grep :5000
sudo systemctl status suma-webhook
```

**Fix:**
Run setup script again:
```powershell
# Windows
.\helm\perintah\setup-webhook-scheduler.ps1

# Linux
sudo ./helm\perintah/setup-webhook-scheduler.sh install
```

## Why This Approach?

### Pros:
- ✅ Webhook has direct host access (no container limitations)
- ✅ Easier debugging (direct logs, no kubectl needed)
- ✅ Lower resource usage (no pod overhead)
- ✅ Still accessible from K8s via service/ingress
- ✅ Can access host resources directly

### Cons:
- ❌ Need to manage webhook separately from K8s
- ❌ Host must be stable and accessible
- ❌ Manual setup required on host

## See Also

- [Setup Webhook on Host](../../perintah/README.md)
- [Main Deployment Guide](../../README.md)
- [Webhook Changes](../../perintah/WEBHOOK_CHANGES.md)
