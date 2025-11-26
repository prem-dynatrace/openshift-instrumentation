# Dynatrace Alert Configuration for OpenShift Cluster Operators
# This file contains recommended alert configurations

---
## Alert 1: Critical Operator Degraded
**Alert Name**: OpenShift Critical Operator Degraded
**Severity**: ERROR
**Type**: Metric Event

### Configuration
```
Metric: cluster_operator_conditions
Dimensions:
  - condition = "Degraded"
  - name in ["authentication", "kube-apiserver", "etcd", "dns", "ingress", "network", "kube-controller-manager", "kube-scheduler", "openshift-apiserver", "service-ca", "storage"]

Threshold: value >= 1
Duration: 2 minutes
Evaluation Window: 5 minutes
Alert on Missing Data: No

Alert Properties:
  Title: "Critical OpenShift Operator Degraded: {name}"
  Description: |
    The OpenShift cluster operator {name} is in a DEGRADED state.
    This is a critical issue that may impact cluster functionality.
    
    Operator: {name}
    Condition: Degraded
    Status: ACTIVE
    
    Impact:
    - authentication: Users cannot login to the cluster
    - kube-apiserver: API calls may fail
    - etcd: Data inconsistency risk
    - dns: Service discovery broken
    - ingress: External traffic routing issues
    - network: Pod networking problems
    
    Investigation:
    1. Check operator pod status: oc get pods -n openshift-{name}
    2. Review operator logs: oc logs -n openshift-{name} <pod-name>
    3. Check operator events: oc describe clusteroperator {name}
    4. Review Dynatrace notebook for correlation
    
  Event Type: CUSTOM_ALERT
  Severity: ERROR
```

### DQL Query for Alert
```sql
fetch dt.metrics.cluster_operator_conditions
| filter condition == "Degraded" and value == 1
| filter name in ["authentication", "kube-apiserver", "etcd", "dns", "ingress", "network"]
| summarize degraded_count = count(), by: {name}
| filter degraded_count > 0
```

---
## Alert 2: Operator Unavailable
**Alert Name**: OpenShift Operator Unavailable
**Severity**: ERROR
**Type**: Metric Event

### Configuration
```
Metric: cluster_operator_conditions
Dimensions:
  - condition = "Available"

Threshold: value < 1
Duration: 5 minutes
Evaluation Window: 10 minutes
Alert on Missing Data: Yes

Alert Properties:
  Title: "OpenShift Operator Unavailable: {name}"
  Description: |
    The OpenShift cluster operator {name} is UNAVAILABLE.
    
    Operator: {name}
    Expected Status: Available = 1
    Current Status: Available = 0
    Duration: {duration}
    
    Immediate Actions:
    1. Check if operator pods are running: oc get pods -n openshift-{name}
    2. Check pod resources: oc top pods -n openshift-{name}
    3. Review recent events: oc get events -n openshift-{name} --sort-by='.lastTimestamp'
    4. Check node status if pods are pending
    
    Escalation:
    - If critical operator: Page on-call immediately
    - If non-critical: Create high-priority ticket
    
  Event Type: RESOURCE_CONTENTION
  Severity: ERROR
```

### DQL Query for Alert
```sql
fetch dt.metrics.cluster_operator_conditions
| filter condition == "Available" and value < 1
| summarize unavailable_duration = sum(duration), by: {name}
| filter unavailable_duration > 5m
```

---
## Alert 3: Operator Stuck in Progressing State
**Alert Name**: OpenShift Operator Stuck Progressing
**Severity**: WARNING
**Type**: Metric Event

### Configuration
```
Metric: cluster_operator_conditions
Dimensions:
  - condition = "Progressing"

Threshold: value == 1
Duration: 30 minutes
Evaluation Window: 60 minutes
Alert on Missing Data: No

Alert Properties:
  Title: "OpenShift Operator Stuck Progressing: {name}"
  Description: |
    The OpenShift cluster operator {name} has been in PROGRESSING state for over 30 minutes.
    This may indicate a stuck update or rollout.
    
    Operator: {name}
    State: Progressing
    Duration: {duration}
    
    This could indicate:
    - Update rollout in progress (normal)
    - Stuck rollout (requires intervention)
    - Configuration reconciliation
    - Resource constraints
    
    Investigation Steps:
    1. Check operator version: oc get clusteroperator {name} -o yaml | grep -A 5 versions
    2. Check rollout status: oc describe clusteroperator {name}
    3. Review operator pod events: oc get events -n openshift-{name}
    4. Check for image pull issues
    5. Verify sufficient cluster resources
    
    Action:
    - If > 60 minutes: Escalate to OpenShift admin
    - Check if cluster upgrade is in progress
    
  Event Type: PERFORMANCE_EVENT
  Severity: WARNING
```

