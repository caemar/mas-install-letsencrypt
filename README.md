# MAS Manual certificate management with letsencrypt

In IBM Cloud the cert-manager with letsencrypt dns solver is not supported. Only the http solver is able to create signed certificates.

This document describes to enable manual certificate management in MAS. The cert-manager will create letsencrypt Certificates that are stored in Secrets. MAS will then use the Certificates from the Secrets.

- MAS version: 9.1.6 (Catalog v9-251127-amd64)
- OpenShift version: 4.18

https://www.ibm.com/docs/en/mas-cd/continuous-delivery?topic=management-manual-certificate

This document describes to:
- Create letsencrypt ClusterIssuer with http solver
- Create NetworkPolicy to allow connections to cert-manager solver Pods
- Enable manual certificate management (`spec.settings.manualCertMgmt` = `true`)
- Create letsencrypt signed certificates that are stored in Secrets:

  Namespace | Secret
  --------- | ------
  mas-_instance_-core | _instance_-cert-public
  mas-_instance_-manage | _instance_-_workspace_-cert-public-81
  mas-_instance_-facilities | _instance_-_workspace_-public-facilities-tls

All steps must be executed in both Namespaces mas-_instance_-core and mas-_instance_-manage except for the cluster resource ClusterIssuer.

The scripts creates the required ClusterIssuer, NetworkPolicy and Certificate. Provide the target Namespace name mas-_instance_-core and mas-_instance_-manage to the scripts.

Example _instance_ = `dev`

```
./crt_mas_core.sh mas-dev-core
```

```
./crt_mas_manage.sh mas-dev-manage
```

```
./crt_mas_facilities.sh mas-dev-facilities
```

```
./crt_mas_monitor.sh mas-dev-monitor
```

```
./crt_mas_visualinspection.sh mas-dev-visualinspection
```

```
./crt_mas_iot.sh mas-dev-iot
```

Note: The first time using letscrypt on a new domain might show a rate limit error: Failed to create Order: 429 urn:ietf:params:acme:error:rateLimited: Error creating new order :: too many certificates (5) already issued for this exact set of domains in the last 168 hours, see https://letsencrypt.org/docs/duplicate-certificate-limit/

Note: The subject CN in a certificate has a 63 character limit. Therefor always add a short (less than 63 characters) DNS name in the first entry in the `dnsNames` list followed by one or more long DNS names. The first DNS name will become the Subject CN name in the certificate.

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

## Create letsencrypt Certificates in Namespace mas-_instance_-core

```
namespace=mas-dev-core
```

```
instance=$(echo $namespace | cut -d"-" -f2)
workspace=$(oc get workspace -n $namespace \
            -o jsonpath='{ ..metadata.labels.mas\.ibm\.com/workspaceId }')
```

Check certificates

```
for route in  $(oc get route -n $namespace -o jsonpath='{ ..metadata.name }')
do
echo "------------------------------ $route ------------------------------"
oc get route $route -n $namespace -o jsonpath='{ .spec.tls.certificate }' | \
openssl x509 -noout -issuer -enddate
done
```

```
for host in $(oc get route -n $namespace -o jsonpath='{ ..spec.host }')
do
echo "------------------------------ $host ------------------------------"
openssl s_client -connect $host:443 < /dev/null 2>/dev/null | \
openssl x509 -noout -issuer -subject -enddate -ext subjectAltName
done
```

```
oc get secret \
-n $namespace $instance-cert-public -o jsonpath='{ .data.tls\.crt }' | base64 -d | \
openssl x509 -noout -issuer -subject -enddate -ext subjectAltName
```

Enable manual certificate management

https://www.ibm.com/docs/en/mas-cd/continuous-delivery?topic=management-enabling-manual-certificate

```
oc get suite $instance -n $namespace -o jsonpath='{ .spec.settings.manualCertMgmt }'
```

In the spec.settings section, change the manualCertMgmt variable from false to true.

```
oc patch suite $instance -n $namespace \
--type merge \
-p '{ "spec": { "settings": { "manualCertMgmt": true }}}'
```

Create letsencrypt certificate in secret _instance_-cert-public

https://www.ibm.com/docs/en/mas-cd/continuous-delivery?topic=management-manual-certificate

https://www.ibm.com/docs/en/mas-cd/continuous-delivery?topic=management-uploading-public-certificates-in-red-hat-openshift

Note: Create different certificates to avoid letsencrypt rate limit.

```yaml
appsdomain=$(oc get ingresses.config/cluster -o jsonpath='{ .spec.domain }')

for certname in admin api auth home
do

cat << EOF | oc create -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: letsencrypt-$instance-cert-public-$certname
  namespace: $namespace
spec:
  secretName: $instance-cert-public-$certname
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
  name: letsencrypt-$instance-cert-public-$workspace-home
  namespace: $namespace
spec:
  secretName: $instance-cert-public-$workspace-home
  issuerRef:
    name: letsencrypt
    kind: ClusterIssuer
  dnsNames:
    - $instance.$appsdomain
    - $workspace.home.$instance.$appsdomain
EOF
```

```yaml
appsdomain=$(oc get ingresses.config/cluster -o jsonpath='{ .spec.domain }')

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
```

Check status if letsencrypt solver Pods run successful

```
oc get pod -n $namespace --sort-by .metadata.creationTimestamp
oc get route -n $namespace
oc get cert letsencrypt-$instance-cert-public -n $namespace
```

Check certificates again

```
for route in  $(oc get route -n $namespace -o jsonpath='{ ..metadata.name }')
do
echo "------------------------------ $route ------------------------------"
oc get route $route -n $namespace -o jsonpath='{ .spec.tls.certificate }' | \
openssl x509 -noout -issuer -enddate
done
```

