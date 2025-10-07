# Redis Global Addition - Summary

## 🎯 Objective

Menambahkan **Redis Cluster** sebagai shared cache global yang dapat digunakan oleh semua aplikasi dalam Suma Platform.

## ✅ Changes Made

### 1. Chart Updates

#### Added Redis Cluster Chart
- ✅ Location: `helm/charts/redis-cluster/`
- ✅ Components:
  - `Chart.yaml` - Chart metadata (v0.1.0, Redis 7.2)
  - `values.yaml` - Configuration values
  - `templates/statefulset.yaml` - Redis StatefulSet
  - `templates/service.yaml` - Headless service
  - `templates/_helpers.tpl` - Template helpers

#### Updated Main Chart
- ✅ File: `Chart.yaml`
- ✅ Added redis-cluster as first dependency (deploy first)
- ✅ Order: redis-cluster → elasticsearch → kibana → applications → monitoring

### 2. Configuration Updates

#### Development (`values-dev.yaml`)
```yaml
redis-cluster:
  enabled: true
  namespace: redis
  replicaCount: 1              # Single instance
  persistence:
    enabled: true
    size: 5Gi
    storageClass: standard
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 200m
      memory: 256Mi
```

#### Production (`values-production.yaml`)
```yaml
redis-cluster:
  enabled: true
  namespace: redis
  replicaCount: 3              # 3-node cluster
  persistence:
    enabled: true
    size: 20Gi
    storageClass: managed-premium
  cluster:
    enabled: true              # Cluster mode
  resources:
    requests:
      cpu: 200m
      memory: 256Mi
    limits:
      cpu: 1
      memory: 1Gi
```

### 3. Deployment Script Updates

#### PowerShell (`deploy.ps1`)
- ✅ Added `redis` namespace to all namespace arrays
- ✅ Added `redis-cluster` as first chart to deploy
- ✅ Updated namespace counts (9 → 10)
- ✅ Updated chart counts (9 → 10)

#### Bash (`deploy.sh`)
- ✅ Added `redis` namespace to all namespace arrays
- ✅ Added `redis-cluster:redis` as first chart entry
- ✅ Consistent with PowerShell version

### 4. Documentation Updates

#### README.md
- ✅ Updated component count: Infrastructure (3 → 4)
- ✅ Added Redis section dengan access examples
- ✅ Added PHP (Laravel) connection example
- ✅ Added Node.js connection example
- ✅ Updated deployment time (5-10min → 6-12min)
- ✅ Updated namespace count (9 → 10)
- ✅ Updated memory requirements (8GB → 10GB recommended)
- ✅ Added Redis troubleshooting section

#### QUICK_REFERENCE.md
- ✅ Added Redis to namespace table
- ✅ Added Redis access URL
- ✅ Added Redis monitoring commands

## 📊 Redis Cluster Details

### Architecture

**Development:**
```
redis namespace
  └── redis-cluster StatefulSet
      └── redis-cluster-0 (single pod)
          ├── Port: 6379
          ├── Storage: 5Gi PVC
          └── Memory: 256Mi limit
```

**Production:**
```
redis namespace
  └── redis-cluster StatefulSet
      ├── redis-cluster-0 (master)
      ├── redis-cluster-1 (replica)
      └── redis-cluster-2 (replica)
          ├── Port: 6379
          ├── Cluster Mode: Enabled
          ├── Storage: 20Gi PVC each
          └── Memory: 1Gi limit each
```

### Service Discovery

**Internal DNS:**
```
redis-cluster.redis.svc.cluster.local:6379
```

**Short form (same namespace):**
```
redis-cluster:6379
```

**Full form (from any namespace):**
```
redis-cluster.redis.svc.cluster.local:6379
```

## 🔌 Integration Examples

### Laravel (PHP)

**Environment Configuration:**
```env
REDIS_HOST=redis-cluster.redis.svc.cluster.local
REDIS_PORT=6379
REDIS_PASSWORD=null
REDIS_DB=0

# Session configuration
SESSION_DRIVER=redis
SESSION_CONNECTION=default

# Cache configuration
CACHE_DRIVER=redis
CACHE_CONNECTION=default

# Queue configuration
QUEUE_CONNECTION=redis
REDIS_QUEUE=default
```

