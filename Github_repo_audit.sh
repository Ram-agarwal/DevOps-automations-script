#!/bin/bash

###################
# GitHub Repository Audit Script
# Author: Ram Agarwal
# Role  : DevOps Engineer
###################

API_URL="https://api.github.com"
USERNAME="Ram-agarwal"

# 👉 Export token securely before running:
# export GITHUB_TOKEN=ghp_xxxxxxxxxxxxx
TOKEN=ghp_Tocker

REPO_OWNER=$1
REPO_NAME=$2

if [[ -z "$REPO_OWNER" || -z "$REPO_NAME" ]]; then
  echo "Usage: $0 <repo_owner> <repo_name>"
  exit 1
fi

github_api_get() {
  curl -s -u "${USERNAME}:${TOKEN}" "${API_URL}/$1"
}

echo "========================================"
echo "📦 GitHub Repository Report"
echo "========================================"

# ================= Repo Basic Info =================
repo_info=$(github_api_get "repos/${REPO_OWNER}/${REPO_NAME}")

echo "🔹 Repository Details"
echo "----------------------------------------"
echo "Name            : $(echo "$repo_info" | jq -r '.name')"
echo "Owner           : $(echo "$repo_info" | jq -r '.owner.login')"
echo "Description     : $(echo "$repo_info" | jq -r '.description')"
echo "Visibility      : $(echo "$repo_info" | jq -r '.visibility')"
echo "Default Branch  : $(echo "$repo_info" | jq -r '.default_branch')"
echo "Created On      : $(echo "$repo_info" | jq -r '.created_at')"
echo "Last Updated    : $(echo "$repo_info" | jq -r '.updated_at')"
echo "Archived        : $(echo "$repo_info" | jq -r '.archived')"
echo ""

# ================= Recent Contributors (Last 24h) =================
echo "🧑‍💻 Recent Contributors (Last 24h)"
echo "----------------------------------------"

github_api_get "repos/${REPO_OWNER}/${REPO_NAME}/commits?since=$(date -u -d '1 day ago' +%Y-%m-%dT%H:%M:%SZ)" | \
jq -r '.[].commit.author.name' | sort | uniq

echo ""


# ================= Branch Protection =================
default_branch=$(echo "$repo_info" | jq -r '.default_branch')
protection=$(github_api_get "repos/${REPO_OWNER}/${REPO_NAME}/branches/${default_branch}/protection")

echo "🔐 Branch Protection (${default_branch})"
echo "----------------------------------------"

if echo "$protection" | jq -e '.required_pull_request_reviews' >/dev/null 2>&1; then
  echo "Protected Branch : YES"
  echo "✔ PR Review required before merge"
else
  echo "Protected Branch : NO ⚠️"
  echo "⚠ Direct push allowed (Risk)"
fi

echo ""

# ================= Security Alerts (Dependabot) =================
alerts=$(github_api_get "repos/${REPO_OWNER}/${REPO_NAME}/dependabot/alerts" | jq length)

echo "🔐 Security Alerts"
echo "----------------------------------------"
echo "Open Dependabot Alerts : $alerts"
echo ""

# ================= CODEOWNERS Check =================
owners=$(github_api_get "repos/${REPO_OWNER}/${REPO_NAME}/contents/.github/CODEOWNERS" 2>/dev/null)

echo "👤 CODEOWNERS Configuration"
echo "----------------------------------------"

if [[ -n "$owners" ]]; then
  echo "✔ CODEOWNERS file present"
else
  echo "⚠ No CODEOWNERS file (Risk)"
fi

echo ""


# ================= Collaborators =================
echo "👥 Collaborators Access"
echo "----------------------------------------"
github_api_get "repos/${REPO_OWNER}/${REPO_NAME}/collaborators" |
jq -r '.[] | "\(.login) | Read:\(.permissions.pull) Write:\(.permissions.push) Admin:\(.permissions.admin)"'
echo ""

# ================= Issues & PRs =================
open_issues=$(echo "$repo_info" | jq -r '.open_issues_count')
open_prs=$(github_api_get "repos/${REPO_OWNER}/${REPO_NAME}/pulls?state=open" | jq length)

echo "🐞 Issues & Pull Requests"
echo "----------------------------------------"
echo "Open Issues : $open_issues"
echo "Open PRs    : $open_prs"
echo ""

# ================= Branch Info =================
branches=$(github_api_get "repos/${REPO_OWNER}/${REPO_NAME}/branches" | jq length)

echo "🌿 Branch Info"
echo "----------------------------------------"
echo "Total Branches : $branches"
echo ""

# ================= Last Commit =================
last_commit=$(github_api_get "repos/${REPO_OWNER}/${REPO_NAME}/commits?per_page=1")

echo "🕒 Last Commit"
echo "----------------------------------------"
echo "Author  : $(echo "$last_commit" | jq -r '.[0].commit.author.name')"
echo "Date    : $(echo "$last_commit" | jq -r '.[0].commit.author.date')"
echo "Message : $(echo "$last_commit" | jq -r '.[0].commit.message')"
echo ""

# ================= Branch Protection =================
default_branch=$(echo "$repo_info" | jq -r '.default_branch')
protection=$(github_api_get "repos/${REPO_OWNER}/${REPO_NAME}/branches/${default_branch}/protection")

echo "🔐 Branch Protection (${default_branch})"
echo "----------------------------------------"
if echo "$protection" | jq -e '.required_pull_request_reviews' >/dev/null 2>&1; then
  echo "Protected Branch : YES"
else
  echo "Protected Branch : NO ⚠️"
fi
echo ""

# ================= CI/CD Status =================
workflow_runs=$(github_api_get "repos/${REPO_OWNER}/${REPO_NAME}/actions/runs?per_page=1")

echo "🚦 CI/CD Status"
echo "----------------------------------------"
echo "Workflow Name : $(echo "$workflow_runs" | jq -r '.workflow_runs[0].name')"
echo "Status        : $(echo "$workflow_runs" | jq -r '.workflow_runs[0].status')"
echo "Conclusion    : $(echo "$workflow_runs" | jq -r '.workflow_runs[0].conclusion')"
echo ""

# ================= Old PRs =================
echo "⏳ Old Open Pull Requests (>7 days)"
echo "----------------------------------------"
github_api_get "repos/${REPO_OWNER}/${REPO_NAME}/pulls?state=open" |
jq -r '.[] |
select((now - (.created_at | fromdateiso8601)) > 604800) |
"- \(.title) | Created: \(.created_at) | Author: \(.user.login)"'
echo ""

# ================= Admin Users =================
echo "🧑‍💼 Admin Access Users"
echo "----------------------------------------"
github_api_get "repos/${REPO_OWNER}/${REPO_NAME}/collaborators" |
jq -r '.[] | select(.permissions.admin == true) | "- \(.login)"'
echo ""

# ================= Repo Health Summary =================
echo "📊 Repo Health Summary"
echo "----------------------------------------"
echo "Repo Active      : YES"
echo "Branch Protected : $(echo "$protection" | jq -e '.required_pull_request_reviews' >/dev/null 2>&1 && echo YES || echo NO)"
echo "CI Status        : $(echo "$workflow_runs" | jq -r '.workflow_runs[0].conclusion')"
echo "Open Issues      : $open_issues"
echo "Open PRs         : $open_prs"
echo ""

echo "✅ Report Generated Successfully"
echo "========================================"

