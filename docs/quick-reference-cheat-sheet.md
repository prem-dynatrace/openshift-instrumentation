# OpenShift Operator Monitoring - Quick Reference
Last Updated: November 2024

---
## Understanding Operator Status

| Status | Value | Meaning | Action Required |
|--------|-------|---------|----------------|
| **AVAILABLE** | 1 (True) | ✅ Operator functioning normally | None |
| **AVAILABLE** | 0 (False) | ❌ Operator not functional | **IMMEDIATE** |
| **DEGRADED** | 1 (True) | ⚠️ Operator has errors | **URGENT** |
| **DEGRADED** | 0 (False) | ✅ No errors | None |
| **PROGRESSING** | 1 (True) | 🔄 Update/reconciliation in progress | Monitor |
| **PROGRESSING** | 0 (False) | ✅ Stable state | None |

---
## Critical Operators (Priority Order)

1. **etcd** - Cluster datastore (HIGHEST PRIORITY)
2. **kube-apiserver** - Kubernetes API
3. **authentication** - User/service login
4. **kube-controller-manager** - Core control loop
5. **kube-scheduler** - Pod scheduling
6. **dns** - Service discovery
7. **network** - Pod networking
8. **ingress** - External traffic routing
9. **storage** - Persistent volumes
10. **service-ca** - Certificate authority

---
## Quick Diagnostics

### Check All Operators
```bash
# View all operators
oc get clusteroperator

# Watch for changes
watch oc get clusteroperator

# JSON output for parsing
oc get clusteroperator -o json
```

### Check Specific Operator
```bash
# Detailed status
oc describe clusteroperator <operator-name>

# YAML output
oc get clusteroperator <operator-name> -o yaml

# Just conditions
oc get clusteroperator <operator-name> -o jsonpath='{.status.conditions[*].type}'
```

### Check Operator Pods
```bash
# List pods
oc get pods -n openshift-<operator-name>

# Check pod status
oc describe pod -n openshift-<operator-name> <pod-name>

# View logs
oc logs -n openshift-<operator-name> <pod-name>

# Previous logs (if crashed)
oc logs -n openshift-<operator-name> <pod-name> --previous
```

### Check Operator Events
```bash
# Recent events for operator
oc get events -n openshift-<operator-name> --sort-by='.lastTimestamp'

# All cluster events
oc get events -A --sort-by='.lastTimestamp' | grep -i <operator>
```

---
## Prometheus Metrics

### Key Metrics
```promql
# Operator availability (1 = available, 0 = unavailable)
cluster_operator_conditions{condition="Available"}

# Operator degraded status (1 = degraded, 0 = healthy)
cluster_operator_conditions{condition="Degraded"}

# Operator progressing status (1 = updating, 0 = stable)
cluster_operator_conditions{condition="Progressing"}
```

### Useful Queries
```promql
# Count degraded operators
count(cluster_operator_conditions{condition="Degraded", value="1"})

# List unavailable operators
cluster_operator_conditions{condition="Available", value="0"}

# Critical operators health
cluster_operator_conditions{name=~"etcd|kube-apiserver|authentication|dns"}

# Operators stuck progressing > 30m
(cluster_operator_conditions{condition="Progressing"} == 1) [30m]
```

---
## Dynatrace DQL Queries

### Dashboard Queries
```sql
// Current operator status
fetch dt.metrics.cluster_operator_conditions
| pivot condition, avg(value), by: {name}

// Degraded operators only
fetch dt.metrics.cluster_operator_conditions
| filter condition == "Degraded" and value == 1

// Availability over time
timeseries avg(cluster_operator_conditions{condition="Available"}), by: {name}

// Critical operators matrix
fetch dt.metrics.cluster_operator_conditions
| filter name in ["etcd", "kube-apiserver", "authentication"]
| pivot condition, avg(value), by: {name}
```

### Alert Queries
```sql
// Any degraded operator
fetch dt.metrics.cluster_operator_conditions
| filter condition == "Degraded" and value == 1
| summarize count = count()
| filter count > 0

// Multiple operators down
fetch dt.metrics.cluster_operator_conditions
| filter condition == "Available" and value == 0
| summarize count = count()
| filter count >= 3
```

