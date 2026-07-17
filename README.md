# IBM MQ on VMware VKS

This repository contains a proof of concept install of IBM MQ on VMware vSphere Kubernetes Service (VKS).  This repository leverages the IBM MQ Operator Helm install (EKS version) to install and manage a mutli-cluster HA MQ Install.

Essential enterprise configurations such as monitoring which are Openshift specific, security hardening parameters, and advanced tuning profiles may be intentionally omitted for clarity. This guide represents a functional proof-of-concept; the authors are not IBM MQ product specialists, and this material is provided on an as-is basis. For production Reference Architectures, always consult official IBM MQ and VMware VKS documentation. 

This documentation and all accompanying code, scripts, and manifests are provided **"AS IS" WITHOUT WARRANTY OF ANY KIND**, either expressed or implied, including but not limited to the implied warranties of merchantability, fitness for a particular purpose, or non-infringement. The entire risk as to the quality, execution, and performance of these steps is borne entirely by you. In no event shall the authors be liable for any damages, system failures, data loss, or production outages resulting from the use of this guide. Use these materials at your own discretion.

## Repo Layout
```
├── infrastructure                            <-- Example Manifiest for VKS CLusters and Post Cluster Config
│   ├── cluster-a
│   │   ├── 01-mq-cluster-a.yaml
│   │   └── 02-cluster-a-infraprep.sh
│   └── cluster-b
│       ├── 01-mq-cluster-b.yaml
│       └── 02-cluster-b-infraprep.sh
├── mq-install                                  <- MQ Install Components
│   ├── qm1-cluster-a                           <- Cluster A Queue Manager 1 files
│   │   ├── 01-cluster-a-replication-svc.yaml
│   │   ├── 02-qm1-cluster-a-configmap.yaml
│   │   ├── 03-qm1-cluster-a.yaml
│   │   └── 04-cluster-a-routing.yaml
│   ├── qm2-cluster-b                           <- Cluster B Queue Manager 2 files
│   │   ├── 01-cluster-b-replication-svc.yaml
│   │   ├── 02-qm2-cluster-b-configmap.yaml
│   │   ├── 03-qm2-cluster-b.yaml
│   │   └── 04-cluster-b-routing.yaml
│   ├── shared                                  <- Common Shared files for both clusters
│   │   ├── 01-ibm-license-instance.yaml
│   │   └── 02-mq-web-console-cm.yaml
│   └── single-cluster-ha                       <- Simplified Single Cluster HA MQ Install
│       ├── 01-gatewayclass.yaml
│       ├── 02-mq-console-tls-secret.yaml
│       ├── 03-mq-web-console-cm.yaml
│       ├── 04-qm-single-cluster-ha.yaml
│       ├── 05-mq-cluster-routing.yaml
│       └── README.md                           <- Single Cluster HA Specific Readme
└── README.md                                   <- This document
```





