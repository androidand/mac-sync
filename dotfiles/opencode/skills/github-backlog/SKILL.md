---
name: github-backlog
description: Query and manage the ExopenGitHub Product backlog on GitHub Projects v2
license: MIT
compatibility: opencode
metadata:
  org: ExopenGitHub
  project: "6"
---

## Defaults

All operations target this project unless explicitly overridden:

- **Organization**: ExopenGitHub
- **Project number**: 6
- **Project node ID**: `PVT_kwDOBFiKmc05Iw`
- **Board URL**: https://github.com/orgs/ExopenGitHub/projects/6
- **My view**: https://github.com/orgs/ExopenGitHub/projects/6/views/45?sliceBy%5Bvalue%5D=androidand

### User identity

- **GitHub username**: androidand
- **Email**: andreas.sylvan@exopen.se
- **Git config**: `user.email = andreas.sylvan@exopen.se`

Always use `andreas.sylvan@exopen.se` for any GitHub operation (commits, issues, etc.). When "assign to me" is requested, use username `androidand`.

Always use this project when creating, querying, or updating backlog items.

## Hard rules

1. **NEVER create draft issues.** Always create real issues in a repository using `gh issue create --repo ExopenGitHub/<repo>`. Draft issues lack a repo tag and break board filtering.
2. **Always tag with a repository.** Every task must be created as an issue in the correct repo. Infer the repo from the prompt context (see Repository tagging below). If ambiguous, ask the user.
3. **Prefer `gh` CLI over MCP tools for creating issues.** The `gh issue create` command is simpler, more reliable, and automatically handles authentication. Use MCP tools for project-specific operations (adding to board, setting fields).
4. **Always set Initiative.** Every new item must have an Initiative set.
5. **Always set Status.** Default to "Ready for development" unless told otherwise.
6. **Always assign.** If the user says "assign to me", use `--assignee androidand`. Otherwise ask who to assign.
7. **Always create a linked branch** after creating an issue, unless the task is non-code or the user says otherwise. Use the naming convention `feat/{issueNumber}-{slug}`. See Step 6.

## Workflow: Creating issues

This is the exact sequence to follow. Do not skip steps or reorder.

### Step 1: Determine the repository

Analyze the prompt and match against the repo table below. If unclear, ask.

### Step 2: Create the issue with `gh issue create`

```bash
gh issue create \
  --repo ExopenGitHub/<repo> \
  --title "<title>" \
  --body "<markdown body>" \
  --assignee androidand
```

Use the issue body template below for consistent formatting.

### Step 3: Get the issue node ID

```bash
gh api graphql -f query='
query {
  repository(owner: "ExopenGitHub", name: "<repo>") {
    issue(number: <NUMBER>) { id }
  }
}'
```

### Step 4: Add to the project board

```bash
gh api graphql -f query='
mutation {
  addProjectV2ItemById(input: {
    projectId: "PVT_kwDOBFiKmc05Iw"
    contentId: "<ISSUE_NODE_ID>"
  }) { item { id } }
}'
```

### Step 5: Set Status and Initiative

Use the item ID from step 4 to set both fields in a single mutation:

```bash
gh api graphql -f query='
mutation {
  status: updateProjectV2ItemFieldValue(input: {
    projectId: "PVT_kwDOBFiKmc05Iw"
    itemId: "<ITEM_ID>"
    fieldId: "PVTSSF_lADOBFiKmc05I84AAZvX"
    value: { singleSelectOptionId: "<STATUS_OPTION_ID>" }
  }) { projectV2Item { id } }

  initiative: updateProjectV2ItemFieldValue(input: {
    projectId: "PVT_kwDOBFiKmc05Iw"
    itemId: "<ITEM_ID>"
    fieldId: "PVTSSF_lADOBFiKmc05I84NNwl6"
    value: { singleSelectOptionId: "<INITIATIVE_OPTION_ID>" }
  }) { projectV2Item { id } }
}'
```

### Step 6: Create a linked branch

After adding the issue to the board, create a feature branch in the local repo and push it. GitHub automatically links branches containing the issue number to the issue.

**Branch naming convention**: `feat/{issueNumber}-{slug}`

The slug is a short kebab-case summary derived from the issue title (max 5 words, lowercase, hyphens).

