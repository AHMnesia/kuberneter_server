# Suma Platform - Deployment Scripts# Suma Platform - Deployment Scripts# Suma Platform Helm Charts



## 📋 Overview



Script deployment yang unified dan sederhana untuk deploy Suma Platform ke Kubernetes menggunakan Helm.## 📋 Overview## Overview



## 🚀 Quick StartThis Helm chart deploys the complete Suma Platform infrastructure, including:



### DevelopmentScript deployment yang unified dan sederhana untuk deploy Suma Platform ke Kubernetes menggunakan Helm.- Elasticsearch & Kibana

```powershell

# Windows- Suma E-commerce API

.\deploy.ps1 dev

## 🚀 Quick Start- Suma Office API

# Linux/Mac

./deploy.sh dev- Suma Chat Service

```

### Development- Monitoring Stack (Prometheus, Grafana, AlertManager)

### Production

```powershell```powershell

# Windows

.\deploy.ps1 production# Windows## Prerequisites



# Linux/Mac.\deploy.ps1 dev- Kubernetes 1.19+

./deploy.sh production

```- Helm 3.0+



## 📝 Command Reference# Linux/Mac- PV provisioner support in the underlying infrastructure



### PowerShell (Windows)./deploy.sh dev- Cert-manager installed for TLS certificate management



```powershell```

# Basic deployment

.\deploy.ps1 dev                                    # Deploy development## Installation

.\deploy.ps1 production                             # Deploy production

### Production

# With options

.\deploy.ps1 dev -SkipBuild                        # Skip Docker build```powershell### Quick Start

.\deploy.ps1 production -ForceRecreate             # Force recreate namespaces

.\deploy.ps1 dev -SkipBuild -ForceRecreate        # Combine options# Windows```powershell

```

.\deploy.ps1 production# Add required dependencies

### Bash (Linux/Mac)

helm repo update

```bash

# Basic deployment# Linux/Mac

./deploy.sh dev                                     # Deploy development

./deploy.sh production                              # Deploy production./deploy.sh production# Install with default values



# With options```helm install suma-platform ./helm -n suma --create-namespace

./deploy.sh dev --skip-build                       # Skip Docker build

./deploy.sh production --force-recreate            # Force recreate namespaces

./deploy.sh dev --skip-build --force-recreate     # Combine options

## 📝 Command Reference# Install with environment-specific values

# Help

./deploy.sh --help                                 # Show helphelm install suma-platform ./helm -n suma-dev -f values-dev.yaml

```

### PowerShell (Windows)```

## 🎯 What It Does



| Step | Description | Time |

|------|-------------|------|```powershell### Environment-specific Installation

| 1. Prerequisites Check | Validasi kubectl, helm, docker | 5s |

| 2. Build Images | Build 6 Docker images | 2-5min |# Basic deployment```powershell

| 3. Setup cert-manager | Install certificate manager | 30s |

| 4. Create Namespaces | Buat 10 namespaces | 10s |.\deploy.ps1 dev                                    # Deploy development# Development

| 5. Deploy Charts | Install/upgrade 10 Helm charts | 3-4min |

| 6. Wait Pods Ready | Tunggu pods running | 1-2min |.\deploy.ps1 production                             # Deploy productionhelm install suma-platform ./helm -n suma-dev -f values-dev.yaml

| 7. Show Status | Display deployment info | 5s |



**Total Time:** ~6-12 minutes

# With options# Staging

## 📦 Deployed Components

.\deploy.ps1 dev -SkipBuild                        # Skip Docker buildhelm install suma-platform ./helm -n suma-staging -f values-staging.yaml

### Applications (6)

- ✅ Suma Android API.\deploy.ps1 production -ForceRecreate             # Force recreate namespaces

- ✅ Suma E-commerce API  

- ✅ Suma Office API.\deploy.ps1 dev -SkipBuild -ForceRecreate        # Combine options# Production

- ✅ Suma PMO API

- ✅ Suma Chat (Socket.io)```helm install suma-platform ./helm -n suma-prod -f values-production.yaml

- ✅ Suma Webhook

```

### Infrastructure (4)

- ✅ **Redis Cluster (3 nodes)** - Global caching & session storage### Bash (Linux/Mac)

- ✅ Elasticsearch (3 nodes) - Search & analytics

- ✅ Kibana - Log visualization## Configuration

- ✅ Monitoring (Prometheus + Grafana + AlertManager)

```bash

## 🌐 Access URLs

# Basic deployment### Global Parameters

### Development Environment

./deploy.sh dev                                     # Deploy development| Parameter | Description | Default |

**Applications:**

```./deploy.sh production                              # Deploy production|-----------|-------------|---------|

