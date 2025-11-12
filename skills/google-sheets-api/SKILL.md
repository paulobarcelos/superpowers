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
4. Helper scripts:
   - `source skills/google-sheets-api/scripts/env-helpers.sh` once per shell to export `BASE/DRIVE/SCRIPT_BASE`, helper `token()`/`H()`, `http_sheets()` (HTTPie wrapper that automatically adds the auth + quota headers), and `check_gsheets_auth`.
   - For long sessions run `skills/google-sheets-api/scripts/sheets-shell.sh` (it sources the helpers then execs `$SHELL`) so you don’t have to re-source before every command.
5. Optional: set `export GCLOUD_QUOTA_PROJECT=<project-id>` so every `http_sheets` call automatically adds the `X-Goog-User-Project` header.

### Session bootstrap checklist
Run these three commands before touching any sheet. Skipping them caused every failure in many test runs.

```bash
source skills/google-sheets-api/scripts/env-helpers.sh
check_gsheets_auth                         # halts with instructions if ADC is missing
export GCLOUD_QUOTA_PROJECT="$(gcloud config get-value core/project)"
```

If `gcloud config get-value core/project` prints nothing, set it first (`gcloud config set project <id>`). Do not touch the API until `check_gsheets_auth` succeeds and the quota project is exported—otherwise you will loop on `PERMISSION_DENIED` errors that demand a quota project.

### Authentication workflow – simplest possible (global ADC)
Most users should just run the standard gcloud workflow once and reuse it everywhere. When `check_gsheets_auth` fails, tell the human to do the following on their machine (with a browser):
1. **Pick or create a GCP project ID** (e.g., `gsheets-skill-123`). If they don’t have one:
   ```bash
   gcloud projects create gsheets-skill-123 --name="Google Sheets Skill"
   ```
2. **Authenticate globally** (uses the active account configured in gcloud):
   ```bash
   gcloud auth login
   gcloud config set project gsheets-skill-123
   gcloud auth application-default login \
     --scopes=https://www.googleapis.com/auth/spreadsheets,https://www.googleapis.com/auth/drive
   gcloud auth application-default set-quota-project gsheets-skill-123
   ```
   - If the wrong account/project keeps appearing, have them run `gcloud config unset account`, `gcloud config unset project`, or explicitly `gcloud config set account you@domain.com` before the login; they can also run `gcloud auth application-default revoke` to clear stale tokens.
3. **Enable APIs (first time only)**
   ```bash
   gcloud services enable sheets.googleapis.com drive.googleapis.com --project=gsheets-skill-123
   ```
4. Once they confirm the commands succeeded, rerun `check_gsheets_auth`. Continue only after it passes.

### Optional: project-local credentials
If they insist on keeping credentials inside the repo, adapt the steps above but prepend `export CLOUDSDK_CONFIG=/path/to/project/.google/gcloud-config` before running gcloud commands. Otherwise the global ADC approach is fine.

## Core Workflow
1. **Authenticate** per the strategy above (repo-local ADC or service account). Always run `check_gsheets_auth` after sourcing the helper; halt if it fails and tell the human what to do.
2. **Create or open a spreadsheet**: capture `SPREADSHEET_ID` once and reuse it. Keep it in an env var for all follow-up requests.
3. **Fetch `sheetId`s** when you need range-based batch updates; store them in env vars.
4. **Use Sheets `values` endpoints** for raw cell data; use `spreadsheets.batchUpdate` for structural / formatting / validation work.
5. **Share access** – if using a service account, make sure the resulting sheet is shared with the human’s email via the Drive API or manual sharing so they can inspect it.
6. **Sheet IDs may be large integers** – always extract them via `jq -r '.properties.sheetId'` and store them as env vars (strings are fine) so JSON precision issues don’t arise.
7. **Log sparingly** – prefer `--print=b` to suppress headers, and pipe to `jq` to pull only the fields you need.

