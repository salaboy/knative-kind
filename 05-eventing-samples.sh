#!/usr/bin/env bash

set -eo pipefail
set -u

NAMESPACE=${NAMESPACE:-default}
BROKER_NAME=${BROKER_NAME:-example-broker}



kubectl -n $NAMESPACE apply -f - << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-display
spec:
  replicas: 1
  selector:
    matchLabels: &labels
      app: hello-display
  template:
    metadata:
      labels: *labels
    spec:
      containers:
        - name: event-display
          image: gcr.io/knative-releases/knative.dev/eventing-contrib/cmd/event_display

---

kind: Service
apiVersion: v1
metadata:
  name: hello-display
spec:
  selector:
    app: hello-display
  ports:
  - protocol: TCP
    port: 80
    targetPort: 8080
EOF

kubectl  -n $NAMESPACE wait pod --timeout=-1s  -l app=hello-display --for=condition=Ready > /dev/null

kubectl -n $NAMESPACE apply -f - << EOF
apiVersion: eventing.knative.dev/v1
kind: Trigger
metadata:
  name: hello-display
spec:
  broker: $BROKER_NAME
  filter:
    attributes:
      type: greeting
  subscriber:
    ref:
      apiVersion: v1
      kind: Service
      name: hello-display
EOF

kubectl -n $NAMESPACE apply -f - << EOF
apiVersion: v1
kind: Pod
metadata:
  labels:
    run: curl
  name: curl
spec:
  containers:
    # This could be any image that we can SSH into and has curl.
  - image: radial/busyboxplus:curl
    imagePullPolicy: IfNotPresent
    name: curl
    tty: true
EOF
kubectl wait -n $NAMESPACE pod curl --timeout=-1s --for=condition=Ready > /dev/null

MSG=""
echo 'Sending Cloud Event to event broker'
until [[ $MSG == *"Hello Knative"* ]]; do
  kubectl -n $NAMESPACE exec curl -- curl -s -v  "http://broker-ingress.knative-eventing.svc.cluster.local/$NAMESPACE/$BROKER_NAME" \
  -X POST \
  -H "Ce-Id: say-hello" \
  -H "Ce-Specversion: 1.0" \
  -H "Ce-Type: greeting" \
  -H "Ce-Source: not-sendoff" \
  -H "Content-Type: application/json" \
  -d '{"msg":"Hello Knative!"}' > /dev/null
  sleep 5
  MSG=$(kubectl -n $NAMESPACE logs -l app=hello-display --tail=100 | grep msg || true)
done
echo "Cloud Event Delivered $MSG" | head -1