Examples:
- Issue #3200 "Add ER modeling for e-conomic" → `feat/3200-er-modeling-e-conomic`
- Issue #3201 "Fix Fortnox token refresh" → `feat/3201-fix-fortnox-token-refresh`

#### 6a. Check for existing branches first

Before creating a branch, always check if one already exists for this issue (locally or on the remote). A branch may exist if the issue was previously worked on, or if someone already started on it.

```bash
REPO_DIR="$WORKSPACE_ROOT/<local_folder>"
cd "$REPO_DIR"
git fetch origin

# Check remote branches for the issue number
EXISTING=$(git branch -r --list "*/<ISSUE_NUMBER>*" | head -1)
```

Also check by topic/name similarity -- sometimes branches exist for the same work but without the issue number:

```bash
git branch -r --list "*e-conomic*" --list "*er-modeling*" | head -5
```

If a likely match is found, warn the user and ask before proceeding.

#### 6b. Create or link the branch

**Use `gh issue develop`** to create branches. This command both creates the branch AND links it to the issue under the "Development" section on GitHub.

**If no existing branch:**

```bash
gh issue develop <ISSUE_NUMBER> \
  --repo ExopenGitHub/<repo> \
  --name "feat/<ISSUE_NUMBER>-<slug>" \
  --base <default_branch>
```

Then check it out locally:
```bash
cd "$REPO_DIR"
git fetch origin
git checkout feat/<ISSUE_NUMBER>-<slug>
```

**If an existing branch was found:**

`gh issue develop` cannot link an existing branch. The workaround is:

1. Save the branch HEAD SHA
2. Delete the remote branch via API
3. Use `gh issue develop` to create and link it (creates from base)
4. Force push the original SHA back to restore commits

```bash
# Save current SHA
SHA=$(gh api repos/ExopenGitHub/<repo>/git/ref/heads/<branch> --jq '.object.sha')

# Delete remote branch
gh api -X DELETE repos/ExopenGitHub/<repo>/git/refs/heads/<branch>

# Create and link
gh issue develop <ISSUE_NUMBER> \
  --repo ExopenGitHub/<repo> \
  --name "<branch>" \
  --base <default_branch>

# Restore commits
git push --force origin "$SHA:refs/heads/<branch>"
```

#### 6c. Verify the link

Always verify the branch appears in the issue's Development section:

```bash
gh issue develop --list <ISSUE_NUMBER> --repo ExopenGitHub/<repo>
```

**Skip branch creation when:**
- The issue is purely organizational (docs, process, non-code)
- The user explicitly says "no branch" or "ticket only"
- The local repo directory is not available

### Step 7: Report back

Print a summary with:
- Issue URL
- Repository
- Status
- Initiative
- Assignee
- Branch name and link status (created / existing / linked)

## Issue body template

Use this markdown structure for all issue bodies. Adjust sections to fit the task — remove sections that don't apply, but keep the structure consistent.

```markdown
## Description

<1-3 sentences describing what needs to be done and why>

## Context

- <Relevant background, links to related issues, or prior work>
- <File paths, modules, or areas of the codebase affected>

## Acceptance criteria

- [ ] <Concrete, verifiable outcome>
- [ ] <Another outcome>
```

Keep it concise. Don't pad with boilerplate. If the user provides a short prompt, write a short description — don't inflate it.

## Cached field IDs

### Status
- Field ID: `PVTSSF_lADOBFiKmc05I84AAZvX`
- Options:
  - `98236657` = Ready for development
  - `ee832dd0` = In progress
  - `dce8b7f5` = Done

### Initiative
- Field ID: `PVTSSF_lADOBFiKmc05I84NNwl6`
- Options:
  - `6d1109db` = V7 - Phase 1
  - `30e9d796` = V7 - Phase 2
  - `c8e0a052` = V7 - Phase 3
  - `fc239093` = V7 - Phase 4
  - `7638587b` = V7 - Phase 5
  - `9ce3281f` = Kill the ETL
  - `7e3c6a34` = Complete Payload
  - `f7408bc5` = Integrations
  - `bdea0d09` = IC Tech
  - `3a22debe` = Cloud Platform Modules
  - `4ac5048b` = Cloud Platform
  - `f1bd264e` = Customer Data Enrichment
  - `6833f7d7` = Technical UX
  - `633539ab` = Security

