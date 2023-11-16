# MAS patch to replace Routes with Ingress and letsencrypt signed certificates

In IBM Cloud the cert-manager with letsencrypt dns solver is not supported. Only the http solver is able to create signed certificates.

Replace Routes with Ingress to allow using a letsencrypt ClusterIssuer to create signed certificates on Routes.

The steps in this document describes to:
- Create letsencrypt ClusterIssuer with http solver
- Create NetworkPolicy to allow connections to cert-manager solver Pods
- Create Role and RoleBinding to allow Ingress creation
- Replace Routes with Ingress that have letscrypt certificate

All steps must be executed in both Namespaces mas-_instance_-core and mas-_instance_-manage excpept for the cluster resource ClusterIssuer.

This document includes modified ansible scripts that replace ansible scripts in the operators. The modified ansible scrips with create Ingress instead Routes.

## Create letsencrypt ClusterIssuer

```yaml
cat << EOF | oc create -f -
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
```

Note: The ClusterIssuer name must be `letsencrypt` because this name is used in the following steps when creating the Ingress.

## Create NetworkPolicy to allow cert-manger http solver Pods to be reachable

Create NetworkPolicy in both Namespaces mas-_instance_-core and mas-_instance_-manage

```
namespace=mas-dev-core
```

```
namespace=mas-dev-manage
```

```yaml
cat << EOF | oc create -f -
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
```

Note: Create the NetworkPolicy in both Namespaces.

## Add required Role and Rolebinding in mas-_instance_-core Namespace

The following Role and RoleBinding is required to create Ingress and to update ansible scripts in operator Pods.

```
namespace=mas-dev-core
```

```yaml
cat << EOF | oc create -f -
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ibm-mas-entitymgr-ingress
  namespace: $namespace
rules:
- apiGroups:
  - networking.k8s.io
  resources:
  - ingresses
  verbs:
  - create
  - delete
  - get
  - list
  - patch
  - update
  - watch
- apiGroups:
  - ""
  resources:
  - pods
  - pods/exec
  verbs:
  - create
  - delete
  - get
  - list
  - patch
  - update
  - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ibm-mas-entitymgr-ingress
  namespace: $namespace
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: ibm-mas-entitymgr-ingress
subjects:
- kind: ServiceAccount
  name: ibm-mas-entitymgr-coreidp
  namespace: $namespace
- kind: ServiceAccount
  name: ibm-mas-entitymgr-suite
  namespace: $namespace
- kind: ServiceAccount
  name: ibm-mas-entitymgr-ws
  namespace: $namespace
EOF
```

## Modify operator ansible scripts in mas-_instance_-core Namespace

Modify operator ansible scripts.

The following `oc apply -k` creates a Job and CronJob that change the ansible scripts in the operators to create Ingress with signed letsencrypt certificates instead of Routes. The Job will also delete exising Routes. A CronJob will continuously update the ansible scripts in order to keep creating Ingress also after updates to the operators.

```
namespace=mas-dev-core
```

```
oc apply -k https://github.com/caemar/mas-install-letsencrypt/mas-core -n $namespace
```

-or- run git clone and oc apply

```
oc apply -k mas-install-letsencrypt/mas-core -n $namespace
```

Note: The Job and CronJob also delete exiting Routes in the mas-_instance_-core Namespace.

## Add required Role and Rolebinding in mas-_instance_-manage Namespace

The following Role and RoleBinding are required to create Ingress and to update ansible scripts in operator Pods.

```
namespace=mas-dev-manage
```

```yaml
cat << EOF | oc create -f -
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ibm-mas-manage-ingress
  namespace: $namespace
rules:
- apiGroups:
  - networking.k8s.io
  resources:
  - ingresses
  verbs:
  - create
  - delete
  - get
  - list
  - patch
  - update
  - watch
- apiGroups:
  - ""
  resources:
  - pods
  - pods/exec
  verbs:
  - create
  - delete
  - get
  - list
  - patch
  - update
  - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ibm-mas-manage-ingress
  namespace: $namespace
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: ibm-mas-manage-ingress
subjects:
- kind: ServiceAccount
  name: ibm-mas-manage-ws-operator
  namespace: $namespace
EOF
```

