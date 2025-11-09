---
name: google-sheets-api
description: Use when you must drive Google Sheets (and related Drive/Apps Script features) directly through the REST API from a shell—covers values, formulas, formatting, validation, conditional formats, named ranges, Drive search/share, and Apps Script triggers.
---

# Google Sheets via REST API (HTTPie + jq)

## Overview
Directly call the Google Sheets REST API (and Drive/Apps Script when needed) using shell tools (`http`/HTTPie + `jq`). This keeps everything dependency-light for agents working outside official SDKs or inside constrained environments.

## When to Use
- You must create/read/update Sheets programmatically from bash without client libraries.
- Need fine-grained control: formulas vs computed values, sheet/tab management, formatting, data validation, conditional formatting, named ranges, Drive file search/share, or invoking Apps Script.
- You already have `gcloud` ADC auth (or a service-account key) and the `http` + `jq` CLIs available.

**Do not use** when a higher-level SDK already exists in the project and the human expects you to stay inside that SDK (e.g., Python `google-api-python-client`).

## Prerequisites
1. `gcloud` configured for the user or service account.
2. `http` (HTTPie) and `jq` installed.
3. Scopes:
   - Full: `https://www.googleapis.com/auth/spreadsheets` and `https://www.googleapis.com/auth/drive`
   - Add read-only variants where possible.
4. Helper script: `source skills/google-sheets-api/scripts/env-helpers.sh` (path announced when loading the skill) to export `BASE/DRIVE/SCRIPT_BASE`, helper `token()` + `H()` functions, and the `check_gsheets_auth` utility. The script lives alongside this skill so credentials stay local to the project.

### Credential strategies (pick one) + exact instructions for the human
When `check_gsheets_auth` fails, respond with the following options and pause until the human confirms which they completed:

1. **Repo-local ADC (recommended)**  
   ```
   export CLOUDSDK_CONFIG=/PATH/TO/PROJECT/.google/gcloud-config
   mkdir -p "$CLOUDSDK_CONFIG"
   gcloud auth application-default revoke || true
   gcloud auth application-default login \
     --scopes=https://www.googleapis.com/auth/spreadsheets,https://www.googleapis.com/auth/drive
   gcloud auth application-default set-quota-project <project-id>
   ```
   - Tell them they can add `export CLOUDSDK_CONFIG=…` to their local shell init so this config applies only to this repo.
   - If `gcloud` keeps referencing the wrong account/project, have them run `gcloud config unset account`, `unset project`, or explicitly `gcloud config set account you@domain.com` before the login.
2. **Service-account JSON scoped to this repo**  
   ```
   gcloud iam service-accounts create sheets-skill-bot --display-name="Sheets Skill Bot"
   gcloud iam service-accounts keys create /PATH/TO/PROJECT/.google/gsheets-skill-key.json \
     --iam-account=sheets-skill-bot@<project-id>.iam.gserviceaccount.com
   gcloud projects add-iam-policy-binding <project-id> \
     --member="serviceAccount:sheets-skill-bot@<project-id>.iam.gserviceaccount.com" \
     --role="roles/editor"
   export GOOGLE_APPLICATION_CREDENTIALS=/PATH/TO/PROJECT/.google/gsheets-skill-key.json
   ```
   - Warn that service accounts must belong to a domain licensed for Drive/Sheets; otherwise sheet creation fails with `PERMISSION_DENIED`.
   - Remind them to share any created sheet back to their human account so they can view it.

### Check authentication before doing anything
1. Run `source skills/google-sheets-api/scripts/env-helpers.sh` and `check_gsheets_auth`.
2. If it fails, reply with the instructions above (mention which steps to run, including clearing old config with `gcloud config unset account/project` or `gcloud auth application-default revoke` when relevant) and **stop**. Do not keep retrying `gcloud login` from Codex.
3. Wait for the human to confirm they completed one of the setups. Then rerun `check_gsheets_auth`. Only proceed once it succeeds.
4. If the human chooses the service-account path and you detect `PERMISSION_DENIED` or `storageQuotaExceeded`, explain that the SA cannot own Sheets and they should switch to user ADC or share an existing sheet.

