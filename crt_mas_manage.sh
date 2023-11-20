#!/bin/sh

namespace=$1

if [ "x$namespace" = "x"  ]; then
    echo "usage: $0 namespace"
    exit 1
fi

echo "Creating letsencrypt signed certificate in Namespace $namespace"
echo

instance=$(echo $namespace | cut -d"-" -f2)

workspace=$(oc get pod -n $namespace \
            -l mas.ibm.com/appTypeName=all \
            -o jsonpath='{ .items[].metadata.labels.mas\.ibm\.com/workspaceId }')

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
