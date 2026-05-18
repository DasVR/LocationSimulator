#!/bin/bash
set -euo pipefail

# Monitor GitHub Actions CI for LocationSimulator
# Usage: ./monitor-ci.sh [--watch] [--limit N]
#   --watch    Poll every 10 seconds until the run completes
#   --limit N  Show N recent runs (default: 5)

REPO="DasVR/LocationSimulator"
WORKFLOW="iOS CI"
WATCH=false
LIMIT=5

while [[ $# -gt 0 ]]; do
  case "$1" in
    --watch)
      WATCH=true
      shift
      ;;
    --limit)
      LIMIT="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--watch] [--limit N]"
      exit 1
      ;;
  esac
done

# Fetch recent runs and extract the latest one
LATEST_RUN=$(gh run list --repo "$REPO" --workflow "$WORKFLOW" --limit 1 --json databaseId,status,conclusion,displayTitle,createdAt,headBranch 2>/dev/null || echo "[]")

if [[ "$LATEST_RUN" == "[]" || -z "$LATEST_RUN" ]]; then
  echo "No CI runs found for $WORKFLOW"
  exit 1
fi

RUN_ID=$(echo "$LATEST_RUN" | jq -r '.[0].databaseId')
RUN_STATUS=$(echo "$LATEST_RUN" | jq -r '.[0].status')
RUN_CONCLUSION=$(echo "$LATEST_RUN" | jq -r '.[0].conclusion')
RUN_TITLE=$(echo "$LATEST_RUN" | jq -r '.[0].displayTitle')
RUN_CREATED=$(echo "$LATEST_RUN" | jq -r '.[0].createdAt')
RUN_BRANCH=$(echo "$LATEST_RUN" | jq -r '.[0].headBranch')

echo "========================================"
echo "  CI Monitor -- $WORKFLOW"
echo "========================================"
echo "Commit:   $RUN_TITLE"
echo "Branch:   $RUN_BRANCH"
echo "Run ID:   $RUN_ID"
echo "Created:  $RUN_CREATED"
echo "Status:   $RUN_STATUS"
if [[ "$RUN_CONCLUSION" != "null" ]]; then
  echo "Result:   $RUN_CONCLUSION"
fi
echo "URL:      https://github.com/$REPO/actions/runs/$RUN_ID"
echo ""

# Show job step status
echo "Job Steps:"
echo "----------------------------------------"
gh run view "$RUN_ID" --repo "$REPO" | grep -E "^[[:space:]]*[✓✗\*]" || true
echo ""

# If watching, poll until completion
if [[ "$WATCH" == "true" && "$RUN_STATUS" == "in_progress" ]]; then
  echo "Watching run $RUN_ID..."
  echo ""

  while true; do
    # Refresh run status
    CURRENT_STATUS=$(gh run view "$RUN_ID" --repo "$REPO" --json status,conclusion 2>/dev/null | jq -r '.status')
    CURRENT_CONCLUSION=$(gh run view "$RUN_ID" --repo "$REPO" --json status,conclusion 2>/dev/null | jq -r '.conclusion')

    if [[ "$CURRENT_STATUS" != "in_progress" ]]; then
      echo ""
      echo "Run $RUN_ID completed: $CURRENT_CONCLUSION"
      echo ""
      echo "Final job steps:"
      gh run view "$RUN_ID" --repo "$REPO" | grep -E "^[[:space:]]*[✓✗\*]" || true
      echo ""
      echo "Full logs: https://github.com/$REPO/actions/runs/$RUN_ID"
      break
    fi

    sleep 10
  done
fi
