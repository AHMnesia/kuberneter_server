# Deployment Flow dengan Kibana User Creation

## Alur Deployment Baru

```
┌─────────────────────────────────────────────────────────────────┐
│                    DEPLOYMENT PHASES                            │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ PHASE 0: Prerequisites                                          │
├─────────────────────────────────────────────────────────────────┤
│ ✓ Check kubectl, helm, docker, node                            │
│ ✓ Build Docker images (android, ecommerce, office, pmo, chat)  │
│ ✓ Setup cert-manager                                            │
│ ✓ Create namespaces (10 namespaces)                            │
│ ✓ Setup Webhook Task Scheduler (on host)                       │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ PHASE 1: Infrastructure Deployment                             │
├─────────────────────────────────────────────────────────────────┤
│ 1. Deploy redis-cluster     → namespace: redis                 │
│ 2. Deploy elasticsearch     → namespace: elasticsearch          │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ WAIT: Elasticsearch Ready                                       │
├─────────────────────────────────────────────────────────────────┤
│ kubectl wait --for=condition=ready pod --all                    │
│   -n elasticsearch --timeout=300s                               │
│ sleep 10  # Extra initialization time                           │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ ⭐ CREATE KIBANA USER (NEW STEP)                               │
├─────────────────────────────────────────────────────────────────┤
│ Script: perintah/create-kibana-user.ps1 (.sh)                  │
│                                                                  │
│ Actions:                                                         │
│ 1. Wait for Elasticsearch accessible (https://domain/)         │
│ 2. Create user: kibana_user                                     │
│ 3. Set password: kibanapass                                     │
│ 4. Assign role: kibana_system                                   │
│ 5. Verify user created                                          │
│                                                                  │
│ Result: Kibana can now connect to Elasticsearch ✓              │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ PHASE 2: Applications Deployment                               │
├─────────────────────────────────────────────────────────────────┤
│ 3. Deploy kibana            → namespace: kibana                 │
│    (Uses kibana_user credentials created above)                │
│ 4. Deploy suma-android      → namespace: suma-android           │
│ 5. Deploy suma-ecommerce    → namespace: suma-ecommerce         │
│ 6. Deploy suma-office       → namespace: suma-office            │
│ 7. Deploy suma-pmo          → namespace: suma-pmo               │
│ 8. Deploy suma-chat         → namespace: suma-chat              │
│ 9. Deploy suma-webhook      → namespace: suma-webhook           │
│    (Service/Endpoints only, app runs on host)                  │
│ 10. Deploy monitoring       → namespace: monitoring             │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ PHASE 3: Verification                                           │
├─────────────────────────────────────────────────────────────────┤
│ ✓ Wait for all pods ready                                       │
│ ✓ Show deployment status                                        │
│ ✓ Show access URLs                                              │
└─────────────────────────────────────────────────────────────────┘
```

## Kenapa Harus Berurutan?

### Problem Sebelumnya ❌
```
Elasticsearch → Kibana (deploy bersamaan)
                  ↓
              Kibana ERROR: No user 'kibana_user' found
              Cannot connect to Elasticsearch
```

### Solusi Sekarang ✅
```
1. Elasticsearch deployed
       ↓
2. Wait until ready
       ↓
3. Create kibana_user ⭐
       ↓
4. Kibana deployed → SUCCESS! 
   Connects with kibana_user credentials
```

## Configuration

### Elasticsearch Credentials
- **Admin User**: `elastic`
- **Admin Pass**: `admin123`
- **Domain Dev**: `search.suma-honda.local`
- **Domain Prod**: `search.suma-honda.id`

### Kibana User Credentials (Created Automatically)
- **Username**: `kibana_user`
- **Password**: `kibanapass`
- **Role**: `kibana_system`

### Values Configuration

Script akan otomatis create user, dan Kibana values harus sudah di-set:

**values-dev.yaml:**
```yaml
kibana:
  env:
    ELASTICSEARCH_HOSTS: "https://elasticsearch-master.elasticsearch.svc.cluster.local:9200"
    ELASTICSEARCH_USERNAME: "kibana_user"
    ELASTICSEARCH_PASSWORD: "kibanapass"
    ELASTICSEARCH_SSL_VERIFICATIONMODE: "none"
```

**values-production.yaml:**
```yaml
kibana:
  env:
    ELASTICSEARCH_HOSTS: "https://elasticsearch-master.elasticsearch.svc.cluster.local:9200"
    ELASTICSEARCH_USERNAME: "kibana_user"
    ELASTICSEARCH_PASSWORD: "kibanapass"
    ELASTICSEARCH_SSL_VERIFICATIONMODE: "certificate"
```

## Deployment Commands

### Single Command (Recommended)
```powershell
# Windows
cd c:\docker\helm
.\deploy.ps1 dev

# Linux
cd /path/to/docker/helm
./deploy.sh dev
```

Script akan otomatis:
1. Deploy Elasticsearch
2. Wait sampai ready
3. **Create Kibana user** ⭐
4. Deploy Kibana (langsung bisa connect)
5. Deploy services lainnya

### Manual Steps (Jika Perlu)

Jika deployment di-skip atau error, bisa manual:

```powershell
# 1. Deploy Elasticsearch dulu
helm install elasticsearch ./charts/elasticsearch -n elasticsearch -f values-dev.yaml

# 2. Wait ready
kubectl wait --for=condition=ready pod --all -n elasticsearch --timeout=300s

# 3. Create Kibana user
cd perintah
.\create-kibana-user.ps1

# 4. Deploy Kibana
helm install kibana ./charts/kibana -n kibana -f values-dev.yaml
```

## Troubleshooting

### Problem: Kibana tidak bisa connect ke Elasticsearch

**Check:**
```bash
# 1. Apakah user kibana_user ada?
kubectl exec -it elasticsearch-master-0 -n elasticsearch -- \
  curl -k -u elastic:admin123 \
  https://localhost:9200/_security/user/kibana_user

# 2. Test authentication
curl -k -u kibana_user:kibanapass \
  https://search.suma-honda.local/_cluster/health
```

**Fix:**
```powershell
# Re-run user creation
cd c:\docker\helm\perintah
.\create-kibana-user.ps1

# Restart Kibana
kubectl rollout restart deployment kibana -n kibana
```

### Problem: Script create-kibana-user.ps1 error

**Check:**
```powershell
# Test Elasticsearch accessible
curl -k -u elastic:admin123 https://search.suma-honda.local/

# Check ingress
kubectl get ingress -n elasticsearch

# Check hosts file
cat C:\Windows\System32\drivers\etc\hosts | Select-String "search.suma-honda"
```

**Fix:**
```powershell
# Add to hosts (if missing)
Add-Content C:\Windows\System32\drivers\etc\hosts "127.0.0.1 search.suma-honda.local"

# Or use NodePort/LoadBalancer IP
kubectl get svc -n elasticsearch
```

## Benefits

### Otomatisasi ✅
- Tidak perlu manual create user
- Deployment script handle semua
- Kibana langsung ready pakai

### Reliability ✅
- Kibana pasti bisa connect
- Tidak ada error authentication
- Proper initialization sequence

### Maintainability ✅
- Credentials konsisten
- Easy troubleshooting
- Clear deployment phases

## See Also

- [Main README](../README.md) - Deployment guide
- [Perintah README](../perintah/README.md) - Script documentation
- [Create Kibana User](../perintah/create-kibana-user.ps1) - User creation script
