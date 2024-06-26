#!/bin/sh

namespace=$1

if [ "x$namespace" = "x"  ]; then
    echo "usage: $0 namespace"
    exit 1
fi

echo "Creating letsencrypt signed certificate in Namespace $namespace"
echo

instance=$(oc get ManageWorkspace -n $namespace \
            -o jsonpath='{ ..metadata.labels.mas\.ibm\.com/instanceId }')

workspace=$(oc get ManageWorkspace -n $namespace \
            -o jsonpath='{ .items[*].metadata.labels.mas\.ibm\.com/workspaceId }' \
            | awk '{ print $1 }')

if [ -z "$instance" ]; then
  echo "ERROR: Wrong Namespace $namespace"
  echo "MAS Manage not installed in Namespace $namespace"
  oc get ManageWorkspace -A
  exit 1
fi

cat << EOF | oc create -f - 2>/dev/null
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: allow-cert-manager-resolver
  namespace: $namespace
spec:
  podSelector:
    matchLabels:
      acme.cert-manager.io/http01-solver: "true"
  ingress:
    - namespaceSelector:
        matchLabels:
          app.kubernetes.io/instance: cert-manager
    - namespaceSelector:
          matchLabels:
            network.openshift.io/policy-group: ingress
EOF

oc get secret \
-n $namespace $instance-$workspace-cert-public-81 \
-o jsonpath='{ .data.tls\.crt }' | base64 -d | \
openssl x509 -noout -issuer -subject -enddate -ext subjectAltName

appsdomain=$(oc get ingresses.config/cluster -o jsonpath='{ .spec.domain }')

for certname in \
manage \
$workspace.manage \
$workspace-all.manage \
$workspace-cron.manage \
$workspace-mea.manage \
$workspace-rpt.manage \
$workspace-ui.manage
do
name=$(echo $certname | sed "s/\./-/g")

cat << EOF | oc create -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: letsencrypt-$name
  namespace: $namespace
spec:
  secretName: letsencrypt-$name
  issuerRef:
    name: letsencrypt
    kind: ClusterIssuer
  dnsNames:
    - $instance.$appsdomain
    - $certname.$instance.$appsdomain
EOF

oc wait --for jsonpath={.status.conditions[0].status}=True \
cert/letsencrypt-$name -n $namespace

done

cat << EOF | oc create -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: letsencrypt-$instance-$workspace-cert-public-81
  namespace: $namespace
spec:
  secretName: $instance-$workspace-cert-public-81
  issuerRef:
    name: letsencrypt
    kind: ClusterIssuer
  dnsNames:
    - $instance.$appsdomain
    - manage.$instance.$appsdomain
    - $workspace.manage.$instance.$appsdomain
    - $workspace-all.manage.$instance.$appsdomain
    - $workspace-cron.manage.$instance.$appsdomain
    - $workspace-mea.manage.$instance.$appsdomain
    - $workspace-rpt.manage.$instance.$appsdomain
    - $workspace-ui.manage.$instance.$appsdomain
    - maxinst.manage.$instance.$appsdomain
EOF

oc get cert letsencrypt-$instance-$workspace-cert-public-81 -n $namespace

echo
echo Check Certificate with
echo oc get cert letsencrypt-$instance-$workspace-cert-public-81 -n $namespace

# oc wait --for jsonpath={.status.conditions[0].status}=True \
# cert/letsencrypt-$instance-$workspace-cert-public-81 -n $namespace

oc set data secret/$instance-$workspace-cert-public-81 \
-n $namespace \
--from-file ca.crt=isrgrootx1.pem

oc delete cert -n $namespace \
letsencrypt-manage \
letsencrypt-$workspace-manage \
letsencrypt-$workspace-all-manage \
letsencrypt-$workspace-cron-manage \
letsencrypt-$workspace-mea-manage \
letsencrypt-$workspace-rpt-manage \
letsencrypt-$workspace-ui-manage
