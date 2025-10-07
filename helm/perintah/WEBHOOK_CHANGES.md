# Webhook Host Deployment - Changes Summary

## Tanggal: 7 Oktober 2025

### Masalah Awal
- Deploy script mencoba build image suma-webhook, padahal webhook seharusnya berjalan di host (bukan di Kubernetes)
- Webhook hanya butuh task scheduler untuk auto-start, tidak perlu container

### Perubahan yang Dilakukan

#### 1. **Script Task Scheduler Baru**
Dibuat 2 script baru di `helm/perintah/`:

**`setup-webhook-scheduler.ps1` (Windows)**
- Setup Task Scheduler untuk auto-start webhook
- Features:
  - Check Node.js dan npm dependencies
  - Install dependencies otomatis jika belum ada
  - Buat scheduled task dengan nama "SumaWebhookService"
  - Auto-restart jika crash (3x retry)
  - Running sebagai SYSTEM account
  - Support uninstall mode: `.\setup-webhook-scheduler.ps1 -Uninstall`
- Commands:
  - Install: `.\setup-webhook-scheduler.ps1`
  - Uninstall: `.\setup-webhook-scheduler.ps1 -Uninstall`
  - Status: `Get-ScheduledTask -TaskName "SumaWebhookService"`

**`setup-webhook-scheduler.sh` (Linux/Mac)**
- Setup systemd service untuk auto-start webhook
- Features:
  - Check Node.js dan npm dependencies
  - Install dependencies otomatis jika belum ada
  - Buat systemd service: `/etc/systemd/system/suma-webhook.service`
  - Auto-restart jika crash (10 detik delay)
  - Memory limit 512MB
  - Log ke journalctl
- Commands:
  - Install: `sudo ./setup-webhook-scheduler.sh install`
  - Status: `sudo ./setup-webhook-scheduler.sh status`
  - Uninstall: `sudo ./setup-webhook-scheduler.sh uninstall`

#### 2. **Update deploy.ps1**
- ✅ Remove suma-webhook dari build process
- ✅ Add fungsi `Setup-WebhookTaskScheduler`
- ✅ Call webhook setup sebelum deploy charts
- ✅ Skip webhook setup jika tidak running sebagai Administrator (dengan warning)
- ✅ Fix suma-office build (gunakan `dockerfile.api` bukan `dockerfile`)
- ✅ Remove suma-webhook dari semua namespace lists

#### 3. **Update deploy.sh**
- ✅ Remove suma-webhook dari build process
- ✅ Add fungsi `setup_webhook_scheduler`
- ✅ Call webhook setup sebelum deploy charts
- ✅ Skip webhook setup jika tidak running sebagai root (dengan warning)
- ✅ Remove suma-webhook dari semua namespace lists

#### 4. **Update Chart.yaml**
- ✅ Remove suma-webhook dari dependencies
- ✅ Add comment: "suma-webhook runs on host via task scheduler, not deployed to K8s"
- Total charts di K8s: 9 (redis-cluster, elasticsearch, kibana, suma-android, suma-ecommerce, suma-office, suma-pmo, suma-chat, monitoring)

#### 5. **Dokumentasi**
Dibuat `helm/perintah/README.md` yang berisi:
- Penjelasan kenapa webhook di host
- Cara penggunaan script untuk Windows dan Linux
- Prerequisites (Node.js, npm)
- Cara kerja Task Scheduler vs systemd
- Integration dengan deployment script
- Troubleshooting guide
- Testing guide

### Struktur Deployment Sekarang

**Di Kubernetes (9 charts):**
1. redis-cluster (namespace: redis)
2. elasticsearch (namespace: elasticsearch)
3. kibana (namespace: kibana)
4. suma-android (namespace: suma-android)
5. suma-ecommerce (namespace: suma-ecommerce)
6. suma-office (namespace: suma-office)
7. suma-pmo (namespace: suma-pmo)
8. suma-chat (namespace: suma-chat)
9. monitoring (namespace: monitoring)

**Di Host (tidak di K8s):**
- suma-webhook (port 5000, task scheduler/systemd)

### Alur Deployment

```
deploy.ps1/deploy.sh
  ├─> Test Prerequisites (kubectl, helm, docker, node)
  ├─> Build Images (5 images: android, ecommerce, office, pmo, chat)
  ├─> Setup cert-manager
  ├─> Create Namespaces (9 namespaces)
  ├─> Setup Webhook Scheduler ⭐ (NEW - setup task scheduler/systemd)
  ├─> Deploy Charts (9 charts ke K8s)
  ├─> Wait for Pods
  ├─> Show Status
  └─> Show URLs
```

### Testing

**Test deployment:**
```powershell
# Windows (sebagai Administrator)
cd c:\docker\helm
.\deploy.ps1 dev

# Linux (dengan sudo)
cd /path/to/docker/helm
sudo ./deploy.sh dev
```

**Test webhook scheduler manual:**
```powershell
# Windows
cd c:\docker\helm\perintah
.\setup-webhook-scheduler.ps1

# Linux
cd /path/to/docker/helm/perintah
sudo ./setup-webhook-scheduler.sh install
```

**Verify webhook running:**
```powershell
# Windows
Get-NetTCPConnection -LocalPort 5000
Get-ScheduledTask -TaskName "SumaWebhookService"

# Linux
sudo netstat -tlnp | grep :5000
sudo systemctl status suma-webhook
```

### Files Changed

1. `helm/deploy.ps1` - Updated
2. `helm/deploy.sh` - Updated
3. `helm/Chart.yaml` - Updated (removed suma-webhook dependency)
4. `helm/perintah/setup-webhook-scheduler.ps1` - Created
5. `helm/perintah/setup-webhook-scheduler.sh` - Created
6. `helm/perintah/README.md` - Created
7. `helm/perintah/WEBHOOK_CHANGES.md` - This file

### Notes

- Script lama di `k8s/update/suma-webhook-task-scheduler.ps1` tidak digunakan lagi
- Chart suma-webhook di `helm/charts/suma-webhook/` tetap ada tapi tidak di-deploy
- Namespace suma-webhook tidak akan dibuat di Kubernetes
- Port 5000 harus bebas di host untuk webhook
- Webhook akan auto-start saat system boot (Windows/Linux)

### Next Steps

1. ✅ Deploy ke development: `.\deploy.ps1 dev`
2. ⏳ Test webhook berjalan di port 5000
3. ⏳ Test webhook auto-start setelah reboot
4. ⏳ Deploy ke production: `.\deploy.ps1 production`