http://suma-android.local

http://suma-ecommerce.local| global.environment | Environment name | production |

http://suma-office.local

http://suma-pmo.local# With options| global.domain | Base domain for ingress | suma-honda.id |

http://suma-chat.local

```./deploy.sh dev --skip-build                       # Skip Docker build| global.storage.class | Default storage class | standard |



**Infrastructure:**./deploy.sh production --force-recreate            # Force recreate namespaces

```

redis-cluster.redis.svc.cluster.local:6379  # Redis (Internal only)./deploy.sh dev --skip-build --force-recreate     # Combine options### Elasticsearch Configuration

http://search.suma-honda.local              # Elasticsearch

http://kibana.suma-honda.local              # Kibana| Parameter | Description | Default |

http://monitoring.suma-honda.local          # Grafana

```# Help|-----------|-------------|---------|



**API Gateway:**./deploy.sh --help                                 # Show help| elasticsearch.replicas | Number of replicas | 3 |

```

http://api.suma-honda.id```| elasticsearch.heap | Heap size | 2g |

http://api.suma-honda.id/android

http://api.suma-honda.id/ecommerce| elasticsearch.storage.size | Storage size | 30Gi |

http://api.suma-honda.id/office

http://api.suma-honda.id/pmo## 🎯 What It Does

http://api.suma-honda.id/chat

```### Application Services



### Production Environment| Step | Description | Time |Detailed configuration options for each service:



Replace `http://` with `https://` and `.local` with `.suma-honda.id`|------|-------------|------|- suma-ecommerce



## ⚙️ Configuration Files| 1. Prerequisites Check | Validasi kubectl, helm, docker | 5s |- suma-office



| File | Purpose | Environment || 2. Build Images | Build 6 Docker images | 2-5min |- suma-chat

|------|---------|-------------|

| `deploy.ps1` | PowerShell deployment script | Windows || 3. Setup cert-manager | Install certificate manager | 30s |- monitoring

| `deploy.sh` | Bash deployment script | Linux/Mac |

| `values-dev.yaml` | Development configuration | Dev || 4. Create Namespaces | Buat 9 namespaces | 10s |

| `values-production.yaml` | Production configuration | Prod |

| `Chart.yaml` | Main chart dependencies | Both || 5. Deploy Charts | Install/upgrade 9 Helm charts | 2-3min |See values.yaml for complete list of configuration options.



## 🔧 Environment Differences| 6. Wait Pods Ready | Tunggu pods running | 1-2min |



| Feature | Development | Production || 7. Show Status | Display deployment info | 5s |## Upgrading

|---------|-------------|------------|

| Image Tag | `latest` | `production` |

| Replicas | 1 | 2-3 |

| Resources | Minimal | Full |**Total Time:** ~5-10 minutesTo upgrade the release:

| Domain | `.local` | `.suma-honda.id` |

| Protocol | HTTP | HTTPS |```powershell

| Storage | 10-20Gi | 50-100Gi |

| Redis Nodes | 1 | 3 (cluster mode) |## 📦 Deployed Componentshelm upgrade suma-platform ./helm -n suma



## 🖥️ System Requirements```



### Development (Local)### Applications (6)

- **CPU:** 4 cores minimum

- **RAM:** 8GB minimum (10GB recommended dengan Redis)- ✅ Suma Android API## Rollback

- **Storage:** 50GB free

- **Kubernetes:** Minikube, k3s, Docker Desktop- ✅ Suma E-commerce API  



### Production- ✅ Suma Office APIIf there are issues after upgrade:

- **Nodes:** 3+ worker nodes

- **CPU per Node:** 4 cores- ✅ Suma PMO API```powershell

- **RAM per Node:** 8GB (16GB recommended)

- **Storage:** SSD-based storage class- ✅ Suma Chat (Socket.io)helm rollback suma-platform -n suma

- **Kubernetes:** 1.24+

- ✅ Suma Webhook```

## 🗄️ Redis Global Configuration



### Purpose

Redis Cluster digunakan sebagai **shared cache** untuk semua aplikasi:### Infrastructure (3)## Uninstallation

- Session management

- Cache API responses- ✅ Elasticsearch (3 nodes)

- Real-time data

- Rate limiting- ✅ KibanaTo remove the deployment:

- Queue management

- ✅ Monitoring (Prometheus + Grafana + AlertManager)```powershell

### Access from Applications

helm uninstall suma-platform -n suma

**PHP Applications (Laravel):**

```php## 🌐 Access URLs```

// .env configuration

