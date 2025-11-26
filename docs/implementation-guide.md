# OpenShift Cluster Operator Monitoring - Implementation Guide
## Using Dynatrace Operator with Prometheus Integration

---

## Overview

This guide demonstrates how to monitor OpenShift cluster operator health using Dynatrace's built-in Kubernetes Prometheus scraping capability when the Dynatrace Operator is already deployed.

**Requirements**:
- Dynatrace Operator installed in OpenShift cluster
- Cluster-admin or equivalent permissions
- OpenShift 4.x cluster with Prometheus monitoring enabled

---

## Solution Architecture

```
OpenShift Prometheus (cluster_operator_conditions metrics)
           ↓
    Service with Dynatrace annotations
           ↓
    Dynatrace Operator (scrapes and ingests metrics)
           ↓
    Dynatrace Platform
```

**Key Components**:
- OpenShift Prometheus: Source of cluster operator metrics
- Dynatrace annotations: Configuration for metric collection
- Dynatrace Operator: Performs metric scraping
- Dynatrace Platform: Stores, analyzes, and visualizes metrics

---

## Implementation Steps

### Prerequisites Check

Before proceeding, verify the following:

1. **Dynatrace Operator Status**
   ```bash
   oc get pods -n dynatrace
   ```
   Expected: ActiveGate pods running

2. **OpenShift Prometheus Accessibility**
   ```bash
   oc get service prometheus-k8s -n openshift-monitoring
   ```
   Expected: Service exists and is accessible

3. **User Permissions**
   ```bash
   oc auth can-i create service -n openshift-monitoring
   ```
   Expected: yes

### Step 1: Enable Prometheus Monitoring in Dynatrace (5 minutes)

### Step 1: Enable Prometheus Monitoring in Dynatrace (5 minutes)

1. Log into the Dynatrace console

2. Navigate to:
   ```
   Settings > Cloud and virtualization > Kubernetes
   ```

3. Locate the target OpenShift cluster in the list

4. Click **Edit** on the cluster configuration

5. Enable the following settings:
   - ✅ **Enable monitoring**
   - ✅ **Monitor annotated Prometheus exporters**

6. Click **Save** to apply changes

**Verification**: The cluster status should show "Monitoring enabled" in the Kubernetes settings page.

### Step 2: Configure Prometheus Service Account (5 minutes)

### Step 2: Configure Prometheus Service Account (5 minutes)

Create a dedicated service account with appropriate permissions for Prometheus access:

```bash
# Create namespace for monitoring resources
oc create namespace dynatrace-monitoring

# Create service account
oc create serviceaccount prometheus-reader -n dynatrace-monitoring

# Grant cluster-monitoring-view role
oc adm policy add-cluster-role-to-user cluster-monitoring-view \
  system:serviceaccount:dynatrace-monitoring:prometheus-reader

# Generate long-lived token (OpenShift 4.11+)
PROM_TOKEN=$(oc create token prometheus-reader -n dynatrace-monitoring --duration=87600h)

# Store token in secret for Dynatrace access
oc create secret generic prometheus-token \
  --from-literal=token="$PROM_TOKEN" \
  -n dynatrace
```

**Note**: The token duration is set to 10 years (87600h). Adjust according to your organization's security policies.

**Verification**: 
```bash
oc get secret prometheus-token -n dynatrace
```
Expected: Secret exists with type "Opaque"

### Step 3: Annotate Prometheus Service (5 minutes)

Apply Dynatrace annotations to the OpenShift Prometheus service to enable metric scraping.

