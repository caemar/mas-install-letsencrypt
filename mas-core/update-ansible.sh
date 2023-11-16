#!/bin/sh

mkdir -p /tmp/scripts
cp /scripts/* /tmp/scripts/

namespace=$(cat /run/secrets/kubernetes.io/serviceaccount/namespace)
instance=$(echo $namespace | cut -d"-" -f2)
app=$instance-entitymgr-coreidp

for pod in $(oc get pod -l app=$app -n $namespace -o jsonpath='{..metadata.name}')
do
oc get pod -n $namespace $pod -o jsonpath='{ .status.containerStatuses[0].image  }{"\n"}'
for i in \
coreidp-routes.yml=roles/coreidp/tasks/routes.yml \
coreidp-ingress.yml=roles/coreidp/templates/coreidp-login/ingress.yml \
coreidp-login-ingress.yml=roles/coreidp/templates/coreidp/ingress.yml
do
j=$(echo $i | cut -d"=" -f1)
k=$(echo $i | cut -d"=" -f2-)
echo /opt/ansible/$k
oc cp /tmp/scripts/$j -n $namespace $pod:/opt/ansible/$k
done
done

echo
app=$instance-entitymgr-suite

for pod in $(oc get pod -l app=$app -n $namespace -o jsonpath='{..metadata.name}')
do
oc get pod -n $namespace $pod -o jsonpath='{ .status.containerStatuses[0].image  }{"\n"}'
oc rsh -n $namespace $pod mkdir -p /opt/ansible/roles/suite/templates/networking/ingress
for i in \
roles/suite/tasks/networking/routes.yml \
roles/suite/templates/networking/ingress.yml.j2 \
roles/suite/templates/networking/ingress/admin.yml \
roles/suite/templates/networking/ingress/api.yml \
roles/suite/templates/networking/ingress/home.yml
do
echo /opt/ansible/$i
j=$(basename $i)
oc cp /tmp/scripts/suite-$j -n $namespace $pod:/opt/ansible/$i
done
done

echo
app=$instance-entitymgr-ws

for pod in $(oc get pod -l app=$app -n $namespace -o jsonpath='{..metadata.name}')
do
oc get pod -n $namespace $pod -o jsonpath='{ .status.containerStatuses[0].image  }{"\n"}'
for i in \
roles/workspace/tasks/main.yml \
roles/workspace/templates/routes/ingress.yml
do
echo /opt/ansible/$i
j=$(basename $i)
oc cp /tmp/scripts/ws-$j -n $namespace $pod:/opt/ansible/$i
done
done

echo

oc delete route -n $namespace -l ingress!=letsencrypt