## Core Workflow
1. **Authenticate** per the strategy above (repo-local ADC or service account). Always run `check_gsheets_auth` after sourcing the helper; halt if it fails and tell the human what to do.
2. **Create or open a spreadsheet**: capture `SPREADSHEET_ID` once and reuse it. Keep it in an env var for all follow-up requests.
3. **Fetch `sheetId`s** when you need range-based batch updates; store them in env vars.
4. **Use Sheets `values` endpoints** for raw cell data; use `spreadsheets.batchUpdate` for structural / formatting / validation work.
5. **Share access** – if using a service account, make sure the resulting sheet is shared with the human’s email via the Drive API or manual sharing so they can inspect it.
6. **Log sparingly** – prefer `--print=b` to suppress headers, and pipe to `jq` to pull only the fields you need.

## Quick Reference
| Goal | Command Snippet |
| --- | --- |
| Create sheet | `jq -n '{properties:{title:"Demo"}}' | http POST "$BASE/spreadsheets" "$(H)"` |
| Add tab | `jq -n '{requests:[{addSheet:{properties:{title:"Data"}}}]}' | http POST "$BASE/spreadsheets/$SPREADSHEET_ID:batchUpdate" "$(H)"` |
| Write values | `http PUT "$BASE/spreadsheets/$SPREADSHEET_ID/values/Data!A1:C5" valueInputOption==USER_ENTERED …` |
| Read formulas vs computed | `valueRenderOption==FORMULA` or `==UNFORMATTED_VALUE` on the GET endpoint |
| Get `sheetId` | `http GET "$BASE/spreadsheets/$SPREADSHEET_ID" "$(H)" | jq -r '.sheets[] | select(.properties.title=="Data") | .properties.sheetId'` |
| Batch format | Send `requests:[{repeatCell…},{autoResizeDimensions…}]` to `:batchUpdate` |
| Data validation | `setDataValidation` request with `condition.type=ONE_OF_LIST`/`NUMBER_BETWEEN` |
| Conditional formatting | `addConditionalFormatRule` with `booleanRule` or `gradientRule` |
| Named range | `addNamedRange` |
| Drive search | `http GET "$DRIVE/files" q=="name='Foo' and mimeType='application/vnd.google-apps.spreadsheet'"` |
| Share file with human | `http --json POST "$DRIVE/files/$SPREADSHEET_ID/permissions" role=writer type=user emailAddress="human@example.com" "$(H)"` |
| Apps Script run | `http POST "$SCRIPT_BASE/scripts/$SCRIPT_ID:run"` with `{function:"myFn"}` |

## Common Operations
### Create Spreadsheet
```bash
SPREADSHEET_ID=$( jq -n '{properties:{title:"Agent Sheet Demo"}}' \
  | http --json POST "$BASE/spreadsheets" "$(H)" --print=b \
  | jq -r .spreadsheetId )
```

### Add Sheet Tab with Frozen Header
```bash
jq -n '{requests:[{addSheet:{properties:{title:"Data",gridProperties:{frozenRowCount:1}}}}]}' \
| http --json POST "$BASE/spreadsheets/$SPREADSHEET_ID:batchUpdate" "$(H)" --print=b | jq .
```

### Write Values (formulas allowed)
```bash
jq -n '{values:[["Item","Qty","Total"],["Apples",3,"=B2*2.5"],["Oranges",4,"=B3*2.5"],["","",""],["Sum","","=SUM(C2:C3)"]]}' \
| http --json PUT "$BASE/spreadsheets/$SPREADSHEET_ID/values/Data!A1:C5" \
  "valueInputOption==USER_ENTERED" "$(H)" --print=b | jq .
```

