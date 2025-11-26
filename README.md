# OpenShift Cluster Operator Monitoring with Dynatrace

Comprehensive solution for monitoring OpenShift cluster operator health using Dynatrace's Kubernetes Prometheus integration.

## Overview

This solution enables real-time monitoring of all OpenShift cluster operators (authentication, etcd, kube-apiserver, dns, ingress, network, etc.) with minimal configuration, leveraging your existing Dynatrace Operator deployment.

**Key Features**:
- ✅ Real-time operator health monitoring (Available/Degraded/Progressing)
- ✅ Pre-built dashboard with operator status matrix
- ✅ Automated setup script
- ✅ Complete alert configurations
- ✅ Monitors all 16 cluster operators automatically
- ✅ Low cost (~1-2 DDU/day)

## Prerequisites

- Dynatrace Operator deployed in OpenShift cluster
- OpenShift 4.x with Prometheus monitoring enabled
- Cluster-admin or equivalent permissions
- `oc` CLI installed and authenticated

## Quick Start

### 1. Clone Repository

```bash
git clone https://github.com/prem-dynatrace/openshift-instrumentation.git
cd openshift-instrumentation
```

### 2. Enable Prometheus Monitoring in Dynatrace

1. Navigate to: **Settings > Cloud and virtualization > Kubernetes**
2. Locate your OpenShift cluster
3. Enable:
   - ✅ **Enable monitoring**
   - ✅ **Monitor annotated Prometheus exporters**
4. Save changes

### 3. Run Automated Setup

```bash
./scripts/setup-operator-monitoring.sh
```

The script will:
- Create service account with monitoring permissions
- Generate authentication token
- Apply Dynatrace annotations to Prometheus
- Configure metric collection

### 4. Import Dashboard

1. In Dynatrace, navigate to: **Dashboards**
2. Click **Import**
3. Upload: `dashboards/openshift-operator-dashboard.json`
4. Save

### 5. Verify Metrics

Wait 3-5 minutes, then verify in Dynatrace:

```
Observe and explore > Metrics
Search: cluster_operator_conditions
```

You should see metrics for all 16 operators!

## Monitored Operators

All OpenShift cluster operators are monitored automatically:

| Operator | Criticality | Function |
|----------|-------------|----------|
| **etcd** | Critical | Cluster state database |
| **kube-apiserver** | Critical | Kubernetes API endpoint |
| **authentication** | High | User authentication |
| **dns** | High | Cluster DNS resolution |
| **ingress** | High | External traffic routing |
| **network** | High | Pod networking |
| **kube-controller-manager** | High | Controller operations |
| **kube-scheduler** | High | Pod scheduling |
| **openshift-apiserver** | High | OpenShift API |
| **openshift-controller-manager** | High | OpenShift controllers |
| **storage** | High | Volume provisioning |
| **cloud-credential** | Medium | Cloud credentials |
| **image-registry** | Medium | Image registry |
| **control-plane-machine-set** | Medium | Control plane machines |
| **operator-lifecycle-manager** | Medium | Operator management |
| **console** | Low | Web console |

## Repository Structure

```
openshift-instrumentation/
├── README.md                                    # This file
├── docs/
│   ├── implementation-guide.md                  # Detailed step-by-step guide
│   ├── alert-configuration.md                   # Alert setup instructions
│   ├── quick-reference-cheat-sheet.md           # Quick reference for ops
│   └── complete-guide.md                        # Comprehensive documentation
├── dashboards/
│   └── openshift-operator-dashboard.json        # Pre-built Dynatrace dashboard
└── scripts/
    └── setup-operator-monitoring.sh             # Automated setup script
```

## Documentation

### Getting Started
- **[Implementation Guide](docs/implementation-guide.md)** - Complete step-by-step implementation
- **[Quick Reference](docs/quick-reference-cheat-sheet.md)** - Commands and troubleshooting

### Configuration
- **[Alert Configuration](docs/alert-configuration.md)** - Setting up proactive alerts
- **[Complete Guide](docs/complete-guide.md)** - Full technical documentation

## Dashboard Features

The pre-built dashboard includes:

- **Critical Operators Matrix** - Health status of all operators at a glance
- **Degraded Count** - Color-coded count of degraded operators
- **Progressing Status** - Operators currently updating
- **24-Hour Trend** - Historical availability over time
- **Active Issues** - List of currently degraded/progressing operators
- **Investigation Guide** - Built-in troubleshooting steps

## Sample Dashboard View

