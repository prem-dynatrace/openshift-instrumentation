# Monitoring OpenShift Cluster Operator Health with Dynatrace

## Executive Summary

This guide provides multiple approaches to monitor OpenShift cluster operator health (AVAILABLE, PROGRESSING, DEGRADED status) using Dynatrace, with step-by-step implementation instructions, dashboard examples, and alerting strategies.

## Understanding OpenShift Cluster Operators

OpenShift cluster operators manage core cluster functionality. The `oc get clusteroperator` command shows:
- **AVAILABLE**: Operator is functioning correctly
- **PROGRESSING**: Operator is being updated/reconciled
- **DEGRADED**: Operator has encountered an error
- **SINCE**: How long the operator has been in current state

Critical operators include:
- `authentication`, `kube-apiserver`, `etcd`, `dns`, `ingress`
- `kube-controller-manager`, `kube-scheduler`, `network`
- `openshift-apiserver`, `service-ca`, `storage`

---

## Solution 1: Prometheus Metrics Integration (RECOMMENDED)

### Why This Approach?
- ✅ Native OpenShift integration
- ✅ Real-time metrics
- ✅ No custom code required
- ✅ Leverages existing Prometheus infrastructure

### Prerequisites
- Dynatrace ActiveGate deployed (Environment or Cluster ActiveGate)
- Access to OpenShift Prometheus endpoint
- Service account with appropriate permissions

### Step 1: Identify OpenShift Prometheus Endpoint

```bash
# Get the Prometheus route in OpenShift
oc get route prometheus-k8s -n openshift-monitoring

# Or use internal service endpoint
# https://prometheus-k8s.openshift-monitoring.svc:9091
```

### Step 2: Create Service Account for Dynatrace

```bash
# Create namespace for Dynatrace monitoring resources
oc create namespace dynatrace-monitoring

# Create service account
cat <<EOF | oc apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: dynatrace-prometheus
  namespace: dynatrace-monitoring
EOF

# Grant cluster-monitoring-view role
oc adm policy add-cluster-role-to-user cluster-monitoring-view \
  system:serviceaccount:dynatrace-monitoring:dynatrace-prometheus

# Get the token
oc create token dynatrace-prometheus -n dynatrace-monitoring --duration=87600h
```

### Step 3: Configure ActiveGate Prometheus Scraping

Create a custom.properties file on your ActiveGate:

**Location**: `/var/lib/dynatrace/remotepluginmodule/agent/conf/custom.properties`

```properties
# OpenShift Prometheus Endpoint Configuration
[prometheus_openshift_operators]
enabled=true
endpoint=https://prometheus-k8s.openshift-monitoring.svc:9091
interval=60s
verify_ssl=true
bearer_token=<YOUR_SERVICE_ACCOUNT_TOKEN>

# Optional: If using self-signed certs
# verify_ssl=false
```

Alternatively, configure via Dynatrace UI:
1. Navigate to: **Settings > Cloud and virtualization > Prometheus**
2. Click **Add Prometheus endpoint**
3. Configure:
   - **Endpoint URL**: `https://prometheus-k8s.openshift-monitoring.svc:9091`
   - **Authentication**: Bearer token
   - **Token**: Paste service account token
   - **Scrape interval**: 60 seconds

### Step 4: Key Prometheus Metrics to Scrape

OpenShift exposes these critical metrics:

```promql
# Cluster Operator Conditions (0=False, 1=True)
cluster_operator_conditions{name="<operator-name>", condition="Available"}
cluster_operator_conditions{name="<operator-name>", condition="Progressing"}
cluster_operator_conditions{name="<operator-name>", condition="Degraded"}

# Cluster Operator Up status
cluster_operator_up{name="<operator-name>"}

# Cluster Version Operator metrics
cluster_version_available_updates
```

### Step 5: Metric Filtering (Optional)

To reduce metric ingestion, add filters in the Prometheus configuration:

```yaml
metric_filters:
  - metric: "cluster_operator_conditions"
    keep: true
  - metric: "cluster_operator_up"
    keep: true
  - metric: "cluster_version_*"
    keep: true
```

---

## Solution 2: Dynatrace Extensions 2.0

### When to Use This Approach?
- Need custom logic or enrichment
- Want to combine multiple data sources
- Require specific data transformations

### Extension Overview

Create a Python-based extension that queries OpenShift API:

**Extension Structure**:
```
openshift-operators/
├── extension.yaml
├── src/
│   └── main.py
└── README.md
```

### extension.yaml