### Read Values as Formulas vs Numbers
```bash
http GET "$BASE/spreadsheets/$SPREADSHEET_ID/values/Data!A1:C10" \
  "valueRenderOption==FORMULA" "$(H)" --print=b | jq .
http GET "$BASE/spreadsheets/$SPREADSHEET_ID/values/Data!A1:C10" \
  "valueRenderOption==UNFORMATTED_VALUE" "$(H)" --print=b | jq .
```

### Format + Auto-resize Columns
```bash
SHEET_ID=$(http GET "$BASE/spreadsheets/$SPREADSHEET_ID" "$(H)" --print=b | jq -r '.sheets[] | select(.properties.title=="Data") | .properties.sheetId')

jq -n --argjson sid "$SHEET_ID" '{requests:[
  {repeatCell:{range:{sheetId:$sid,startRowIndex:0,endRowIndex:1},
    cell:{userEnteredFormat:{textFormat:{bold:true}}},
    fields:"userEnteredFormat.textFormat.bold"}},
  {autoResizeDimensions:{dimensions:{sheetId:$sid,dimension:"COLUMNS",startIndex:0,endIndex:3}}}
]}' | http --json POST "$BASE/spreadsheets/$SPREADSHEET_ID:batchUpdate" "$(H)" --print=b | jq .
```

### Data Validation Examples
Dropdown:
```bash
jq -n --argjson sid "$SHEET_ID" '{requests:[{setDataValidation:{range:{sheetId:$sid,startRowIndex:1,endRowIndex:100,startColumnIndex:0,endColumnIndex:1},
  rule:{condition:{type:"ONE_OF_LIST",values:[
    {userEnteredValue:"Apples"},{userEnteredValue:"Oranges"},{userEnteredValue:"Bananas"}
  ]},inputMessage:"Choose an item",strict:true,showCustomUi:true}}}]}' \
| http --json POST "$BASE/spreadsheets/$SPREADSHEET_ID:batchUpdate" "$(H)" --print=b | jq .
```
Number between 0 and 100:
```bash
jq -n --argjson sid "$SHEET_ID" '{requests:[{setDataValidation:{range:{sheetId:$sid,startRowIndex:1,endRowIndex:100,startColumnIndex:1,endColumnIndex:2},
  rule:{condition:{type:"NUMBER_BETWEEN",values:[{userEnteredValue:"0"},{userEnteredValue:"100"}]},inputMessage:"Enter 0–100",strict:true}}}]}' \
| http --json POST "$BASE/spreadsheets/$SPREADSHEET_ID:batchUpdate" "$(H)" --print=b | jq .
```

### Conditional Formatting Examples
Greater-than rule:
```bash
jq -n --argjson sid "$SHEET_ID" '{requests:[{addConditionalFormatRule:{rule:{
  ranges:[{sheetId:$sid,startRowIndex:1,startColumnIndex:0,endColumnIndex:3}],
  booleanRule:{condition:{type:"CUSTOM_FORMULA",values:[{userEnteredValue:"=$C2>10"}]},
  format:{backgroundColor:{red:0.85,green:0.97,blue:0.88}}}},index:0}}]}' \
| http --json POST "$BASE/spreadsheets/$SPREADSHEET_ID:batchUpdate" "$(H)" --print=b | jq .
```
Color scale:
```bash
jq -n --argjson sid "$SHEET_ID" '{requests:[{addConditionalFormatRule:{rule:{
  ranges:[{sheetId:$sid,startRowIndex:1,endRowIndex:100,startColumnIndex:2,endColumnIndex:3}],
  gradientRule:{minpoint:{type:"MIN",color:{red:0.90,green:0.95,blue:1.00}},
                midpoint:{type:"PERCENTILE",value:"50",color:{red:1,green:1,blue:1}},
                maxpoint:{type:"MAX",color:{red:0.98,green:0.90,blue:0.90}}}},index:0}}]}' \
| http --json POST "$BASE/spreadsheets/$SPREADSHEET_ID:batchUpdate" "$(H)" --print=b | jq .
```

