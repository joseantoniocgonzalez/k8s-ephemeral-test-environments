#!/usr/bin/env bash
set -Eeuo pipefail

NAMESPACE="${NAMESPACE:-ioc-test}"
RELEASE_NAME="${RELEASE_NAME:-ioc-test}"
API_SERVICE="${RELEASE_NAME}-api"
API_PORT="${API_PORT:-8000}"

kubectl exec -i \
  --namespace "$NAMESPACE" \
  deployment/"${RELEASE_NAME}-api" \
  -c api \
  -- env API_SERVICE="$API_SERVICE" API_PORT="$API_PORT" python - <<'PY'
import json
import os
from urllib.request import Request, urlopen

base_url = f"http://{os.environ['API_SERVICE']}:{os.environ['API_PORT']}"

def get_json(path):
    with urlopen(f"{base_url}{path}", timeout=10) as response:
        return json.load(response)

def post_json(path, payload):
    request = Request(
        f"{base_url}{path}",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urlopen(request, timeout=10) as response:
        return json.load(response)

health = get_json("/health")
if health.get("status") != "ok":
    raise SystemExit("API health check failed")

database = get_json("/health/db")
if database.get("database") != "ok":
    raise SystemExit("Database health check failed")

analysis = post_json(
    "/api/v1/iocs/check",
    {"value": "http://192.0.2.10/login/verify-account"},
)

if analysis.get("final_verdict") != "high":
    raise SystemExit("Unexpected IOC verdict")

analysis_id = analysis.get("analysis_id")
if not analysis_id:
    raise SystemExit("Analysis ID was not returned")

stored = get_json(f"/api/v1/iocs/{analysis_id}")
if stored.get("analysis_id") != analysis_id:
    raise SystemExit("Stored analysis could not be retrieved")

print(f"Smoke test passed: {analysis_id}")
PY