### DQL Query for Alert
```sql
fetch dt.metrics.cluster_operator_conditions
| filter condition == "Progressing" and value == 1
| summarize progressing_duration = sum(duration), by: {name}
| filter progressing_duration > 30m
```

---
## Alert 4: Multiple Operators Degraded
**Alert Name**: Multiple OpenShift Operators Degraded
**Severity**: CRITICAL
**Type**: Custom Event

### Configuration
```
Query Type: DQL
Evaluation Interval: 1 minute

Query:
fetch dt.metrics.cluster_operator_conditions
| filter condition == "Degraded" and value == 1
| summarize degraded_count = count()
| filter degraded_count >= 3

Threshold: degraded_count >= 3
Duration: 1 minute

Alert Properties:
  Title: "CRITICAL: Multiple OpenShift Operators Degraded"
  Description: |
    {degraded_count} OpenShift cluster operators are currently DEGRADED.
    This indicates a systemic cluster issue.
    
    Count: {degraded_count} operators degraded
    Severity: CRITICAL
    
    Possible Causes:
    - Cluster-wide resource exhaustion
    - Network connectivity issues
    - Storage problems
    - Control plane issues
    - Failed cluster upgrade
    
    IMMEDIATE ACTIONS:
    1. Page SRE team immediately
    2. Check cluster overall health: oc get nodes
    3. Check control plane pods: oc get pods -n openshift-*
    4. Review cluster events: oc get events -A --sort-by='.lastTimestamp' | head -50
    5. Check etcd health
    6. Verify API server accessibility
    
    DO NOT PROCEED WITH:
    - Cluster upgrades
    - Major configuration changes
    - Operator updates
    
    ESCALATION PATH:
    1. SRE on-call (immediate)
    2. OpenShift SME (if not resolved in 15 minutes)
    3. Red Hat support case (if not resolved in 30 minutes)
    
  Event Type: RESOURCE_CONTENTION
  Severity: CRITICAL
```

---
## Alert 5: ETCD Operator Issues
**Alert Name**: ETCD Operator Health Issues
**Severity**: CRITICAL
**Type**: Metric Event

### Configuration
```
Metric: cluster_operator_conditions
Dimensions:
  - name = "etcd"
  - condition in ["Available", "Degraded"]

Conditions:
  Available: value < 1 for 2 minutes
  OR
  Degraded: value == 1 for 1 minute

Alert Properties:
  Title: "CRITICAL: ETCD Operator Health Issue"
  Description: |
    The ETCD operator is experiencing health issues.
    ETCD is the critical datastore for the entire cluster.
    
    Current Status:
    - Available: {available_value}
    - Degraded: {degraded_value}
    
    CRITICAL IMPACT:
    - Cluster state may become inconsistent
    - API operations may fail
    - Pod scheduling issues
    - ConfigMap/Secret operations fail
    - Potential data loss risk
    
    IMMEDIATE RESPONSE:
    1. **DO NOT RESTART ETCD PODS** unless instructed by SRE
    2. Check etcd pod status: oc get pods -n openshift-etcd
    3. Check etcd member health: oc exec -n openshift-etcd <pod> -- etcdctl member list
    4. Review etcd logs: oc logs -n openshift-etcd <pod> --tail=100
    5. Check etcd metrics in Dynatrace
    
    ESCALATION (IMMEDIATE):
    - This is a P1 incident
    - Page SRE lead immediately
    - Open Red Hat support case (Critical severity)
    - Prepare for possible cluster restore procedures
    
  Event Type: ERROR_EVENT
  Severity: CRITICAL
```

---
## Alert 6: Authentication Operator Down
**Alert Name**: Authentication Operator Down
**Severity**: ERROR
**Type**: Metric Event