## Modify operator ansible scripts in mas-dev-manage Namespace

Modify operator ansible scripts.

The following `oc apply -k` creates a Job and CronJob that change the ansible scripts in the operators to create Ingress with signed letscrypt certificates instead of Routes. The Job will also delete exising Routes. A CronJob will continuously update the ansible scripts in order to keep creating Ingress also after updates to the operators.

```
namespace=mas-dev-manage
```

```
oc apply -k https://github.com/caemar/mas-install-letsencrypt/mas-manage -n $namespace
```

-or- run git clone and oc apply

```
oc apply -k mas-install-letsencrypt/mas-manage -n $namespace
```

Note: The Job and CronJob also delete exiting Routes in the mas-_instance_-manage Namespace.

## Uninstall Ingress and restore operators

```
namespace=mas-dev-core
```

```
instance=$(echo $namespace | cut -d"-" -f2)

oc delete -k mas-install-letsencrypt/mas-core -n $namespace

oc delete pod \
-l "app in ($instance-entitymgr-coreidp,$instance-entitymgr-suite,$instance-entitymgr-ws)" \
-n $namespace

oc delete ingress -n $namespace --all
```

```
namespace=mas-dev-manage
```

```
oc delete -k mas-install-letsencrypt/mas-manage -n $namespace

oc delete pod -l mas.ibm.com/appType=entitymgr-ws-operator -n $namespace

oc delete ingress -n $namespace --all
```

Note: Deleting the operator Pods will recreate the original operators and Routes.

## Reference

For reference the following steps describes how to retrieve the ansible scriptps from the operator and to modify the scripts to replace a Route with Ingress. The Ingress uses the letencrypt ClusterIssuer to create signed certificates.

1. Retrieve operators ansible scripts from entitymgr Pods.

```
namespace=mas-dev-core
```

```
for i in $(oc get pod -n $namespace -l mas.ibm.com/appType=entitymgr -o jsonpath='{..metadata.name}')
do
j=$(echo $i | cut -d"-" -f3)
echo $i
mkdir -p mas-entitymgr-$j
oc cp -n $namespace ${i}:/opt/ansible/ mas-entitymgr-$j
rm -rf mas-entitymgr-$j/.bash_history
find mas-entitymgr-$j -name "*.pyc" -exec rm {} +
done
```

```
namespace=mas-dev-manage
```

```
for i in $(oc get pod -n $namespace -l mas.ibm.com/appType=entitymgr-ws-operator -o jsonpath='{..metadata.name}')
do
j=$(echo $i | cut -d"-" -f3)
echo $i
mkdir -p mas-manage-entitymgr-$j
oc exec -n $namespace $i -- tar cf - -C /opt/ansible ./ | tar -xf - -C mas-manage-entitymgr-$j
rm -rf mas-manage-entitymgr-$j/.bash_history
find mas-manage-entitymgr-$j -name "*.pyc" -exec rm {} +
done
```

2. Modify ansible scripts to use Ingress

The ansible scripts are modified to create Ingress instead Routes.

```
mas-entitymgr-coreidp/roles/coreidp/tasks/routes.yml
mas-entitymgr-coreidp/roles/coreidp/templates/coreidp/ingress.yml
mas-entitymgr-coreidp/roles/coreidp/templates/coreidp-login/ingress.yml

mas-entitymgr-suite/roles/suite/tasks/networking/routes.yml
mas-entitymgr-suite/roles/suite/templates/networking/ingress.yml.j2
mas-entitymgr-suite/roles/suite/templates/networking/ingress/admin.yml
mas-entitymgr-suite/roles/suite/templates/networking/ingress/api.yml
mas-entitymgr-suite/roles/suite/templates/networking/ingress/home.yml

mas-entitymgr-ws/roles/workspace/tasks/main.yml
mas-entitymgr-ws/roles/workspace/templates/routes/ingress.yml

mas-manage-entitymgr-ws/roles/manage-deployment/action_plugins/routeManager.py
```