```
for host in $(oc get route -n $namespace -o jsonpath='{ ..spec.host }')
do
echo "------------------------------ $host ------------------------------"
openssl s_client -connect $host:443 < /dev/null 2>/dev/null | \
openssl x509 -noout -issuer -subject -enddate -ext subjectAltName
done
```

```
for route in  $(oc get route -n $namespace -o jsonpath='{ ..metadata.name }')
do
echo "------------------------------ $route ------------------------------"
oc get route $route -n $namespace -o jsonpath='{ .spec.tls.certificate }' | \
openssl x509 -noout -issuer -subject -enddate -ext subjectAltName
done
```

```
oc get secret \
-n $namespace $instance-cert-public -o jsonpath='{ .data.tls\.crt }' | base64 -d | \
openssl x509 -noout -issuer -subject -enddate -ext subjectAltName
```

Check that Routes respond with code 404, 301 or 302. A code 503 indicates a wrong ca certificate in the Route.

```
for url in \
$(oc get route -n $namespace \
-o jsonpath='{ range @.items[*] }{ .spec.host }{ .spec.path } { end }')
do
  curl https://$url -o /dev/null -s -w '%{http_code} '
  echo https://$url
done
```

Note: Run curl without -k to check signed certificate.

## Create letsencrypt Certificates in Namespace mas-_instance_-manage

```
namespace=mas-dev-manage
```

```
instance=$(echo $namespace | cut -d"-" -f2)
workspace=$(oc get pod -n $namespace \
            -o jsonpath='{ .items[*].metadata.labels.mas\.ibm\.com/workspaceId }' \
            | awk '{ print $1 }')
```

Check certificates

```
for route in  $(oc get route -n $namespace -o jsonpath='{ ..metadata.name }')
do
echo "------------------------------ $route ------------------------------"
oc get route $route -n $namespace -o jsonpath='{ .spec.tls.certificate }' | \
openssl x509 -noout -issuer -enddate
done
```

```
for host in $(oc get route -n $namespace -o jsonpath='{ ..spec.host }')
do
echo "------------------------------ $host ------------------------------"
openssl s_client -connect $host:443 < /dev/null 2>/dev/null | \
openssl x509 -noout -issuer -subject -enddate -ext subjectAltName
done
```

```
oc get secret \
-n $namespace $instance-$workspace-cert-public-81 \
-o jsonpath='{ .data.tls\.crt }' | base64 -d | \
openssl x509 -noout -issuer -subject -enddate -ext subjectAltName
```

Create letsencrypt certificate in secret _instance_-_workspace_-cert-public-81

https://www.ibm.com/docs/en/mas-cd/continuous-delivery?topic=management-manual-certificate

https://www.ibm.com/docs/en/mas-cd/continuous-delivery?topic=management-uploading-public-certificates-in-red-hat-openshift

```yaml
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
    - $workspace-foundation.manage.$instance.$appsdomain
EOF
```

Check status if letsencrypt solver Pods run successful

```
oc get pod -n $namespace --sort-by .metadata.creationTimestamp
oc get route -n $namespace
oc get cert letsencrypt-$instance-$workspace-cert-public-81 -n $namespace
```

Add letsencrypt root CA ca.crt to secret.

```
curl -LO https://letsencrypt.org/certs/isrgrootx1.pem
```

```
oc set data secret/$instance-$workspace-cert-public-81 \
-n $namespace \
--from-file ca.crt=isrgrootx1.pem
```

Check certificates again

```
for route in  $(oc get route -n $namespace -o jsonpath='{ ..metadata.name }')
do
echo "------------------------------ $route ------------------------------"
oc get route $route -n $namespace -o jsonpath='{ .spec.tls.certificate }' | \
openssl x509 -noout -issuer -enddate
done
```

```
for host in $(oc get route -n $namespace -o jsonpath='{ ..spec.host }')
do
echo "------------------------------ $host ------------------------------"
openssl s_client -connect $host:443 < /dev/null 2>/dev/null | \
openssl x509 -noout -issuer -subject -enddate -ext subjectAltName
done
```

```
for route in  $(oc get route -n $namespace -o jsonpath='{ ..metadata.name }')
do
echo "------------------------------ $route ------------------------------"
oc get route $route -n $namespace -o jsonpath='{ .spec.tls.certificate }' | \
openssl x509 -noout -issuer -subject -enddate -ext subjectAltName
done
```

```
oc get secret -n $namespace \
$instance-$workspace-cert-public-81 -o jsonpath='{ .data.tls\.crt }' | base64 -d | \
openssl x509 -noout -issuer -subject -enddate -ext subjectAltName
```

Check that Routes respond with code 404, 301 or 302. A code 503 indicates a wrong ca certificate in the Ingress.

```
for url in \
$(oc get route -n $namespace \
-o jsonpath='{ range @.items[*] }{ .spec.host }{ .spec.path } { end }')
do
  curl https://$url -o /dev/null -s -w '%{http_code} '
  echo https://$url
done
```

Note: Run curl without -k to check signed certificate.

## Troubleshooting letsencrypt certs

```
openssl verify -untrusted chain.pem cert.pem
```

With `chain.pem` the intermediate certificates and `cert.pem` the certificate.

```
openssl crl2pkcs7 -nocrl -certfile chain.pem | openssl pkcs7 -print_certs -noout
```

```
while openssl x509 -noout -issuer -subject -dates; do :; done < chain.pem 2>/dev/null
```

Download `chain.pem` letsencrypt intermediate CAs

https://letsencrypt.org/certificates/

```
curl https://letsencrypt.org/certs/2024/r12.pem >  chain.pem
curl https://letsencrypt.org/certs/2024/r13.pem >> chain.pem
```
