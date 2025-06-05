## :rocket: Quick installation of Kubecost on OpenShift and securing it using self-signed certificates from Let's Encrypt

Contribution made by:
[Jignesh Kumar Panchal - Brand Technical Specialist at IBM](https://www.linkedin.com/in/jigneshkpanchal)

### Pre-requisites:

  - RedHat OpenShift cluster v4.10 and above
  - S3 compatible storage (For multi-cluster env.)
    - https://www.ibm.com/docs/en/kubecost/self-hosted/2.x?topic=cluster-long-term-storage-configuration
    - MinIO - S3 compatible storage
  - ```oc``` CLI installed locally on your machine
  - ```helm``` installed locally on your machine

---

### Kubecost installation on OpenShift Cluster:

On your local terminal,

- Login to OpenShift cluster

  ```sh
  # From your OCP cluster, 'Copy login command' that will look like this
  oc login --token=xxxxx -server=https://api.xxxxx.ocp.techzone.ibm.com:6443
  ```

- Add Kubecost Helm chart repository

  ```sh
  helm repo add kubecost https://kubecost.github.io/cost-analyzer/
  helm repo update
  ```

- Install Kubecost with OpenShift specific values

  ```sh
  helm upgrade --install kubecost kubecost/cost-analyzer -n kubecost --create-namespace \
  -f https://raw.githubusercontent.com/kubecost/cost-analyzer-helm-chart/v2.5/cost-analyzer/values-openshift.yaml
  ```

- Wait for the Kubecost installation to finish (5-7m)

---

### Expose Kubecost frontend

#### Non-HTTPS

- Get the port name for the port 9090/TCP from the kubecost-cost-analyzer service

  ```sh
  oc describe svc kubecost-cost-analyzer

  # Output
    Name:               kubecost-cost-analyzer
    Namespace:          kubecost
    Labels:             app=cost-analyzer
                        app.kubernetes.io/instance=kubecost
                        app.kubernetes.io/managed-by=Helm
                        app.kubernetes.io/name=cost-analyzer
                        helm.sh/chart=cost-analyzer-2.7.0
    Annotations:        meta.helm.sh/release-name: kubecost
                        meta.helm.sh/release-namespace: kubecost
    Selector:           app.kubernetes.io/instance=kubecost,app.kubernetes.io/name=cost-analyzer,app=cost-analyzer
    Type:               ClusterIP
    IP Family Policy:   SingleStack
    IP Families:        IPv4
    IP:                 xxx.xx.xx.xxx
    IPs:                xxx.xx.xx.xxx
    Port:               tcp-model  9003/TCP
    TargetPort:         9003/TCP
    Endpoints:          xx.xxx.xx.xx:9003
    Port:               tcp-frontend  9090/TCP
    TargetPort:         9090/TCP
    Endpoints:          xx.xxx.xx.xx:9090
    Session Affinity:   None
    Events:             <none>
  ```

- Expose the port **'tcp-frontend'** of the kubecost cost analyzer service using the command line

  ```sh
  oc expose svc kubecost-cost-analyzer --port=tcp-frontend
  ```

- Get the route and open the route in browser
  ```sh
  oc get route kubecost -n kubecost -o jsonpath='{.spec.host}'
  ```

#### HTTPS using Self-signed LetsEncrypt certificate

#### Prerequisites

- Install **RedHat's** 'cert-manager' operator from OperatorHub
- Install **Community** 'cert-utils' operator from OperatorHub
- Use the **'Default'** Openshift Ingress class. Get the ingress class using:

  ```sh
  oc get ingressclass

  #Output for OCP hosted in techzone environment
  NAME                CONTROLLER                      PARAMETERS                                        AGE
  openshift-default   openshift.io/ingress-to-route   IngressController.operator.openshift.io/default   5h31m
  ```

- Get your OpenShift Cluster HostName

  ```sh
  oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}'
  ```

  ```sh
  #Output for OCP hosted in techzone environment
  apps.xxxxxxxxxxx.ocp.techzone.ibm.com
  ```

#### Self-Signed certificate

- Create ClusterIssuer (remains cluster-wide, no namespace)

  ```yaml
  apiVersion: cert-manager.io/v1
  kind: ClusterIssuer
  metadata:
    name: letsencrypt-prod
  spec:
    acme:
      server: https://acme-v02.api.letsencrypt.org/directory
      privateKeySecretRef:
        name: letsencrypt-prod
      solvers:
      - http01:
          ingress:
            class: openshift-default # default ingress class name
  ```

- Create Certificate (must be in the same namespace where kubecost is installed)

  ```yaml
  apiVersion: cert-manager.io/v1
  kind: Certificate
  metadata:
    name: kubecost-tls
    namespace: kubecost
  spec:
    secretName: kubecost-tls
    duration: 2160h # 90 days = 90 * 24 = 2160 hours
    renewBefore: 720h # 30 days = 30 * 24 = 720 hours
    commonName: kubecost.apps.xxxxxxxxxxx.ocp.techzone.ibm.com # Append kubecost to OpenShift host name
    dnsNames: 
      - kubecost.apps.xxxxxxxxxxx.ocp.techzone.ibm.com # Append kubecost to OpenShift host name
    issuerRef:
      name: letsencrypt-prod
      kind: ClusterIssuer
  ```

  - Check the state of the 'Certificate' - 'kuebcost-tls'

  ```sh
  oc get certificate kubecost-tls -o wide

  # Output - Check Status - should be - Certificate is up to date and has not expired
  NAME           READY   SECRET         ISSUER             STATUS                                          AGE
  kubecost-tls   True    kubecost-tls   letsencrypt-prod   Certificate is up to date and has not expired   3d18h
  ```

- Create OpenShift Route (must be in the same namespace where kubecost is installed)

```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: kubecost-frontend
  namespace: kubecost
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  host: kubecost.apps.xxxxxxxxxxx.ocp.techzone.ibm.com # Append kubecost to OpenShift host name
  to:
    kind: Service
    name: kubecost-analyzer # Service name
  port:
    targetPort: tcp-frontend # Port exposed on the service
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect # Redirect HTTP to HTTPS
    certificate: "" # Leave empty, cert-manager will manage this
    key: ""
    caCertificate: ""
```

- Get the new route

  ```sh
  oc get route kubecost-frontend -n kubecost -o jsonpath='{.spec.host}'

  # Output
  kubecost.apps.xxxxxxxxxxx.ocp.techzone.ibm.com
  ```

- Open the URL in a browser window
- Check the self-signed certificate details by clicking on the lock :lock: icon next to the URL in the address bar

---