**Method 1: Direct Service Annotation (Recommended)**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: dynatrace-prometheus-operators
  namespace: openshift-monitoring
  annotations:
    # Tell Dynatrace to scrape this endpoint
    metrics.dynatrace.com/scrape: "true"
    
    # Prometheus endpoint details
    metrics.dynatrace.com/port: "9091"
    metrics.dynatrace.com/path: "/api/v1/query"
    metrics.dynatrace.com/secure: "true"
    metrics.dynatrace.com/insecure_skip_verify: "true"
    
    # Authentication (use the service account token)
    metrics.dynatrace.com/http.auth: "bearer"
    metrics.dynatrace.com/token: "${PROMETHEUS_TOKEN}"
    
    # Filter to ONLY get cluster operator metrics
    metrics.dynatrace.com/filter: |
      {
        "mode": "include",
        "names": [
          "cluster_operator_conditions",
          "cluster_operator_up"
        ]
      }
spec:
  type: ClusterIP
  clusterIP: None
  ports:
    - name: prometheus
      port: 9091
      protocol: TCP
      targetPort: 9091
  # Point to the actual Prometheus pods
  selector:
    app.kubernetes.io/name: prometheus
```

**Apply it:**
```bash
oc apply -f openshift-operators-monitoring.yaml
```

### Step 3: Annotate Prometheus Service (5 minutes)

Apply Dynatrace annotations to the OpenShift Prometheus service to enable metric scraping.

**Method 1: Direct Service Annotation (Recommended)**

```bash
oc annotate service prometheus-k8s -n openshift-monitoring \
  metrics.dynatrace.com/scrape="true" \
  metrics.dynatrace.com/port="9091" \
  metrics.dynatrace.com/path="/metrics" \
  metrics.dynatrace.com/secure="true" \
  metrics.dynatrace.com/insecure_skip_verify="true" \
  metrics.dynatrace.com/filter='{"mode": "include", "names": ["cluster_operator_conditions", "cluster_operator_up"]}' \
  --overwrite
```

**Annotation Parameters**:
- `scrape="true"`: Enables metric collection by Dynatrace
- `port="9091"`: Prometheus service port
- `path="/metrics"`: Metrics endpoint path
- `secure="true"`: Use HTTPS connection
- `insecure_skip_verify="true"`: Skip TLS certificate verification
- `filter`: Limits collection to cluster operator metrics only

**Verification**:
```bash
oc get service prometheus-k8s -n openshift-monitoring -o yaml | grep -A 10 annotations
```

**Method 2: Create Dedicated Service (Alternative)**

If direct annotation is not preferred, create a dedicated service:

Create file `openshift-operators-monitoring.yaml`:

Apply the configuration:
```bash
oc apply -f openshift-operators-monitoring.yaml
```

### Step 4: Verify Metrics Ingestion (5 minutes)

Allow 3-5 minutes for metrics to begin flowing to Dynatrace, then verify:

**1. Check Metrics Browser**

Navigate to Dynatrace: **Observe and explore > Metrics**

Search for: `cluster_operator_conditions`

**Expected Results**:
- Metric appears in the list
- Dimensions visible:
  - `name` (operator name: authentication, dns, etcd, etc.)
  - `condition` (Available, Degraded, Progressing)
  - `value` (1 or 0)

**2. Verify All Operators Present**

Use the Data Explorer to confirm all 16 operators are reporting:

```dql
fetch dt.metrics.cluster_operator_conditions
| summarize by: {name}
```

**Expected operators**:
- authentication
- cloud-credential
- console
- control-plane-machine-set
- dns
- etcd
- image-registry
- ingress
- kube-apiserver
- kube-controller-manager
- kube-scheduler
- network
- openshift-apiserver
- openshift-controller-manager
- operator-lifecycle-manager
- storage

**3. Test Metric Query**

Execute a sample query to verify data accuracy:

```dql
fetch dt.metrics.cluster_operator_conditions
| filter condition == "Available"
| fields name, value, timestamp
```

Expected: All operators should show value = 1 (Available)

### Step 5: Import Pre-Built Dashboard (5 minutes)

Import the provided dashboard to visualize cluster operator health.

**Obtain Dashboard JSON**:
- Dashboard file: `openshift-operator-dashboard.json`
- Provided separately in this solution package

**Import Procedure**:

1. Navigate to: **Dashboards** in Dynatrace

2. Click **Import** or the ellipsis menu (**...**)

3. Paste the complete JSON content

4. Click **Save**

**Dashboard Components**:
- Critical Operators Health Matrix
- Degraded Operators Count (with color-coded thresholds)
- Progressing Operators Status
- 24-hour Availability Trend
- Currently Degraded Operators List
- Investigation Guide (Markdown tile)

**Post-Import Verification**:
Navigate to the imported dashboard. All tiles should populate with real-time data showing the 16 cluster operators.

### Step 6: Configure Alerting (30 minutes)

Establish proactive alerting for cluster operator issues.

**Alert 1: Critical Operator Degraded**
**Alert 1: Critical Operator Degraded**

Configuration:
```
Metric: cluster_operator_conditions
Filter: condition = "Degraded"
Threshold: value >= 1 for 2 minutes
Severity: ERROR
Alert Type: Metric Event
```

**Alert 2: Critical Operator Unavailable**

Configuration:
```
Metric: cluster_operator_conditions
Filters:
  - condition = "Available"
  - name in [authentication, etcd, kube-apiserver, dns, ingress, network]