---
## Common Issues & Solutions

### Issue: Operator Degraded

**Symptoms**: `DEGRADED = True`

**Investigation**:
1. Check pod status: `oc get pods -n openshift-<operator>`
2. Review logs: `oc logs -n openshift-<operator> <pod-name>`
3. Check events: `oc describe clusteroperator <operator>`
4. Verify resources: `oc top pods -n openshift-<operator>`

**Common Causes**:
- Resource exhaustion (CPU/Memory)
- Configuration errors
- Certificate expiration
- Dependency failures
- Network connectivity

**Resolution**:
- Review operator-specific runbooks
- Check for resource constraints
- Validate configuration
- Restart pods if safe (non-critical operators only)

---
### Issue: Operator Unavailable

**Symptoms**: `AVAILABLE = False`

**Investigation**:
1. Are pods running? `oc get pods -n openshift-<operator>`
2. Are pods ready? `oc get pods -n openshift-<operator> -o wide`
3. Recent events? `oc get events -n openshift-<operator>`
4. Node issues? `oc get nodes`

**Common Causes**:
- Pods not scheduled (resource constraints)
- Pods crashing (CrashLoopBackOff)
- Image pull failures
- Node issues
- API server connectivity

**Resolution**:
- Scale pods if needed
- Check image pull secrets
- Verify node capacity
- Review pod logs for errors

---
### Issue: Operator Stuck Progressing

**Symptoms**: `PROGRESSING = True` for > 30 minutes

**Investigation**:
1. Is update in progress? `oc get clusterversion`
2. Check operator versions: `oc get co <operator> -o yaml | grep version`
3. Pod rollout status: `oc rollout status -n openshift-<operator>`
4. Any failed pods? `oc get pods -n openshift-<operator>`

**Common Causes**:
- Cluster upgrade in progress (normal)
- Failed rollout
- Insufficient resources
- Configuration change reconciliation
- Image pull delays

**Resolution**:
- Wait if upgrade in progress
- Check rollout history
- Verify sufficient resources
- Review operator logs

---
## Alert Severity Matrix

| Operator | Degraded | Unavailable | Stuck Progressing |
|----------|----------|-------------|-------------------|
| etcd | 🔴 P1 | 🔴 P1 | 🟡 P2 |
| kube-apiserver | 🔴 P1 | 🔴 P1 | 🟡 P2 |
| authentication | 🔴 P2 | 🔴 P2 | 🟡 P3 |
| dns | 🔴 P2 | 🔴 P2 | 🟡 P3 |
| ingress | 🔴 P2 | 🔴 P2 | 🟡 P3 |
| network | 🔴 P2 | 🔴 P2 | 🟡 P3 |
| storage | 🔴 P2 | 🔴 P2 | 🟡 P3 |
| Others | 🟡 P3 | 🟡 P3 | ⚪ P4 |

🔴 = Critical (Immediate response)
🟡 = Warning (15-30 min response)
⚪ = Info (Investigation required)

---
## Escalation Matrix

### Level 1 - Operations Team
**Response Time**: 15 minutes
**Handles**:
- Non-critical operators
- Initial triage
- Log collection
- Basic troubleshooting

### Level 2 - OpenShift Administrators
**Response Time**: 30 minutes
**Handles**:
- Critical operator issues
- Configuration changes
- Cluster-wide issues
- Complex troubleshooting

### Level 3 - Red Hat Support
**Response Time**: As per SLA
**Handles**:
- Escalated issues
- Operator bugs
- Upgrade issues
- Data integrity concerns

**When to Escalate to Red Hat**:
- ETCD issues
- Multiple operators degraded (>3)
- Cluster upgrade failures
- Data loss concerns
- Unknown/unexplained behavior

---
## Monitoring Setup Checklist

### Initial Setup
- [ ] Prometheus endpoint configured
- [ ] Service account created
- [ ] Token generated and stored
- [ ] ActiveGate configured
- [ ] Metrics flowing to Dynatrace

### Dashboard Setup
- [ ] Dashboard imported
- [ ] Tiles configured
- [ ] Management zone assigned
- [ ] Auto-refresh enabled
- [ ] Shared with team