## Quick Reference
Assume you already sourced `env-helpers.sh`; use `http_sheets …` for every API call so auth + quota headers travel together. When streaming a JSON file into HTTPie (e.g., `@payload.json` or via `< file`), add `--ignore-stdin` so the CLI doesn’t wait for interactive input—it otherwise blocks the request.
| Goal | Command Snippet |
| --- | --- |
| Create sheet | `jq -n '{properties:{title:"Demo"}}' | http_sheets POST "$BASE/spreadsheets"` |
| Add tab | `jq -n '{requests:[{addSheet:{properties:{title:"Data"}}}]}' | http_sheets POST "$BASE/spreadsheets/$SPREADSHEET_ID:batchUpdate"` |
| Write values | `jq -n '{valueInputOption:"USER_ENTERED",data:[{range:"Data!A1",values:[[...]]}]}' \| http_sheets POST "$BASE/spreadsheets/$SPREADSHEET_ID/values:batchUpdate"` |
| Read formulas vs computed | `http_sheets GET "$BASE/spreadsheets/$SPREADSHEET_ID/values/Data!A1:C5" valueRenderOption==FORMULA` / `…==UNFORMATTED_VALUE` |
| Get `sheetId` | `http_sheets GET "$BASE/spreadsheets/$SPREADSHEET_ID" | jq -r '.sheets[] | select(.properties.title=="Data") | .properties.sheetId'` |
| Batch format | `jq -n '{requests:[{repeatCell:{…}}]}' | http_sheets POST "$BASE/spreadsheets/$SPREADSHEET_ID:batchUpdate"` |
| Data validation | Load template from `skills/google-sheets-api/templates/…`, patch `sheetId` via `jq --argjson sid`, pipe to `http_sheets POST ...:batchUpdate` |
| Conditional formatting | Same pattern—patch template, send via `http_sheets POST ...:batchUpdate` |
| Named range | `jq -n '{requests:[{addNamedRange:{…}}]}' | http_sheets POST "$BASE/spreadsheets/$SPREADSHEET_ID:batchUpdate"` |
| Drive search | `http_sheets GET "$DRIVE/files" q=="name='Demo' and mimeType='application/vnd.google-apps.spreadsheet'"` |
| Share file with human | `http_sheets POST "$DRIVE/files/$SPREADSHEET_ID/permissions" role=writer type=user emailAddress=user@example.com` |
| Apps Script run | `http_sheets POST "$SCRIPT_BASE/scripts/$SCRIPT_ID:run"` with `{function:"myFn"}` |

## Common Operations
### Create Spreadsheet
```bash
SPREADSHEET_ID=$(jq -n '{properties:{title:"Agent Sheet Demo"}}' \
  | http_sheets POST "$BASE/spreadsheets" --print=b \
  | jq -r .spreadsheetId)
```

### Add Sheet Tab with Frozen Header
```bash
jq -n '{requests:[{addSheet:{properties:{title:"Data",gridProperties:{frozenRowCount:1}}}}]}' \
| http_sheets POST "$BASE/spreadsheets/$SPREADSHEET_ID:batchUpdate" --print=b | jq .
```

### Write Values (formulas allowed)
```bash
jq -n '{valueInputOption:"USER_ENTERED",data:[{range:"Data!A1",values:[["Item","Qty","Total"],["Apples",3,"=B2*2.5"],["Oranges",4,"=B3*2.5"],["","",""],["Sum","","=SUM(C2:C3)"]]}]}' \
| http_sheets POST "$BASE/spreadsheets/$SPREADSHEET_ID/values:batchUpdate" --print=b | jq .
```

### Read Values as Formulas vs Numbers
```bash
http_sheets GET "$BASE/spreadsheets/$SPREADSHEET_ID/values/Data!A1:C10" \
  valueRenderOption==FORMULA --print=b | jq .
http_sheets GET "$BASE/spreadsheets/$SPREADSHEET_ID/values/Data!A1:C10" \
  valueRenderOption==UNFORMATTED_VALUE --print=b | jq .
```

