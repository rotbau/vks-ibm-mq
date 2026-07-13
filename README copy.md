# IBM MQ on VMware VKS

## Preparation
1. Create mq-cluster-a by deploying cluster-a/mq-cluster-a.yaml to the Supervisor (or feel free to create your own cluster)
2. Run cluster-a-infra-prep.sh
3. Deploy cluster-a-replication-svc.yaml manifest
4. Create mq-cluster-b by deploying cluster-b/mq-cluster-b.yaml to the Supervisor (or feel free to create your own cluster)
5. Run cluster-b-infra-prep.sh
6. Deploy cluster-b-replication-svc.yaml manifest

## Deploy IBM License Server

We are manually downloading the chart tar file but you can also add the helm 


echo "DISPLAY CLUSQMGR(*) CLUSTER(GLOBAL_HA_CLUSTER) QMTYPE STATUS" | kubectl exec -i vks-prod-nativeha-mq1-ibm-mq-0 -n prod-mq -c qmgr -- runmqsc QM1

kubectl exec -it vks-prod-nativeha-mq1-ibm-mq-0 -n prod-mq -c qmgr -- sh

On QM1

echo "REFRESH CLUSTER(GLOBAL_HA_CLUSTER) REPOS(YES)" | runmqsc QM1
echo "DISPLAY CHSTATUS(GLOBAL_HA_CHL_QM2) ALL" | runmqsc QM1

Manually create QM2 channel on QM1
echo "DEFINE CHANNEL(GLOBAL_HA_CHL_QM2) CHLTYPE(CLUSSDR) TRPTYPE(TCP) CONNAME('qm2-clusterb.vtechk8s.com(1414)') CLUSTER(GLOBAL_HA_CLUSTER) REPLACE" | runmqsc QM1

echo "DISPLAY CHSTATUS(GLOBAL_HA_CHL_QM2) ALL" | runmqsc QM1
grep -E "AMQ9[0-9]{3}" /mnt/mqm/data/qmgrs/QM1/errors/AMQERR01.LOG | tail -n 5
timeout 3 bash -c 'cat < /dev/tcp/qm2-clusterb.vtechk8s.com/1414' 2>&1
bash: connect: Connection refused
bash: line 1: /dev/tcp/qm2-clusterb.vtechk8s.com/1414: Connection refused

VERIFICATION COMMANDS:

echo "DISPLAY CLUSQMGR(*) CLUSTER(GLOBAL_HA_CLUSTER) QMTYPE STATUS" | kubectl exec -i vks-prod-nativeha-mq1-ibm-mq-0 -n prod-mq -- runmqsc QM1

echo "DISPLAY CLUSQMGR(*) CLUSTER(GLOBAL_HA_CLUSTER) QMTYPE STATUS" | kubectl exec -i vks-prod-nativeha-mq2-ibm-mq-0 -n prod-mq -- runmqsc QM2