The Ingress are configured to `reencrypt` incoming traffic. The tls is terminated at the Route with a signed letsencrypt certifcate. Then the traffic is forwarded to the internal service using tls with an internal ca certificate. The internal ca certificate must be stored in the tls.crt file in a secret and specified in the Ingress annotation `route.openshift.io/destination-ca-certificate-secret`.

https://docs.openshift.com/container-platform/4.12/networking/routes/route-configuration.html#nw-ingress-creating-a-route-via-an-ingress_route-configuration

Note: In the Ingress the ClusterIssuer name `letsencrypt` is assumed. Some effort would be required to make this name variable. Also, further improvements would allow to configure a choice between Route and Ingress.

In Namespace mas-_instance_-core the secret _instance_-cert-internal-ca contains a tls.crt file with the internal ca certificate. However, in Namespace mas-_instance_-manage a new secret cert-internal-ca is created with a tls.crt file that is copied from the ca.crt file in secret _instance_-internal-manage-tls.

```sh
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
```

New Ingress with signed letsencrypt certificates and label `ingress: letsencrypt`

Example: /opt/ansible/roles/coreidp/templates/coreidp/ingress.yml

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    # add an annotation indicating the issuer to use.
    cert-manager.io/cluster-issuer: letsencrypt
    route.openshift.io/termination: "reencrypt"
    route.openshift.io/destination-ca-certificate-secret: "{{ certNames.internalCoreIDP }}"
  labels:
    ingress: letsencrypt
    mas.ibm.com/instanceId: "{{ instanceId }}"
    app.kubernetes.io/instance: "{{ instanceId }}"
    app.kubernetes.io/managed-by: "{{ operatorName }}"
    app.kubernetes.io/name: ibm-mas
  name: "{{ instanceId }}-auth"
  namespace: "{{ coreNamespace }}"
spec:
  rules:
  - host: "auth.{{ domain }}"
    http:
      paths:
      - pathType: Prefix
        path: /
        backend:
          service:
            name: coreidp
            port:
              name: coreidp
  tls:
  - hosts:
    - "{{ domain }}"
    - "auth.{{ domain }}"
    secretName:  "letsencrypt-{{ instanceId }}-auth"
```

Old Route with selfsigned certificates

Example: /opt/ansible/roles/coreidp/templates/coreidp/route.yml

```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: "{{ instanceId }}-auth"
  namespace: "{{ coreNamespace }}"
  labels:
    mas.ibm.com/instanceId: "{{ instanceId }}"
    app.kubernetes.io/instance: "{{ instanceId }}"
    app.kubernetes.io/managed-by: "{{ operatorName }}"
    app.kubernetes.io/name: ibm-mas
  annotations:
    haproxy.router.openshift.io/proxy-connect-timeout: "300s"
    haproxy.router.openshift.io/proxy-read-timeout: "300s"
    haproxy.router.openshift.io/timeout: "300s"
spec:
  host: "auth.{{ domain }}"
  path: /
  to:
    kind: Service
    name: coreidp
    weight: 100
  port:
    targetPort: coreidp
  tls:
    termination: reencrypt
    certificate: |
      {{ externalCertificate | indent(6, False) }}
    key: |
      {{ externalKey | indent(6, False) }}
    caCertificate: |
      {{ externalCertificateAuthorityCertificate | indent(6, False) }}
    destinationCACertificate: |
      {{ internalCertificateAuthorityCertificate | indent(6, False) }}
  wildcardPolicy: None
```

3. Replace ansible scripts in operator Pods

```
namespace=mas-dev-core
instance=$(echo $namespace | cut -d"-" -f2)
```

Optional: Get conatainer image sha

```
namespace=mas-dev-core

