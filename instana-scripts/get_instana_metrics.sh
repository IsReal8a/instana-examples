#!/bin/sh
# Script to get the data out of Instana API
# In this example, Infrastructure CPU, MEM
# Reads the env variables:
#     INSTANA_API_TOKEN
#     INSTANA_API_URL
# Change the values as needed

# JSON File path
JSON_FILE="/tmp/instana_data.json"

TIMEFRAME_TO=$(date +%s000)
wget --quiet --output-document=$JSON_FILE --header="authorization: apiToken $INSTANA_API_TOKEN" \
--header="Content-Type: application/json" \
--post-data='{
    "timeFrame": {
      "to": '"$TIMEFRAME_TO"',
      "windowSize": 3600000
    },
    "tagFilterExpression": {
        "type": "TAG_FILTER",
        "name": "zone",
        "operator": "EQUALS",
        "entity": "NOT_APPLICABLE",
        "value": "ocp-zone",
        "tagDefinition": {
          "name": "zone",
          "type": "STRING",
          "path": [
            {
              "label": "Other"
            },
            {
              "label": "zone"
            }
          ],
          "availability": []
        }
      },
    "pagination": {
      "retrievalSize": 20
    },
    "type": "host",
    "metrics": [
      {
        "metric": "cpu.used",
        "aggregation": "MEAN",
        "label": "Used (Cpu)"
      },
      {
        "metric": "memory.used",
        "aggregation": "MEAN",
        "label": "Used (Memory)"
      }
    ],
    "order": {
      "by": "label",
      "direction": "ASC"
    }
}' \
"$INSTANA_API_URL"

# Start JSON array
echo "["

# Extract the relevant parts using a more robust approach
first=true
# Use sed to isolate each item block
sed -n '/"items":\[/,/\]/{/"snapshotId"/,/"entityHealthInfo"/p}' "$JSON_FILE" | tr '\n' ' ' | sed 's/},{/}|{/g' | tr '|' '\n' | while read -r block; do
  label=$(echo "$block" | grep -o '"label":"[^"]*"' | head -1 | cut -d':' -f2- | tr -d '"')
  cpu=$(echo "$block" | grep -o '"cpu.used.MEAN":\[\[[0-9]*,[0-9.]*' | cut -d',' -f2)
  mem=$(echo "$block" | grep -o '"memory.used.MEAN":\[\[[0-9]*,[0-9.]*' | cut -d',' -f2)

  if [[ -n "$label" && -n "$cpu" && -n "$mem" ]]; then
    if [ "$first" = true ]; then
      first=false
    else
      echo ","
    fi
    # echo -n "  {\"tags\": {\"hostname\": \"$label\"}, \"fields\": {\"cpu_used_MEAN\": $cpu, \"memory_used_MEAN\": $mem}}"
    echo -n "  {\"hostname\": \"$label\", \"cpu_used_MEAN\": $cpu, \"memory_used_MEAN\": $mem}"
  fi
done

# End JSON array
echo
echo "]"
