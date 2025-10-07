# Changelog - Suma Platform Helm Deployment

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2025-10-07

### Added
- ✅ **Redis Cluster** - Global caching and session storage (3 nodes in production)
- ✅ Redis connection examples for Laravel and Node.js
- ✅ Redis monitoring and management commands
- ✅ Comprehensive Redis documentation (REDIS_ADDITION.md)
- ✅ Chart completeness verification (CHART_COMPLETENESS.md)

### Fixed
- 🐛 **CRITICAL:** Added missing charts to Chart.yaml dependencies:
  - suma-android (was missing, now added)
  - suma-pmo (was missing, now added)
  - suma-webhook (was missing, now added)
- 🐛 Chart.yaml now includes all 10 charts (was 7, now 10)
- 🐛 Deployment would have skipped 3 applications without this fix

### Changed
- 🔄 Organized Chart.yaml dependencies into logical groups:
  - Infrastructure (redis, elasticsearch, kibana)
  - Applications (6 apps)
  - Monitoring (prometheus/grafana)
- 🔄 Updated deployment time estimate (6-12 minutes with Redis)
- 🔄 Updated namespace count (9 → 10 with Redis)
- 🔄 Updated memory requirements (10GB recommended with Redis)

## [1.0.0] - 2025-10-07

### Added
- ✅ New unified deployment scripts (`deploy.ps1` and `deploy.sh`)
- ✅ Support for multiple environments (dev/production) dalam single script
- ✅ Comprehensive documentation (README.md, DEPLOYMENT.md, QUICK_REFERENCE.md)
- ✅ Individual chart deployment per namespace
- ✅ Automatic cert-manager setup dengan ClusterIssuer
- ✅ Colored output dengan status indicators
- ✅ Progress reporting dan status display
- ✅ Environment-specific URL listing
- ✅ Docker image building dengan environment-based tags
- ✅ Separate namespaces untuk each component (9 namespaces total)
- ✅ `.gitignore` untuk Helm-specific files
- ✅ Complete Helm templates untuk all applications:
  - Suma Android (deployment, service, ingress, hpa, pvc, networkpolicy, pdb, certificate)
  - Suma E-commerce (deployment, service, ingress, hpa, pvc, networkpolicy, pdb, certificate)
  - Suma Office (deployment, service, ingress, hpa, pvc, networkpolicy, pdb, certificate)
  - Suma PMO (deployment, service, ingress, hpa, pvc, networkpolicy, pdb, certificate)
  - Suma Chat (deployment, service, ingress, hpa, networkpolicy, pdb, certificate, _helpers.tpl)
  - Suma Webhook (deployment, service, ingress, certificate, endpoints)
- ✅ Infrastructure templates:
  - Elasticsearch (ingress, certificate, networkpolicy, pdb)
  - Kibana (certificate, networkpolicy, pdb)
  - Monitoring (ingress, certificate, networkpolicy, pvc, pdb)

### Changed
- 🔄 Deployment architecture dari single namespace ke per-component namespaces
- 🔄 Helm deployment dari umbrella chart ke individual charts
- 🔄 Image tagging strategy: environment-based (latest/production)
- 🔄 Domain configuration: environment-specific (.local vs .suma-honda.id)
- 🔄 Values file organization: standardized format across all charts
- 🔄 NetworkPolicy format: unified allowedNamespaces array pattern
- 🔄 Ingress format: multi-host configuration dengan proper paths
- 🔄 Optimized Kibana resources (500m→200m CPU, 1Gi→512Mi memory)

### Removed
- ❌ Old separate deployment scripts (deploy-dev.ps1, deploy-dev.sh)
- ❌ Single-namespace deployment approach
- ❌ Hardcoded environment configurations
- ❌ Inconsistent values.yaml formats
- ❌ Dead code dan unused configurations

### Fixed
- 🐛 Missing _helpers.tpl in suma-chat causing template errors
- 🐛 Inconsistent NetworkPolicy configurations across charts
- 🐛 Wrong domain suffixes in ingress configurations
- 🐛 Missing certificate templates untuk TLS support
- 🐛 Incorrect resource allocations
- 🐛 Missing PersistentVolumeClaim templates
- 🐛 Incomplete HorizontalPodAutoscaler configurations
- 🐛 Missing PodDisruptionBudget untuk high availability

### Security
- 🔐 Added NetworkPolicy untuk namespace isolation
- 🔐 TLS certificate support via cert-manager
- 🔐 Proper secrets management dalam values files
- 🔐 Resource limits untuk prevent resource exhaustion
- 🔐 PodDisruptionBudget untuk availability guarantees

## [0.2.0] - Previous Work

### Added
- Initial Helm chart structure
- Basic deployment configurations
- Manual K8s YAML files in k8s/ directory

### Changed
- Migrated from pure K8s YAML to Helm charts (partial)

## [0.1.0] - Initial

### Added
- Manual Kubernetes YAML deployments
- Individual application dockerfiles
- Basic service configurations

---

## Migration Summary

### From: Manual K8s Deployment (0.1.0)
- Individual YAML files per resource
- Manual kubectl apply commands
- No templating or reusability
- Environment-specific duplicate files

### To: Helm-based Deployment (1.0.0)
- Centralized Helm charts dengan templates
- Single command deployment
- Values-based configuration
- Environment overrides
- Automated rollback support

## Breaking Changes

### v0.x → v1.0.0

**Namespace Changes:**
- Old: Single namespace `suma-dev`
- New: Multiple namespaces per component

**Deployment Command:**
```bash
# Old
./deploy-dev.sh

# New
./deploy.sh dev
```

**Chart Installation:**
```bash
# Old
helm install suma-platform . -n suma-dev

# New
# Individual charts automatically deployed per namespace
./deploy.sh dev  # or ./deploy.ps1 dev
```

**Migration Steps:**
1. Uninstall old deployment: `helm uninstall suma-platform -n suma-dev`
2. Delete old namespace: `kubectl delete namespace suma-dev`
3. Run new script: `./deploy.sh dev`

## Future Roadmap

### v1.1.0 (Planned)
- [ ] CI/CD pipeline integration
- [ ] Automated testing
- [ ] Health check endpoints
- [ ] Backup automation
- [ ] Multi-region support

### v1.2.0 (Planned)
- [ ] Service mesh integration (Istio/Linkerd)
- [ ] Advanced monitoring dashboards
- [ ] Automated scaling policies
- [ ] Disaster recovery procedures
- [ ] Performance optimization

### v2.0.0 (Future)
- [ ] GitOps workflow (ArgoCD/Flux)
- [ ] Multi-cluster deployment
- [ ] Advanced security hardening
- [ ] Cost optimization
- [ ] Compliance automation

## Support

For questions or issues with specific versions:
- Check documentation for that version
- Review migration guides
- Contact DevOps team

---

**Note:** This project follows semantic versioning. Major version changes may include breaking changes.
