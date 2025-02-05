# Install Instana agent with Dual Backend
---
Instana Agent **doesn't support K8sensor dual backend**, but, there is a temporary workaround...
**NOTE: This is not supported by IBM Instana Support**, please see the official limitations here:
https://www.ibm.com/docs/en/instana-observability/current?topic=ise-migrating-from-self-hosted-classic-edition-docker-standard-edition#limitations

On how to configure multiple backends, more details can be found in the `instana-agent` GitHub repo
https://github.com/instana/helm-charts/tree/main/instana-agent#configuring-additional-backends

---

- Install the agent as you normally do for just one backend.
- Edit `ConfigMap`for the `instana-agent` and add the section `additional-backend-2` as follows:

```
kind: ConfigMap
metadata:
  name: instana-agent
data:
  additional-backend-2: |
    host=<Instana endpoint 2>
    port=1444
    key=<AGENT_KEY_2>
    protocol=HTTP/2
```

- Edit daemonset `instana-agent`, add volume and volumeMount `additional-backend-2` as shown below:

```
kind: DaemonSet
metadata:
  name: instana-agent
spec:
  template:
    spec:
      containers:
        - env:
            ...
          volumeMounts:
            - name: additional-backend-2
              mountPath: >-
                /opt/instana/agent/etc/instana/com.instana.agent.main.sender.Backend-2.cfg
              subPath: additional-backend-2
      volumes:
        - name: additional-backend-2
          configMap:
            name: instana-agent
            defaultMode: 420
```

## Configure k8sensor for additional backend

K8sensor can only report to one backend at the moment, BUT the temporary workaround is to create an additional deployment of the `k8sensor` for each additional backend.

- Specify the additional backend in the `configMap/k8sensor` by adding a key `backend-2` with the same format as `backend`

```
kind: ConfigMap
metadata:
  name: k8sensor
data:
  backend: '<BACKEND>:443'
  backend-2: '<ADDITIONAL BACKEND>:1444'
```

- Export current k8sensor's manifest:

`oc get deployment -n instana-agent k8sensor -oyaml > k8sensor2.yaml`

- If the key for the second backend is different from the first backend then define second key in the secret `instana-agent`:

```
kind: Secret
metadata:
  name: instana-agent
data:
  downloadKey: <base64 encoded key1>
  key: <base64 encoded key1>
  key-2: <base64 encoded key2>
```

- Adjust the following parameters in `k8sensor2.yaml` as shown below ONLY, all other parameters are the same:

```
kind: Deployment
apiVersion: apps/v1
metadata:
  name: k8sensor2
  labels:
    app.kubernetes.io/instance: instana-agent2
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/instance: instana-agent2
  template:
    metadata:
      labels:
        app.kubernetes.io/instance: instana-agent2
    spec:
      containers:
        - name: instana-agent
          env:
            - name: AGENT_KEY
              valueFrom:
                secretKeyRef:
                  name: instana-agent
                  key: key
            - name: BACKEND
              valueFrom:
                configMapKeyRef:
                  name: k8sensor
                  key: backend-2
```

- If the key for the second backend is different from the first backend then change Agent Key for the second backend in `k8sensor2.yaml` as below:

```
            - name: AGENT_KEY
              valueFrom:
                secretKeyRef:
                  name: instana-agent
                  key: key-2
```

- Apply changes:

`oc apply -f k8sensor2.yaml`

# Important after all configuration
Ensure there are no errors in the `k8sensor2` pod log.
