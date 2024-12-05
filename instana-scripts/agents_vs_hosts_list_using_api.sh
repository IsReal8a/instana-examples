#!/bin/bash
# Script to query agents and hosts from the Instana API
# To get the Instana's version from a host.

AGENTS_FILE="/tmp/api_query_agents.txt"
HOSTS_FILE="/tmp/api_query_hosts.txt"
REPORT_FILE="instana_host_vs_agent_report.csv"

_usage()
{
    echo " $(basename $0) [-h]"
    echo ""
    echo " -h Displays this message"
    echo ""
    echo " Run export API_TOKEN and TENANT_UNIT separately for security purposes"
    echo " export API_TOKEN=<your-api-token>"
    echo " export TENANT_UNIT=<your-instana-tenant-unit>"
    echo ""
    echo " The script is going to create a CSV file with the Entity, Agent Version and Hostname"
}

_check_env_variables(){
    if [[ -z ${API_TOKEN+x} || -z ${TENANT_UNIT+x} ]]; then echo "Necessary environmental variables not set."; exit 1; else echo "Variables OK"; fi
}

_api_query_agents(){
    curl -s --request GET --header "authorization: apiToken $API_TOKEN" \
    --url https://$TENANT_UNIT.instana.io/api/host-agent | \
    jq -r '.items[] | .snapshotId' | \
    xargs -I {} curl -s --request GET --header "authorization: apiToken $API_TOKEN" \
    --url https://$TENANT_UNIT.instana.io/api/host-agent/{} | \
    jq -r '.entityId.host + "," + .data.agentVersion' | sort -t "," -k1
}

_api_query_hosts(){
    curl -s --request GET --header "authorization: apiToken $API_TOKEN" \
    --url "https://$TENANT_UNIT.instana.io/api/infrastructure-monitoring/snapshots?plugin=host" | \
    jq -r '.items[] | .host + "," + .label' | sort -t "," -k1
}

_check_results() {
    if [ "$1" -ne 0 ]
    then
        echo "There has been an error querying the data for the ${2}."
        exit 1
    fi
}

_jointz() {
    join -t "," -j 1 $1 $2
}

_clean_up() {
    echo "Cleaning up things..."
    rm -vfr $1 $2
}

_main() {
    echo "Executing..."
    echo "____________________________"
    echo "Checking necessary environmental variables..."
    _check_env_variables
    echo "Getting information from Agents..."
    _api_query_agents > $AGENTS_FILE
    RETURN_CODE=$?
    _check_results $RETURN_CODE "agents"
    echo "Getting information from Hosts..."
    _api_query_hosts > $HOSTS_FILE
    RETURN_CODE=$?
    _check_results $RETURN_CODE "hosts"
    echo "Processing report file..."
    _jointz $AGENTS_FILE $HOSTS_FILE > $REPORT_FILE
    if [[ -f $REPORT_FILE ]] ; then echo "${REPORT_FILE} created successfully."; else "Error creating ${REPORT_FILE}."; exit 1; fi
    echo "Wrapping up..."
    sed -i '' $'1i\\\nENTITYID,AGENTVERSION,HOST\n' $REPORT_FILE
    _clean_up $AGENTS_FILE $HOSTS_FILE
    echo "____________________________"
    echo "Process complete."
}

while getopts "h" opt; do
    case $opt in
        h)
            _usage
            exit
        ;;
    esac
done
_main
