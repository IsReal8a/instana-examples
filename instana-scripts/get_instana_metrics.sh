#!/bin/sh
# Script to get the metrics out of Instana API
# In this example, Infrastructure CPU, MEM
# Reads the env variables:
#     INSTANA_API_TOKEN
#     INSTANA_API_URL
# Change the values as needed

set -e

# JSON File path
JSON_FILE="/tmp/instana_metrics.json"
PRETTY_JSON="/tmp/instana_pretty.json"
TIMEFRAME_TO=$(date +%s000)

# Fetch data from Instana API (windowSize in milliseconds)
wget --quiet --output-document=$JSON_FILE --header="authorization: apiToken $INSTANA_API_TOKEN" \
--header="Content-Type: application/json" \
--post-data='{
  "metrics": [
    "cpu.used","memory.used"
  ],
  "plugin": "host",
  "query": "entity.zone:ocp-zone",
  "rollup": 5,
  "timeFrame": {
    "to": '"$TIMEFRAME_TO"',
    "windowSize": 300000
  }
}' "$INSTANA_API_URL/api/infrastructure-monitoring/metrics"

# Preprocess JSON: split each item block onto a new line
sed 's/},{/},\n{/g' "$JSON_FILE" > "$PRETTY_JSON"

# Start JSON array
echo "["

awk '
  function process_block() {
    if (label != "" && cpu_line != "" && mem_line != "") {
      gsub(/.*"cpu.used":\[\[/, "", cpu_line)
      gsub(/\]\].*/, "", cpu_line)
      gsub(/.*"memory.used":\[\[/, "", mem_line)
      gsub(/\]\].*/, "", mem_line)

      n = split(cpu_line, cpu_arr, "\\],\\[")
      split(mem_line, mem_arr, "\\],\\[")

      for (i = 1; i <= n; i++) {
        split(cpu_arr[i], cpu_vals, ",")
        split(mem_arr[i], mem_vals, ",")

        ts = cpu_vals[1]
        cpu = cpu_vals[2]
        mem = mem_vals[2]

        if (ts != "" && cpu != "" && mem != "") {
          if (first == 1) {
            first = 0
          } else {
            printf(",\n")
          }
          printf("  {\"measurement\": \"instana_metrics\", \"hostname\": \"%s\", \"timestamp\": %s, \"cpu_used\": %s, \"memory_used\": %s}", label, ts, cpu, mem)

        }
      }
    }
  }

  BEGIN {
    first = 1
    label = ""
    cpu_line = ""
    mem_line = ""
  }

  /"snapshotId":/ {
    process_block()
    label = ""
    cpu_line = ""
    mem_line = ""
  }

  /"label":/ {
    match($0, /"label"[[:space:]]*:[[:space:]]*"[^"]+"/)
    label = substr($0, RSTART + 9, RLENGTH - 10)
  }

  /"cpu.used":\[\[/ {
    cpu_line = $0
    while (cpu_line !~ /\]\]/ && (getline line) > 0) {
      cpu_line = cpu_line line
    }
  }

  /"memory.used":\[\[/ {
    mem_line = $0
    while (mem_line !~ /\]\]/ && (getline line) > 0) {
      mem_line = mem_line line
    }
  }

  END {
    process_block()
  }
' "$PRETTY_JSON"

# End JSON array
echo
echo "]"

# Cleanup
rm -f "$PRETTY_JSON"
