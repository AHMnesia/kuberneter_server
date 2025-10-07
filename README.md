# 🚀 Suma Kubernetes Deployment

## ⚡ Quick Start (TL;DR)

**Just run this one command:**
```powershell
.\one-click.ps1
```
**That's it!** ✅ Auto-detects and handles everything.

---

## 📋 Overview

Complete Kubernetes deployment for Suma applications:
- **NGINX**: Load balancer & reverse proxy
- **Suma Ecommerce**: Laravel API 
- **Suma Office**: Laravel API
- **Monitoring**: Prometheus, Grafana, AlertManager

---

## 📁 Simple Structure

```
k8s/
├── 🚀 one-click.ps1          👈 Main script - daily use!
├── 🔨 build-images.ps1       👈 Build images + NGINX config!
├── 🏗️ deploy.ps1             👈 Deploy to Kubernetes!
├── nginx/                    (NGINX load balancer config)
├── suma-ecommerce/           (Ecommerce API deployment)
├── suma-office/              (Office API deployment)
└── monitoring/               (Prometheus & Grafana)
```

**Simple & Clean** - Hanya 3 script utama! 🎯

---

## 🎯 Usage

### **🆕 First Time Setup:**
```powershell
.\one-click.ps1
```
- Auto-detects fresh setup
- Builds Docker images + updates NGINX config  
- Deploys complete infrastructure
- **Time:** ~5-10 minutes

### **💻 Daily Development:**
```powershell
.\one-click.ps1  # Always updates nginx config + restarts services!
```
**✅ Smart and comprehensive**: 
- Existing deployment = Update nginx + build images + restart services (~2-3 min)
- No deployment = Full build & deploy (~5-10 min)
- **Always ensures nginx config is up-to-date!**

### **🔨 Manual Build (when needed):**
```powershell
.\build-images.ps1  # Build images + update NGINX config
```

### **🏗️ Manual Deploy (when needed):**
```powershell
.\deploy.ps1       # Deploy/update Kubernetes resources
```

---

## 🔄 Development Workflow

### **📈 Common Scenarios:**

| **Scenario** | **Command** | **What Happens** | **Time** |
|--------------|-------------|------------------|----------|
| **First time setup** | `.\one-click.ps1` | Full build + deploy + nginx | ~5-10 min |
| **Daily development** | `.\one-click.ps1` | Build + nginx + restart | ~2-3 min |
| **Manual build only** | `.\build-images.ps1` | Build + nginx update | ~1-2 min |
| **Manual deploy only** | `.\deploy.ps1` | Deploy/update resources | ~1-2 min |

### **🎯 Smart Detection Logic:**
- **No K8s deployed** → Full setup (build + deploy + nginx)
- **K8s exists** → Update nginx + build + restart (comprehensive update)
- **Manual operations** → Use individual scripts for specific tasks

---

## 🌐 Access Applications

After deployment, access your applications:

### **🖥️ Main Applications:**
- **Localhost**: `http://localhost`
- **Virtual Domain**: `http://api.public.suma-honda.id`

### **🔗 API Endpoints:**
```
http://localhost/suma-office/api/*
http://localhost/suma-ecommerce/api/*
http://api.public.suma-honda.id/suma-office/api/*
http://api.public.suma-honda.id/suma-ecommerce/api/*
```

### **📊 Monitoring:**
- **Grafana**: `http://localhost:3000` (admin/admin)
- **Prometheus**: `http://localhost:9090`
- **AlertManager**: `http://localhost:9093`

---

## 🛠️ Troubleshooting

### **Common Issues:**

1. **"kubectl not found"**
   ```powershell
   # Install kubectl first
   winget install kubectl
   ```

2. **"Docker not found"**
   ```powershell
   # Install Docker Desktop first
   winget install Docker.DockerDesktop
   ```

3. **Pods not starting**
   ```powershell
   # Check pod status
   kubectl get pods --all-namespaces
   
   # Check logs
   kubectl logs -n suma-office deployment/suma-office-api
   ```

4. **NGINX not accessible**
   ```powershell
   # Check nginx service
   kubectl get svc -n nginx-system
   
   # Check nginx logs
   kubectl logs -n nginx-system deployment/nginx-proxy
   ```

---

## 📚 Technical Details

### **🏗️ Architecture:**
- **Load Balancer**: NGINX (with virtual domain support)
- **Container Runtime**: Docker Desktop with Kubernetes
- **Image Registry**: Local Docker (no external registry needed)
- **Storage**: Local PersistentVolumes
- **Monitoring**: Prometheus + Grafana stack

### **🔧 Configuration:**
- **Namespaces**: `nginx-system`, `suma-office`, `suma-ecommerce`, `monitoring`
- **Services**: ClusterIP for internal, LoadBalancer for external access
- **ConfigMaps**: NGINX configuration with dual domain support
- **Secrets**: SSL certificates (if available)

### **📊 Resource Requirements:**
- **CPU**: ~2 cores minimum
- **Memory**: ~4GB minimum  
- **Storage**: ~10GB for images and data
- **Network**: LoadBalancer support (Docker Desktop provides this)

### **🔄 Script Details:**

#### **📋 Simplification Summary:**

**Before (Complex):**
- 7 scripts: `one-click.ps1`, `build-images.ps1`, `deploy.ps1`, `manual-rebuild.ps1`, `nginx-helpers.ps1`, `add-new-service.ps1`, `validate-nginx-config.ps1`
- Confusing dependencies and scattered responsibilities

**After (Simple):**
- **3 scripts** with clear responsibilities:

#### **1. `one-click.ps1` - Main Orchestrator**
- Daily use script with smart detection
- Calls other scripts as needed
- User-friendly interface

#### **2. `build-images.ps1` - Build Everything**  
- Build Docker images
- Update NGINX configuration
- Self-contained (no external dependencies)

#### **3. `deploy.ps1` - Deploy to Kubernetes**
- Pure deployment logic
- Create namespaces, secrets, deployments
- Wait for rollouts and status reporting

#### **🎯 Benefits of Simplification:**
1. **Simpler**: 3 scripts vs 7 scripts
2. **Clearer**: Each script has one clear purpose  
3. **Self-contained**: No external dependencies
4. **User-friendly**: `one-click.ps1` handles 90% of use cases
5. **Maintainable**: Less code, easier to debug

---

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch
3. Make changes to the appropriate service
4. Test with `.\one-click.ps1`
5. Submit a pull request

---

## 📄 License

This project is licensed under the MIT License.

---

## 🆘 Support

Need help? Check:
1. **This README** first
2. **Kubernetes Dashboard**: `kubectl proxy` then visit `http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/`
3. **Application Logs**: `kubectl logs -f deployment/<app-name> -n <namespace>`
4. **Contact**: Your development team

---

**🎉 Happy Coding!** 