### Named Ranges
```bash
jq -n --arg name "TABLE" --argjson sid "$SHEET_ID" '{requests:[{addNamedRange:{namedRange:{
  name:$name,
  range:{sheetId:$sid,startRowIndex:0,endRowIndex:4,startColumnIndex:0,endColumnIndex:3}
}}}]}' | http --json POST "$BASE/spreadsheets/$SPREADSHEET_ID:batchUpdate" "$(H)" --print=b | jq .
```

### Drive Search & Sharing
```bash
qs="name = 'Agent Sheet Demo' and mimeType = 'application/vnd.google-apps.spreadsheet'"
http GET "$DRIVE/files" q=="$qs" fields=="files(id,name,owners(displayName))" "$(H)" --print=b | jq .
```
Share a file (add reader):
```bash
http --json POST "$DRIVE/files/$SPREADSHEET_ID/permissions" "$(H)" \
  role=reader type=user emailAddress="user@example.com"
```

### Apps Script Trigger (optional)
```bash
jq -n '{function:"myFn",parameters:["arg1"]}' \
| http --json POST "$SCRIPT_BASE/scripts/$SCRIPT_ID:run" "$(H)" --print=b | jq .
```

## Discovery Document (Use sparingly)
When you need to confirm fields for a request:
1. Cache the discovery doc:
   ```bash
   DISC="$HOME/.cache/gsheets_discovery_v4.json"
   mkdir -p "$(dirname "$DISC")"
   curl -sS -z "$DISC" -o "$DISC" "https://sheets.googleapis.com/$discovery/rest?version=v4" || true
   test -s "$DISC" || http --download --output "$DISC" "https://sheets.googleapis.com/$discovery/rest?version=v4"
   ```
2. Query only the pieces you need. Examples:
   ```bash
   jq -r '.resources.spreadsheets.methods.batchUpdate.request."$ref"' "$DISC"
   jq -r '.schemas.ConditionalFormatRule.properties | keys[]' "$DISC"
   jq -r '.schemas.DataValidationRule.properties.condition."$ref" as $c | .schemas[$c].properties.type.enum[]' "$DISC"
   ```
Never dump the whole document into context—extract specific nodes.

## Troubleshooting
- **400 Bad Request** – Usually malformed JSON (element/field mismatch) or formula typo. Inspect the response body via `--print=hHbB` and narrow with `jq`.
- **403/404** – Sheet not shared with the current credentials or Drive scope missing.
- **PERMISSION_DENIED / storageQuotaExceeded when creating a sheet** – Service accounts without Google Workspace/Drive license can’t own Docs. Use a user ADC login (scoped to this project) or have the human share an existing sheet with the service account instead of having it create one.
- **429/5xx** – Add exponential backoff; batch multiple `requests` in one `batchUpdate`.
- **Locale formatting** – If decimals look wrong, set `userEnteredValue` with `.` decimal and rely on spreadsheet locale, or change spreadsheet locale via `spreadsheetProperties.locale`.
- **Large fetches** – Use `majorDimension=ROWS`/`COLUMNS` and limit ranges to avoid massive payloads.

## Checklist Before Finishing
- [ ] Stored `SPREADSHEET_ID` (and any `sheetId`s) in env vars or notes for future steps.
- [ ] Clearly noted whether values were USER_ENTERED or RAW.
- [ ] Logged only minimal JSON needed (use `jq`).
- [ ] Documented any assumptions (e.g., “Sheet locale is en-US”).
- [ ] Shared the Drive file or instructions for the human to access it.
- [ ] Verified ADC/service-account creds before attempting API calls; if missing, halted and instructed the human how to enable them.
- [ ] Service-account flows: sheet shared back to human account (or confirmed they can open it).