for i in $(oc get pod -l mas.ibm.com/appType=entitymgr -n $namespace -o jsonpath='{..metadata.name}')
do
j=$(echo $i | cut -d"-" -f1-3)
echo $i
oc get pod -n $namespace $i -o jsonpath='{ .status.containerStatuses[0].image  } '
echo $j
done
```

Replace ansible scripts in operators

```
namespace=mas-dev-core
```

```
instance=$(echo $namespace | cut -d"-" -f2)
app=$instance-entitymgr-coreidp

for pod in $(oc get pod -l app=$app -n $namespace -o jsonpath='{..metadata.name}')
do
for i in \
roles/coreidp/tasks/routes.yml \
roles/coreidp/templates/coreidp-login/ingress.yml \
roles/coreidp/templates/coreidp/ingress.yml
do
echo /opt/ansible/$i
oc cp mas-entitymgr-coreidp/$i -n $namespace $pod:/opt/ansible/$i
done
done

app=$instance-entitymgr-suite

for pod in $(oc get pod -l app=$app -n $namespace -o jsonpath='{..metadata.name}')
do
for i in \
roles/suite/tasks/networking/routes.yml \
roles/suite/templates/networking/ingress.yml.j2 \
roles/suite/templates/networking/ingress
do
echo /opt/ansible/$i
oc cp mas-entitymgr-suite/$i -n $namespace $pod:/opt/ansible/$i
done
done

app=$instance-entitymgr-ws

for pod in $(oc get pod -l app=$app -n $namespace -o jsonpath='{..metadata.name}')
do
for i in \
roles/workspace/tasks/main.yml \
roles/workspace/templates/routes/ingress.yml
do
echo /opt/ansible/$i
oc cp mas-entitymgr-ws/$i -n $namespace $pod:/opt/ansible/$i
done
done
```

Delete Routes

```
namespace=mas-dev-core
```

```
instance=$(echo $namespace | cut -d"-" -f2)

for i in \
$(oc get route -n $namespace \
$instance-admin $instance-api $instance-auth $instance-home $instance-masdev-home -o name 2>/dev/null)
do
oc delete $i -n $namespace
done

oc get route -n $namespace
```

Replace ansible in mas-dev-manage

```
pod=$(oc get pod -n mas-dev-manage -l mas.ibm.com/appType=entitymgr-ws-operator -o name)

oc cp mas-manage/mas-manage-entitymgr-ws/roles/manage-deployment/action_plugins/routeManager.py \
-n mas-dev-manage $pod:/opt/ansible/roles/manage-deployment/action_plugins/routeManager.py
```

Delete routes in mas-dev-manage

```
oc delete route -n mas-dev-manage \
all-dev-manage-masdev-81 dev-manage-masdev erd-dev-manage-masdev-81 maxinst-dev-manage-masdev-81
```

## Troubleshooting

```
namespace=mas-dev-core
```

```
instance=$(echo $namespace | cut -d"-" -f2)
app=$instance-entitymgr-coreidp
```

```
app=$instance-entitymgr-suite
```

```
app=$instance-entitymgr-ws
```

```
oc logs -n $namespace -l app=$app --tail 5 -f
```

```
oc logs -n $namespace job/mas-install-letsencrypt
```

```
namespace=mas-dev-manage
```

```
oc logs -n $namespace -l mas.ibm.com/appType=entitymgr-ws-operator --tail 5 -f
```

```
oc logs -n $namespace job/mas-install-letsencrypt
```

Check that Routes respond with code other than 503, for example 404, 301 or 302

```
for url in \
$(oc get route -n $namespace -o jsonpath='{ range @.items[*] }{ .spec.host }{ .spec.path } { end }')
do
  curl https://$url -o /dev/null -s -w '%{http_code} '
  echo https://$url
done
```

Note: Run curl without -k to check signed certificate.
