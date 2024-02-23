#!/bin/sh

namespace=$1

if [ "x$namespace" = "x"  ]; then
    echo "usage: $0 namespace"
    exit 1
fi

echo "Creating letsencrypt signed certificate in Namespace $namespace"
echo

instance=$(echo $namespace | cut -d"-" -f2)

workspace=$(oc get PredictWorkspace -n $namespace \
            -o jsonpath='{ .items[*].metadata.labels.mas\.ibm\.com/workspaceId }' \
            | awk '{ print $1 }')

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
-n $namespace $instance-public-predict-tls \
-o jsonpath='{ .data.tls\.crt }' | base64 -d | \
openssl x509 -noout -issuer -subject -enddate -ext subjectAltName

appsdomain=$(oc get ingresses.config/cluster -o jsonpath='{ .spec.domain }')

for certname in \
$workspace.predict predict
do
name=$(echo $certname | sed "s/\./-/g")

cat << EOF | oc create -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: letsencrypt-$instance-public-tls-$name
  namespace: $namespace
spec:
  secretName: $instance-public-tls-$name
  issuerRef:
    name: letsencrypt
    kind: ClusterIssuer
  dnsNames:
    - $instance.$appsdomain
    - $certname.$instance.$appsdomain
EOF

done

cat << EOF | oc create -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: letsencrypt-$instance-public-predict-tls
  namespace: $namespace
spec:
  secretName: $instance-public-predict-tls
  issuerRef:
    name: letsencrypt
    kind: ClusterIssuer
  dnsNames:
    - $instance.$appsdomain
    - $workspace.predict.$instance.$appsdomain
    - predict.$instance.$appsdomain
EOF

oc get cert letsencrypt-$instance-public-predict-tls -n $namespace

echo
echo Check Certificate with
echo oc get cert letsencrypt-$instance-public-predict-tls -n $namespace
