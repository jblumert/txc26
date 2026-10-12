#!/bin/sh

for i in demo1; do
	echo "removing Deploy and STS from $i..."
	oc delete -n $i deploy,sts --all
	echo "removing VolumeReplications from $i..."
	oc delete vr -n $i --all
	echo "removing ReplicationSources from $i..."
	oc delete replicationsources -n $i --all
done
for i in demo1; do
	echo "removing PVCs from $i..."
	oc delete pvc -n $i --all
done