Threshold: value < 1 for 5 minutes
Severity: CRITICAL
Alert Type: Metric Event
```

**Alert 3: Multiple Operators Degraded**

Configuration:
```
Query Type: DQL
Query:
  fetch dt.metrics.cluster_operator_conditions
  | filter condition == "Degraded" and value == 1
  | summarize count = count()
  | filter count >= 3

Threshold: count >= 3
Severity: CRITICAL
Alert Type: Custom Event
```

**Alert Configuration Location**:
```
Settings > Anomaly detection > Metric events
```

Refer to the `alert-configuration.md` file for detailed alert definitions and escalation procedures.

---

## Troubleshooting Guide

### Common Issues and Resolutions

#### Issue 1: Metrics Not Appearing in Dynatrace

**Symptom**: No `cluster_operator_conditions` metrics visible after 10 minutes

**Diagnostic Steps**:
**Diagnostic Steps**:

**1. Verify Dynatrace Operator Status**
```bash
oc get pods -n dynatrace
```
Expected: All pods in "Running" state

**2. Verify Kubernetes Monitoring Configuration**

Navigate to: `Settings > Cloud and virtualization > Kubernetes`

Verify:
- Cluster is listed
- "Enable monitoring" is enabled
- "Monitor annotated Prometheus exporters" is enabled

**3. Check Dynatrace Operator Logs**
```bash
# Identify ActiveGate pod
oc get pods -n dynatrace | grep activegate

# Review logs for Prometheus scraping
oc logs -n dynatrace <activegate-pod-name> | grep -i prometheus
```

Look for:
- Successful scraping messages
- Authentication errors
- Connection errors

**4. Verify Service Annotations**
```bash
oc get service prometheus-k8s -n openshift-monitoring -o yaml
```

Confirm presence of:
- `metrics.dynatrace.com/scrape: "true"`
- `metrics.dynatrace.com/port: "9091"`
- `metrics.dynatrace.com/filter` with correct metric names

**5. Test Prometheus Endpoint Accessibility**
```bash
# Create test pod
oc run test-curl --image=curlimages/curl -n openshift-monitoring -- sleep 3600

# Test Prometheus endpoint
oc exec -it test-curl -n openshift-monitoring -- \
  curl -k https://prometheus-k8s.openshift-monitoring.svc:9091/api/v1/query?query=cluster_operator_conditions