### Format + Auto-resize Columns
```bash
SHEET_ID=$(http_sheets GET "$BASE/spreadsheets/$SPREADSHEET_ID" --print=b \
  | jq -r '.sheets[] | select(.properties.title=="Data") | .properties.sheetId')

jq --argjson sid "$SHEET_ID" \
   '.requests[0].repeatCell.range.sheetId=$sid |
    .requests[1].autoResizeDimensions.dimensions.sheetId=$sid' \
   skills/google-sheets-api/templates/format-header-autosize.json \
| http_sheets POST "$BASE/spreadsheets/$SPREADSHEET_ID:batchUpdate" --print=b | jq .
```

### Data Validation Examples
Dropdown (template-driven):
```bash
jq --argjson sid "$SHEET_ID" \
   '.requests[0].setDataValidation.range.sheetId=$sid |
    .requests[0].setDataValidation.rule.condition.values=[
      {"userEnteredValue":"Apples"},
      {"userEnteredValue":"Oranges"},
      {"userEnteredValue":"Bananas"}
    ]' \
   skills/google-sheets-api/templates/set-data-validation-one-of-list.json \
| http_sheets POST "$BASE/spreadsheets/$SPREADSHEET_ID:batchUpdate" --print=b | jq .
```

### Conditional Formatting Examples
Greater-than rule (template):
```bash
jq --argjson sid "$SHEET_ID" --arg formula "=$C2>10" \
   '.requests[0].addConditionalFormatRule.rule.ranges[0].sheetId=$sid |
    .requests[0].addConditionalFormatRule.rule.booleanRule.condition.values[0].userEnteredValue=$formula' \
   skills/google-sheets-api/templates/conditional-format-greater-than.json \
| http_sheets POST "$BASE/spreadsheets/$SPREADSHEET_ID:batchUpdate" --print=b | jq .
```
Color scale (template):
```bash
jq --argjson sid "$SHEET_ID" \
   '.requests[0].addConditionalFormatRule.rule.ranges[0].sheetId=$sid' \
   skills/google-sheets-api/templates/conditional-format-gradient.json \
| http_sheets POST "$BASE/spreadsheets/$SPREADSHEET_ID:batchUpdate" --print=b | jq .
```

### Named Ranges
```bash
jq -n --arg name "TABLE" --argjson sid "$SHEET_ID" '{requests:[{addNamedRange:{namedRange:{
  name:$name,
  range:{sheetId:$sid,startRowIndex:0,endRowIndex:4,startColumnIndex:0,endColumnIndex:3}
}}}]}' | http_sheets POST "$BASE/spreadsheets/$SPREADSHEET_ID:batchUpdate" --print=b | jq .
```

### Drive Search & Sharing
```bash
qs="name = 'Agent Sheet Demo' and mimeType = 'application/vnd.google-apps.spreadsheet'"
http_sheets GET "$DRIVE/files" q=="$qs" fields=="files(id,name,owners(displayName))" --print=b | jq .
```
Share a file (add reader/commenter/editor):
```bash
http_sheets POST "$DRIVE/files/$SPREADSHEET_ID/permissions" \
  role=commenter type=user emailAddress="user@example.com"
```

### Apps Script Trigger (optional)
```bash
jq -n '{function:"myFn",parameters:["arg1"]}' \
| http_sheets POST "$SCRIPT_BASE/scripts/$SCRIPT_ID:run" --print=b | jq .
```

### Structural controls reference
Rename the default sheet (grid ID 0) and add a new tab in one request:
```bash
jq -n '{requests:[
  {updateSheetProperties:{properties:{sheetId:0,title:"Energy Data"},fields:"title"}},
  {addSheet:{properties:{title:"Dashboard"}}}
]}' | http_sheets POST "$BASE/spreadsheets/$SPREADSHEET_ID:batchUpdate"
```

