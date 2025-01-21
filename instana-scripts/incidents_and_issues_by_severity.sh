#!/bin/bash
# Script to query incidents and issues from the Events API
# and creates a JSON file based on Severity.
# API information:
# https://instana.github.io/openapi/#operation/getEvents
#
# Things to note:
#   Severity values
#     Critical = 10
#     Warning  = 5

REPORT_FILE="critical_incidents_and_issues_report.json"
WINDOW_SIZE=3600000 # One Hour
EXCLUDE_TRIGGERED_BEFORE="true"
FILTER_EVENT_UPDATES="true"
SEVERITY=10 # Critical by default

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
    echo " The script is going to create a JSON file with Incidents and Issues"
    echo " within the Window Size scope, default is one hour, based on Severity."
}

_check_env_variables(){
    if [[ -z ${API_TOKEN+x} || -z ${TENANT_UNIT+x} ]]; then echo "Necessary environmental variables not set."; exit 1; else echo "Variables OK"; fi
}

_api_query_events(){
    echo ${SEVERITY}
    curl -s --request GET --header "authorization: apiToken $API_TOKEN" \
    --url "https://${TENANT_UNIT}.instana.io/api/events?eventTypeFilters=INCIDENT&eventTypeFilters=ISSUE&windowSize=${WINDOW_SIZE}&excludeTriggeredBefore=${EXCLUDE_TRIGGERED_BEFORE}&filterEventUpdates=${FILTER_EVENT_UPDATES}" | \
    jq --argjson severity "$SEVERITY" -r '.[] | select(.severity == $severity)' # We change the severity level here :)
}

_main() {
    echo "Executing..."
    echo "____________________________"
    echo "Checking necessary environmental variables..."
    _check_env_variables
    echo "Getting information from Hosts..."
    # Uncomment to send to local REPORT_FILE
    _api_query_events #> $REPORT_FILE
    RETURN_CODE=$?
    echo "____________________________"
    echo "Process complete."
    exit ${RETURN_CODE}
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