# Cleanup
oc delete pod test-curl -n openshift-monitoring
```

Expected: JSON response with metric data

#### Issue 2: Partial Operator Coverage

**Symptom**: Some operators missing from metrics

**Resolution**:

Check if all operators are healthy in OpenShift:
```bash
oc get clusteroperator
```

Operators not showing "AVAILABLE=True" will not report complete metrics.

#### Issue 3: Authentication Errors in Logs

**Symptom**: 401/403 errors in ActiveGate logs

**Resolution**:

Verify service account permissions:
```bash
oc auth can-i get --subresource=metrics services -n openshift-monitoring \
  --as=system:serviceaccount:dynatrace-monitoring:prometheus-reader
```

Expected: yes

If no, re-apply cluster-monitoring-view role:
```bash
oc adm policy add-cluster-role-to-user cluster-monitoring-view \
  system:serviceaccount:dynatrace-monitoring:prometheus-reader
```

---

## Alternative Implementation: Prometheus Federation

If the annotation-based approach encounters issues, use Prometheus federation:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: dynatrace-prometheus-federate
  namespace: openshift-monitoring
  annotations:
    metrics.dynatrace.com/scrape: "true"
    metrics.dynatrace.com/port: "9091"
    metrics.dynatrace.com/path: "/federate"
    metrics.dynatrace.com/secure: "true"
    metrics.dynatrace.com/insecure_skip_verify: "true"
    metrics.dynatrace.com/params: |
      match[]=cluster_operator_conditions
      match[]=cluster_operator_up
spec:
  type: ClusterIP
  clusterIP: None
  ports:
    - name: federate
      port: 9091
      protocol: TCP
  selector:
    app.kubernetes.io/name: prometheus
```

---

## Operator Criticality Classification

The following table categorizes the 16 monitored operators by criticality for alert prioritization:

| Operator | Function | Criticality | Alert Priority |
|----------|----------|-------------|----------------|
| authentication | User and service account authentication | High | P1 |
| cloud-credential | Cloud provider credential management | Medium | P2 |
| console | Web console availability | Low | P3 |
| control-plane-machine-set | Control plane machine management | Medium | P2 |
| dns | Cluster DNS resolution | High | P1 |
| etcd | Cluster state database | **Critical** | **P0** |
| image-registry | Container image registry | Medium | P2 |
| ingress | External traffic routing | High | P1 |
| kube-apiserver | Kubernetes API endpoint | **Critical** | **P0** |
| kube-controller-manager | Core controller operations | High | P1 |
| kube-scheduler | Pod scheduling | High | P1 |
| network | Pod networking | High | P1 |
| openshift-apiserver | OpenShift API endpoint | High | P1 |
| openshift-controller-manager | OpenShift controller operations | High | P1 |
| operator-lifecycle-manager | Operator lifecycle management | Medium | P2 |
| storage | Persistent volume provisioning | High | P1 |

**Priority Definitions**:
- **P0** (Critical): Immediate response required, cluster stability at risk
- **P1** (High): Response within 15 minutes, major functionality impaired
- **P2** (Medium): Response within 1 hour, degraded functionality
- **P3** (Low): Response within 4 hours, minimal impact

---

## Expected Dashboard Visualization

Upon successful implementation, the dashboard displays:

**Dashboard Tile: Critical Operators Health Matrix**
```
                  Available  Degraded  Progressing
authentication         1         0          0
etcd                   1         0          0
kube-apiserver         1         0          0
dns                    1         0          0
...
```

**Dashboard Tile: Degraded Count**
```
Status: 0 operators degraded (GREEN)
```

**Dashboard Tile: Unavailable Count**
```
Status: All operators available (GREEN)
```

**Dashboard Tile: 24-Hour Availability Trend**
```
Line chart displaying 100% availability for all operators
```

---

## Solution Benefits

**Operational Advantages**:
- Leverages existing Dynatrace Operator infrastructure
- No additional components or services required
- Native Dynatrace integration
- Minimal maintenance overhead

**Technical Advantages**:
- Simple annotation-based configuration
- Real-time metric collection
- Automatic coverage of all cluster operators
- Low resource consumption (~1 DDU/day)

