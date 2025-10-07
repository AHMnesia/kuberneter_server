# Suma Platform Setup Scripts

Script-script ini digunakan untuk setup dan konfigurasi komponen Suma Platform.

## Available Scripts

### 1. Webhook Task Scheduler

Setup suma-webhook untuk berjalan otomatis di host (bukan di Kubernetes).

**Files:**
- `setup-webhook-scheduler.ps1` - Windows (PowerShell)
- `setup-webhook-scheduler.sh` - Linux/Mac (Bash)

### 2. Kibana User Creation

Membuat user Kibana di Elasticsearch untuk koneksi Kibana.

**Files:**
- `create-kibana-user.ps1` - Windows (PowerShell)
- `create-kibana-user.sh` - Linux/Mac (Bash)

---

## Webhook Task Scheduler Setup

Script ini digunakan untuk mengatur suma-webhook agar berjalan otomatis di host. Webhook akan dijalankan sebagai background service menggunakan:
- **Windows**: Task Scheduler
- **Linux**: systemd service

### Kenapa di Host?

Suma-webhook dijalankan di host karena:
1. Webhook hanya untuk monitoring dan tidak perlu resource Kubernetes
2. Lebih mudah untuk debugging dan melihat log
3. Akses langsung ke port 5000 tanpa perlu expose melalui K8s

## File Script

- `setup-webhook-scheduler.ps1` - Script untuk Windows (PowerShell)
- `setup-webhook-scheduler.sh` - Script untuk Linux/Mac (Bash)

## Penggunaan

### Windows (PowerShell)

**Install/Setup:**
```powershell
# Jalankan sebagai Administrator
.\setup-webhook-scheduler.ps1
```

**Uninstall:**
```powershell
.\setup-webhook-scheduler.ps1 -Uninstall
```

**Command Lainnya:**
```powershell
# Lihat status task
Get-ScheduledTask -TaskName "SumaWebhookService"

# Start manual
Start-ScheduledTask -TaskName "SumaWebhookService"

# Stop
Stop-ScheduledTask -TaskName "SumaWebhookService"

# Cek apakah webhook running di port 5000
Get-NetTCPConnection -LocalPort 5000
```

### Linux/Mac (Bash)

**Install/Setup:**
```bash
# Jalankan dengan sudo
sudo ./setup-webhook-scheduler.sh install
```

**Status:**
```bash
sudo ./setup-webhook-scheduler.sh status
```

**Uninstall:**
```bash
sudo ./setup-webhook-scheduler.sh uninstall
```

**Command Lainnya:**
```bash
# Lihat status service
sudo systemctl status suma-webhook

# Start manual
sudo systemctl start suma-webhook

# Stop
sudo systemctl stop suma-webhook

# Restart
sudo systemctl restart suma-webhook

# Lihat log real-time
sudo journalctl -u suma-webhook -f

# Cek apakah webhook running di port 5000
sudo netstat -tlnp | grep :5000
```

## Cara Kerja

### Windows (Task Scheduler)

1. Script akan membuat scheduled task bernama `SumaWebhookService`
2. Task akan menjalankan `node webhook.js` di directory suma-webhook
3. Task diset untuk:
   - Start otomatis saat system boot
   - Restart otomatis jika crash (3x retry dengan interval 1 menit)
   - Running sebagai SYSTEM account
   - No execution time limit

### Linux (systemd)

1. Script akan membuat systemd service file di `/etc/systemd/system/suma-webhook.service`
2. Service akan menjalankan `node webhook.js` di directory suma-webhook
3. Service diset untuk:
   - Start otomatis saat system boot
   - Restart otomatis jika crash (setelah 10 detik)
   - Running sebagai user yang menjalankan script
   - Memory limit 512MB
   - Log ke systemd journal

## Prerequisites

### Semua Platform

1. **Node.js** harus sudah terinstall
   - Windows: Download dari https://nodejs.org/
   - Linux Ubuntu/Debian: 
     ```bash
     curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash -
     sudo apt-get install -y nodejs
     ```
   - Linux CentOS/RHEL:
     ```bash
     curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -
     sudo yum install -y nodejs
     ```
   - macOS: `brew install node`