### Basic Cluster Requirements.
- 1 Control plan (best-effort medium) and 3 Worker Nodes (best-effort-large)
- Storage Class defined (block storage backed, )
- Contour and Cert Manager installed (I'm using the addon framework in my examples)
- TLS pair and secret for Contour to use for MQ Web Console
- VKS 3.6 or 3.7*
- Kubernetes version (vKR) 1.35.5*
- DNS Entries for Replication Service FQDN and Web Console HTTP Route FQDN

* These were the versions tested but should work with most recent vKR versions.

## Single Cluster MQ HA Cluster
The following guide covers a more complex multi-cluster IBM MQ install.  If you prefer to deploy a single cluster HA MQ instance, please jump to the [Single Cluster HA section](mq-install/single-cluster-ha/).

## Multi-Cluster MQ HA Clusters
Continue Below for the multi-cluster MQ HA Guide

### VKS Cluster Preparation
You can use your own process to deploy clusters for MQ testing, however for convience I've provided a sample manifest for mq-cluster-a and mq-cluster-b.  I've also included a helper script that creates a key pair and secret for Contour to use when accessing the MQ Console.  As long as the components in the Basic Cluster Requirements section is met you can use any method to deploy the clusters.

### Deploy Test Clusters
1. Create `mq-cluster-a` by applying `infrastructure/cluster-a/01-mq-cluster-a.yaml` to the Supervisor context
2. Authenticate to `mq-cluster-a` and set as active context
3. Run `infrastructure/cluster-a/02-cluster-a-infraprep.sh` which will configure the following:
- creates prod-mq namespace
- creates ibm-licensing namespace
- generate self-signed cert/key pair for mq-console-secret
- create mq-console-secret
- create Contour gateway class
4. Create `mq-cluster-b` by applying `infrastructure/cluster-b/01-mq-cluster-b.yaml` to the Supervisor context
5. Authenticate to `mq-cluster-b` and set as active context
6. Run `mq-cluster-b` by running `infrastructure/cluster-b/02-cluster-b-infraprep.sh`

## Deploy IBM License Operator and License Instance

### Download and Untar License Operator
1. Download IBM Cluster Scoped License Server (we are manually downloading by you could also add the IBM Helm Repository) 
```
curl -L -O https://github.com/IBM/charts/raw/refs/heads/master/repo/ibm-helm/ibm-licensing-cluster-scoped-4.2.16+20250606.101044.0.tgz
```
2. Untar IBM Cluster Scoped License Server file
```
 tar -zxvf ibm-licensing-cluster-scoped-4.2.16+20250606.101044.0.tgz
```
### Cluster A
1. Install on cluster-A (mq-cluster-a context)
```
helm template ibm-licensing-edge ./ibm-licensing-cluster-scoped \
  --namespace ibm-licensing \
  --set ibmLicensing.namespace=ibm-licensing | kubectl apply -f -
```
**Note**: If you encounter the error "error: resource mapping not found for name: "instance" namespace: "" from "STDIN": no matches for kind "IBMLicensing" in version "operator.ibm.com/v1alpha1"
ensure CRDs are installed first" - Just rerun the same command
2. Verify License Server is Running
```
kubectl get po -n ibm-licensing

NAME                                      READY   STATUS    RESTARTS   AGE
ibm-licensing-operator-8456b9c7b9-2rhsj   1/1     Running   0          89s
```
3. Configure License Instance on cluster-a (mq-cluster-a)
```
kubectl apply -f mq-install/shared/01-ibm-license-instance.yaml
```
4. Verify License Instance is Configured and Running (Note this make take several minutes to appear)
```
kubectl get po -n ibm-licensing

NAME                                              READY   STATUS    RESTARTS   AGE
ibm-licensing-operator-8456b9c7b9-2rhsj           1/1     Running   0          11m
ibm-licensing-service-instance-68f6559cd6-c642c   1/1     Running   0          2m16s
```
### Cluster B
1. Repeat Steps 1-4 on cluster-b (mq-cluster-b)

## Deploy IBM MQ Operator

1. Download IBM MQ Operator (we are manually downloading by you could also add the IBM Helm Repository) 
```
curl -L -O https://github.com/IBM/charts/raw/refs/heads/master/repo/ibm-helm/ibm-mq-operator-4.0.0.tgz
```
2. Untar IBM MQ Operator file
```
tar -zxvf ibm-mq-operator-4.0.0.tgz
```
### Cluster A
1. Install MQ Operator on Cluster A (mq-cluster-a)
```
helm install --set name=ibm-mq-operator ibm-mq-operator ./ibm-mq-operator --namespace prod-mq
```
2. Verify Operator is running
```
kubectl get po -n prod-mq

NAME                              READY   STATUS    RESTARTS   AGE
ibm-mq-operator-cd68b77bf-knh9g   1/1     Running   0          39s
```
### Cluster B
1. Repeat steps 1-2 on Cluster B (mq-cluster-b) 


## Configure Shared Uniform Cluster Topology

**NOTE:** This Configuration does not contain the MQ Cross Cluster Replication (CRR) component.  Message data will not be replicated across clusters A and B, only within the 3 replica pods within the cluster. This guide is intented to prove out installation, basic configuration and communication of IBM MQ Operator and MQ global HA clusters.  It does not configure the cross-cluster component.  This configuration is not suitable or intented for production.

### Replication Service
We are configuring a L4 Load Balance to provide intercluster communication.  This service uses the native IBM MQ selector to find the active MQ Queue Manager.

**Cluster A**
1. Change context to cluster A (mq-cluster-a)
2. Apply replication service manifest
```
kubectl apply -f mq-install/qm1-cluster-a/01-cluster-a-replication-svc.yaml
```
3. Validate service and record service IP
```
kubectl get svc -n prod-mq

NAME                          TYPE           CLUSTER-IP       EXTERNAL-IP      PORT(S)          AGE
mq-replication-loadbalancer   LoadBalancer   10.111.248.124   192.168.150.13   1414:32565/TCP   7s
```
**Cluster B**
1. Change context to cluster B (mq-cluster-b)
2. Apply replication service manifest
```
kubectl apply -f mq-install/qm2-cluster-b/01-cluster-b-replication-svc.yaml
```
3. Validate service and record service IP
```
kubectl get svc -n prod-mq

NAME                          TYPE           CLUSTER-IP       EXTERNAL-IP     PORT(S)          AGE
mq-replication-loadbalancer   LoadBalancer   10.104.219.246   192.168.151.3   1414:30977/TCP   6s
```
### Prepare Cluster HA Configuration and Replication DNS
We will need to modify the `qm1-cluster-a-configmap.yaml` and `qm2-cluster-b-configmap.yaml` files to reflect our desired FQDN for the replication service created above.  We then need to create DNS entries for the FQDNs to the corresponding replication service IPs.

**Cluster A**
1. Modify `mq-install/qm1-cluster-a/02-qm1-cluster-a-configmap.yaml`
2. Adjust the FQDN to the desired value for the Following Sections:
```
Autocluster.ini Section:
Repository1Conname - Replace with FQDN of Cluster A Replication Service
Repository2Conname - Replace with FQDN of Cluster B Replication Service
Uniform.mqsc Section:
DEFINE CHANNEL(GLOBAL_HA_CHL_QM1) - Replace with FQDN of Cluster A Replication Service
DEFINE CHANNEL(GLOBAL_HA_CHL_QM2) - Replace with FQDN of Cluster B Replication Service
```
3. Create DNS entry for the FQDN entered for `Repository1Conname` pointing to the IP for the Cluster A mq-replication-loadbalancer service.

**Cluster B**
1. Modify `mq-install/qm2-cluster-b/02-qm2-cluster-b-configmap.yaml`
2. Adjust the FQDN to the desired value for the Following Sections:
```
Autocluster.ini Section:
Repository1Conname - Replace with FQDN of Cluster A Replication Service
Repository2Conname - Replace with FQDN of Cluster B Replication Service
Uniform.mqsc Section:
DEFINE CHANNEL(GLOBAL_HA_CHL_QM2) - Replace with FQDN of Cluster B Replication Service
DEFINE CHANNEL(GLOBAL_HA_CHL_QM1) - Replace with FQDN of Cluster A Replication Service
```
3. Create DNS entry for the FQDN entered for `Repository2Conname` pointing to the IP for the Cluster B mq-replication-loadbalancer service.

### Apply Configmap Manifests

**Cluster A**
1. Set context to Cluster A (mq-cluster-a)
2. Apply Configmap
```
 kubectl apply -f mq-install/qm1-cluster-a/02-qm1-cluster-a-configmap.yaml
```

**Cluster B***
1. Set Context to Cluster B (mq-cluster-b)
2. Apply Configmap
```
 kubectl apply -f mq-install/qm2-cluster-b/02-qm2-cluster-b-configmap.yaml
```

## QueueManager Workload Deployment
Deploy the specific QueueManager engines. This creates the queue manager objects on each cluster using the qm1 and qm2 configmaps to establish the Global MQ install.   We are also deploying a custom MQ Web Console configmap so we can log in and validate the Queue operations.  **Note**: The webconfig is insecure and should only be used for testing purposes.  

### VKS Specific Configurations
- Adjust Security context fsGroup:1001 to allow queues to read PVC
- Disable route and metrics as these are OpenShift specific items

### Cluster A
1. Set context to Cluster A
2. Deploy MQ Web Console Configmap
```
kubectl apply -f mq-install/shared/02-mq-web-console-cm.yaml
```
3. Modify the mq-install/qm1-cluster-a/03-qm1-cluster-a.yaml file with your license
4. Deploy QueueManager
```
kubectl apply -f mq-install/qm1-cluster-a/03-qm1-cluster-a.yaml
```
5. Validate Queuemanager Status.  Normal status should show 1 QueueManager in 1/1 Status and 2 in 0/1
```
kubectl get po -n prod-mq

NAME                              READY   STATUS    RESTARTS      AGE
ibm-mq-operator-cd68b77bf-knh9g   1/1     Running   1 (58m ago)   83m
vks-prod-nativeha-mq1-ibm-mq-0    1/1     Running   0             68s
vks-prod-nativeha-mq1-ibm-mq-1    0/1     Running   0             68s
vks-prod-nativeha-mq1-ibm-mq-2    0/1     Running   0             68s
```

### Cluster B
1. Set context to Cluster b
2. Deploy MQ Web Console Configmap
```
kubectl apply -f mq-install/shared/02-mq-web-console-cm.yaml
```
3. Modify the mq-install/qm2-cluster-b/03-qm2-cluster-b.yaml file with your license
4. Deploy QueueManager
```
kubectl apply -f mq-install/qm2-cluster-b/03-qm2-cluster-b.yaml
```
5. Validate Queuemanager Status.  Normal status should show 1 QueueManager in 1/1 Status and 2 in 0/1
```
kubectl get po -n prod-mq

NAME                              READY   STATUS    RESTARTS      AGE
ibm-mq-operator-cd68b77bf-8k6gx   1/1     Running   1 (63s ago)   87m
vks-prod-nativeha-mq2-ibm-mq-0    1/1     Running   0             3m53s
vks-prod-nativeha-mq2-ibm-mq-1    0/1     Running   0             3m53s
vks-prod-nativeha-mq2-ibm-mq-2    0/1     Running   0             3m53s
```

### Multi-Cluster Channel Configuration Check
**Note:** The command must run against the active queuemanager pod.   In the output from kubectl get pods -n prod-mq; this is the vks-prod-nativeha-mq1-ibm-mq-0 which is marked Ready 1/1.  You may need to adjust the command depending on your active pod.

**Cluster A**
```
echo "DISPLAY CLUSQMGR(*) CLUSTER(GLOBAL_HA_CLUSTER) QMTYPE STATUS" | kubectl exec -i vks-prod-nativeha-mq1-ibm-mq-0 -n prod-mq -- runmqsc QM1
```
Expected Output
```
5724-H72 (C) Copyright IBM Corp. 1994, 2026.
Starting MQSC for queue manager QM1.


     1 : DISPLAY CLUSQMGR(*) CLUSTER(GLOBAL_HA_CLUSTER) QMTYPE STATUS
AMQ8441I: Display Cluster Queue Manager details.
   CLUSQMGR(QM1)                           CHANNEL(GLOBAL_HA_CHL_QM1)
   CLUSTER(GLOBAL_HA_CLUSTER)              QMTYPE(REPOS)
   STATUS(RUNNING)
AMQ8441I: Display Cluster Queue Manager details.
   CLUSQMGR(QM2)                           CHANNEL(GLOBAL_HA_CHL_QM2)
   CLUSTER(GLOBAL_HA_CLUSTER)              QMTYPE(REPOS)
   STATUS(RUNNING)
One MQSC command read.
No commands have a syntax error.
All valid MQSC commands were processed.
```

**Cluster B**
```
echo "DISPLAY CLUSQMGR(*) CLUSTER(GLOBAL_HA_CLUSTER) QMTYPE STATUS" | kubectl exec -i vks-prod-nativeha-mq2-ibm-mq-0 -n prod-mq -- runmqsc QM2
```
Expected Output
```
5724-H72 (C) Copyright IBM Corp. 1994, 2026.
Starting MQSC for queue manager QM2.


     1 : DISPLAY CLUSQMGR(*) CLUSTER(GLOBAL_HA_CLUSTER) QMTYPE STATUS
AMQ8441I: Display Cluster Queue Manager details.
   CLUSQMGR(QM1)                           CHANNEL(GLOBAL_HA_CHL_QM1)
   CLUSTER(GLOBAL_HA_CLUSTER)              QMTYPE(REPOS)
   STATUS(RUNNING)
AMQ8441I: Display Cluster Queue Manager details.
   CLUSQMGR(QM2)                           CHANNEL(GLOBAL_HA_CHL_QM2)
   CLUSTER(GLOBAL_HA_CLUSTER)              QMTYPE(REPOS)
   STATUS(RUNNING)
One MQSC command read.
No commands have a syntax error.
All valid MQSC commands were processed.
```

## MQ Web Console Routing

The final step is to expose the MQ Web Console on both Cluster A and Cluster B.  In this example we are using Contour and Gateway API to expose the service.  We also use a custom front end service to bypass the constraint of the VKS Contour package to only listen on ports 80 and 443.

### Cluster A Routing
1. Set context to Cluster A
2. Modify mq-install/qm1-cluster-a/04-cluster-a-routing.yaml Hostname(s) section in  the Gateway and HTTPROUTE sections to your preferred FQDN for the Web Console.
3. Apply cluster A routing config which creates the custom service and the gateway and httproute objects.
```
 kubectl apply -f mq-install/qm1-cluster-a/04-cluster-a-routing.yaml 
```
4. Verify objects are created as expected httproute, qm1-console-custom-svc
```
kubectl get svc,httproute -n prod-mq

 NAME                                             TYPE           CLUSTER-IP       EXTERNAL-IP      PORT(S)             AGE
service/mq-replication-loadbalancer              LoadBalancer   10.111.248.124   192.168.150.13   1414:32565/TCP      170m
service/qm1-console-custom-svc                   ClusterIP      10.106.98.106    <none>           9443/TCP            16s
service/vks-prod-nativeha-mq1-ibm-mq             ClusterIP      10.105.67.15     <none>           9443/TCP,1414/TCP   96m
service/vks-prod-nativeha-mq1-ibm-mq-metrics     ClusterIP      10.103.71.155    <none>           9157/TCP            96m
service/vks-prod-nativeha-mq1-ibm-mq-replica-0   ClusterIP      10.102.205.80    <none>           9414/TCP            96m
service/vks-prod-nativeha-mq1-ibm-mq-replica-1   ClusterIP      10.103.43.123    <none>           9414/TCP            96m
service/vks-prod-nativeha-mq1-ibm-mq-replica-2   ClusterIP      10.102.216.46    <none>           9414/TCP            96m

NAME                                                   HOSTNAMES                     AGE
httproute.gateway.networking.k8s.io/mq-console-route   ["qm1-console.example.com"]   16s
```
```
kubectl get gateway -n tanzu-system-ingress

NAME      CLASS     ADDRESS          PROGRAMMED   AGE
contour   contour   192.168.150.10   True         107s
```
5. Create a DNS record for you MQ Web Console FQDN pointing to the IP of the Gateway Object

### Cluster B Routing
1. Set context to Cluster B
2. Modify mq-install/qm2-cluster-b/04-cluster-b-routing.yaml Hostname(s) section in  the Gateway and HTTPROUTE sections to your preferred FQDN for the Web Console.
3. Apply cluster A routing config which creates the custom service and the gateway and httproute objects.
```
 kubectl apply -f mq-install/qm1-cluster-a/04-cluster-a-routing.yaml 
```
4. Verify objects are created as expected httproute, qm2-console-custom-svc
```
kubectl get svc,httproute -n prod-mq

NAME                                             TYPE           CLUSTER-IP       EXTERNAL-IP     PORT(S)             AGE
service/mq-replication-loadbalancer              LoadBalancer   10.104.219.246   192.168.151.3   1414:30977/TCP      174m
service/qm2-console-custom-svc                   ClusterIP      10.107.12.120    <none>          9443/TCP            19s
service/vks-prod-nativeha-mq2-ibm-mq             ClusterIP      10.111.234.166   <none>          9443/TCP,1414/TCP   78m
service/vks-prod-nativeha-mq2-ibm-mq-metrics     ClusterIP      10.104.194.104   <none>          9157/TCP            78m
service/vks-prod-nativeha-mq2-ibm-mq-replica-0   ClusterIP      10.101.232.18    <none>          9414/TCP            78m
service/vks-prod-nativeha-mq2-ibm-mq-replica-1   ClusterIP      10.104.120.186   <none>          9414/TCP            78m
service/vks-prod-nativeha-mq2-ibm-mq-replica-2   ClusterIP      10.96.118.129    <none>          9414/TCP            78m

NAME                                                   HOSTNAMES                     AGE
httproute.gateway.networking.k8s.io/mq-console-route   ["qm2-console.example.com"]   19s
```
```
kubectl get gateway -n tanzu-system-ingress

NAME      CLASS     ADDRESS         PROGRAMMED   AGE
contour   contour   192.168.151.2   True         56s
```
5. Create a DNS record for you MQ Web Console FQDN pointing to the IP of the Gateway Object

### MQ Web Console Testing
1. Open browser to https://qm1-console.example.com and https://qm2-console.example.com - you do not need to specify port 9443 as our custom service is re-writing this
2. Log in with admin / Passw0rd!
