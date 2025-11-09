#!/usr/bin/env bash
# Helper functions for google-sheets-api skill
# Source this file before running HTTPie/jq commands.

export BASE="https://sheets.googleapis.com/v4"
export DRIVE="https://www.googleapis.com/drive/v3"
export SCRIPT_BASE="https://script.googleapis.com/v1"

# Print an access token using gcloud ADC or service-account creds.
token() {
  gcloud auth application-default print-access-token
}

# Authorization header helper for HTTPie/curl.
H() {
  echo "Authorization:Bearer $(token)"
}

# Quick check to ensure credentials exist before running API calls.
check_gsheets_auth() {
  if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
    cat <<'MSG'
ERROR: No Application Default Credentials were found.
Please run one of the following on a local machine with browser access, then rerun this script:
  gcloud auth application-default login \
    --scopes=https://www.googleapis.com/auth/spreadsheets,https://www.googleapis.com/auth/drive

Or provide a service-account key JSON and export:
  export GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json
MSG
    return 1
  fi
  return 0
}
