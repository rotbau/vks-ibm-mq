# Single Cluster IBM MQ HA Install

This repository contains a proof of concept install of IBM MQ on VMware vSphere Kubernetes Service (VKS).  This repository leverages the IBM MQ Operator Helm install (EKS version) to install and manage a mutli-cluster HA MQ Install.

Essential enterprise configurations such as monitoring which are Openshift specific, security hardening parameters, and advanced tuning profiles may be intentionally omitted for clarity. This guide represents a functional proof-of-concept; the authors are not IBM MQ product specialists, and this material is provided on an as-is basis. For production Reference Architectures, always consult official IBM MQ and VMware VKS documentation. 

This documentation and all accompanying code, scripts, and manifests are provided **"AS IS" WITHOUT WARRANTY OF ANY KIND**, either expressed or implied, including but not limited to the implied warranties of merchantability, fitness for a particular purpose, or non-infringement. The entire risk as to the quality, execution, and performance of these steps is borne entirely by you. In no event shall the authors be liable for any damages, system failures, data loss, or production outages resulting from the use of this guide. Use these materials at your own discretion.

## Preparation

This is a simplified single cluster MQ HA install.  You can leverage one of the test cluster manifests under the [infrastucture](../../infrastructure/) folder or create your own.

### Basic Cluster Requirements.
- 1 Control plan (best-effort medium) and 3 Worker Nodes (best-effort-large)
- Storage Class defined (block storage backed)
- Contour and Cert Manager installed (I'm using the addon framework in my examples)
- TLS pair and secret for Contour to use for MQ Web Console
- VKS 3.6 or 3.7*
- Kubernetes version (vKR) 1.35.5*
- DNS Entries for Replication Service FQDN and Web Console HTTP Route FQDN

* These were the versions tested but should work with most recent vKR versions.

## Create and Prepare VKS Cluster

1. Create `mq-cluster-a` by applying `infrastructure/cluster-a/01-mq-cluster-a.yaml` to the Supervisor context or using your prefered cluster creation method.  If you create your own, be sure to have Cert-manager and Contour installed.
2. Authenticate to `mq-cluster-a` and set as active context
3. Create contour gatewayclass
```
kubectl apply -f mq-install/single-cluster-ha/01-gatewayclass.yaml
```
4. Generate TLS keypair for the MQ Web Console - Customize subj and addext sections for your desired FQDN
```
# openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
#  -keyout "tls.key" \
#  -out "tls.crt" \
#  -subj "/CN=qm-console.example.com" \
#  -addext "subjectAltName=DNS:qm-console.example.com"
```
5. Edit `02-mq-console-tls-secret.yaml` and add the values of the tls.crt and tls.key
```
kubectl apply -f 02-mq-console-tls-secret.yaml
```
6. Create prod-mq and ibm-licensing namespaces
```
kubectl create ns prod-mq
kubectl create ns ibm-licensing
```

## Deploy IBM License Server and MQ Operators

1. Deploy IBM License Server (cluster scoped)
```
# Download Helm Chart
curl -L -O https://github.com/IBM/charts/raw/refs/heads/master/repo/ibm-helm/ibm-licensing-cluster-scoped-4.2.16+20250606.101044.0.tgz

# Untar Helm Chart
 tar -zxvf ibm-licensing-cluster-scoped-4.2.16+20250606.101044.0.tgz

# Install IMB MQ Operator Helm Chart
helm template ibm-licensing-edge ./ibm-licensing-cluster-scoped \
  --namespace ibm-licensing \
  --set ibmLicensing.namespace=ibm-licensing | kubectl apply -f -

**Note:** If you encounter the error "error: resource mapping not found for name: "instance" namespace: "" from "STDIN": no matches for kind "IBMLicensing" in version "operator.ibm.com/v1alpha1"
ensure CRDs are installed first" - Just rerun the same command

# Verify Operator is in running state
kubectl get po -n ibm-licensing

NAME                                      READY   STATUS    RESTARTS   AGE
ibm-licensing-operator-8456b9c7b9-2rhsj   1/1     Running   0          89s
```

2. Deploy MQ Operator Helm Chart
```
# Download Helm Chart
curl -L -O https://github.com/IBM/charts/raw/refs/heads/master/repo/ibm-helm/ibm-mq-operator-4.0.0.tgz

# Untar Helm Chart
tar -zxvf ibm-mq-operator-4.0.0.tgz

# Install IMB MQ Operator Helm Chart
helm install --set name=ibm-mq-operator ibm-mq-operator ./ibm-mq-operator --namespace prod-mq

# Verify Operator is in running state
kubectl get po -n prod-mq

NAME                              READY   STATUS    RESTARTS       AGE
ibm-mq-operator-cd68b77bf-fpjpz   1/1     Running   3 (124m ago)   18h
```
## Configure IBM License Instance and MQ Server
1. Deploy IBM License Instance
```
kubectl apply -f 03-ibm-license-instance.yaml

# Verify License instance is running (Note: this may take a few minutes to appear and go running)

kubectl get po -n ibm-licensing

NAME                                              READY   STATUS    RESTARTS   AGE
ibm-licensing-operator-8456b9c7b9-2rhsj           1/1     Running   0          11m
ibm-licensing-service-instance-68f6559cd6-c642c   1/1     Running   0          2m16s
```
2. Deploy MQ Web Console Configmap
```
kubectl apply -f mq-install/single-cluster-ha/03-mq-web-console-cm.yaml
```
3. Deploy IBM MQ HA Queue Manifest
```
kubectl apply -f mq-install/single-cluster-ha/04-qm-single-cluster-ha.yaml

# Expected outcome is 3 pods with a single pod in 1/1 state
kubectl get po -n prod-mq

vks-prod-nativeha-mq-ibm-mq-0     1/1     Running   0              18h
vks-prod-nativeha-mq-ibm-mq-1     0/1     Running   0              18h
vks-prod-nativeha-mq-ibm-mq-2     0/1     Running   0              18h
```
4. Deploy Web Console Routing Manifest.  Adjust the Hostname(s) section in the Gateway and HTTPROUTE sections to your preferred FQDN for the Web Console
```
kubectl apply -f mq-install/single-cluster-ha/05-mq-cluster-routing.yaml
```
5. Determine IP of Envoy Proxy Service (or whatever L4/L7 solution you are using)
```
kubectl get svc -n tanzu-system-ingress

NAME      TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)                      AGE
contour   ClusterIP      10.98.251.84    <none>           8001/TCP                     19h
envoy     LoadBalancer   10.108.207.55   192.168.150.10   80:31162/TCP,443:32660/TCP   19h
```
6. Create DNS entry for MQ Web Console 
7. Test MQ Web Console using https://qm-console.example.com - you do not need to use 9443 because our qm-console-custom-svc handles rewriting the port fromm 443 -> 9443
8. Validate MQ HA Install is functinal (adjust pod to active 1/1 MQ instance)
```
echo "DISPLAY QMSTATUS TYPE(NATIVEHA)" | kubectl exec -i vks-prod-nativeha-mq-ibm-mq-0 -n prod-mq -- runmqsc haqueuemgr
```
Expected Output:
```
5724-H72 (C) Copyright IBM Corp. 1994, 2026.
Starting MQSC for queue manager haqueuemgr.


     1 : DISPLAY QMSTATUS TYPE(NATIVEHA)
AMQ8705I: Display Queue Manager Status Details.
   INSTANCE(vks-prod-nativeha-mq-ibm-mq-0)
   TYPE(NATIVEHA)                          NHATYPE(INSTANCE)
   ROLE(ACTIVE)                            HAINITDA(2026-07-15)
   HAINITL(<0:0:9:13456>)                  HAINITTI(22.27.55)
   HASTATUS(NORMAL)
   REPLADDR(vks-prod-nativeha-mq-ibm-mq-replica-0(9414))
AMQ8705I: Display Queue Manager Status Details.
   INSTANCE(vks-prod-nativeha-mq-ibm-mq-1)
   TYPE(NATIVEHA)                          NHATYPE(INSTANCE)
   ROLE(REPLICA)                           ACKLSN(<0:0:19:17407>)
   BACKLOG(0)                              CONNACTV(YES)
   HASTATUS(NORMAL)                        INSYNC(YES)
   REPLADDR(vks-prod-nativeha-mq-ibm-mq-replica-1(9414))
   SYNCTIME(2026-07-16T17:52:03.622800Z)
AMQ8705I: Display Queue Manager Status Details.
   INSTANCE(vks-prod-nativeha-mq-ibm-mq-2)
   TYPE(NATIVEHA)                          NHATYPE(INSTANCE)
   ROLE(REPLICA)                           ACKLSN(<0:0:19:17407>)
   BACKLOG(0)                              CONNACTV(YES)
   HASTATUS(NORMAL)                        INSYNC(YES)
   REPLADDR(vks-prod-nativeha-mq-ibm-mq-replica-2(9414))
   SYNCTIME(2026-07-16T17:52:03.622800Z)
One MQSC command read.
No commands have a syntax error.
All valid MQSC commands were processed.
```