```yaml
name: custom:openshift.operators
version: 1.0.0
minDynatraceVersion: "1.282"
author:
  name: "Your Name"

metrics:
  - key: openshift.operator.available
    metadata:
      displayName: "OpenShift Operator Available"
      description: "Whether the operator is available (1=True, 0=False)"
      unit: Count
    
  - key: openshift.operator.degraded
    metadata:
      displayName: "OpenShift Operator Degraded"
      description: "Whether the operator is degraded (1=True, 0=False)"
      unit: Count
    
  - key: openshift.operator.progressing
    metadata:
      displayName: "OpenShift Operator Progressing"
      description: "Whether the operator is progressing (1=True, 0=False)"
      unit: Count

topology:
  types:
    - name: openshift:cluster
      displayName: OpenShift Cluster
      rules:
        - idPattern: openshift_cluster_{cluster_name}
          sources:
            - sourceType: Metrics
              condition: $prefix(openshift.operator)
          attributes:
            - key: cluster_name
              displayName: Cluster Name

python:
  runtime:
    module: main
    version:
      min: "3.10"
  activation:
    remote:
      path: src/main.py
```

### src/main.py

```python
from dynatrace_extension import Extension, Status, StatusValue
import requests
import os

class OpenShiftOperatorExtension(Extension):
    def query(self):
        # Get OpenShift API endpoint and token from environment
        api_url = os.getenv('OPENSHIFT_API_URL')
        token = os.getenv('OPENSHIFT_TOKEN')
        
        headers = {
            'Authorization': f'Bearer {token}',
            'Accept': 'application/json'
        }
        
        # Query cluster operators
        response = requests.get(
            f'{api_url}/apis/config.openshift.io/v1/clusteroperators',
            headers=headers,
            verify=True
        )
        
        if response.status_code != 200:
            self.report_status(Status(StatusValue.ERROR, f"API call failed: {response.status_code}"))
            return
        
        operators = response.json()['items']
        
        for operator in operators:
            name = operator['metadata']['name']
            conditions = operator['status'].get('conditions', [])
            
            # Parse conditions
            available = 0
            degraded = 0
            progressing = 0
            
            for condition in conditions:
                if condition['type'] == 'Available':
                    available = 1 if condition['status'] == 'True' else 0
                elif condition['type'] == 'Degraded':
                    degraded = 1 if condition['status'] == 'True' else 0
                elif condition['type'] == 'Progressing':
                    progressing = 1 if condition['status'] == 'True' else 0
            
            # Report metrics
            self.report_metric(
                'openshift.operator.available',
                available,
                dimensions={'operator.name': name}
            )
            self.report_metric(
                'openshift.operator.degraded',
                degraded,
                dimensions={'operator.name': name}
            )
            self.report_metric(
                'openshift.operator.progressing',
                progressing,
                dimensions={'operator.name': name}
            )

def main():
    OpenShiftOperatorExtension().run()

if __name__ == '__main__':
    main()
```

### Deployment

```bash
# Build and sign extension
dt extension build
dt extension upload

# Create monitoring configuration in Dynatrace UI
# Settings > Monitoring > Monitored technologies > Add technology monitoring
# Select your custom extension and configure endpoints
```

---

## Solution 3: Kubernetes Events + Log Monitoring

### Approach Overview
- Monitor Kubernetes events related to operator state changes
- Parse OpenShift operator logs for error patterns
- Leverage existing Dynatrace Kubernetes integration

### Configuration

**1. Ensure Dynatrace Operator is deployed with events enabled**

```yaml
apiVersion: dynatrace.com/v1beta1
kind: DynaKube
metadata:
  name: dynakube
  namespace: dynatrace
spec:
  apiUrl: https://your-tenant.live.dynatrace.com/api
  oneAgent:
    cloudNativeFullStack:
      enabled: true
  activeGate:
    capabilities:
      - kubernetes-monitoring
    env:
      - name: DT_KUBERNETES_EVENTS_ENABLED
        value: "true"
```

**2. Create Log Processing Rules**

Navigate to: **Settings > Log Monitoring > Processing**

Create a rule to parse operator logs:

```
Matcher: content="clusteroperator" AND (content="degraded" OR content="unavailable")
Action: Extract attributes
  - operator_name from "clusteroperator/(?<operator_name>[a-z-]+)"
  - status from "status=(?<status>[A-Z]+)"
```

**3. Create Custom Events from Logs**

Navigate to: **Settings > Anomaly detection > Custom events for alerting**