2. **npm dependencies** (akan diinstall otomatis oleh script jika belum ada)
   - Script akan menjalankan `npm install --production` di folder suma-webhook

### Windows

- PowerShell 5.1 atau lebih baru
- Harus dijalankan sebagai Administrator

### Linux

- systemd (untuk service management)
- Harus dijalankan dengan sudo

## Integrasi dengan Deployment

Script ini akan dipanggil otomatis oleh deployment script:

**deploy.ps1 (Windows):**
```powershell
.\deploy.ps1 dev
# Akan memanggil setup-webhook-scheduler.ps1 jika running sebagai Administrator
```

**deploy.sh (Linux):**
```bash
./deploy.sh dev
# Akan memanggil setup-webhook-scheduler.sh jika running sebagai root/sudo
```

Jika deployment script tidak running dengan privilege yang cukup, webhook setup akan di-skip dan script akan menampilkan pesan cara menjalankan manual.

## Troubleshooting

### Windows

**Problem: Task tidak jalan**
```powershell
# Cek event log task scheduler
Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-TaskScheduler/Operational'; ID=119} | Select-Object -First 10
```

**Problem: Port 5000 sudah digunakan**
```powershell
# Cek process yang menggunakan port 5000
Get-NetTCPConnection -LocalPort 5000 | Select-Object -Property OwningProcess, State
Get-Process -Id <PID>

# Kill process jika perlu
Stop-Process -Id <PID> -Force
```

### Linux

**Problem: Service tidak jalan**
```bash
# Cek status detail
sudo systemctl status suma-webhook

# Cek log error
sudo journalctl -u suma-webhook --since "10 minutes ago"

# Reload service jika ada perubahan
sudo systemctl daemon-reload
sudo systemctl restart suma-webhook
```

**Problem: Port 5000 sudah digunakan**
```bash
# Cek process yang menggunakan port 5000
sudo netstat -tlnp | grep :5000
sudo lsof -i :5000

# Kill process jika perlu
sudo kill -9 <PID>
```

### Semua Platform

**Problem: webhook.js tidak ditemukan**
- Pastikan folder suma-webhook ada di struktur project
- Path yang dicari: `c:\docker\suma-webhook\webhook.js` (Windows) atau `/path/to/docker/suma-webhook/webhook.js` (Linux)

**Problem: Node.js tidak ditemukan**
- Install Node.js sesuai instruksi di atas
- Pastikan `node` ada di PATH
- Test: `node -v` harus menampilkan versi Node.js

**Problem: npm dependencies tidak terinstall**
- Masuk ke folder suma-webhook
- Jalankan: `npm install --production`
- Cek file `node_modules` sudah ada

### Testing

Setelah setup, test webhook:

```bash
# Test webhook endpoint (contoh)
curl http://localhost:5000/health

# Atau
curl http://localhost:5000/webhook
```

---

## Kibana User Creation

Script untuk membuat user Kibana di Elasticsearch. User ini diperlukan agar Kibana dapat terkoneksi ke Elasticsearch dengan credentials yang tepat.

### Penggunaan

#### Windows (PowerShell)

**Basic usage:**
```powershell
.\create-kibana-user.ps1
```

**With custom parameters:**
```powershell
.\create-kibana-user.ps1 `
    -ElasticsearchDomain "search.suma-honda.id" `
    -ElasticsearchUser "elastic" `
    -ElasticsearchPass "admin123" `
    -KibanaUserName "kibana_user" `
    -KibanaUserPass "kibanapass"
```

#### Linux/Mac (Bash)

**Basic usage:**
```bash
./create-kibana-user.sh
```

**With custom parameters:**
```bash
./create-kibana-user.sh \
    --domain search.suma-honda.id \
    --user elastic \
    --pass admin123 \
    --kibana-user kibana_user \
    --kibana-pass kibanapass