REDIS_HOST=redis-cluster.redis.svc.cluster.local

REDIS_PORT=6379

REDIS_PASSWORD=null### Development Environment## Architecture

REDIS_DB=0

The platform consists of several microservices:

// Usage

Cache::put('key', 'value', $seconds);**Applications:**

$value = Cache::get('key');

``````1. **Backend Services**



**Node.js Applications:**http://suma-android.local   - Suma E-commerce API (Laravel)

```javascript

const redis = require('redis');http://suma-ecommerce.local   - Suma Office API (Laravel)

const client = redis.createClient({

  host: 'redis-cluster.redis.svc.cluster.local',http://suma-office.local   - Suma Chat Service (Node.js)

  port: 6379

});http://suma-pmo.local



client.set('key', 'value');http://suma-chat.local2. **Data Storage**

client.get('key', (err, value) => {

  console.log(value);```   - Elasticsearch

});

```   - Redis



### Redis Configuration**Infrastructure:**   - MySQL (external)



**Development:**```

- 1 replica (non-cluster)

- 5Gi storagehttp://search.suma-honda.local        # Elasticsearch3. **Monitoring**

- 256MB memory limit

- Standard storage classhttp://kibana.suma-honda.local        # Kibana   - Prometheus



**Production:**http://monitoring.suma-honda.local    # Grafana   - Grafana

- 3 replicas (cluster mode)

- 20Gi storage per node```   - AlertManager

- 1GB memory limit per node

- Premium storage class

- Persistence enabled

**API Gateway:**## Security

## 📖 Documentation

```- TLS encryption enabled by default

- **[DEPLOYMENT.md](./DEPLOYMENT.md)** - Detailed deployment guide

- **[MIGRATION_REPORT.md](./MIGRATION_REPORT.md)** - K8s to Helm migrationhttp://api.suma-honda.id- Network policies for inter-service communication

- **[CLEANUP_REPORT.md](./CLEANUP_REPORT.md)** - Cleanup & optimization

- **[QUICK_REFERENCE.md](./QUICK_REFERENCE.md)** - Command cheat sheethttp://api.suma-honda.id/android- RBAC configuration



## 📁 Structurehttp://api.suma-honda.id/ecommerce- Secrets management for sensitive data



```http://api.suma-honda.id/office

helm/

├── deploy.ps1                # PowerShell deployment scripthttp://api.suma-honda.id/pmo## Maintenance

├── deploy.sh                 # Bash deployment script

├── Chart.yaml                # Main chart definitionhttp://api.suma-honda.id/chat- Regular backups recommended for all persistent volumes

├── values.yaml              # Default values

├── values-dev.yaml          # Development environment values```- Monitor resource usage through Grafana dashboards

├── values-production.yaml   # Production environment values

├── charts/                  # Dependency charts- Check logs for any potential issues

│   ├── redis-cluster/       # NEW: Global Redis

│   ├── elasticsearch/### Production Environment- Keep values-*.yaml files secure and backed up

│   ├── kibana/

│   ├── suma-android/

│   ├── suma-ecommerce/

│   ├── suma-office/Replace `http://` with `https://` and `.local` with `.suma-honda.id`## Troubleshooting

│   ├── suma-pmo/

│   ├── suma-chat/Common issues and solutions:

│   ├── suma-webhook/

│   └── monitoring/## ⚙️ Configuration Files

└── templates/

    └── resource-quota.yaml1. **Pod Startup Issues**

```

| File | Purpose | Environment |   - Check events: `kubectl get events -n suma`

## ❓ Common Issues

|------|---------|-------------|   - Check logs: `kubectl logs -n suma <pod-name>`

### 1. Pods Not Starting

```bash| `deploy.ps1` | PowerShell deployment script | Windows |

kubectl get pods -A

kubectl logs -n suma-ecommerce <pod-name>| `deploy.sh` | Bash deployment script | Linux/Mac |2. **Performance Issues**

kubectl describe pod -n suma-ecommerce <pod-name>

```| `values-dev.yaml` | Development configuration | Dev |   - Monitor through Grafana dashboards



### 2. Redis Connection Issues| `values-production.yaml` | Production configuration | Prod |   - Check resource usage and limits

```bash

# Check Redis pods| `Chart.yaml` | Main chart dependencies | Both |

kubectl get pods -n redis

3. **Certificate Issues**

# Test Redis connection

kubectl exec -it -n redis redis-cluster-0 -- redis-cli ping## 🔧 Environment Differences   - Verify cert-manager is running



# Check Redis logs   - Check certificate status: `kubectl get certificates -n suma`

kubectl logs -n redis redis-cluster-0| Feature | Development | Production |