```
Event name: OpenShift Operator Degraded
Query:
  fetch logs
  | filter k8s.namespace.name == "openshift-*"
  | filter matchesPhrase(content, "clusteroperator")
  | filter matchesPhrase(content, "degraded")
  | summarize count = count(), by: {k8s.pod.name, operator_name}
  | filter count > 0
```

---

## Solution 4: Workflow Automation (Quick Win)

### For Immediate Implementation

Create a Dynatrace Workflow that runs on schedule:

**Workflow Configuration:**

```yaml
name: OpenShift Operator Health Check
trigger:
  schedule:
    cron: "*/5 * * * *"  # Every 5 minutes
    timezone: "UTC"

tasks:
  - name: check_operators
    action: dynatrace.automations:run-javascript
    input:
      script: |
        import { execution } from '@dynatrace-sdk/automation-utils';
        import { eventsClient } from '@dynatrace-sdk/client-classic-environment-v2';
        
        export default async function ({ execution_id }) {
          // Execute oc command via ActiveGate
          const result = await executeCommand('oc get clusteroperator -o json');
          const operators = JSON.parse(result);
          
          for (const op of operators.items) {
            const name = op.metadata.name;
            const conditions = op.status.conditions;
            
            const available = conditions.find(c => c.type === 'Available')?.status === 'True';
            const degraded = conditions.find(c => c.type === 'Degraded')?.status === 'True';
            
            if (!available || degraded) {
              // Send custom event
              await eventsClient.createEvent({
                eventType: 'CUSTOM_ALERT',
                title: `OpenShift Operator ${name} is unhealthy`,
                properties: {
                  operator: name,
                  available: available,
                  degraded: degraded
                },
                entitySelector: 'type("KUBERNETES_CLUSTER")'
              });
            }
          }
        }
```

---

## Dashboard Creation

### Using DQL (Recommended for Prometheus Metrics)

**Dashboard: OpenShift Operator Health Overview**

```sql
// Tile 1: Operator Availability Status
timeseries available = avg(cluster_operator_conditions{condition="Available"}), 
           by: {name}
| fieldsAdd status = if(available == 1, "Available", "Unavailable")

// Tile 2: Degraded Operators
fetch dt.metrics.cluster_operator_conditions
| filter condition == "Degraded" and value == 1
| fieldsAdd operator = name
| fields operator, value

// Tile 3: Critical Operators Health Matrix
fetch dt.metrics.cluster_operator_conditions
| filter name in ["authentication", "kube-apiserver", "etcd", "dns", "ingress", "network"]
| pivot condition, avg(value)

// Tile 4: Operator State Duration
timeseries since = timestamp - (cluster_operator_conditions_since * 1000)
| fieldsAdd operator = name, condition
| filter condition == "Degraded" and value == 1

// Tile 5: Operators in Progressing State
fetch dt.metrics.cluster_operator_conditions
| filter condition == "Progressing" and value == 1
| summarize count = count(), by: {name}
```

### Dashboard JSON Template

```json
{
  "dashboardMetadata": {
    "name": "OpenShift Cluster Operators Health",
    "shared": true,
    "owner": "admin",
    "preset": true
  },
  "tiles": [
    {
      "name": "Operator Availability",
      "tileType": "DATA_EXPLORER",
      "configured": true,
      "query": "timeseries available = avg(cluster_operator_conditions{condition=\"Available\"}), by: {name}",
      "visualizationType": "GRAPH_CHART"
    },
    {
      "name": "Degraded Operators (Critical)",
      "tileType": "DATA_EXPLORER",
      "configured": true,
      "query": "fetch dt.metrics.cluster_operator_conditions | filter condition == \"Degraded\" and value == 1",
      "visualizationType": "SINGLE_VALUE",
      "thresholds": [
        {"value": 0, "color": "GREEN"},
        {"value": 1, "color": "RED"}
      ]
    },
    {
      "name": "Critical Operators Matrix",
      "tileType": "DATA_EXPLORER",
      "configured": true,
      "query": "fetch dt.metrics.cluster_operator_conditions | filter name in [\"authentication\", \"kube-apiserver\", \"etcd\"] | pivot condition, avg(value)",
      "visualizationType": "TABLE"
    }
  ]
}
```

---

## Alerting Configuration

### Metric Events for Alerting

**Navigate to**: Settings > Anomaly Detection > Metric events

**Alert 1: Critical Operator Degraded**

```
Metric: cluster_operator_conditions
Filter: 
  - condition = "Degraded"
  - name in ["authentication", "kube-apiserver", "etcd", "dns", "ingress", "network", "kube-controller-manager", "kube-scheduler"]

Threshold: value >= 1 for 2 minutes

Alert:
  Title: "Critical OpenShift Operator Degraded: {name}"
  Severity: ERROR
  Event type: CUSTOM_ALERT
```

