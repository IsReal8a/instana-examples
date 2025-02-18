# Script to get the latest Instana Agent changes from the Latest to the Previous version, from GITHUB.
# Tested in MACOS Sequoia 15.X and RedHat Linux 9.X, it should work in your machine.
#!/bin/sh

# First of all install xmlstarlet
# Linux
#   yum install xmlstarlet
# MacOS
#   brew install xmlstarlet

# It's ideal to use the GitHub API Token to avoid limits calling the API :).
# You can comment the Authorization header and use the script as it's.

GITHUB_API_TOKEN="github_pat_ADD_YOUR_API_KEY"

# Set the headers for the API request.
HEADERS=(
    "Authorization: token ${GITHUB_API_TOKEN}"
    "Accept: application/vnd.github.v3+json"
)

# The following is a nasty approach for getting the latest and previous main Agent version
# there is no other way to get the data anywhere unfortunately as how things have been built in Instana and GitHub,
# this is used to get the latest two commits that contain a major Instana Agent version,
# aka "Agent 1.2.X". The elegant way to get the HTML data is using xmlstarlet.

GET_AGENT_COMMITS_DATA=$(curl -Ls https://github.com/search\?q\=repo%3Ainstana%2Fagent-updates+%22Agent+1.%22\&type\=commits\&s\=committer-date\&o\=desc\&p\=1 | xmlstarlet format -H - 2>/dev/null | xmlstarlet sel -t -v '//a/@href' -)

# Get the two latest commits.
GET_LATEST_COMMITS=$(echo $GET_AGENT_COMMITS_DATA | grep -o 'commit/[a-z0-9]*' | head -n 2 | cut -d '/' -f 2)

# Convert the string to an array and then use the items to construct our variables.
GET_REFERENCE_COMMITS=($GET_LATEST_COMMITS)

# Get the commit data from the latest major Agent version .
GET_COMMIT_DATA_LATEST="$(curl -s -X GET https://api.github.com/repos/instana/agent-updates/commits/${GET_REFERENCE_COMMITS[0]}  -H "${HEADERS[@]}")"

# Get the commit data from the previous major Agent version.
GET_COMMIT_DATA_PREVIOUS="$(curl -s -X GET https://api.github.com/repos/instana/agent-updates/commits/${GET_REFERENCE_COMMITS[1]}  -H "${HEADERS[@]}")"

# Extract and format the data from the latest agent information.
AGENT_DATA_LATEST=($(jq -r '([.commit.author.date, (.commit.message | split("\n") | .[0])] | join(" "))' <<<"${GET_COMMIT_DATA_LATEST}"))

# Extract and format the data from the previous agent information.
AGENT_DATA_PREVIOUS=($(jq -r '([.commit.author.date, (.commit.message | split("\n") | .[0])] | join(" "))' <<<"${GET_COMMIT_DATA_PREVIOUS}"))

# Map things for later use.
AGENT_SHA_LATEST="${GET_REFERENCE_COMMITS[0]}"
AGENT_DATE_LATEST="${AGENT_DATA_LATEST[0]}"
AGENT_VERSION_LATEST="${AGENT_DATA_LATEST[2]}"
AGENT_SHA_PREVIOUS="${GET_REFERENCE_COMMITS[1]}"
AGENT_DATE_PREVIOUS="${AGENT_DATA_PREVIOUS[0]}"
AGENT_VERSION_PREVIOUS="${AGENT_DATA_PREVIOUS[2]}"

# Present the data to the end user.
echo "Latest Instana Agent commit information..."
echo "------------------------------------------"
echo "SHA: ${AGENT_SHA_LATEST}, Agent Version: ${AGENT_VERSION_LATEST}, Date: ${AGENT_DATE_LATEST}"
echo ""
echo "Previous Instana Agent commit information..."
echo "------------------------------------------"
echo "SHA: ${AGENT_SHA_PREVIOUS}, Agent Version: ${AGENT_VERSION_PREVIOUS}, Date: ${AGENT_DATE_PREVIOUS}"
echo "GitHub URL for reference"
echo "------------------------------------------"
echo "https://github.com/search?q=repo%3Ainstana%2Fagent-updates+%22Agent+1.%22&type=commits&s=committer-date&o=desc&p=1"

# Get the commit range and talk to the GitHub API.
COMMIT_DATE_RANGE="?since=${AGENT_DATE_PREVIOUS}&until=${AGENT_DATE_LATEST}"
API_URL_COMMITS="https://api.github.com/repos/instana/agent-updates/commits${COMMIT_DATE_RANGE}"

# Get all commmits between both major Instana Agent versions.
GET_COMMITS_BETWEEN_VERSIONS=$(curl -s -X GET ${API_URL_COMMITS} -H "${HEADERS[@]}")

# Format the git commits information.
COMMITS=$(jq -r '(.[] | [ .commit.author.date, "CHANGE: " + (.commit.message | split("\n") | .[0]), "CHANGE URL: " + .html_url ] | join(" | "))' <<<"${GET_COMMITS_BETWEEN_VERSIONS}")

# Print all commits including GitHub URLs.
echo ""
echo "All commits between version ${AGENT_VERSION_PREVIOUS} and version ${AGENT_VERSION_LATEST}..."
echo "------------------------------------------"
echo "$COMMITS"
exit 0
