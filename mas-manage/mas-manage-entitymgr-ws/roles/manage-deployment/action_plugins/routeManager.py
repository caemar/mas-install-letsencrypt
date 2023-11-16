#!/usr/bin/python3

# -----------------------------------------------------------
# Licensed Materials - Property of IBM
# 5737-M66, 5900-AAA
# (C) Copyright IBM Corp. 2021 All Rights Reserved.
# US Government Users Restricted Rights - Use, duplication, or disclosure
# restricted by GSA ADP Schedule Contract with IBM Corp.
# -----------------------------------------------------------

# Ansible plugin for managing route.openshift.io/v1.
#
# Sach Balagopalan
#



from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

from ansible.plugins.action import ActionBase
from kubernetes.client.rest import ApiException
from ansible.module_utils._text import to_native
from ansible.errors import AnsibleError, AnsibleParserError
from openshift.dynamic.exceptions import NotFoundError

# Import the K8sAnsibleMixin class so we can access the DynamicClient
from ansible_collections.kubernetes.core.plugins.module_utils.common import get_api_client

# Use the display module to log errors
from ansible.utils.display import Display
display = Display()

import base64
import os

# Only way to figure out import exceptions inside mas.utils module, is to catch the exception and raise an error.
# Unfortunately native logging for plugins is inadequate.
try:
    import mas.utils.openid as openidUtil
except Exception as e:
    raise AnsibleError('Error when importing mas.utils.openid ***: %s' % to_native(e))


class ActionModule(ActionBase):

    # Implement ActionBase's run() method
    def run(self, tmp=None, task_vars=None):
        super(ActionModule, self).run(tmp, task_vars)

        #Initialize DynamicClient (python api for Kube) and grab the task args
        dynaClient = get_api_client()
        task_args = self._task.args.copy()
        routeManager = RouteManager(dynaClient, task_args)
        if task_args['constructor'] == 'deleteonly':
            ret = routeManager.delete()
            #ret = dict()
            #ret['status'] = "deleteonly - done"
            return ret
        #routeManager.delete()
        routeManager.create()
        return dict()