**Config File (config/database.php):**
```php
'redis' => [
    'client' => 'phpredis', // or 'predis'
    
    'default' => [
        'host' => env('REDIS_HOST', '127.0.0.1'),
        'password' => env('REDIS_PASSWORD', null),
        'port' => env('REDIS_PORT', 6379),
        'database' => env('REDIS_DB', 0),
    ],
    
    'cache' => [
        'host' => env('REDIS_HOST', '127.0.0.1'),
        'password' => env('REDIS_PASSWORD', null),
        'port' => env('REDIS_PORT', 6379),
        'database' => env('REDIS_CACHE_DB', 1),
    ],
],
```

**Usage:**
```php
// Cache
Cache::put('user.'.$id, $user, 3600);
$user = Cache::get('user.'.$id);
Cache::forget('user.'.$id);

// Session
session()->put('key', 'value');
$value = session('key');

// Queue
dispatch(new ProcessOrder($order));
```

### Node.js

**Package Installation:**
```bash
npm install redis
# or
yarn add redis
```

**Connection:**
```javascript
const redis = require('redis');

const client = redis.createClient({
  socket: {
    host: 'redis-cluster.redis.svc.cluster.local',
    port: 6379
  }
});

client.on('error', (err) => console.log('Redis Client Error', err));

await client.connect();

// Usage
await client.set('key', 'value');
const value = await client.get('key');
await client.del('key');

// With expiration
await client.setEx('key', 3600, 'value'); // 1 hour TTL
```

**For Suma Chat (Socket.io with Redis):**
```javascript
const { Server } = require('socket.io');
const { createAdapter } = require('@socket.io/redis-adapter');
const { createClient } = require('redis');

const io = new Server(server);

const pubClient = createClient({
  socket: {
    host: 'redis-cluster.redis.svc.cluster.local',
    port: 6379
  }
});

const subClient = pubClient.duplicate();

Promise.all([pubClient.connect(), subClient.connect()]).then(() => {
  io.adapter(createAdapter(pubClient, subClient));
});
```

## 🛠️ Redis Management

### Access Redis CLI

```bash
# Connect to Redis pod
kubectl exec -it -n redis redis-cluster-0 -- redis-cli

# Test connection
kubectl exec -n redis redis-cluster-0 -- redis-cli ping
# Output: PONG

# Check cluster info (production)
kubectl exec -n redis redis-cluster-0 -- redis-cli cluster info

# Get all keys (dev only)
kubectl exec -n redis redis-cluster-0 -- redis-cli keys '*'

# Monitor commands
kubectl exec -n redis redis-cluster-0 -- redis-cli monitor
```

### Check Redis Status

```bash
# Pod status
kubectl get pods -n redis

# StatefulSet status
kubectl get statefulset -n redis

# Service status
kubectl get svc -n redis

# PVC status
kubectl get pvc -n redis

# Resource usage
kubectl top pods -n redis
```

### Redis Logs

```bash
# View logs
kubectl logs -n redis redis-cluster-0

# Follow logs
kubectl logs -f -n redis redis-cluster-0

# Previous logs (if crashed)
kubectl logs -n redis redis-cluster-0 --previous
```

## 🔍 Testing Redis

### From Application Pod

```bash
# Enter application pod
kubectl exec -it -n suma-ecommerce <pod-name> -- bash

# Install redis-cli (if not available)
apt-get update && apt-get install -y redis-tools

# Test connection
redis-cli -h redis-cluster.redis.svc.cluster.local -p 6379 ping

# Set/Get value
redis-cli -h redis-cluster.redis.svc.cluster.local -p 6379 set test "Hello Redis"
redis-cli -h redis-cluster.redis.svc.cluster.local -p 6379 get test
```

### From Local Machine (Port Forward)

```bash
# Forward Redis port
kubectl port-forward -n redis redis-cluster-0 6379:6379

# In another terminal
redis-cli -h localhost -p 6379 ping
redis-cli -h localhost -p 6379 info
redis-cli -h localhost -p 6379 monitor
```

## 📈 Performance Tuning

### Memory Management

```yaml
# values-production.yaml
redis-cluster:
  config:
    maxmemory: 256mb              # Per pod
    maxmemoryPolicy: allkeys-lru  # Eviction policy
```

