#!/bin/sh

namespace=$1

if [ "x$namespace" = "x"  ]; then
    echo "usage: $0 namespace"
    exit 1
fi

instance=$(echo $namespace | cut -d"-" -f2)
workspace=$(oc get workspace -n $namespace \
            -o jsonpath='{ ..metadata.labels.mas\.ibm\.com/workspaceId }')

echo "Creating letsencrypt signed certificate in Namespace $namespace"
echo

cat << EOF | oc create -f - 2>/dev/null
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt
spec:
  acme:
    preferredChain: ""
    privateKeySecretRef:
      name: letsencrypt-secret
    server: https://acme-v02.api.letsencrypt.org/directory
    solvers:
    - http01:
        ingress:
          class: openshift-default
EOF

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

oc patch suite $instance -n $namespace \
--type merge \
-p '{ "spec": { "settings": { "manualCertMgmt": true }}}'

oc get secret \
-n $namespace $instance-cert-public -o jsonpath='{ .data.tls\.crt }' | base64 -d | \
openssl x509 -noout -issuer -subject -enddate -ext subjectAltName

appsdomain=$(oc get ingresses.config/cluster -o jsonpath='{ .spec.domain }')

for certname in admin api auth home $workspace.home
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
cert/letsencrypt-$name -n $namespace --timeout=120s

done

cat << EOF | oc create -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: letsencrypt-$instance-cert-public
  namespace: $namespace
spec:
  secretName: $instance-cert-public
  issuerRef:
    name: letsencrypt
    kind: ClusterIssuer
  dnsNames:
    - $instance.$appsdomain
    - admin.$instance.$appsdomain
    - api.$instance.$appsdomain
    - auth.$instance.$appsdomain
    - home.$instance.$appsdomain
    - $workspace.home.$instance.$appsdomain
EOF

oc get cert letsencrypt-$instance-cert-public -n $namespace

echo
echo Check Certificate with
echo oc get cert letsencrypt-$instance-cert-public -n $namespace

oc delete cert -n $namespace \
letsencrypt-$workspace-home \
letsencrypt-admin \
letsencrypt-api \
letsencrypt-auth \
letsencrypt-home

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
