# Instana Agent with Dual Backend in Kubernetes/OpenShift
Customers have been successful to connect the agent to dual backend for Classic (Docker) and Standard which is needed for migration purposes and that's the only recommended way.
---

On how to install and configure the agent for multiple backends, more details can be found in the `instana-agent` [GitHub repo](https://github.com/instana/helm-charts/tree/main/instana-agent#configuring-additional-backends)

## Configure the Instana Agent for additional backend
### For YAML installations
First, install the agent as per the instructions in the documentation, or maybe you have the agent installed already.

Please note that this is NOT recommended, you should use HELM or Operator but you can add the new backend as follows, if you have issues, please contact [IBM Support](https://www.ibm.com/mysupport/s/?language=en_US):

- Edit `ConfigMap`for the `instana-agent` and add the section `additional-backend`:

```
kind: ConfigMap
metadata:
  name: instana-agent
data:
  additional-backend: |
    host=myinstana.instana.io # Change it to your Instana backend.
    port=443 # This is default, you can change it to any other port, example port 1443
    key=AGENT_KEY_2 # Change it to your Agent key.
    protocol=HTTP/2
```

<details>
  <summary>For an example, click HERE!</summary>

![image](https://github.com/user-attachments/assets/8b51d070-2db6-4166-8a27-1653f064dbd5)

</details>

- Edit daemonset `instana-agent`, add volume and volumeMount `additional-backend` as shown below:

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
            - name: additional-backend
              mountPath: >-
                /opt/instana/agent/etc/instana/com.instana.agent.main.sender.Backend-2.cfg
              subPath: additional-backend
      volumes:
        - name: additional-backend
          configMap:
            name: instana-agent
            defaultMode: 420
```
<details>
  <summary>For an example, click HERE!</summary>

![image](https://github.com/user-attachments/assets/e4c0abb1-f2bb-4247-b4f6-fb1c0cfd3c57)

</details>

If using OpenShift, go to any `instana-agent` Pod, go into the terminal and see if you have a `/opt/instana/agent/etc/instana/com.instana.agent.main.sender.Backend-2.cfg` file:

![image](https://github.com/user-attachments/assets/fff4e6b7-5f78-41cf-90d8-9f0d1dc7c5d1)

## For HELM installations
You can enable additional backends when you're installing the Instana Agent, example:

```
helm install instana-agent \
   --repo https://agents.instana.io/helm \
   --create-namespace \
   --namespace instana-agent \
   --set openshift=true \
   --set agent.mode=INFRASTRUCTURE \
   --set agent.key=AGENT_KEY \
   --set agent.downloadKey=DOWNLOAD_KEY \
   --set agent.endpointHost=my-instana.instana.io \
   --set agent.endpointPort=443 \
   --set 'agent.additionalBackends[0].endpointHost=my-instana2.instana.io' \
   --set 'agent.additionalBackends[0].endpointPort=443' \
   --set 'agent.additionalBackends[0].key=AGENT_KEY2' \
   --set cluster.name='mycluster' \
   --set zone.name='DarkZone' \
   instana-agent
```

In case you installed the Instana Agent first and want to update the config, you can do some upgrade:

```
helm pull --repo https://agents.instana.io/helm --untar instana-agent && oc apply -f instana-agent/crds; helm upgrade --namespace instana-agent instana-agent \
--repo https://agents.instana.io/helm instana-agent \
--set 'agent.additionalBackends[0].endpointHost=my-instana2.instana.io' \
--set 'agent.additionalBackends[0].endpointPort=443' \
--set 'agent.additionalBackends[0].key=AGENT_KEY2' \
--reuse-values
```

Confirm the configuration is there:

```
helm get values instana-agent -n instana-agent
USER-SUPPLIED VALUES:
    agent:
      additionalBackends:
      - endpointHost: my-instana2.instana.io
        endpointPort: 443
        key: AGENT_KEY2
      downloadKey: DOWNLOAD_KEY
      endpointHost: my-instana.instana.io
      endpointPort: 443
      key: AGENT_KEY
      mode: INFRASTRUCTURE
    cluster:
      name: instana-cluster
    openshift: true
    zone:
      name: DarkZone
```

## Configure k8sensor in the Instana Agent for additional backend
**IMPORTANT:** Instana Agent **doesn't support K8sensor dual backend officially**, but, there is a temporary workaround...

**NOTE: This is not supported by IBM Instana Support**, you can't ask support for this, please see the official limitations here:

https://www.ibm.com/docs/en/instana-observability/current?topic=ise-migrating-from-self-hosted-classic-edition-docker-standard-edition#limitations

**K8sensor** can only report to one backend at the moment, BUT the temporary workaround is to create an additional deployment of the `k8sensor` for each additional backend.

- Specify the additional backend in the `configMap/k8sensor` by adding a key `backend-2` with the same format as `backend`

```
kind: ConfigMap
metadata:
  name: k8sensor
data:
  backend: '<BACKEND>:443'
  backend-2: '<ADDITIONAL BACKEND>:443'
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

**Important after all configuration**

Ensure there are no errors in the `k8sensor2` pod log.
