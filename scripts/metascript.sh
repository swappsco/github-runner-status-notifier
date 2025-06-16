#!/bin/bash

# === CONFIGURACIÓN ===
GITHUB_TOKEN="GHTOKEN"
REPO_OWNER="swappsco"
REPOS=("zuckermanlaw" "idk" "dejusticia" "ncarb" "wp-swappscom" "wp-facialart" "wp-facialartdentalforum" )

# === CONFIGURACIÓN CLICKUP ===
CLICKUP_TOKEN="CLICKUPTOKEN"
CLICKUP_WORKSPACE_ID="ID_WORKSPACE"
CLICKUP_CHANNEL_ID="CHANNEL_ID"

# === CONFIGURACIÓN GLOBAL ===
RUNNER_NAME_PREFIX="self-hosted-linux"
FAILURE_TIME_WINDOW_MINUTES=30

check_runner_status() {
  echo "========== Date & time $(date '+%Y-%m-%d %H:%M:%S') =========="
  echo "📡 Verificando estado del runner..."
  RESPONSE=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/orgs/$REPO_OWNER/actions/runners")

  RUNNER_ONLINE=$(echo "$RESPONSE" | jq -e \
    --arg prefix "$RUNNER_NAME_PREFIX" \
    '.runners[] | select((.name | startswith($prefix)) and (.status == "online"))')

  if [[ -n "$RUNNER_ONLINE" ]]; then
    echo -e "🚦✅ Runner $RUNNER_NAME_PREFIX está activo.\n"
    return 0
  else
    echo -e "🚦❌ Runner $RUNNER_NAME_PREFIX está inactivo.\n"
    return 1
  fi
}

check_queued_workflows() {
  echo "🚦 Buscando workflows en cola..."
  local queued_workflows=""
  local has_queued=false

  for repo in "${REPOS[@]}"; do
    echo "🔍 Repositorio: $repo"

    response=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/$REPO_OWNER/$repo/actions/runs?per_page=10")

    queued=$(echo "$response" | jq -r '.workflow_runs[] | select(.status == "queued") | "• \(.name) - \(.html_url)"')
    if [[ -n "$queued" ]]; then
      queued_workflows+="📦 $repo\n$queued\n"
      echo -e "👀 El proyecto: $repo tiene workflows encolados 👀\n"
      has_queued=true
    fi
  done

  if $has_queued; then
    echo "🚦❌ Hay workflows encolados"
    QUEUED_MESSAGE="$queued_workflows"
    return 0
  else
    echo "🚦✅ No hay workflows encolados"
    return 1
  fi
}

check_failed_workflows_recent() {
  echo "❌ Verificando workflows fallidos en los últimos $FAILURE_TIME_WINDOW_MINUTES minutos..."
  local now_epoch=$(date +%s)
  local window_seconds=$((FAILURE_TIME_WINDOW_MINUTES * 60))
  local failed_workflows=""
  local has_failures=false

  for repo in "${REPOS[@]}"; do
    response=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/$REPO_OWNER/$repo/actions/runs?per_page=10")

    while IFS=$'\t' read -r name run_number status conclusion branch created_at html_url; do
      created_epoch=$(date -d "$created_at" +%s 2>/dev/null)
      if [[ -n "$created_epoch" && $((now_epoch - created_epoch)) -le $window_seconds && "$conclusion" == "failure" ]]; then
        failed_workflows+="📦 $repo\n> $name (#$run_number) en \`$branch\`\n> $created_at\n> 🔗 $html_url\n"
        has_failures=true
      fi
    done < <(echo "$response" | jq -r '.workflow_runs[] | [.name, .run_number, .status, .conclusion, .head_branch, .created_at, .html_url] | @tsv')
  done

  if $has_failures; then
    FAILED_MESSAGE="$failed_workflows"
    return 0
  else
    echo "✅ No hay workflows con fallos en la ultima hora"
    return 1
  fi
}

send_clickup_message() {
  local content="$1"
  echo -e "\n📤 Enviando mensajes a ClickUp...\n"
  curl -s -X POST "https://api.clickup.com/api/v3/workspaces/$CLICKUP_WORKSPACE_ID/chat/channels/$CLICKUP_CHANNEL_ID/messages" \
    -H "Authorization: $CLICKUP_TOKEN" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    --data "{
      \"type\": \"message\",
      \"content_format\": \"text/md\",
      \"content\": \"$content\"
    }" >/dev/null
}

main() {
  # Variables globales para almacenar los mensajes
  local QUEUED_MESSAGE=""
  local FAILED_MESSAGE=""

  check_runner_status || send_clickup_message "🖥️ El runner \`$RUNNER_NAME_PREFIX\` está *inactivo ❌*."

  if check_queued_workflows; then
    send_clickup_message "⚠️ *Workflows en cola detectados:*\n$QUEUED_MESSAGE"
  fi

  if check_failed_workflows_recent; then
    send_clickup_message "❌ *Workflows fallidos recientemente:*\n$FAILED_MESSAGE"
  fi
}

echo ""
main
