# Scripts to help you with Instana

These are some scripts that can help you with some Instana tasks.

## Using the Instana API
### List to get Agent vs host

`agent_vs_hosts_list_using_api.sh`

Script to query agents and hosts from the Instana API to get the Instana's version from a host.

### Get Incidents and Issues by Severity

`incidents_and_issues_by_severity.sh`

Script to query incidents and issues from the Instana Events API and creates a JSON file (optional) based on Severity.

## Others
### Get the list of the Instana Agent latest changes
`get_agent_latest_changes.sh`

Script to get the latest Instana Agent changes using the last two major commits aka "Agent 1.2.X" from GITHUB.

First of all install xmlstarlet

Linux

`yum install xmlstarlet`

MacOS

`brew install xmlstarlet`

This is useful for customers that use the static Agent approach. Still you can see all major versions here:
[GitHub Agent 1.2.X commits](https://github.com/search?q=repo%3Ainstana%2Fagent-updates+%22Agent+1.%22&type=commits&s=committer-date&o=desc&p=1)

<details>
  <summary>For an example, click HERE!</summary>

```
# ./get_latest_agent_changes.sh
Latest Instana Agent commit information...
------------------------------------------
SHA: 9028b5633315af7fafcc8baf43b74f53c521cf99, Agent Version: 1.2.17, Date: 2025-02-13T14:25:24Z

Previous Instana Agent commit information...
------------------------------------------
SHA: 89f11bf00f3a54eb650120de5e67106bb49c8789, Agent Version: 1.2.16, Date: 2025-01-23T09:50:09Z

GitHub URL for reference
------------------------------------------
https://github.com/search?q=repo%3Ainstana%2Fagent-updates+%22Agent+1.%22&type=commits&s=committer-date&o=desc&p=1

All commits between version 1.2.16 and version 1.2.17...
------------------------------------------
2025-02-13T14:25:24Z | CHANGE: Agent 1.2.17 | CHANGE URL: https://github.com/instana/agent-updates/commit/9028b5633315af7fafcc8baf43b74f53c521cf99
2025-02-13T13:02:57Z | CHANGE: Updated Agent Dependencies | CHANGE URL: https://github.com/instana/agent-updates/commit/2954efe41bf15f95ed829209a3cbf97745165871
2025-02-13T10:29:50Z | CHANGE: ClickHouse Sensor 1.0.31: Fix metrics attr namespace, extract log_comment | CHANGE URL: https://github.com/instana/agent-updates/commit/743c50cf16f9efc5a4f38fc6fc195f863c76ec9c
2025-02-13T08:45:43Z | CHANGE: Crio Sensor 1.0.14: Add cri-client support | CHANGE URL: https://github.com/instana/agent-updates/commit/76301eacedbba5d53bd21d6463bb1eec159eb448
2025-02-12T06:40:34Z | CHANGE: IBM i Sensor 1.0.51: Add inquiry message without reply event | CHANGE URL: https://github.com/instana/agent-updates/commit/a1017ff7e4910995ebb97733a77f2dc377928296
2025-02-10T16:13:41Z | CHANGE: Java Trace Sensor 1.2.487: Fix Wicket, Spring-context, Spring.boot.starter.webflux, Spring-batch, Amazon SNS, Jboss.data.grid.(infinispan.hot.rod.client.legacy), JMS apache activemq , Spring starter data jpa, Couchbase, Aws.java.sdk.for.amazon.sqs, Updated JMS solace, Spring.web, Eclipse jetty, Spring Mail, Grizzly, Version upgrade of Kinesis, Vert.x web and vert.x core, Redis (Redisson), Vaadin, Spring.solace, Google.cloud.pub/sub.(client.for.java), Spring Boot Starter Undertow, Spring.boot.starter.web, Google.cloud.pub/sub.(spring.cloud.gcp), Micronaut, Spring.cloud.gateway, Vaadin, Spring rest, Jboss.data.grid.(infinispan.hot.rod.client.legacy), Akka Remote, Apache.httpclient.5 & apache.httpclient.5.fluent.api | CHANGE URL: https://github.com/instana/agent-updates/commit/cd9a7d29fa0881adb43cf896f91f207ddd3faace
2025-02-10T13:39:52Z | CHANGE: ElasticSearch 1.1.78: ES support version 8.17.1 | CHANGE URL: https://github.com/instana/agent-updates/commit/2f83a4bb2ab06a92f5826ba3d9bc485811e7a15a
2025-02-10T13:21:33Z | CHANGE: SAP HANA 1.1.19 : Support SSL Communication | CHANGE URL: https://github.com/instana/agent-updates/commit/f9825999e81e9ebe278b532765112cb3d17ef968
2025-02-10T12:59:55Z | CHANGE: Jboss Sensor 1.1.58: Support for wildfly version 35.0.0 | CHANGE URL: https://github.com/instana/agent-updates/commit/c5101f6353f61d018f77dd779241f34c43744e3e
2025-02-10T09:28:10Z | CHANGE: Host 1.1.184: AIX - Adding Volume Group and Additional Memory Metrics to AIX. | CHANGE URL: https://github.com/instana/agent-updates/commit/1c0329f5042d2928289610b87c045aecfc2c9ae5
2025-02-10T07:59:13Z | CHANGE: ActiveDirectory Sensor 1.0.3: DHCP and DNS metrics | CHANGE URL: https://github.com/instana/agent-updates/commit/6598069d91d1a918fa030c8bf01fba113fab02c1
2025-02-05T11:34:32Z | CHANGE: Prometheus Sensor 1.0.88: Improve logging | CHANGE URL: https://github.com/instana/agent-updates/commit/856f0241639bd4d092cdee123eed85707f6c7bfa
2025-02-05T10:45:43Z | CHANGE: Oracle Sensor 1.1.40: Improvements for Table space usage metrics | CHANGE URL: https://github.com/instana/agent-updates/commit/5e5ee6d488c327b563cee7a3a7751bde78d0aefd
2025-02-04T16:39:48Z | CHANGE: CLR Sensor 1.1.128: Expand WCF span with HTTP Status Code and new library supports | CHANGE URL: https://github.com/instana/agent-updates/commit/dcb4b58e8ad496075177431a158558000c1ce66c
2025-02-04T14:42:28Z | CHANGE: Prometheus Sensor 1.0.87: Improve parsing | CHANGE URL: https://github.com/instana/agent-updates/commit/0c2a1d59dd6cd7d06eb09d336bd16d2f08d7439a
2025-02-04T13:13:19Z | CHANGE: Ruby Profile Sensor 1.2.1 : Update sensor to use latest version of rbspy | CHANGE URL: https://github.com/instana/agent-updates/commit/4af32e3b0a319f039e1ddf958c1d18f82eaad787
2025-02-03T20:03:10Z | CHANGE: AWS Sensor 1.0.145: Warning message for not supported AWS Timestream region | CHANGE URL: https://github.com/instana/agent-updates/commit/5552f445f2870f7c3132bf8d2fc0071fa15f7feb
2025-02-03T11:48:21Z | CHANGE: CDC Transformer 1.0.39: Support fully qualified paths in identity expression column targets | CHANGE URL: https://github.com/instana/agent-updates/commit/f2b2bc65734767d0959f5db9578e15b80450fb96
2025-01-29T14:08:37Z | CHANGE: Java Trace Sensor 1.2.486: Grizzly, JMS apache activemq artemis, Jersey, Dropwizard, Spring-web, Vert.x-web, Apache.camel, Vaadin patch update, Micronaut, Spring Kafka and RabbitMQ, SpringWebFlux, Amazon.s3, Spring-context Redis, Spring Data redis & Mongodb | CHANGE URL: https://github.com/instana/agent-updates/commit/d4346b5a24918c240763089ce95b99ec517c5ef0
2025-01-29T10:29:28Z | CHANGE: IBM Openstack Sensor 1.0.14 : Adding multi project support for single Host | CHANGE URL: https://github.com/instana/agent-updates/commit/efc80bda218463ccbb30ce3b589cbbfedd3d2f1a
2025-01-29T09:06:52Z | CHANGE: MySQL Sensor 1.1.76: Enhancements for MySQL Versions 8.4 and 9.1 support | CHANGE URL: https://github.com/instana/agent-updates/commit/a498d87165aede81b7c89f9bf2b804d1a833ab79
2025-01-28T15:53:16Z | CHANGE: IBM i Sensor 1.0.50: Add new disk metrics | CHANGE URL: https://github.com/instana/agent-updates/commit/0a27d24a08579052564f6b5de144a62ab0e535b2
2025-01-28T15:02:27Z | CHANGE: Containerd Sensor 1.0.41: Normalized CPU usage and Memory Working Set Usage for cgroupv2 | CHANGE URL: https://github.com/instana/agent-updates/commit/b9d6d01ea2c60bbb10d255343e4336ec69a457bc
2025-01-27T11:51:28Z | CHANGE: SAP HANA Sensor 1.1.18: Display 24-hour backup info and disk usage for 1.x versions | CHANGE URL: https://github.com/instana/agent-updates/commit/736021bb653cbbe384cbe105605819dc6a443af0
2025-01-27T10:53:59Z | CHANGE: KubeCost Sensor 1.0.0: Add Kubernetes cost information | CHANGE URL: https://github.com/instana/agent-updates/commit/df12a9395d4fec7a99b91fb51b9284305bd023b1
2025-01-27T08:26:36Z | CHANGE: IBM Datapower Sensor 1.0.18 : Adding support for IBM MQ v9+ | CHANGE URL: https://github.com/instana/agent-updates/commit/3135d7212e6dfd2d4cc40558acb8353e07c00b03
2025-01-23T09:50:09Z | CHANGE: Agent 1.2.16 | CHANGE URL: https://github.com/instana/agent-updates/commit/89f11bf00f3a54eb650120de5e67106bb49c8789
```
</details>
