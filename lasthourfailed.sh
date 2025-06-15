#!/bin/bash

# === CONFIGURACIÓN ===
GITHUB_TOKEN="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"
REPO_OWNER="swappsco"                     # Cambia esto según tu organización o usuario
REPOS=("zuckermanlaw" "idk" "dejusticia") # Agrega aquí los repos que quieras analizar

# === CONFIGURACIÓN CLICKUP ===
CLICKUP_TOKEN="pk_88274481_1CA0UT34AZ3K6MOHJ4WLNVQOBI2O4WJ0"
CLICKUP_WORKSPACE_ID="454056"
CLICKUP_CHANNEL_ID="dvd8-39934"

now_epoch=$(date +%s)
limit_seconds=3600
message="❌ *Workflows fallidos en la última hora:*\n"

failures_found=false

for REPO in "${REPOS[@]}"; do
  response=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$REPO_OWNER/$REPO/actions/runs?per_page=10")

  if ! echo "$response" | jq -e '.workflow_runs | length > 0' >/dev/null; then
    continue
  fi

  while read -r name run_number status conclusion branch created_at html_url; do
    created_epoch=$(date -d "$created_at" +%s 2>/dev/null)
    if [[ -n "$created_epoch" && $((now_epoch - created_epoch)) -le $limit_seconds && "$conclusion" == "failure" ]]; then
      if [ "$failures_found" = false ]; then
        failures_found=true
      fi
      message+="\n📦 *$REPO_OWNER/$REPO*\n> ❌ *$name* (#$run_number) en \`$branch\`\n> 🕒 $created_at\n> 🔗 <$html_url>"
    fi
  done < <(echo "$response" | jq -r '.workflow_runs[] | [.name, .run_number, .status, .conclusion, .head_branch, .created_at, .html_url] | @tsv')
done

# === Si no hubo errores encontrados ===
if [ "$failures_found" = false ]; then
  message="✅ No se encontraron workflows fallidos en la última hora."
fi

# === ENVÍA A CLICKUP ===
curl -s --request POST \
  --url "https://api.clickup.com/api/v3/workspaces/$CLICKUP_WORKSPACE_ID/chat/channels/$CLICKUP_CHANNEL_ID/messages" \
  --header "Authorization: $CLICKUP_TOKEN" \
  --header 'accept: application/json' \
  --header 'content-type: application/json' \
  --data "{
    \"type\": \"message\",
    \"content_format\": \"text/md\",
    \"content\": \"$message\"
  }" >/dev/null

echo "📨 Notificación enviada a ClickUp:"
echo "$message"