**Monitoring Capabilities**:
- Complete visibility into all 16 cluster operators
- Historical trending and analysis
- Proactive alerting on degradation
- Integration with Davis AI for root cause analysis

---

## Implementation Summary

**Total Implementation Time**: ~45 minutes

**Step Breakdown**:
1. Enable Prometheus monitoring (5 min)
2. Configure service account (5 min)
3. Annotate Prometheus service (5 min)
4. Verify metrics ingestion (5 min)
5. Import dashboard (5 min)
6. Configure alerts (30 min)

**Prerequisites Met**:
- ✓ Dynatrace Operator deployed
- ✓ OpenShift 4.x cluster
- ✓ Cluster-admin permissions

**Deliverables**:
- Real-time operator monitoring
- Pre-built dashboard
- Configured alerting
- Complete operator coverage

---

## Automation Script

The following script automates steps 2-3 of the implementation:

## Automation Script

The following script automates steps 2-3 of the implementation:

```bash
#!/bin/bash
#
# OpenShift Cluster Operator Monitoring Setup Script
# Prerequisites: Dynatrace Operator deployed, oc CLI configured, cluster-admin access
#
# Usage: ./setup-operator-monitoring.sh
#

set -e

# Configuration
MONITORING_NAMESPACE="dynatrace-monitoring"
SERVICE_ACCOUNT="prometheus-reader"
DYNATRACE_NAMESPACE="dynatrace"

echo "================================================================"
echo " OpenShift Cluster Operator Monitoring - Setup Script"
echo "================================================================"
echo ""

# Prerequisite Validation
echo "[1/6] Validating prerequisites..."

# Check oc CLI
if ! command -v oc &> /dev/null; then
    echo "ERROR: oc CLI not found. Please install OpenShift CLI."
    exit 1
fi

# Check cluster connection
if ! oc whoami &> /dev/null; then
    echo "ERROR: Not authenticated to OpenShift cluster."
    echo "Please run: oc login <cluster-url>"
    exit 1
fi

echo "  ✓ Prerequisites validated"
echo ""

# Manual step reminder
echo "[2/6] Dynatrace UI Configuration Required"
echo ""
echo "  Before proceeding, complete the following in Dynatrace:"
echo "  1. Navigate to: Settings > Cloud and virtualization > Kubernetes"
echo "  2. Locate your OpenShift cluster"
echo "  3. Enable: 'Enable monitoring'"
echo "  4. Enable: 'Monitor annotated Prometheus exporters'"
echo "  5. Save changes"
echo ""
read -p "Press ENTER after completing these steps..."
echo ""

# Create monitoring namespace
echo "[3/6] Creating monitoring namespace..."
oc create namespace $MONITORING_NAMESPACE 2>/dev/null || echo "  (Namespace already exists)"
echo "  ✓ Namespace ready: $MONITORING_NAMESPACE"
echo ""

# Create service account
echo "[4/6] Configuring service account..."
oc create serviceaccount $SERVICE_ACCOUNT -n $MONITORING_NAMESPACE 2>/dev/null || echo "  (Service account already exists)"

# Grant permissions
oc adm policy add-cluster-role-to-user cluster-monitoring-view \
  system:serviceaccount:$MONITORING_NAMESPACE:$SERVICE_ACCOUNT &>/dev/null

echo "  ✓ Service account configured with cluster-monitoring-view role"
echo ""

# Generate token
echo "[5/6] Generating authentication token..."
PROM_TOKEN=$(oc create token $SERVICE_ACCOUNT -n $MONITORING_NAMESPACE --duration=87600h)

if [ -z "$PROM_TOKEN" ]; then
    echo "ERROR: Failed to generate token"
    exit 1
fi

# Save token
echo "$PROM_TOKEN" > prometheus-token.txt
oc create secret generic prometheus-token \
  --from-literal=token="$PROM_TOKEN" \
  -n $DYNATRACE_NAMESPACE \
  --dry-run=client -o yaml | oc apply -f - &>/dev/null

echo "  ✓ Token generated and stored"
echo "  ✓ Token saved to: prometheus-token.txt"
echo ""

# Annotate Prometheus service
echo "[6/6] Applying Dynatrace annotations to Prometheus service..."
oc annotate service prometheus-k8s -n openshift-monitoring \
  metrics.dynatrace.com/scrape="true" \
  metrics.dynatrace.com/port="9091" \
  metrics.dynatrace.com/path="/metrics" \
  metrics.dynatrace.com/secure="true" \
  metrics.dynatrace.com/insecure_skip_verify="true" \
  metrics.dynatrace.com/filter='{"mode": "include", "names": ["cluster_operator_conditions", "cluster_operator_up"]}' \
  --overwrite &>/dev/null

echo "  ✓ Annotations applied successfully"
echo ""

# Summary
echo "================================================================"
echo " Setup Complete"
echo "================================================================"
echo ""
echo "Next Steps:"
echo "  1. Wait 3-5 minutes for metrics to begin flowing"
echo "  2. Verify in Dynatrace: Observe and explore > Metrics"
echo "  3. Search for: cluster_operator_conditions"
echo "  4. Import dashboard: openshift-operator-dashboard.json"
echo "  5. Configure alerts as documented"
echo ""
echo "All 16 cluster operators will be monitored automatically."
echo ""
echo "Troubleshooting:"
echo "  - Check Dynatrace Operator logs: oc logs -n dynatrace <pod-name>"
echo "  - Verify annotations: oc get svc prometheus-k8s -n openshift-monitoring -o yaml"
echo "  - Review documentation for additional diagnostic steps"
echo ""
echo "================================================================"
```

