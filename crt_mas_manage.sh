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

cat << EOF | oc create -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: letsencrypt-$instance-$workspace-cert-public-81
  namespace: $namespace
spec:
  secretName: $instance-$workspace-cert-public-81
  privateKey:
    rotationPolicy: Always
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
    - $workspace-foundation.manage.$instance.$appsdomain
EOF

oc get cert letsencrypt-$instance-$workspace-cert-public-81 -n $namespace

echo
echo Check Certificate with
echo oc get cert letsencrypt-$instance-$workspace-cert-public-81 -n $namespace

oc wait --for jsonpath={.status.conditions[0].status}=True \
cert/letsencrypt-$instance-$workspace-cert-public-81 -n $namespace

oc set data secret/$instance-$workspace-cert-public-81 \
-n $namespace \
--from-file ca.crt=isrgrootx1.pem

cat <<EOF
Check route certificates

for url in \
\$(oc get route -n $namespace \
-o jsonpath='{ range @.items[*] }{ .spec.host }{ .spec.path } { end }')
do
  curl https://\$url -o /dev/null -s -w '%{http_code} '
  echo https://\$url
done
EOF
