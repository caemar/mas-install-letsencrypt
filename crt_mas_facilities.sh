#!/bin/sh

namespace=$1

if [ "x$namespace" = "x"  ]; then
    echo "usage: $0 namespace"
    exit 1
fi

echo "Creating letsencrypt signed certificate in Namespace $namespace"
echo

instance=$(oc get FacilitiesWorkspace -n $namespace \
            -o jsonpath='{ ..metadata.labels.mas\.ibm\.com/instanceId }')

workspace=$(oc get FacilitiesWorkspace -n $namespace \
            -o jsonpath='{ .items[*].metadata.labels.mas\.ibm\.com/workspaceId }' \
            | awk '{ print $1 }')

if [ -z "$instance" ]; then
  echo "ERROR: Wrong Namespace $namespace"
  echo "MAS Facilities not installed in Namespace $namespace"
  oc get FacilitiesWorkspace -A
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
-n $namespace $instance-$workspace-public-facilities-tls \
-o jsonpath='{ .data.tls\.crt }' | base64 -d | \
openssl x509 -noout -issuer -subject -enddate -ext subjectAltName

appsdomain=$(oc get ingresses.config/cluster -o jsonpath='{ .spec.domain }')

# small  pod-0
# medium pod-0, pod-1, pod-2
# large  pod-0, ..., pod-12

echo "Deleting old cert"
oc delete cert -n mas-dev-facilities dev-masdev-public-facilities-tls

cat << EOF | oc create -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: letsencrypt-$instance-$workspace-public-facilities-tls
  namespace: $namespace
spec:
  secretName: $instance-$workspace-public-facilities-tls
  privateKey:
    rotationPolicy: Always
  issuerRef:
    name: letsencrypt
    kind: ClusterIssuer
  dnsNames:
    - facilities.$instance.$appsdomain
    - $workspace.facilities.$instance.$appsdomain
    - multiagents.$workspace.facilities.$instance.$appsdomain
    - dataconnectagent.$workspace.facilities.$instance.$appsdomain
    - extendedformulaagent.$workspace.facilities.$instance.$appsdomain
    - formularecalcagent.$workspace.facilities.$instance.$appsdomain
    - incomingmailagent.$workspace.facilities.$instance.$appsdomain
    - objectmigrationagent.$workspace.facilities.$instance.$appsdomain
    - objectpublishagent.$workspace.facilities.$instance.$appsdomain
    - pmscheduleragent.$workspace.facilities.$instance.$appsdomain
    - reportqueueagent.$workspace.facilities.$instance.$appsdomain
    - reservesmtpagent.$workspace.facilities.$instance.$appsdomain
    - wfagent.$workspace.facilities.$instance.$appsdomain
    - wffutureagent.$workspace.facilities.$instance.$appsdomain
    - wfnotificationagent.$workspace.facilities.$instance.$appsdomain
    - appserver.$workspace.facilities.$instance.$appsdomain
    - pod-0.$workspace.facilities.$instance.$appsdomain
    - pod-1.$workspace.facilities.$instance.$appsdomain
    - pod-2.$workspace.facilities.$instance.$appsdomain
    - pod-3.$workspace.facilities.$instance.$appsdomain
    - pod-4.$workspace.facilities.$instance.$appsdomain
    - pod-5.$workspace.facilities.$instance.$appsdomain
    - pod-6.$workspace.facilities.$instance.$appsdomain
    - pod-7.$workspace.facilities.$instance.$appsdomain
    - pod-8.$workspace.facilities.$instance.$appsdomain
    - pod-9.$workspace.facilities.$instance.$appsdomain
    - pod-10.$workspace.facilities.$instance.$appsdomain
    - pod-11.$workspace.facilities.$instance.$appsdomain
    - pod-12.$workspace.facilities.$instance.$appsdomain
$(for j in \
$(oc get FacilitiesWorkspace -n $namespace \
-o jsonpath='{.items[*].spec.settings.dwfagents[*].name}')
do
echo "    - dwfagent-$j.$workspace.facilities.$instance.$appsdomain"
done )
EOF

oc get cert letsencrypt-$instance-$workspace-public-facilities-tls -n $namespace

echo
echo Check Certificate with
echo oc get cert letsencrypt-$instance-$workspace-public-facilities-tls -n $namespace

oc wait --for jsonpath={.status.conditions[0].status}=True \
cert/letsencrypt-$instance-$workspace-public-facilities-tls -n $namespace

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