**Script Features**:
- Prerequisite validation
- Automated configuration
- Error handling
- Progress indication
- Token persistence
- Idempotent execution

**Execution**:
```bash
chmod +x setup-operator-monitoring.sh
./setup-operator-monitoring.sh
```

---

## Post-Implementation Validation

After completing the implementation, verify the following:

**Checklist**:
- [ ] Metrics visible in Dynatrace Metrics browser
- [ ] All 16 operators reporting data
- [ ] Dashboard displays real-time status
- [ ] Test alert triggers correctly
- [ ] Documentation updated with cluster-specific details
- [ ] Team trained on dashboard usage
- [ ] Escalation procedures established

**Validation Query**:
```dql
fetch dt.metrics.cluster_operator_conditions
| filter condition == "Available"
| summarize operators = count(), by: {condition}
```

Expected: Count = 16 (all operators reporting)

---

## Additional Resources

**Documentation**:
- Alert configuration details: `alert-configuration.md`
- Quick reference guide: `quick-reference-cheat-sheet.md`
- Comprehensive guide: `openshift-operator-monitoring-guide.md`

**Dynatrace Documentation**:
- Kubernetes monitoring: https://docs.dynatrace.com/docs/setup-and-configuration/setup-on-container-platforms/kubernetes
- Prometheus integration: https://docs.dynatrace.com/docs/observe/infrastructure-monitoring/container-platform-monitoring/kubernetes-monitoring/monitor-prometheus-metrics

**OpenShift Documentation**:
- Cluster operators: https://docs.openshift.com/container-platform/latest/operators/operator-reference.html
- Monitoring stack: https://docs.openshift.com/container-platform/latest/monitoring/monitoring-overview.html

---

## Support and Assistance

For issues or questions regarding this implementation:

**Dynatrace Support**:
- Portal: https://support.dynatrace.com
- Documentation: https://docs.dynatrace.com

**OpenShift Support**:
- Red Hat Customer Portal: https://access.redhat.com/support
- Documentation: https://docs.openshift.com

**Internal Escalation**:
Contact your Dynatrace Customer Success Engineer or Platform Engineering team for implementation assistance.