Add a slicer (column index must lie inside the referenced range—0-based, exclusive of `endColumnIndex`):
```bash
jq -n --argjson sid "$DASHBOARD_SHEET_ID" '{requests:[{addSlicer:{slicer:{
  spec:{
    dataRange:{sheetId:$sid,startRowIndex:3,endRowIndex:203,startColumnIndex:7,endColumnIndex:13},
    columnIndex:1,
    title:"Region focus"
  },
  position:{
    overlayPosition:{
      anchorCell:{sheetId:$sid,rowIndex:1,columnIndex:9},
      offsetXPixels:16,offsetYPixels:10,widthPixels:220,heightPixels:120
    }
  }
}}]}]' | http_sheets POST "$BASE/spreadsheets/$SPREADSHEET_ID:batchUpdate"
```

Line + combo chart (trend + stacked column) targeting a normalized helper range:
```bash
jq -n --argjson sid "$DASHBOARD_SHEET_ID" '{
  requests:[{
    addChart:{
      chart:{
        spec:{
          title:"Regional MWh Trend",
          basicChart:{
            chartType:"COMBO",
            legendPosition:"BOTTOM_LEGEND",
            axis:[{position:"BOTTOM_AXIS",title:"Month"},{position:"LEFT_AXIS",title:"MWh"}],
            domains:[{domain:{sourceRange:{sources:[{sheetId:$sid,startRowIndex:0,endRowIndex:6,startColumnIndex:0,endColumnIndex:1}]}}}],
            series:[
              {series:{sourceRange:{sources:[{sheetId:$sid,startRowIndex:0,endRowIndex:6,startColumnIndex:1,endColumnIndex:2}]}},targetAxis:"LEFT_AXIS"},
              {series:{sourceRange:{sources:[{sheetId:$sid,startRowIndex:0,endRowIndex:6,startColumnIndex:2,endColumnIndex:3}]}},targetAxis:"LEFT_AXIS"}
            ],
            stackedType:"STACKED"
}} ,
      position:{overlayPosition:{anchorCell:{sheetId:$sid,rowIndex:0,columnIndex:0}}}
}}]}' | http_sheets POST "$BASE/spreadsheets/$SPREADSHEET_ID:batchUpdate"
```

Filter view that lets reviewers toggle status/workstream without touching formulas:
```bash
jq -n --argjson sid "$TIMELINE_SHEET_ID" '{
  requests:[{
    addFilterView:{
      filter:{
        title:"Status & Workstream Filters",
        range:{sheetId:$sid,startRowIndex:0,endRowIndex:1000,startColumnIndex:0,endColumnIndex:7},
        filterSpecs:[
          {columnIndex:3, filterCriteria:{condition:{type:"VALUE"}}},
          {columnIndex:4, filterCriteria:{condition:{type:"VALUE"}}}
        ]
}}}]}' | http_sheets POST "$BASE/spreadsheets/$SPREADSHEET_ID:batchUpdate"
```

