#!/bin/sh

mkdir -p /tmp/scripts
cp /scripts/* /tmp/scripts/

namespace=$(cat /run/secrets/kubernetes.io/serviceaccount/namespace)
instance=$(echo $namespace | cut -d"-" -f2)

# copy ca.crt from $instance-internal-manage-tls
# into tls.crt in new secret cert-inernal-ca
cacrt=$(oc get secret $instance-internal-manage-tls \
                    -n $namespace \
                    -o jsonpath='{ .data.ca\.crt }' \
                    | base64 -d)
oc create secret generic cert-internal-ca \
-n $namespace \
--from-literal tls.crt="$cacrt" \
--dry-run=client -o yaml \
| oc apply -f -

echo

for pod in $(oc get pod -l mas.ibm.com/appType=entitymgr-ws-operator -n $namespace -o jsonpath='{..metadata.name}')
do
oc get pod -n $namespace $pod -o jsonpath='{ .status.containerStatuses[0].image  }{"\n"}'
for i in \
roles/manage-deployment/action_plugins/routeManager.py
do
echo /opt/ansible/$i
j=$(basename $i)
oc cp /tmp/scripts/$j -n $namespace $pod:/opt/ansible/$i
done
done

echo

oc delete route -n $namespace -l ingress!=letsencrypt