**Alert 2: Operator Unavailable**

```
Metric: cluster_operator_conditions
Filter: 
  - condition = "Available"

Threshold: value < 1 for 5 minutes

Alert:
  Title: "OpenShift Operator Unavailable: {name}"
  Severity: ERROR
  Event type: RESOURCE_CONTENTION
```

**Alert 3: Operator Stuck in Progressing**

```
Metric: cluster_operator_conditions
Filter: 
  - condition = "Progressing"

Threshold: value == 1 for 30 minutes

Alert:
  Title: "OpenShift Operator Stuck Progressing: {name}"
  Severity: WARNING
  Event type: PERFORMANCE_EVENT
```

### Custom Event for Multiple Operators Down

```sql
fetch dt.metrics.cluster_operator_conditions
| filter condition == "Degraded" and value == 1
| summarize degraded_count = count()
| filter degraded_count >= 3
```

---

## Notebook for Investigation

### Create a Notebook for Troubleshooting

**Title**: OpenShift Operator Health Investigation

**Section 1: Current Operator Status**
```sql
fetch dt.metrics.cluster_operator_conditions
| filter in(timeframe(now()-5m, now()))
| pivot condition, avg(value), by: {name}
| sort name asc
```

**Section 2: Operator State History (24h)**
```sql
timeseries {
  available = avg(cluster_operator_conditions{condition="Available"}),
  degraded = avg(cluster_operator_conditions{condition="Degraded"}),
  progressing = avg(cluster_operator_conditions{condition="Progressing"})
}, by: {name}, interval: 5m
```

**Section 3: Correlated Pod Restarts**
```sql
fetch dt.entity.cloud_application
| filter k8s.namespace.name == "openshift-*"
| fields name = entity.name, restarts = k8s.container.restarts
| filter restarts > 0
| sort restarts desc
```

**Section 4: Related Kubernetes Events**
```sql
fetch events
| filter event.type == "k8s" 
| filter matchesPhrase(event.name, "operator")
| filter event.level == "ERROR"
| sort timestamp desc
| limit 50
```

**Section 5: Operator Pod Resource Usage**
```sql
timeseries {
  cpu = avg(builtin:containers.cpu.usagePercent),
  memory = avg(builtin:containers.memory.usagePercent)
}, by: {k8s.pod.name}
| filter k8s.namespace.name == "openshift-*"
```

---

## Site Reliability Guardian (SLO) Configuration

### Define SLOs for Cluster Operators

**SLO 1: Operator Availability**

```
Objective: 99.9% of time all critical operators are Available

Metric:
  Success: cluster_operator_conditions{condition="Available", name in [critical_operators]} == 1
  Total: cluster_operator_conditions{condition="Available", name in [critical_operators]}

Target: 99.9%
Warning: 99.5%
Timeframe: 7 days
```

**SLO 2: Degradation-Free Operation**

```
Objective: 99.95% of time no operators are Degraded

Metric:
  Success: count(cluster_operator_conditions{condition="Degraded", value=1}) == 0
  Total: All measurements

Target: 99.95%
Warning: 99.9%
Timeframe: 30 days
```

**SLO 3: Update Completion Time**

```
Objective: Operator updates complete within 30 minutes

Metric:
  Success: cluster_operator_conditions{condition="Progressing", value=1} duration < 30m
  Total: All operator updates

Target: 95%
Timeframe: 30 days
```

---

## Implementation Roadmap

### Phase 1: Quick Wins (Week 1)
1. ✅ Enable Kubernetes events monitoring in Dynatrace Operator
2. ✅ Create basic Workflow for operator health checks
3. ✅ Set up log processing rules for operator errors
4. ✅ Create initial dashboard with basic metrics

### Phase 2: Production Ready (Week 2-3)
1. ✅ Configure Prometheus metrics scraping
2. ✅ Create comprehensive dashboards with DQL
3. ✅ Set up metric-based alerting
4. ✅ Define SLOs for critical operators
5. ✅ Create investigation notebook

### Phase 3: Advanced Monitoring (Week 4+)
1. ✅ Deploy custom Extensions 2.0 if needed
2. ✅ Implement Davis AI correlation rules
3. ✅ Create automated remediation workflows
4. ✅ Set up cross-cluster operator health comparison
5. ✅ Integrate with ServiceNow/PagerDuty

---

## Best Practices

### 1. Metric Cardinality Management
- Focus on critical operators first
- Use metric filters to prevent unnecessary ingestion
- Aggregate metrics by operator category

