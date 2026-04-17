---
description: Check failing integrations in App Insights and sync with GitHub backlog
---

Load the github-backlog skill first.

## Task

Query Azure Application Insights for failing FusionHub integrations and ensure each failing integration has a tracked GitHub issue.

## Steps

### 1. Query App Insights for failures

Run this exact command:

```bash
az monitor app-insights query \
  --app appi-fusionhub-prod \
  --resource-group rg-fusionhub-prod \
  --analytics-query '
traces
| where timestamp > ago(24h)
| where customDimensions.scope == "JobService" and customDimensions.status == "FAILED"
| extend jobId = tostring(customDimensions.jobId)
| extend jobName = tostring(customDimensions.name)
| extend errJson = parse_json(tostring(customDimensions.err))
| extend errorMessage = tostring(errJson.message)
| join kind=inner (
    traces
    | where timestamp > ago(24h)
    | where customDimensions has "integrationId"
    | extend integrationId = tostring(customDimensions.integrationId)
    | extend companyDomainId = tostring(customDimensions.companyDomainId)
    | extend jobId = tostring(customDimensions.jobId)
    | where isnotempty(integrationId)
    | distinct jobId, integrationId, companyDomainId
) on jobId
| summarize
    failureCount = count(),
    firstFailure = min(timestamp),
    lastFailure = max(timestamp),
    jobIds = make_set(jobId, 5),
    errors = make_set(errorMessage, 3)
    by integrationId, companyDomainId, jobName
| order by failureCount desc
' -o json
```

The result rows have columns: `integrationId`, `companyDomainId`, `jobName`, `failureCount`, `firstFailure`, `lastFailure`, `jobIds`, `errors`.

### 2. For each failing integration, search GitHub for existing issue

Search for an open issue in ExopenGitHub/FusionHub with the title prefix pattern:
`[Failing] JOBNAME (integration INTEGRATIONID)`

Use: `gh search issues "[Failing] (integration INTEGRATIONID)" --repo ExopenGitHub/FusionHub --state open`

### 3. Create or update

**If no existing issue**: Create a new issue following the github-backlog skill workflow:

Title: `[Failing] {jobName} (integration {integrationId})`

Body:
```markdown
## Failing integration

| Field | Value |
|---|---|
| Integration ID | {integrationId} |
| Company Domain | {companyDomainId} |
| Job Name | {jobName} |
| Portal URL | https://exopen.app/company-domains/{companyDomainId}/data-sources/{integrationId} |
| Failure count (24h) | {failureCount} |
| First failure | {firstFailure} |
| Last failure | {lastFailure} |

## Error

{most recent error message}

## Job IDs

{list of failing job IDs}
```

Set:
- Repository: ExopenGitHub/FusionHub
- Status: Ready for development
- Initiative: Integrations
- Assignee: androidand

**If existing issue**: Add a comment with the latest failure data:

```markdown
## Update {date}

Still failing. {failureCount} failures in last 24h.

Latest error: {errorMessage}

Job IDs: {jobIds}
```

### 4. Report summary

Print a table of all failing integrations with their status (new ticket created / existing ticket updated / already tracked).

$ARGUMENTS