```|---------|-------------|------------|

| Image Tag | `latest` | `production` |

### 3. Image Pull Errors| Replicas | 1 | 2-3 |

```bash| Resources | Minimal | Full |

# Check images| Domain | `.local` | `.suma-honda.id` |

docker images | grep suma| Protocol | HTTP | HTTPS |

| Storage | 10-20Gi | 50-100Gi |

# Rebuild

docker build -t suma-ecommerce-api:latest ../suma-ecommerce## 🖥️ System Requirements



# Load to cluster (minikube)### Development (Local)

minikube image load suma-ecommerce-api:latest- **CPU:** 4 cores minimum

```- **RAM:** 8GB minimum

- **Storage:** 50GB free

### 4. Ingress Not Working- **Kubernetes:** Minikube, k3s, Docker Desktop

```bash

# Check ingress controller### Production

kubectl get pods -n ingress-nginx- **Nodes:** 3+ worker nodes

- **CPU per Node:** 4 cores

# Enable (minikube)- **RAM per Node:** 8GB

minikube addons enable ingress- **Storage:** SSD-based storage class

- **Kubernetes:** 1.24+

# Check ingress

kubectl get ingress -A## 📖 Documentation

```

- **[DEPLOYMENT.md](./DEPLOYMENT.md)** - Detailed deployment guide

## 🔄 Update/Rollback- **[MIGRATION_REPORT.md](./MIGRATION_REPORT.md)** - K8s to Helm migration

- **[CLEANUP_REPORT.md](./CLEANUP_REPORT.md)** - Cleanup & optimization

### Update Single Chart

```bash## 📁 Structure

helm upgrade suma-ecommerce ./charts/suma-ecommerce \

  -n suma-ecommerce \```

  -f values-dev.yamlhelm/

```├── deploy.ps1                # PowerShell deployment script

├── deploy.sh                 # Bash deployment script

### Update Redis Cluster├── Chart.yaml                # Main chart definition

```bash├── values.yaml              # Default values

helm upgrade redis-cluster ./charts/redis-cluster \├── values-dev.yaml          # Development environment values

  -n redis \├── values-production.yaml   # Production environment values

  -f values-dev.yaml├── charts/                  # Dependency charts

```│   ├── elasticsearch/

│   ├── kibana/

### Rollback│   ├── suma-android/

```bash│   ├── suma-ecommerce/

# List revisions│   ├── suma-office/

helm history suma-ecommerce -n suma-ecommerce│   ├── suma-pmo/

│   ├── suma-chat/

# Rollback to previous│   ├── suma-webhook/

helm rollback suma-ecommerce -n suma-ecommerce│   └── monitoring/

└── templates/

# Rollback to specific revision    └── resource-quota.yaml

helm rollback suma-ecommerce 1 -n suma-ecommerce```

```

## ❓ Common Issues

### Restart Pod

```bash### 1. Pods Not Starting

kubectl rollout restart deployment suma-ecommerce -n suma-ecommerce```bash

kubectl rollout restart statefulset redis-cluster -n rediskubectl get pods -A

```kubectl logs -n suma-ecommerce <pod-name>

kubectl describe pod -n suma-ecommerce <pod-name>

## 🧹 Cleanup```



### Uninstall Single Chart### 2. Image Pull Errors

```bash```bash

helm uninstall suma-ecommerce -n suma-ecommerce# Check images

kubectl delete namespace suma-ecommercedocker images | grep suma

```

# Rebuild

### Uninstall Alldocker build -t suma-ecommerce-api:latest ../suma-ecommerce

```bash

# Uninstall all charts# Load to cluster (minikube)

helm uninstall redis-cluster -n redisminikube image load suma-ecommerce-api:latest

helm uninstall elasticsearch -n elasticsearch```

helm uninstall kibana -n kibana

helm uninstall suma-android -n suma-android### 3. Ingress Not Working

helm uninstall suma-ecommerce -n suma-ecommerce```bash

helm uninstall suma-office -n suma-office# Check ingress controller

helm uninstall suma-pmo -n suma-pmokubectl get pods -n ingress-nginx

helm uninstall suma-chat -n suma-chat

helm uninstall suma-webhook -n suma-webhook# Enable (minikube)

helm uninstall monitoring -n monitoringminikube addons enable ingress



# Delete namespaces# Check ingress

kubectl delete namespace redis elasticsearch kibana suma-android suma-ecommerce suma-office suma-pmo suma-chat suma-webhook monitoringkubectl get ingress -A

``````



## 📊 Monitoring### 4. Certificate Issues