### Alerting Setup
- [ ] Critical operator alerts configured
- [ ] Notification channels tested
- [ ] Escalation paths defined
- [ ] Runbooks linked
- [ ] Maintenance windows configured

### Validation
- [ ] Metrics verified in Data Explorer
- [ ] Dashboard displays data
- [ ] Test alert triggered successfully
- [ ] Notifications received
- [ ] Team trained

---
## Useful Links

### Dynatrace
- Dashboard: `https://<tenant>.live.dynatrace.com/ui/dashboards/<dashboard-id>`
- Data Explorer: Settings > Data Explorer
- Metric Events: Settings > Anomaly Detection > Metric Events
- Notebooks: Apps > Notebooks

### OpenShift
- Operator Reference: https://docs.openshift.com/container-platform/latest/operators/operator-reference.html
- Monitoring Stack: https://docs.openshift.com/container-platform/latest/monitoring/
- Troubleshooting: https://docs.openshift.com/container-platform/latest/support/troubleshooting/

### Support
- Dynatrace Support: https://support.dynatrace.com
- Red Hat Support: https://access.redhat.com/support

---
## Emergency Contacts

```
Primary On-Call: <pager-duty-number>
OpenShift Team: <slack-channel>
Dynatrace Support: <support-email>
Red Hat Support: <support-portal>

Slack Channels:
  #openshift-alerts
  #dynatrace-monitoring
  #platform-incidents

War Room Bridge:
  <conference-bridge-number>
```

---
## Monthly Review Checklist

- [ ] Review alert trends
- [ ] Tune alert thresholds
- [ ] Update operator criticality
- [ ] Review MTTR metrics
- [ ] Update runbooks
- [ ] Test escalation procedures
- [ ] Review false positives
- [ ] Update dashboard
- [ ] Train new team members
- [ ] Document improvements

---
## One-Page Reference Card

```
╔══════════════════════════════════════════════════════════════╗
║         OPENSHIFT OPERATOR MONITORING - QUICK REF            ║
╠══════════════════════════════════════════════════════════════╣
║ CHECK STATUS:    oc get clusteroperator                      ║
║ CHECK DETAILS:   oc describe clusteroperator <name>          ║
║ CHECK PODS:      oc get pods -n openshift-<operator>         ║
║ CHECK LOGS:      oc logs -n openshift-<operator> <pod>       ║
╠══════════════════════════════════════════════════════════════╣
║ CRITICAL OPERATORS (Check First):                            ║
║   1. etcd              6. dns                                ║
║   2. kube-apiserver    7. network                            ║
║   3. authentication    8. ingress                            ║
║   4. kube-controller   9. storage                            ║
║   5. kube-scheduler   10. service-ca                         ║
╠══════════════════════════════════════════════════════════════╣
║ SEVERITY LEVELS:                                             ║
║   🔴 P1: etcd, kube-apiserver (Page immediately)            ║
║   🟡 P2: auth, dns, network, ingress (Alert ops)            ║
║   ⚪ P3: Others (Create ticket)                              ║
╠══════════════════════════════════════════════════════════════╣
║ ESCALATION:                                                  ║
║   L1 → Ops Team (15 min)                                     ║
║   L2 → OpenShift Admins (30 min)                             ║
║   L3 → Red Hat Support (As needed)                           ║
╠══════════════════════════════════════════════════════════════╣
║ PROMETHEUS METRIC:                                           ║
║   cluster_operator_conditions{condition="<type>"}            ║
║   Types: Available, Degraded, Progressing                    ║
║   Values: 1 (True), 0 (False)                                ║
╠══════════════════════════════════════════════════════════════╣
║ DYNATRACE DASHBOARD:                                         ║
║   Search: "OpenShift Cluster Operators Health"               ║
╠══════════════════════════════════════════════════════════════╣
║ EMERGENCY CONTACTS:                                          ║
║   PagerDuty: <number>                                        ║
║   Slack: #openshift-alerts                                   ║
║   Support: support@company.com                               ║
╚══════════════════════════════════════════════════════════════╝
```

---
**Print this page and keep it handy for quick reference!**
