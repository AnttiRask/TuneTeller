#!/usr/bin/env bash
# Uptime check on /health and an email alert for TuneTeller (Cloud Monitoring).
#
#   ALERT_EMAIL=you@example.com infra/setup_uptime_alert.sh
#
# Creates, if they don't exist yet (matched by display name, so re-running is safe):
#   1. an email notification channel
#   2. an uptime check: GET https://tuneteller.youcanbeapirate.com/health every 5 minutes,
#      10 s timeout, passes only on HTTP 200 with the body "ok"
#   3. an alert policy that emails when the check fails from at least two locations at the
#      same time (one flaky probe or a cold start doesn't wake anybody), and when it recovers
# Uptime checks, alert policies and email notifications are in Google's free tier at this
# volume. The address is not kept in the repository (it is public): pass it in.
#
# Uses the Monitoring REST API with the project named as the quota project, so nothing is
# billed to or enabled in whatever project gcloud happens to default to.
set -euo pipefail

PROJECT=tuneteller-app
HOST=tuneteller.youcanbeapirate.com
CHECK_NAME="TuneTeller /health"
CHANNEL_NAME="TuneTeller alerts"
POLICY_NAME="TuneTeller /health is failing"
: "${ALERT_EMAIL:?Set ALERT_EMAIL to the address that should get the alerts}"

TOKEN=$(gcloud auth print-access-token)
BASE="https://monitoring.googleapis.com/v3/projects/${PROJECT}"

# call METHOD PATH [JSON BODY]: prints the response; stops on an API error
call() {
    local method="$1" path="$2" body="${3:-}" out
    out=$(curl -s -X "$method" "${BASE}/${path}" \
        -H "Authorization: Bearer ${TOKEN}" -H "X-Goog-User-Project: ${PROJECT}" \
        -H "Content-Type: application/json" ${body:+-d "$body"})
    if echo "$out" | python3 -c "import json,sys; sys.exit(0 if 'error' not in json.load(sys.stdin) else 1)"; then
        echo "$out"
    else
        echo "API error on ${method} ${path}:" >&2
        echo "$out" | python3 -c "import json,sys; e=json.load(sys.stdin)['error']; print(' ', e.get('status'), '-', e.get('message'))" >&2
        exit 1
    fi
}

# name of the first item in a list whose displayName matches, or nothing
find_named() {
    call GET "$1" | python3 -c "
import json,sys
want = sys.argv[1]
d = json.load(sys.stdin)
for items in d.values():
    if isinstance(items, list):
        for i in items:
            if i.get('displayName') == want:
                print(i['name']); sys.exit(0)
" "$2"
}

echo "== notification channel"
CHANNEL=$(find_named notificationChannels "$CHANNEL_NAME")
if [ -z "$CHANNEL" ]; then
    CHANNEL=$(call POST notificationChannels "$(python3 -c "
import json,sys
print(json.dumps({'type': 'email', 'displayName': sys.argv[1], 'enabled': True,
                  'labels': {'email_address': sys.argv[2]}}))" "$CHANNEL_NAME" "$ALERT_EMAIL")" \
        | python3 -c "import json,sys; print(json.load(sys.stdin)['name'])")
    echo "  created: $CHANNEL"
else
    echo "  exists: $CHANNEL"
fi

echo "== uptime check"
CHECK=$(find_named uptimeCheckConfigs "$CHECK_NAME")
if [ -z "$CHECK" ]; then
    CHECK=$(call POST uptimeCheckConfigs "$(python3 -c "
import json,sys
print(json.dumps({
    'displayName': sys.argv[1],
    'monitoredResource': {'type': 'uptime_url', 'labels': {'project_id': sys.argv[2], 'host': sys.argv[3]}},
    'httpCheck': {'path': '/health', 'port': 443, 'useSsl': True, 'validateSsl': True, 'requestMethod': 'GET'},
    'period': '300s', 'timeout': '10s',
    'contentMatchers': [{'content': '^ok\$', 'matcher': 'MATCHES_REGEX'}],
}))" "$CHECK_NAME" "$PROJECT" "$HOST")" | python3 -c "import json,sys; print(json.load(sys.stdin)['name'])")
    echo "  created: $CHECK"
else
    echo "  exists: $CHECK"
fi
CHECK_ID="${CHECK##*/}"

echo "== alert policy"
POLICY=$(find_named alertPolicies "$POLICY_NAME")
if [ -z "$POLICY" ]; then
    POLICY=$(call POST alertPolicies "$(python3 -c "
import json,sys
name, check_id, channel = sys.argv[1:4]
print(json.dumps({
    'displayName': name, 'combiner': 'OR', 'enabled': True,
    'notificationChannels': [channel],
    'conditions': [{
        'displayName': 'Uptime check failing from two or more locations',
        'conditionThreshold': {
            'filter': 'metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND metric.label.check_id=\"%s\" AND resource.type=\"uptime_url\"' % check_id,
            'aggregations': [{'alignmentPeriod': '1200s', 'perSeriesAligner': 'ALIGN_NEXT_OLDER',
                              'crossSeriesReducer': 'REDUCE_COUNT_FALSE', 'groupByFields': ['resource.label.*']}],
            'comparison': 'COMPARISON_GT', 'thresholdValue': 1, 'duration': '60s', 'trigger': {'count': 1},
        },
    }],
    'alertStrategy': {'autoClose': '604800s'},
    'documentation': {'mimeType': 'text/markdown', 'content':
        'https://tuneteller.youcanbeapirate.com/health did not answer 200 ok from at least two locations.\n\n'
        'Open it in a browser: a 503 names what is wrong (OPENAI_API_KEY, SPOTIFY_CLIENT_ID or SPOTIFY_CLIENT_SECRET). '
        'Then see DEPLOY.md: check the revision and the logs, roll back if the last deploy did it.'},
}))" "$POLICY_NAME" "$CHECK_ID" "$CHANNEL")" | python3 -c "import json,sys; print(json.load(sys.stdin)['name'])")
    echo "  created: $POLICY"
else
    echo "  exists: $POLICY"
fi
echo "Done. See it at https://console.cloud.google.com/monitoring/uptime?project=${PROJECT}"
