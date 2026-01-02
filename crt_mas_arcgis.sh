#!/bin/sh

namespace=$1

if [ "x$namespace" = "x"  ]; then
    echo "usage: $0 namespace"
    exit 1
fi

echo "Creating letsencrypt signed certificate in Namespace $namespace"
echo

instance=$(echo $namespace | cut -d"-" -f2)

workspace=$(oc get ArcGISWorkspace -n $namespace \
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
-n $namespace arcgis-ingress-cert-pem \
-o jsonpath='{ .data.tls\.crt }' | base64 -d | \
openssl x509 -noout -issuer -subject -enddate -ext subjectAltName

appsdomain=$(oc get ingresses.config/cluster -o jsonpath='{ .spec.domain }')

cat << EOF | oc create -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: letsencrypt-arcgis-ingress-cert-pem
  namespace: $namespace
spec:
  secretName: arcgis-ingress-cert-pem
  privateKey:
    rotationPolicy: Always
  issuerRef:
    name: letsencrypt
    kind: ClusterIssuer
  dnsNames:
    - $instance.$appsdomain
    - visualinspection.$instance.$appsdomain
    - $workspace.visualinspection.$instance.$appsdomain
EOF

oc get cert arcgis-ingress-cert-pem -n $namespace

echo
echo Check Certificate with
echo oc get cert letsencrypt-arcgis-ingress-cert-pem -n $namespace

oc wait --for jsonpath={.status.conditions[0].status}=True \
cert/letsencrypt-arcgis-ingress-cert-pem -n $namespace

oc set data secret/arcgis-ingress-cert-pem \
-n $namespace \
--from-file ca.crt=isrgrootx1.pem
