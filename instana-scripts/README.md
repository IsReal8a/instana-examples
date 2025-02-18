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
### Get the list of the Instana Agent latest changes from last two commits
`get_agent_latest_changes.sh`

Script to get the latest Instana Agent changes using the last two major commits in the agent aka "Agent 1.2.X" from GITHUB.

First of all install xmlstarlet

Linux

`yum install xmlstarlet`

MacOS

`brew install xmlstarlet`

This is useful for customers that use the static Agent approach. Still you can see all major versions here:
[GitHub Agent 1.2.X commits](https://github.com/search?q=repo%3Ainstana%2Fagent-updates+%22Agent+1.%22&type=commits&s=committer-date&o=desc&p=1)