```

**View help:**
```bash
./create-kibana-user.sh --help
```

### Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `ElasticsearchDomain` / `--domain` | Elasticsearch domain | `search.suma-honda.local` |
| `ElasticsearchUser` / `--user` | Elasticsearch admin user | `elastic` |
| `ElasticsearchPass` / `--pass` | Elasticsearch admin password | `admin123` |
| `KibanaUserName` / `--kibana-user` | Kibana username to create | `kibana_user` |
| `KibanaUserPass` / `--kibana-pass` | Kibana user password | `kibanapass` |
| `MaxWaitSeconds` / `--max-wait` | Max wait time for ES | `300` |

### Apa yang Dilakukan Script?

1. **Check prerequisites** - Memastikan curl tersedia
2. **Wait for Elasticsearch** - Menunggu Elasticsearch siap (max 5 menit)
3. **Create Kibana user** - Membuat user dengan role `kibana_system`
4. **Verify user** - Memverifikasi user berhasil dibuat

### Kibana Configuration

Setelah user dibuat, update konfigurasi Kibana:

**values-dev.yaml / values-production.yaml:**
```yaml
kibana:
  env:
    ELASTICSEARCH_HOSTS: "https://elasticsearch-master.elasticsearch.svc.cluster.local:9200"
    ELASTICSEARCH_USERNAME: "kibana_user"
    ELASTICSEARCH_PASSWORD: "kibanapass"
```

**Atau update via kubectl:**
```bash
# Edit configmap
kubectl edit configmap kibana-config -n kibana

# Restart Kibana pods
kubectl rollout restart deployment kibana -n kibana
```

### Troubleshooting

#### Problem: Elasticsearch tidak accessible

**Check:**
```bash
# Windows
nslookup search.suma-honda.local
curl -k -u elastic:admin123 https://search.suma-honda.local/

# Linux
nslookup search.suma-honda.local
curl -k -u elastic:admin123 https://search.suma-honda.local/
```

**Fix:**
1. Check Elasticsearch pods: `kubectl get pods -n elasticsearch`
2. Check ingress: `kubectl get ingress -n elasticsearch`
3. Add to hosts file:
   - Windows: `C:\Windows\System32\drivers\etc\hosts`
   - Linux: `/etc/hosts`
   ```
   127.0.0.1 search.suma-honda.local
   ```

#### Problem: User already exists

Script akan menampilkan warning jika user sudah ada. Ini normal dan tidak error.

```
[!] Kibana user 'kibana_user' already exists
```

#### Problem: Wrong credentials

```
[x] Failed to create Kibana user
Response: {"error":{"root_cause":[{"type":"security_exception",...
```

**Fix:**
- Pastikan Elasticsearch admin credentials benar
- Default: `elastic:admin123`

#### Problem: curl not found

**Windows:**
- Windows 10+ sudah include curl
- Atau download: https://curl.se/windows/

**Linux:**
```bash
# Ubuntu/Debian
sudo apt-get install curl

# CentOS/RHEL
sudo yum install curl

# macOS
brew install curl
```

### Testing User

Setelah user dibuat, test dengan:

```bash
# Test authentication
curl -k -u kibana_user:kibanapass \
    https://search.suma-honda.local/_cluster/health

# Should return cluster health info
```

### Integration dengan Deployment

Script ini bisa dipanggil otomatis setelah Elasticsearch deploy, atau dijalankan manual setelah deployment selesai.

**Manual run after deployment:**
```powershell
# Windows
cd c:\docker\helm\perintah
.\create-kibana-user.ps1

# Linux
cd /path/to/docker/helm/perintah
./create-kibana-user.sh
```

---

## Catatan Penting

### Webhook
1. **Jangan deploy webhook ke Kubernetes** - webhook HANYA berjalan di host
2. **Chart suma-webhook** - hanya membuat Service/Endpoints/Ingress, bukan pod
3. **Port 5000 harus bebas** - pastikan tidak ada aplikasi lain yang menggunakan port 5000
4. **Backup script lama** - script di `k8s/update/suma-webhook-task-scheduler.ps1` adalah versi lama

### Kibana User
1. **Run after Elasticsearch ready** - tunggu Elasticsearch pod running dulu
2. **Update Kibana config** - jangan lupa update credentials di Kibana values
3. **Security** - ganti password default di production
4. **Role kibana_system** - role khusus untuk Kibana internal communication

## See Also

- [Main Deployment README](../README.md) - Deployment utama
- [Quick Reference](../QUICK_REFERENCE.md) - Command cheat sheet
- [Webhook Changes](WEBHOOK_CHANGES.md) - Perubahan webhook deployment