class RouteManager(object):

    #Constructor
    def __init__(self, k8sDynaClient, taskArgs):
        self.taskArgs = taskArgs
        self.k8sDynaClient = k8sDynaClient
        self.routename= self.taskArgs['routename']
        self.namespace = self.taskArgs['namespace']
        self.constructor = self.taskArgs['constructor']
        self.appId = self.taskArgs['appId']
        self.oidcRedirectURI = 'https://' + self.taskArgs['host']  + '/oidcclient/redirect/oidc'
        if self.constructor == "create":
            self.operatorversion = self.taskArgs['operatorversion']
            self.instanceId = self.taskArgs['instanceId']
            self.routeDetails = self._routeDetails(self.taskArgs)
            self.routeLabels = dict(self.routeDetails['labels'])
            self.routeSpec = self._routeSpec(self.routeDetails, self.taskArgs)
            self.routeBody = self._routeBody(self.routename, self.routeLabels, self.routeSpec)
            self.ingressSpec = self._ingressSpec(self.routeDetails, self.taskArgs)
            self.ingressBody = self._ingressBody(self.routename, self.routeLabels, self.ingressSpec)
            self.workspaceid = self.taskArgs['workspaceid']
            self.subdomain = self.taskArgs['subdomain']
            self.registerOIDC = self.taskArgs['registerOIDC']
            self.domain = self.taskArgs['domain']
            self.core_namespace = self.taskArgs['core_namespace']

    def create(self):
        # routev1 = self.k8sDynaClient.resources.get(api_version="route.openshift.io/v1", kind='Route')
        routev1 = self.k8sDynaClient.resources.get(api_version="networking.k8s.io/v1", kind='Ingress')
        try:
            # resp = routev1.create(body=self.routeBody, namespace=self.namespace)
            resp = routev1.create(body=self.ingressBody, namespace=self.namespace)
            self._registerOpenID()
        except Exception as e:
            #raise AnsibleError('create() Error creating route***: %s' % to_native(e))
            # Route Exists, let's attempt to patch it incase the RouteSpec changed.
            try:
                # respatch = routev1.patch(body=self.routeBody, namespace=self.namespace)
                respatch = routev1.patch(body=self.ingressBody, namespace=self.namespace)
                self._registerOpenID()
            except:
                # If create and patch failed indicates the route is not new/changed, so let's leave it alone.
                # Route already exists.
                display.debug(e) # Eat the error. Route already exists.

    def delete(self):
        # routev1 = self.k8sDynaClient.resources.get(api_version="route.openshift.io/v1", kind='Route')
        routev1 = self.k8sDynaClient.resources.get(api_version="networking.k8s.io/v1", kind='Ingress')
        try:
            routev1.delete(name=self.routename, namespace=self.namespace)
            return self._unRegisterOpenID()
        except Exception as e:
            # Just eat the error instead of raising an AnsibleError. We don't care if the route does not exist.
            display.debug(e)

    def _mountInternalTLS(self):
        try:
            internalsecretname = self.taskArgs['internaltls']
            namespace = self.taskArgs['namespace']
            externalCert = self._secret(internalsecretname, namespace).decodeB64('tls.crt')
            file = open("/etc/ssl/certs/agent-cert/tls.crt", "w")
            file.write(externalCert)
            file.close()
            externalKey = self._secret(internalsecretname, namespace).decodeB64('tls.key')
            file = open("/etc/ssl/certs/agent-cert/tls.key", "w")
            file.write(externalKey)
            file.close()
        except Exception as e:
            raise AnsibleError('_mountInternalTLS() Error writing tls***: %s' % to_native(e))

    def _mountInternalCA(self):
        try:
            internalsecretname = self.taskArgs['internaltls']
            namespace = self.taskArgs['namespace']
            internalCA = self._secret(internalsecretname, namespace).decodeB64('ca.crt')
            file = open("/etc/ssl/certs/internal-" + self.appId+ "-tls/ca.crt", "w")
            file.write(internalCA)
            file.close()
        except Exception as e:
            raise AnsibleError('_mountInternalCA() Error writing ca.crt***: %s' % to_native(e))

    def _retDict(self, status="ok", message="successful"):
        ret = dict()
        ret['status'] = status
        ret['routename'] =  self.routename
        ret['OidcURI'] = self.oidcRedirectURI
        ret['constructor'] = self.constructor
        ret['message'] = message
        return ret

    def _unRegisterOpenID(self, redirectUri=None):
        try:
            if redirectUri is None:
                redirectUri = self.oidcRedirectURI
            # Unregister old ones
            openidUtil.removeOpenIdClientURI(self.appId, redirectUri, self.core_namespace,clientIDVersion=2)
            return self._retDict(status="success")
        except Exception as e:
            # Log the error and skip
            display.debug(e)
            return self._retDict(status="skip", message=to_native(e))

    def _registerOpenID(self, redirectUri=None):
        if self.registerOIDC == True:
            self._mountInternalCA()
            self._mountInternalTLS()
            # Commenting out self.subdomain for now. Looks like mas needs the subdomain to be manage
            #baseUri = 'https://' + self.workspaceid  + '.' + self.subdomain + '.' + self.domain
            #baseUri = 'https://' + self.workspaceid  + '.manage' + '.' + self.domain
            #redirectUri = baseUri + '/oidcclient/redirect/oidc'
            if redirectUri is None:
                redirectUri = self.oidcRedirectURI
            #self._unRegisterOpenID() # MASISMIG-29765
            #self._unRegisterOpenID(self.oidcRedirectURI+"/auth/callback")
            try:
                # Register new one
                #openidUtil.addOpenIdClientURI("manage", redirectUri, self.core_namespace)
                openidUtil.addOpenIdClientURI(self.appId, redirectUri, self.core_namespace, clientIDVersion=2)
            except Exception as e:
                raise AnsibleError('registerOpenID() Error from MaximoAppSuite ***: %s' % to_native(e))

    def _routeDetails(self, module_params):

        routename= module_params['routename']
        host = module_params['host']
        subdomain = module_params['subdomain']
        targetServiceName = module_params['targetServiceName']
        targetServiceName = module_params['targetServiceName']
        targetPortName = module_params['targetPortName']
        publicsecret = module_params['publictls']
        instid = module_params['instanceId']
        appid = module_params['appId']
        wrkspid = module_params['workspaceid']
        ov = module_params['operatorversion']
        path = '/' if 'path' not in module_params else module_params['path']
        uiRoute = {
            'name': f"{routename}",
            'host': f'{host}',
            'subdomain': f'{subdomain}',
            'targetServiceName': f"{targetServiceName}",
            'targetPortName':f"{targetPortName}",
            'labels':{'mas.ibm.com/applicationId':appid,'mas.ibm.com/instanceId':instid,'mas.ibm.com/workspaceId':wrkspid, 'operatorversion':ov },
            'path': f'{path}'
        }
        return uiRoute

    def _routeSpec(self, routeDetails, module_params):

        publicsecretname = module_params['publictls']
        internalsecretname = module_params['internaltls']
        namespace = module_params['namespace']

        isIntCaNull = self._secret(internalsecretname, namespace).isNull('ca.crt')
        if isIntCaNull != "True":
            internalCA = self._secret(internalsecretname, namespace).decodeB64('ca.crt')
        else:
            internalCA = ""
        #internalCA = self._secret(internalsecretname, namespace).decodeB64('ca.crt')
        externalCert = self._secret(publicsecretname, namespace).decodeB64('tls.crt')
        externalKey = self._secret(publicsecretname, namespace).decodeB64('tls.key')
        hostName = routeDetails['host']
        subdomain = routeDetails['subdomain']
        targetServiceName = routeDetails['targetServiceName']
        targetPortName = routeDetails['targetPortName']
        certs=dict(termination='reencrypt',certificate=externalCert,key=externalKey,destinationCACertificate=internalCA)
        xstr = lambda s: s or ""

        routeSpec = dict(host=hostName,
            subdomain=subdomain,
            path=xstr(routeDetails['path']),
            to=dict(kind='Service',name=targetServiceName,weight=100),
            port=dict(targetPort=targetPortName),
            tls=certs,
            wildcardPolicy='None')

        return routeSpec

    def _routeBody(self, name, labels, spec):
        return {
            "kind": "Route",
            "apiVersion": "route.openshift.io/v1",
            "metadata": {
                "name": name,
                "labels": labels,
                "annotations": {
                    "haproxy.router.openshift.io/client-max-body-size": "200m",
                    "haproxy.router.openshift.io/proxy-connect-timeout": "7200s",
                    "haproxy.router.openshift.io/proxy-read-timeout": "7200s",
                    "haproxy.router.openshift.io/timeout": "7200s"
                }
            },
            "spec": spec
        }

    def _ingressSpec(self, routeDetails, module_params):

        hostName = routeDetails['host']
        targetServiceName = routeDetails['targetServiceName']
        targetPortName = routeDetails['targetPortName']
        xstr = lambda s: s or ""

        routename= module_params['routename']
        domain = module_params['domain']
        service = dict(name=targetServiceName,
                       port=dict(name=targetPortName))
        path=dict(pathType="Prefix",
                  path=xstr(routeDetails['path']),
                  backend=dict(service=service))
        paths = [path]
        http = dict(paths=paths)
        rule = dict(host=hostName,
                    http=http)
        rules = [rule]

        hosts = [domain, hostName]
        tls = [dict(hosts=hosts,
                    secretName="lestencrypt-"+ routename)]

        ingressSpec = dict(rules=rules,
                           tls=tls)

        # spec:
        #   rules:
        #   - host: "{{ homeDomain }}"
        #     http:
        #       paths:
        #       - pathType: Prefix
        #         path: /
        #         backend:
        #           service:
        #             name: navigator
        #             port:
        #               name: navigator
        #   tls:
        #   - hosts:
        #     - "{{ masDomain }}"
        #     - "{{ homeDomain }}"
        #     secretName: "letsencrypt-{{ instanceId }}-{{workspaceId}}-home"

        return ingressSpec

    def _ingressBody(self, name, labels, spec):
        labels['ingress'] = "letsencrypt"
        return {
            "kind": "Ingress",
            "apiVersion": "networking.k8s.io/v1",
            "metadata": {
                "name": name,
                "labels": labels,
                "annotations": {
                    "cert-manager.io/cluster-issuer": "letsencrypt",
                    "route.openshift.io/termination": "reencrypt",
                    "route.openshift.io/destination-ca-certificate-secret": "cert-internal-ca"
                }
            },
            "spec": spec
        }

    def _secret(self, name, namespace):
        try:
            secretv1 = self.k8sDynaClient.resources.get(api_version="v1", kind='Secret')
            return SecretUtility(secretv1.get(name, namespace))
        except NotFoundError as e:
            raise AnsibleError('Error***: %s' % to_native(e))

class SecretUtility(object):
    def __init__(self, k8sSecret):
        self.k8sSecret = k8sSecret

    # Decode base64 data inside the secret and return the raw value
    def decodeB64(self, key):
        decodedData = base64.b64decode(self.k8sSecret.data[key]).decode('utf-8')
        return decodedData

    # Test if the given key in a secret is null
    def isNull(self, key):
        data = self.k8sSecret.data[key]
        if data is None:
            return True
        return False
