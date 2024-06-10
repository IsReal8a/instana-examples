# Instana Agent DaemonSet for two backends

You can prepare the YAML file in two ways:
- Running HELM, get some YAML files and mix them.
- Just copy the `instana_agent_2backend_example.yml` and edit it with your details.

## Running HELM and mix

The procedure needs a few steps, first you need to run the following:

```
helm template instana-agent \
   --repo https://agents.instana.io/helm \
   --namespace instana-agent \
   --create-namespace \
   --set agent.key=AGENT_KEY \
   --set agent.downloadKey=DOWNLOAD_KEY \
   --set agent.endpointHost=INSTANA_ENDPOINT \
   --set agent.endpointPort=443 \
   --set cluster.name='CLUSTER_NAME' \
   --set "agent.additionalBackends[0].endpointHost=ADDITIONAL_ENDPOINT" \
   --set "agent.additionalBackends[0].key=INSTANA_THAT_ADDITIONAL_ENDPOINT_KEY" \
   --set "agent.additionalBackends[0].endpointPort=443" \
   instana-agent --output-dir agent-helm-chart
   ```

- Go to `agent-helm-chart/instana-agent/templates/` 
- Create a new file like `instana_agent_2backend.yml`
- In the Instana UI go to "Deploy Agents"->"Kubernetes/OpenShift YAML", write the Clustername, copy the YAML output and paste that in the new file we created above.
- From the files created by the HELM command, the `agent-configmap.yml`, copy the code at the end additional-backend-2, something like below to the `instana_agent_2backend.yml` in the configMap section, inside configuration.yaml:
```  additional-backend-2: |
    host=ingress-orange-saas.instana.io
    port=443
    key=AGENT_KEY
    protocol=HTTP/2
```

From agent-daemonset.yaml you need to copy the section:
```
            - name: additional-backend-2
              subPath: additional-backend-2
              mountPath: /opt/instana/agent/etc/instana/com.instana.agent.main.sender.Backend-2.cfg
```

To `spec->template->spec->containers->volumeMounts` under configuration.yaml in the `instana_agent_2backend.yml` file

And this section from the same file agent-daemonset.yaml
```
        - name: additional-backend-2
          configMap:
            name: instana-agent
```
To `spec->template->spec->volumes` add the additional backend info under configuration.

And that's it, this option is for people who wants to know how this is done.

## Using the YAML example file

Just use the `instana_agent_2backend_example.yml` and modify it per your needs.

Hope this helps!