**Eviction Policies:**
- `noeviction` - Return errors when memory limit reached
- `allkeys-lru` - Remove least recently used keys
- `allkeys-lfu` - Remove least frequently used keys
- `volatile-lru` - Remove LRU keys with expire set
- `volatile-ttl` - Remove keys with shortest TTL

### Persistence

```yaml
redis-cluster:
  persistence:
    enabled: true                 # Enable AOF persistence
    size: 20Gi
    storageClass: managed-premium # Fast storage
```

## 🔐 Security Considerations

### 1. Network Isolation

```yaml
# NetworkPolicy untuk Redis (to be added)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: redis-allow-apps
  namespace: redis
spec:
  podSelector:
    matchLabels:
      app: redis-cluster
  ingress:
    - from:
      - namespaceSelector:
          matchLabels:
            name: suma-android
      - namespaceSelector:
          matchLabels:
            name: suma-ecommerce
      - namespaceSelector:
          matchLabels:
            name: suma-office
      - namespaceSelector:
          matchLabels:
            name: suma-pmo
      - namespaceSelector:
          matchLabels:
            name: suma-chat
      ports:
        - protocol: TCP
          port: 6379
```

### 2. Authentication (Production)

**Add to values-production.yaml:**
```yaml
redis-cluster:
  auth:
    enabled: true
    password: <strong-random-password>
```

**Application Connection:**
```php
// Laravel
REDIS_PASSWORD=your-secure-password

// Node.js
const client = redis.createClient({
  socket: { host: '...', port: 6379 },
  password: 'your-secure-password'
});
```

## 📊 Monitoring Metrics

### Key Metrics to Monitor

```bash
# Memory usage
kubectl exec -n redis redis-cluster-0 -- redis-cli info memory

# Stats
kubectl exec -n redis redis-cluster-0 -- redis-cli info stats

# Clients
kubectl exec -n redis redis-cluster-0 -- redis-cli info clients

# Replication (production cluster)
kubectl exec -n redis redis-cluster-0 -- redis-cli info replication
```

### Grafana Dashboard

Prometheus metrics exposed by Redis:
- `redis_up` - Redis availability
- `redis_connected_clients` - Number of connected clients
- `redis_used_memory_bytes` - Memory usage
- `redis_commands_processed_total` - Total commands processed
- `redis_keyspace_hits_total` - Cache hit rate
- `redis_keyspace_misses_total` - Cache miss rate

## 🚨 Troubleshooting

### Redis Pod Not Starting

```bash
# Check pod status
kubectl describe pod -n redis redis-cluster-0

# Common issues:
# - PVC not binding: Check storage class
# - Resource limits: Check node resources
# - Image pull: Check image availability
```

### Connection Refused

```bash
# Check service
kubectl get svc -n redis

# Check endpoints
kubectl get endpoints -n redis

# Test from same namespace
kubectl run -it --rm debug --image=redis:7.2-alpine --restart=Never -n redis -- redis-cli -h redis-cluster ping
```

### High Memory Usage

```bash
# Check memory
kubectl exec -n redis redis-cluster-0 -- redis-cli info memory

# Flush database (CAUTION: dev only!)
kubectl exec -n redis redis-cluster-0 -- redis-cli flushall

# Restart pod
kubectl delete pod -n redis redis-cluster-0
```

## ✨ Benefits

### For Applications
1. ✅ Shared cache across all services
2. ✅ Faster response times
3. ✅ Reduced database load
4. ✅ Session management
5. ✅ Real-time features support

### For Operations
1. ✅ Centralized cache management
2. ✅ Consistent caching strategy
3. ✅ Easy monitoring
4. ✅ Scalable architecture
5. ✅ High availability (production)

### For Development
1. ✅ Consistent dev/prod environment
2. ✅ Easy testing
3. ✅ Quick setup
4. ✅ No additional configuration

## 📚 Next Steps

1. ✅ Deploy Redis: `./deploy.sh dev`
2. ✅ Test connectivity from apps
3. ✅ Update application configs dengan Redis host
4. ✅ Implement caching strategy
5. ✅ Monitor Redis metrics
6. ✅ Setup backup untuk production
7. ✅ Configure authentication untuk production

---

**Summary:** Redis Cluster berhasil ditambahkan sebagai komponen infrastructure global yang dapat digunakan oleh semua aplikasi untuk caching, session management, dan real-time features. ✨