### Configuration
```
Metric: cluster_operator_conditions
Dimensions:
  - name = "authentication"
  - condition = "Available"

Threshold: value < 1
Duration: 3 minutes

Alert Properties:
  Title: "Authentication Operator Unavailable"
  Description: |
    The OpenShift authentication operator is unavailable.
    Users cannot login to the cluster.
    
    Impact:
    - oc login commands will fail
    - Web console access blocked
    - API authentication issues
    - Service account token generation may fail
    
    Investigation:
    1. Check oauth pods: oc get pods -n openshift-authentication
    2. Check oauth-openshift pods: oc get pods -n openshift-authentication-operator
    3. Review authentication config: oc get oauth cluster -o yaml
    4. Check for identity provider issues
    5. Verify oauth certificates
    
    Workaround:
    - Existing authenticated sessions may continue to work
    - Emergency kubeconfig may be used if available
    
  Event Type: RESOURCE_CONTENTION
  Severity: ERROR
```

---
## Alert Notification Configuration

### Alerting Profile: OpenShift Operators
```yaml
Name: OpenShift Cluster Operators
Scope: 
  - Management Zone: "OpenShift Production"
  - Entity tags: "environment:production", "platform:openshift"

Severity Filters:
  - ERROR
  - CRITICAL

Notification Rules:

1. Critical Operators (Immediate):
   - Channel: PagerDuty
   - Operators: etcd, kube-apiserver, authentication
   - Response: Immediate page

2. Important Operators (5 min delay):
   - Channel: Slack + Email
   - Operators: dns, ingress, network, storage
   - Response: Alert ops team

3. Multiple Operators (Immediate):
   - Channel: PagerDuty + Slack
   - Condition: >= 3 operators degraded
   - Response: Major incident protocol

4. Stuck Progressing (30 min delay):
   - Channel: Email + Jira
   - Operators: All
   - Response: Create investigation ticket
```

### PagerDuty Integration
```
Service Name: OpenShift Cluster Operators
Integration Key: <your-integration-key>
Severity Mapping:
  - CRITICAL → P1
  - ERROR → P2
  - WARNING → P3
```

### Slack Integration
```
Channel: #openshift-alerts
Webhook URL: <your-webhook-url>
Message Format:
  - Include operator name
  - Include cluster name
  - Link to Dynatrace dashboard
  - Link to runbook
```

---
## Alert Maintenance Windows

### Planned Maintenance
```
Name: OpenShift Cluster Maintenance
Schedule: As needed
Duration: Configurable

Suppress Alerts:
  - All operator progressing alerts
  - Non-critical unavailable alerts

Keep Active:
  - ETCD issues
  - Multiple operators degraded (>3)
  - Authentication issues (if not maintenance-related)
```

---
## Alert Dashboard

### Metrics to Track
```
1. Total alerts triggered (last 30 days)
2. Mean Time to Alert (MTTA)
3. Mean Time to Resolution (MTTR)
4. False positive rate
5. Alert distribution by operator
6. Alert distribution by severity
```

### Review Schedule
- Daily: Review active alerts
- Weekly: Review alert trends
- Monthly: Tune thresholds and rules
- Quarterly: Full alert audit

---
## Testing Alert Configuration

### Test Procedure
1. **Create Test Scenario (Non-Prod Only)**
```bash
# Simulate degraded operator (DO NOT USE IN PRODUCTION)
oc scale deployment -n openshift-<operator> <deployment-name> --replicas=0
```

2. **Verify Alert Triggers**
   - Check alert appears in Dynatrace (within 2 minutes)
   - Verify notification is sent
   - Confirm correct severity
   - Validate alert description

3. **Restore Service**
```bash
oc scale deployment -n openshift-<operator> <deployment-name> --replicas=1
```

4. **Verify Alert Closes**
   - Confirm alert auto-resolves
   - Check resolution notification

---
## Runbook References

Each alert should link to appropriate runbooks:

- **ETCD Issues**: /runbooks/openshift/etcd-troubleshooting.md
- **API Server Issues**: /runbooks/openshift/apiserver-troubleshooting.md
- **Authentication Issues**: /runbooks/openshift/auth-troubleshooting.md
- **Network Issues**: /runbooks/openshift/network-troubleshooting.md
- **Storage Issues**: /runbooks/openshift/storage-troubleshooting.md
- **Multiple Operators**: /runbooks/openshift/cluster-health-check.md

---
## Change Log

| Date | Version | Changes | Author |
|------|---------|---------|--------|
| 2024-11 | 1.0 | Initial alert configuration | CSE Team |

---
## Notes

- All duration thresholds can be adjusted based on your environment
- Test alerts in non-production first
- Review and tune monthly based on alert fatigue
- Document any customizations
- Keep runbooks up to date