```bash

### Check Status# Check cert-manager

```bashkubectl get pods -n cert-manager

# All pods

kubectl get pods -A# Check certificates

kubectl get certificates -A

# Specific namespacekubectl describe certificate -n suma-ecommerce suma-ecommerce-tls

kubectl get pods -n suma-ecommerce```



# Redis status## 🔄 Update/Rollback

kubectl get pods -n redis

kubectl get statefulset -n redis### Update Single Chart

```bash

# With wide outputhelm upgrade suma-ecommerce ./charts/suma-ecommerce \

kubectl get pods -A -o wide  -n suma-ecommerce \

```  -f values-dev.yaml

```

### View Logs

```bash### Rollback

# Follow logs```bash

kubectl logs -f -n suma-chat <pod-name># List revisions

helm history suma-ecommerce -n suma-ecommerce

# Redis logs

kubectl logs -f -n redis redis-cluster-0# Rollback to previous

helm rollback suma-ecommerce -n suma-ecommerce

# All containers

kubectl logs -n suma-ecommerce --all-containers=true -l app=suma-ecommerce# Rollback to specific revision

helm rollback suma-ecommerce 1 -n suma-ecommerce

# Previous container (crashed)```

kubectl logs -n suma-office <pod-name> --previous

```### Restart Pod

```bash

### Resource Usagekubectl rollout restart deployment suma-ecommerce -n suma-ecommerce

```bash```

# Node resources

kubectl top nodes## 🧹 Cleanup



# Pod resources### Uninstall Single Chart

kubectl top pods -A```bash

helm uninstall suma-ecommerce -n suma-ecommerce

# Redis resourceskubectl delete namespace suma-ecommerce

kubectl top pods -n redis```

```

### Uninstall All

## 🎓 Next Steps```bash

# Uninstall all charts

1. ✅ Deploy to development: `./deploy.sh dev`helm uninstall elasticsearch -n elasticsearch

2. ✅ Add hosts entries (see DEPLOYMENT.md)helm uninstall kibana -n kibana

3. ✅ Test Redis connectivity from appshelm uninstall suma-android -n suma-android

4. ✅ Test all applicationshelm uninstall suma-ecommerce -n suma-ecommerce

5. ✅ Configure monitoring alertshelm uninstall suma-office -n suma-office

6. ✅ Setup backup strategyhelm uninstall suma-pmo -n suma-pmo

7. ✅ Deploy to production: `./deploy.sh production`helm uninstall suma-chat -n suma-chat

helm uninstall suma-webhook -n suma-webhook

## 📞 Supporthelm uninstall monitoring -n monitoring



**Issues?** Check:# Delete namespaces

1. Logs: `kubectl logs -n <namespace> <pod-name>`kubectl delete namespace elasticsearch kibana suma-android suma-ecommerce suma-office suma-pmo suma-chat suma-webhook monitoring

2. Events: `kubectl get events -n <namespace>````

3. Redis: `kubectl exec -it -n redis redis-cluster-0 -- redis-cli ping`

4. Documentation: `DEPLOYMENT.md`## 📊 Monitoring

5. Contact DevOps team

### Check Status

---```bash

# All pods

**Version:** 1.1.0  kubectl get pods -A

**Last Updated:** October 2025  

**New in 1.1:** Redis Cluster global caching  # Specific namespace

**Maintained by:** DevOps Teamkubectl get pods -n suma-ecommerce


# With wide output
kubectl get pods -A -o wide
```

### View Logs
```bash
# Follow logs
kubectl logs -f -n suma-chat <pod-name>

# All containers
kubectl logs -n suma-ecommerce --all-containers=true -l app=suma-ecommerce

# Previous container (crashed)
kubectl logs -n suma-office <pod-name> --previous
```

### Resource Usage
```bash
# Node resources
kubectl top nodes

# Pod resources
kubectl top pods -A

# Specific namespace
kubectl top pods -n suma-ecommerce
```

## 🎓 Next Steps

1. ✅ Deploy to development: `./deploy.sh dev`
2. ✅ Add hosts entries (see DEPLOYMENT.md)
3. ✅ Test all applications
4. ✅ Configure monitoring alerts
5. ✅ Setup backup strategy
6. ✅ Deploy to production: `./deploy.sh production`

## 📞 Support

**Issues?** Check:
1. Logs: `kubectl logs -n <namespace> <pod-name>`
2. Events: `kubectl get events -n <namespace>`
3. Documentation: `DEPLOYMENT.md`
4. Contact DevOps team

---

**Version:** 1.0.0  
**Last Updated:** October 2025  
**Maintained by:** DevOps Team
