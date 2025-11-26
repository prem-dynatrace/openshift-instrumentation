#!/bin/bash
#
# OpenShift Operator Monitoring Setup Script
# This script automates the configuration of OpenShift cluster operator monitoring in Dynatrace
#
# Prerequisites:
# - oc CLI installed and configured
# - Access to OpenShift cluster with cluster-admin privileges
# - Dynatrace ActiveGate deployed and accessible
#
# Usage: ./setup-operator-monitoring.sh [options]
#

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
NAMESPACE="dynatrace-monitoring"
SERVICE_ACCOUNT="dynatrace-prometheus"
TOKEN_DURATION="87600h" # 10 years

# Functions
print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check if oc is installed
    if ! command -v oc &> /dev/null; then
        print_error "oc CLI is not installed. Please install it first."
        exit 1
    fi
    print_success "oc CLI is installed"
    
    # Check if logged into OpenShift
    if ! oc whoami &> /dev/null; then
        print_error "Not logged into OpenShift. Please login first: oc login"
        exit 1
    fi
    print_success "Logged into OpenShift as $(oc whoami)"
    
    # Check cluster admin privileges
    if ! oc auth can-i create namespace &> /dev/null; then
        print_error "Insufficient privileges. Cluster admin access required."
        exit 1
    fi
    print_success "Cluster admin privileges confirmed"
    
    # Check if Prometheus is accessible
    if oc get route prometheus-k8s -n openshift-monitoring &> /dev/null; then
        print_success "OpenShift monitoring stack is deployed"
    else
        print_warning "Cannot find Prometheus route. Continuing anyway..."
    fi
    
    echo ""
}

create_namespace() {
    print_header "Creating Namespace"
    
    if oc get namespace $NAMESPACE &> /dev/null; then
        print_warning "Namespace $NAMESPACE already exists"
    else
        oc create namespace $NAMESPACE
        print_success "Created namespace: $NAMESPACE"
    fi
    echo ""
}

create_service_account() {
    print_header "Creating Service Account"
    
    if oc get sa $SERVICE_ACCOUNT -n $NAMESPACE &> /dev/null; then
        print_warning "Service account $SERVICE_ACCOUNT already exists"
    else
        cat <<EOF | oc apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $SERVICE_ACCOUNT
  namespace: $NAMESPACE
EOF
        print_success "Created service account: $SERVICE_ACCOUNT"
    fi
    echo ""
}

grant_permissions() {
    print_header "Granting Permissions"
    
    oc adm policy add-cluster-role-to-user cluster-monitoring-view \
        system:serviceaccount:${NAMESPACE}:${SERVICE_ACCOUNT}
    
    print_success "Granted cluster-monitoring-view role to service account"
    echo ""
}

generate_token() {
    print_header "Generating Service Account Token"
    
    TOKEN=$(oc create token $SERVICE_ACCOUNT -n $NAMESPACE --duration=$TOKEN_DURATION)
    
    if [ -z "$TOKEN" ]; then
        print_error "Failed to generate token"
        exit 1
    fi
    
    print_success "Generated long-lived token (10 years)"
    
    # Save token to file
    echo "$TOKEN" > dynatrace-prometheus-token.txt
    print_success "Token saved to: dynatrace-prometheus-token.txt"
    
    echo ""
    print_warning "IMPORTANT: Store this token securely!"
    echo ""
}