### Other fields
- Title: `PVTF_lADOBFiKmc05I84AAZvV`
- Assignees: `PVTF_lADOBFiKmc05I84AAZvW`
- Labels: `PVTF_lADOBFiKmc05I84AAZvY`
- Repository: `PVTF_lADOBFiKmc05I84AAZvZ`
- Start date: `PVTF_lADOBFiKmc05I84NMOlU`
- Target date: `PVTF_lADOBFiKmc05I84NMOnO`

## Repository tagging

Every task MUST be linked to a repository. Analyze the prompt for keywords, feature names, file paths, or technology references and match against the table below. If ambiguous, ask the user.

The **Workspace root** is the parent directory of all repos (typically `~/exopen`). The `WORKSPACE_ROOT` env var is set by `backlog.sh`. The **Local path** column gives the absolute path to each repo as `$WORKSPACE_ROOT/<folder>`.

| Local folder | GitHub repo | Default branch | Keywords / signals |
|---|---|---|---|
| FusionHub | ExopenGitHub/FusionHub | main | integrations, sync, data pipeline, source systems, ER modeling, events, service bus, fortnox, visma, e-conomic, netvisor, tripletex, xero, poweroffice, prisma, sync jobs |
| eldvakt | ExopenGitHub/eldvakt | main | AI chat, Teams notification, Fastify, chat backend, access control |
| portal | ExopenGitHub/portal | main | frontend, React, Vite, UI, data-sources page, company domains, portal |
| Pumpstation | ExopenGitHub/Pumpstation | master | user management, company management, C#, .NET, email sending, admin emails |
| nexus | ExopenGitHub/nexus | master | infra, internal tooling, deployment, CI/CD, finance mart |
| eox7 | ExopenGitHub/eox7 | main | report app, v7, reports, selections, Excel |
| excel-addin | ExopenGitHub/excel-addin | main | Excel add-in, v6, spreadsheet |
| ExoKit | ExopenGitHub/ExoKit | main | shared libraries, kit, SDK |
| consolidation | ExopenGitHub/consolidation | main | consolidation, group reporting |
| planning-api | ExopenGitHub/planning-api | main | planning, budgeting, forecasting |
| pegasus | ExopenGitHub/pegasus | main | pegasus |
| NodeTools | ExopenGitHub/NodeTools | main | node tools, utilities |
| metaverse | ExopenGitHub/metaverse | main | metaverse, wow, way of working |
| mail-templates | ExopenGitHub/mail-templates | main | email templates, mail templates |
| it | ExopenGitHub/it | main | IT operations, internal IT |

## Querying items

### List items by status

```bash
gh project item-list 6 --owner ExopenGitHub --limit 50 --format json
```

### Query with field filters (GraphQL)

```bash
gh api graphql -f query='
query {
  organization(login: "ExopenGitHub") {
    projectV2(number: 6) {
      items(first: 50) {
        nodes {
          id
          content {
            ... on Issue { title number repository { name } url }
            ... on DraftIssue { title }
          }
          fieldValues(first: 10) {
            nodes {
              ... on ProjectV2ItemFieldSingleSelectValue {
                name
                field { ... on ProjectV2SingleSelectField { name } }
              }
              ... on ProjectV2ItemFieldUserValue {
                users(first: 5) { nodes { login } }
              }
            }
          }
        }
      }
    }
  }
}'
```

## Batch operations

When creating multiple issues, run the `gh issue create` commands in parallel, then batch the GraphQL mutations (add to project + set fields) into a single call using aliases:

```bash
gh api graphql -f query='
mutation {
  add1: addProjectV2ItemById(input: { projectId: "PVT_kwDOBFiKmc05Iw", contentId: "<ID1>" }) { item { id } }
  add2: addProjectV2ItemById(input: { projectId: "PVT_kwDOBFiKmc05Iw", contentId: "<ID2>" }) { item { id } }
}'
```

Then set fields for all items in another batched mutation.

## Error recovery

- **Stale field IDs**: re-run `gh project field-list 6 --owner ExopenGitHub`
- **Permission denied**: verify `project` scope with `gh auth status`
- **Rate limited**: batch mutations into fewer GraphQL calls
- **Issue created but not on board**: run step 4 manually with the issue node ID
- **Branch creation fails (dirty working tree)**: stash or warn the user; never force-checkout
- **Branch already exists on remote**: report it and skip creation; ask the user if they want to check it out
- **Similar branch exists without issue number**: warn and ask before creating a new one -- may be duplicate work