### 2. Alerting Hygiene
- Use appropriate severity levels
- Implement alert dampening (avoid alert storms)
- Create runbook links in alert descriptions

### 3. Dashboard Design
- Separate overview and detailed dashboards
- Use drill-down capabilities
- Include business context (impact on services)

### 4. Regular Validation
- Test alerting monthly
- Review operator criticality quarterly
- Update dashboards based on team feedback

### 5. Documentation
```markdown
# Runbook: OpenShift Operator Degraded

## Impact
When an operator is degraded, specific cluster functionality may be impaired.

## Critical Operators
- authentication: User login failures
- kube-apiserver: API calls fail
- etcd: Data inconsistency
- dns: Service discovery breaks
- ingress: External access issues

## Investigation Steps
1. Check Dynatrace notebook: [Link]
2. Review operator pod logs: `oc logs -n openshift-<operator> <pod-name>`
3. Check operator events: `oc describe clusteroperator <name>`
4. Review Davis AI root cause analysis

## Escalation
- L1: Restart operator pod if CPU/Memory issue
- L2: OpenShift admin team
- L3: Red Hat support case
```

---

## Troubleshooting

### Common Issues

**Issue 1: Prometheus Metrics Not Appearing**
```bash
# Verify ActiveGate can reach Prometheus
curl -k -H "Authorization: Bearer <token>" \
  https://prometheus-k8s.openshift-monitoring.svc:9091/metrics

# Check ActiveGate logs
tail -f /var/log/dynatrace/remotepluginmodule/remotepluginmodule.log | grep prometheus
```

**Issue 2: High Metric Cardinality**
- Add metric filters in Prometheus configuration
- Use regex to exclude non-critical operators
- Aggregate by operator category

**Issue 3: False Positive Alerts**
- Increase alert threshold duration
- Add additional conditions (e.g., pod restarts)
- Use anomaly detection instead of static thresholds

---

## Cost Optimization

### Estimated DDU Consumption

**Metrics (Prometheus approach)**:
- ~40 operators × 3 conditions × 1 metric = 120 metric series
- At 1-minute intervals: 120 × 60 × 24 = 172,800 data points/day
- Estimated: 0.5-1 DDU/day

**Custom Events**:
- Alert events: ~10 events/month
- Estimated: <0.1 DDU/month

**Logs** (if enabled):
- Operator pod logs: Variable based on verbosity
- Estimated: 2-5 DDU/day (if full logging enabled)

**Recommendation**: Start with Prometheus metrics only, add logs if needed.

---

## Validation Checklist

Before going to production:

- [ ] Verified Prometheus metrics are ingesting
- [ ] Dashboard displays real-time operator status
- [ ] Test alert triggers with degraded operator
- [ ] Alert notifications reach correct teams
- [ ] Runbooks linked and accessible
- [ ] SLOs defined and tracking
- [ ] Team trained on dashboard usage
- [ ] Escalation procedures documented
- [ ] Backup monitoring in place
- [ ] Metrics retention configured

---

## Support and Resources

### Dynatrace Documentation
- [Kubernetes monitoring](https://www.dynatrace.com/support/help/setup-and-configuration/setup-on-container-platforms/kubernetes)
- [Prometheus integration](https://www.dynatrace.com/support/help/how-to-use-dynatrace/metrics/prometheus)
- [Extensions 2.0](https://www.dynatrace.com/support/help/extend-dynatrace/extensions20)

### OpenShift Documentation
- [Cluster operators reference](https://docs.openshift.com/container-platform/latest/operators/operator-reference.html)
- [Monitoring stack](https://docs.openshift.com/container-platform/latest/monitoring/monitoring-overview.html)

### Sample Queries Repository
GitHub: https://github.com/dynatrace-oss/dynatrace-openshift-monitoring

---

## Next Steps for Customer

1. **Discovery Call**: 
   - Identify which solution approach best fits their environment
   - Understand their current OpenShift monitoring setup
   - Define critical vs. non-critical operators

2. **Proof of Concept**:
   - Implement Solution 1 (Prometheus) in non-prod environment
   - Build initial dashboard
   - Validate alerting works

3. **Production Rollout**:
   - Deploy to production cluster
   - Train operations team
   - Establish feedback loop

4. **Continuous Improvement**:
   - Review alert noise monthly
   - Add additional operators as needed
   - Optimize metric collection

---

**Document Version**: 1.0  
**Last Updated**: November 2024  
**Author**: Dynatrace Customer Success Engineering  
**Status**: Ready for Customer Review