get_prometheus_endpoint() {
    print_header "Getting Prometheus Endpoint"
    
    # Try to get external route
    EXTERNAL_ENDPOINT=$(oc get route prometheus-k8s -n openshift-monitoring -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
    
    # Internal service endpoint
    INTERNAL_ENDPOINT="prometheus-k8s.openshift-monitoring.svc:9091"
    
    echo "Prometheus Endpoints:"
    echo ""
    if [ ! -z "$EXTERNAL_ENDPOINT" ]; then
        echo "External: https://${EXTERNAL_ENDPOINT}"
    fi
    echo "Internal: https://${INTERNAL_ENDPOINT}"
    echo ""
    
    # Save to file
    cat > prometheus-endpoints.txt <<EOF
Prometheus Endpoints for Dynatrace Configuration:

External Route (if accessible from ActiveGate):
https://${EXTERNAL_ENDPOINT}

Internal Service (if ActiveGate is in cluster):
https://${INTERNAL_ENDPOINT}

Note: Use the internal endpoint if your ActiveGate is deployed within the OpenShift cluster.
Use the external endpoint if ActiveGate is deployed outside the cluster.
EOF
    
    print_success "Endpoint information saved to: prometheus-endpoints.txt"
    echo ""
}

test_prometheus_access() {
    print_header "Testing Prometheus Access"
    
    print_info "Testing internal Prometheus endpoint..."
    
    # Create a test pod to verify access
    cat <<EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: prometheus-test
  namespace: $NAMESPACE
spec:
  serviceAccountName: $SERVICE_ACCOUNT
  containers:
  - name: curl
    image: curlimages/curl:latest
    command: ['sleep', '3600']
  restartPolicy: Never
EOF
    
    print_info "Waiting for test pod to be ready..."
    oc wait --for=condition=Ready pod/prometheus-test -n $NAMESPACE --timeout=60s &> /dev/null || true
    
    sleep 5
    
    # Test the connection
    TOKEN=$(cat dynatrace-prometheus-token.txt)
    TEST_RESULT=$(oc exec prometheus-test -n $NAMESPACE -- \
        curl -k -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $TOKEN" \
        https://prometheus-k8s.openshift-monitoring.svc:9091/api/v1/query?query=up 2>/dev/null || echo "000")
    
    if [ "$TEST_RESULT" = "200" ]; then
        print_success "Successfully connected to Prometheus!"
    else
        print_warning "Could not verify Prometheus access (HTTP $TEST_RESULT). This may be normal if testing from outside the cluster."
    fi
    
    # Cleanup test pod
    oc delete pod prometheus-test -n $NAMESPACE &> /dev/null || true
    
    echo ""
}

verify_metrics() {
    print_header "Verifying Cluster Operator Metrics"
    
    print_info "Checking if cluster operator metrics are available in Prometheus..."
    
    # Create a job to query Prometheus
    TOKEN=$(cat dynatrace-prometheus-token.txt)
    
    cat <<EOF | oc apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: verify-metrics
  namespace: $NAMESPACE
spec:
  template:
    spec:
      serviceAccountName: $SERVICE_ACCOUNT
      containers:
      - name: curl
        image: curlimages/curl:latest
        command:
        - /bin/sh
        - -c
        - |
          curl -k -s -H "Authorization: Bearer $TOKEN" \
          'https://prometheus-k8s.openshift-monitoring.svc:9091/api/v1/query?query=cluster_operator_conditions' \
          | grep -q 'cluster_operator_conditions' && echo "SUCCESS" || echo "FAILED"
      restartPolicy: Never
  backoffLimit: 1
EOF
    
    print_info "Waiting for verification job to complete..."
    sleep 10
    
    # Check job logs
    POD_NAME=$(oc get pods -n $NAMESPACE -l job-name=verify-metrics -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ ! -z "$POD_NAME" ]; then
        RESULT=$(oc logs $POD_NAME -n $NAMESPACE 2>/dev/null || echo "")
        if echo "$RESULT" | grep -q "SUCCESS"; then
            print_success "Cluster operator metrics are available in Prometheus!"
        else
            print_warning "Could not verify metrics. Please check manually."
        fi
    fi
    
    # Cleanup
    oc delete job verify-metrics -n $NAMESPACE &> /dev/null || true
    
    echo ""
}

generate_activegate_config() {
    print_header "Generating ActiveGate Configuration"
    
    TOKEN=$(cat dynatrace-prometheus-token.txt)
    
    cat > activegate-prometheus-config.yaml <<EOF
# ActiveGate Prometheus Configuration for OpenShift Operators
# Deploy this on your Dynatrace ActiveGate

# Option 1: Using custom.properties file
# Location: /var/lib/dynatrace/remotepluginmodule/agent/conf/custom.properties

# Add the following to custom.properties:
[prometheus_openshift_operators]
enabled=true
endpoint=https://prometheus-k8s.openshift-monitoring.svc:9091
interval=60s
verify_ssl=true
bearer_token=$TOKEN

# Metric filters (optional - to reduce cardinality)
metric_filter=cluster_operator_conditions|cluster_operator_up|cluster_version_available_updates

---

# Option 2: Using Dynatrace UI Configuration
# Navigate to: Settings > Cloud and virtualization > Prometheus

Configuration Values:
  Endpoint URL: https://prometheus-k8s.openshift-monitoring.svc:9091
  Authentication: Bearer token
  Token: $TOKEN
  Scrape interval: 60 seconds
  
  Metrics to include (optional):
    - cluster_operator_conditions
    - cluster_operator_up
    - cluster_version_available_updates

---

# Option 3: Using Kubernetes ConfigMap (if ActiveGate is in cluster)

apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  namespace: dynatrace
data:
  custom.properties: |
    [prometheus_openshift_operators]
    enabled=true
    endpoint=https://prometheus-k8s.openshift-monitoring.svc:9091
    interval=60s
    verify_ssl=true
    bearer_token=$TOKEN
EOF
    
    print_success "Configuration saved to: activegate-prometheus-config.yaml"
    echo ""
}

create_sample_queries() {
    print_header "Creating Sample Queries"
    
    cat > sample-queries.txt <<EOF
# Sample Prometheus Queries for OpenShift Operator Monitoring

# Query 1: Check all operators' availability status
cluster_operator_conditions{condition="Available"}

# Query 2: Find degraded operators
cluster_operator_conditions{condition="Degraded", value="1"}

# Query 3: Monitor operators in progressing state
cluster_operator_conditions{condition="Progressing", value="1"}

# Query 4: Critical operators health
cluster_operator_conditions{name=~"authentication|kube-apiserver|etcd|dns|ingress|network"}

# Query 5: Count of unavailable operators
count(cluster_operator_conditions{condition="Available", value="0"})

# Query 6: Operators unavailable for more than 5 minutes
cluster_operator_conditions{condition="Available", value="0"} [5m]

---

# Sample DQL Queries for Dynatrace Dashboards

// Query 1: All operators status
fetch dt.metrics.cluster_operator_conditions
| fieldsAdd operator = name, condition, status = value
| pivot condition, avg(status), by: {operator}

// Query 2: Critical operators only
fetch dt.metrics.cluster_operator_conditions
| filter name in ["authentication", "kube-apiserver", "etcd", "dns", "ingress"]
| fieldsAdd operator = name, condition, status = value
| pivot condition, avg(status), by: {operator}

// Query 3: Degraded operators alert
fetch dt.metrics.cluster_operator_conditions
| filter condition == "Degraded" and value == 1
| summarize count = count(), by: {name}

// Query 4: Availability trend over 24h
timeseries available = avg(cluster_operator_conditions{condition="Available"}), by: {name}, interval: 5m

// Query 5: Time in degraded state
fetch dt.metrics.cluster_operator_conditions
| filter condition == "Degraded" and value == 1
| fieldsAdd operator = name, degraded_since = timestamp
EOF
    
    print_success "Sample queries saved to: sample-queries.txt"
    echo ""
}

print_next_steps() {
    print_header "Next Steps"
    
    cat <<EOF
Configuration is complete! Here's what to do next:

1. ${GREEN}Configure ActiveGate${NC}
   - Review: activegate-prometheus-config.yaml
   - Choose deployment method (custom.properties, UI, or ConfigMap)
   - Deploy configuration to your ActiveGate
   - Restart ActiveGate if using custom.properties

2. ${GREEN}Verify Metrics Ingestion${NC}
   - Wait 2-3 minutes after ActiveGate configuration
   - In Dynatrace, go to: Data Explorer
   - Search for: cluster_operator_conditions
   - Verify metrics are appearing

3. ${GREEN}Import Dashboard${NC}
   - Download: openshift-operator-dashboard.json
   - In Dynatrace: Dashboards > Import
   - Paste the JSON content
   - Save and view the dashboard

4. ${GREEN}Configure Alerts${NC}
   - Settings > Anomaly Detection > Metric events
   - Create alerts for:
     * Degraded operators (critical)
     * Unavailable operators (critical)
     * Stuck progressing state (warning)

5. ${GREEN}Test Alerting${NC}
   - Simulate a degraded operator (in non-prod)
   - Verify alert triggers in Dynatrace
   - Test notification delivery

6. ${GREEN}Documentation${NC}
   - Review: openshift-operator-monitoring-guide.md
   - Create runbooks for your team
   - Document escalation procedures

${YELLOW}Important Files Created:${NC}
  - dynatrace-prometheus-token.txt (KEEP SECURE!)
  - prometheus-endpoints.txt
  - activegate-prometheus-config.yaml
  - sample-queries.txt

${YELLOW}Security Reminder:${NC}
  The generated token has a 10-year expiration. Store it securely and
  rotate it according to your organization's security policies.

${GREEN}Support Resources:${NC}
  - Full guide: openshift-operator-monitoring-guide.md
  - Dynatrace docs: https://www.dynatrace.com/support/help/
  - OpenShift docs: https://docs.openshift.com/

${BLUE}Need Help?${NC}
  Contact your Dynatrace Customer Success Engineer or
  open a support ticket at: https://support.dynatrace.com/

EOF
}

# Main execution
main() {
    clear
    print_header "OpenShift Operator Monitoring Setup"
    echo "This script will configure Dynatrace monitoring for OpenShift cluster operators"
    echo ""
    
    check_prerequisites
    create_namespace
    create_service_account
    grant_permissions
    generate_token
    get_prometheus_endpoint
    test_prometheus_access
    verify_metrics
    generate_activegate_config
    create_sample_queries
    print_next_steps
    
    print_success "Setup completed successfully!"
}

# Run main function
main