Protected range that warns (rather than blocks) edits:
```bash
jq -n --argjson sid "$TIMELINE_SHEET_ID" '{
  requests:[{
    addProtectedRange:{
      protectedRange:{
        range:{sheetId:$sid,startRowIndex:0,endRowIndex:1000,startColumnIndex:2,endColumnIndex:3},
        warningOnly:true,
        description:"Warn before editing Launch Timeline due dates"
}}}]}' | http_sheets POST "$BASE/spreadsheets/$SPREADSHEET_ID:batchUpdate"
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

## Formula injection & debugging workflow
Complex formulas (LET/LAMBDA/MAP, array logic) are painful when you cannot use the Sheets UI. Follow this loop instead of pasting a 60‑line formula blindly:

1. **Prototype with helper ranges.** Build intermediate columns/tabs (e.g., `Helper!A:Z`) using simple formulas so every `SUMIFS`, `INDEX`, or `FILTER` references literal grid ranges. Many Sheets functions reject inline arrays (`MAP(...)`) as range arguments—the #REF! loops in the November 2025 Brand Studio test were all caused by this.
2. **Store multi-line formulas in a file** to avoid quoting hell:
   ```bash
   cat <<'EOF' >/tmp/formula.txt
   =LET(…)
   EOF
   jq -Rs '{valueInputOption:"USER_ENTERED",data:[{range:"Schedule!A2",values:[[.]]}]}' /tmp/formula.txt \
     | http_sheets POST "$BASE/spreadsheets/$SPREADSHEET_ID/values:batchUpdate"
   ```
3. **Inspect what Sheets actually stored** by pulling grid data:
   ```bash
   http_sheets GET "$BASE/spreadsheets/$SPREADSHEET_ID?includeGridData=true&ranges=Schedule!A2" \
     | jq '.sheets[0].data[0].rowData[0].values[0].userEnteredValue.formulaValue,
           .sheets[0].data[0].rowData[0].values[0].effectiveValue'
   ```
   The `effectiveValue.errorValue.message` field repeats the UI tooltip (e.g., “Function INDEX parameter 3 value is 2”).
4. **Use `valueRenderOption=UNFORMATTED_VALUE`** when verifying numbers vs. accidentally formatted dates (`1900-03-20` in the studio session turned out to be “80” hours rendered as a date).
5. **Iterate incrementally.** Start with a single column (priority rank). Once stable, extend the formula. If a function needs a range, materialize it via helper rows rather than trying to coerce an array literal.

When the sheet does not support modern functions (service accounts tied to older Workspace tiers), fall back to helper tables or Apps Script—they compile reliably, whereas LET/MAP will throw parse errors forever.

## Troubleshooting
- **“Your application … requires a quota project” (403 PERMISSION_DENIED)** – You skipped the bootstrap checklist. Run `export GCLOUD_QUOTA_PROJECT="$(gcloud config get-value core/project)"`, rerun your command via `http_sheets`, and ensure `check_gsheets_auth` passes first.
- **HTTPie `argument REQUEST_ITEM` / token printed inline** – Never expand `$(H)` yourself. Pipe payloads into `http_sheets …` (wrapper sends `Authorization` + quota header). For curl, explicitly set `-H "Authorization: Bearer $(token)" -H "X-Goog-User-Project:$GCLOUD_QUOTA_PROJECT"`.
- **400 Bad Request** – Inspect `--print=hHbB` output and run the offending JSON through `jq` to verify fields (common when `overlayPosition` is missing). Keep column indexes within the provided range bounds (see slicer example).
- **`Invalid requests[0].addSlicer: Slicer column must be within range bounds`** – Column indexes are zero-based relative to the provided `dataRange`. Ensure `columnIndex >= startColumnIndex` and `< endColumnIndex`.
- **`Argument must be a range` / `Function INDEX parameter …`** – A formula is handing arrays to a function that expects literal ranges. Materialize helper ranges and reference them directly; pull `includeGridData=true` to read the precise error via `effectiveValue.errorValue`.
- **403/404** – Sheet not shared with the current credentials or Drive scope missing. Use the Drive sharing snippet to grant yourself access.
- **PERMISSION_DENIED / storageQuotaExceeded when creating a sheet** – Service accounts without Google Workspace licensing can’t own Docs. Use user ADC credentials or have the human create the sheet and share it with the service account.
- **429/5xx** – Add exponential backoff and batch multiple `requests` per `batchUpdate`.
- **Locale formatting surprises** – Fetch with `valueRenderOption=UNFORMATTED_VALUE`, write numbers as `USER_ENTERED`, or set `spreadsheetProperties.locale`.
- **Large fetches** – Use `majorDimension=COLUMNS/ROWS` and request only the ranges you need to reduce payload + token usage.

## Checklist Before Finishing
- [ ] Stored `SPREADSHEET_ID` (and any `sheetId`s) in env vars or notes for future steps.
- [ ] Clearly noted whether values were USER_ENTERED or RAW.
- [ ] Logged only minimal JSON needed (use `jq`).
- [ ] Documented any assumptions (e.g., “Sheet locale is en-US”).
- [ ] Shared the Drive file or instructions for the human to access it.
- [ ] Verified ADC/service-account creds before attempting API calls; if missing, halted and instructed the human how to enable them.
- [ ] Service-account flows: sheet shared back to human account (or confirmed they can open it).
