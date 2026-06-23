#!/usr/bin/env bash
# PreToolUse guardrail for Bash and Edit/Write tools.
# Reads the tool call as JSON on stdin and blocks risky actions with a
# friendly explanation aimed at non-technical users.

set -euo pipefail

input="$(cat)"
tool_name="$(jq -r '.tool_name // ""' <<<"$input")"

block() {
  local reason="$1"
  jq -n --arg reason "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

ask() {
  local reason="$1"
  jq -n --arg reason "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

is_sensitive_path() {
  local path="$1"
  case "$path" in
    *.env|*.env.*|*credentials*|*secrets*|*.pem|*.key|*id_rsa*) return 0 ;;
    */.github/workflows/*|*.gitlab-ci.yml|*Jenkinsfile*|*.circleci/*|*Dockerfile|*docker-compose*.yml) return 0 ;;
    *) return 1 ;;
  esac
}

if [[ "$tool_name" == "Bash" ]]; then
  command="$(jq -r '.tool_input.command // ""' <<<"$input")"

  if grep -qE '(^|[;&|]\s*)rm\s+(-[a-zA-Z]*r[a-zA-Z]*f[a-zA-Z]*|-[a-zA-Z]*f[a-zA-Z]*r[a-zA-Z]*)\s' <<<"$command"; then
    block "I blocked this command because it permanently deletes files and folders, with no way to undo it ('rm -rf'). If you really need to delete something, please double-check the path and ask a developer to confirm, or delete it manually."
  fi

  if grep -qE 'git\s+reset\s+--hard' <<<"$command"; then
    block "I blocked this command because 'git reset --hard' throws away uncommitted work permanently. If you want to discard changes, let's confirm first what you'd be losing."
  fi

  if grep -qE 'git\s+push\s+.*(--force|-f\b)' <<<"$command"; then
    block "I blocked this command because a force push can overwrite other people's work on the remote, permanently losing their commits. If this is really needed, please confirm explicitly and consider --force-with-lease instead."
  fi

  if grep -qE 'git\s+push\b' <<<"$command" && grep -qE '\b(main|master)\b' <<<"$command"; then
    block "I blocked this command because it pushes directly to the main/master branch. Changes to this branch usually go through a pull request so they can be reviewed first."
  fi

  ask "This is a command-line (Bash) action: '$command'. I always check with you before running any Bash command, just so nothing happens on your computer without your okay."
fi

if [[ "$tool_name" == "Edit" || "$tool_name" == "Write" ]]; then
  file_path="$(jq -r '.tool_input.file_path // ""' <<<"$input")"

  if is_sensitive_path "$file_path"; then
    block "I blocked this change because '$file_path' looks like it holds secrets (passwords, API keys) or controls how your project is built/deployed (CI/CD config). Editing it by mistake could break things or expose private information. If this change is intentional, please make it yourself or ask a developer to review it."
  fi
fi

exit 0