```
┌─────────────────────────────────────────────────────────┐
│ 🎯 Critical Operators Status                            │
│                                                          │
│                Available  Degraded  Progressing          │
│ authentication      1         0          0              │
│ etcd                1         0          0              │
│ kube-apiserver      1         0          0              │
│ dns                 1         0          0              │
└─────────────────────────────────────────────────────────┘
```

## Alerting

Configure proactive alerts for:
- ⚠️ Any operator degraded
- 🔴 Critical operators unavailable
- 🟡 Operators stuck in progressing state
- 🔥 Multiple operators down simultaneously

See [Alert Configuration Guide](docs/alert-configuration.md) for detailed setup.

## Troubleshooting

### Metrics Not Appearing

**1. Check Dynatrace Operator**
```bash
oc get pods -n dynatrace
```

**2. Verify Service Annotations**
```bash
oc get service prometheus-k8s -n openshift-monitoring -o yaml | grep metrics.dynatrace
```

**3. Check ActiveGate Logs**
```bash
oc logs -n dynatrace $(oc get pods -n dynatrace -l app=dynatrace-activegate -o name | head -1) | grep prometheus
```

**4. Test Prometheus Endpoint**
```bash
oc exec -n openshift-monitoring $(oc get pods -n openshift-monitoring -l app.kubernetes.io/name=prometheus -o name | head -1) -- curl -k https://localhost:9091/metrics | grep cluster_operator
```

For detailed troubleshooting, see the [Implementation Guide](docs/implementation-guide.md#troubleshooting-guide).

## Implementation Time

- **Setup Script**: 5 minutes
- **Dashboard Import**: 2 minutes
- **Alert Configuration**: 30 minutes
- **Total**: ~45 minutes

## Cost

**Estimated DDU Consumption**: 1-2 DDU/day
- Metrics ingestion: ~0.5 DDU/day
- Dashboard queries: ~0.5 DDU/day
- Alert evaluation: minimal

## Manual Implementation

If you prefer manual setup over the automated script:

1. **Create service account**:
```bash
oc create serviceaccount prometheus-reader -n dynatrace-monitoring
oc adm policy add-cluster-role-to-user cluster-monitoring-view \
  system:serviceaccount:dynatrace-monitoring:prometheus-reader
```

2. **Annotate Prometheus service**:
```bash
oc annotate service prometheus-k8s -n openshift-monitoring \
  metrics.dynatrace.com/scrape="true" \
  metrics.dynatrace.com/port="9091" \
  metrics.dynatrace.com/path="/metrics" \
  metrics.dynatrace.com/secure="true" \
  metrics.dynatrace.com/insecure_skip_verify="true" \
  metrics.dynatrace.com/filter='{"mode": "include", "names": ["cluster_operator_conditions"]}' \
  --overwrite
```

## Support and Resources

- **GitHub Issues**: [Report issues or ask questions](https://github.com/prem-dynatrace/openshift-instrumentation/issues)
- **Dynatrace Docs**: [Kubernetes Monitoring](https://docs.dynatrace.com/docs/setup-and-configuration/setup-on-container-platforms/kubernetes)
- **OpenShift Docs**: [Cluster Operators](https://docs.openshift.com/container-platform/latest/operators/operator-reference.html)
- **Dynatrace Support**: [support.dynatrace.com](https://support.dynatrace.com)

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## Author

**Prem**  
Lead Customer Success Engineer, Dynatrace  
Singapore

## License

This project is provided as-is for Dynatrace customers and partners.

## Version History

- **v1.0.0** (November 2024) - Initial release
  - Complete implementation guide
  - Pre-built dashboard
  - Automated setup script
  - Alert configurations
  - Comprehensive documentation

## FAQ

**Q: Do I need OpenTelemetry Collector?**  
A: No! This solution uses Dynatrace's built-in Kubernetes Prometheus scraping.

**Q: Will this work with OpenShift 3?**  
A: This guide is for OpenShift 4.x. OpenShift 3 requires different annotation methods.

**Q: Can I monitor custom operators?**  
A: Yes! The `cluster_operator_conditions` metric automatically includes all cluster operators.

**Q: What if I don't have Dynatrace Operator?**  
A: See the [Complete Guide](docs/complete-guide.md) for alternative implementation methods including OpenTelemetry Collector.

**Q: How do I stop monitoring?**  
A: Remove the annotations:
```bash
oc annotate service prometheus-k8s -n openshift-monitoring \
  metrics.dynatrace.com/scrape- \
  metrics.dynatrace.com/port- \
  metrics.dynatrace.com/filter-
```

---

**⭐ If this solution helps you, please star the repository!**

For questions or support, open an [issue](https://github.com/prem-dynatrace/openshift-instrumentation/issues) or contact your Dynatrace Customer Success Engineer.
