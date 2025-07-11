#!/bin/bash

# === CONFIGURACIÓN ===
GITHUB_TOKEN="GHTOKEN"
REPO_OWNER="swappsco"
REPOS=("zuckermanlaw" "idk" "dejusticia" "ncarb" "wp-swappscom" "wp-facialart" "wp-facialartdentalforum" )

# === CONFIGURACIÓN CLICKUP ===
CLICKUP_TOKEN="CLICKUPTOKEN"
CLICKUP_WORKSPACE_ID="ID_WORKSPACE"
CLICKUP_CHANNEL_ID="CHANNEL_ID"

# Lista de repos en formato owner/repo
REPOS=(
  "swappsco/zuckermanlaw"
  "swappsco/dejusticia"
  "swappsco/idk"
)

# Mensaje final
message="📋 *Resumen de los últimos 5 workflows por repositorio*\n\n"

for repo in "${REPOS[@]}"; do
  response=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$repo/actions/runs?per_page=5")

  if ! echo "$response" | jq -e '.workflow_runs' >/dev/null 2>&1; then
    message+="📦 *$repo*\n⚠️ No se pudo obtener workflows.\n\n"
    continue
  fi

  repo_section="📦 *$repo*\n"

  run_count=$(echo "$response" | jq '.workflow_runs | length')

  for i in $(seq 0 $((run_count - 1))); do
    name=$(echo "$response" | jq -r ".workflow_runs[$i].name")
    status=$(echo "$response" | jq -r ".workflow_runs[$i].status")
    conclusion=$(echo "$response" | jq -r ".workflow_runs[$i].conclusion")
    created=$(echo "$response" | jq -r ".workflow_runs[$i].created_at")
    run_number=$(echo "$response" | jq -r ".workflow_runs[$i].run_number")
    url=$(echo "$response" | jq -r ".workflow_runs[$i].html_url")

    emoji="ℹ️"
    [[ "$conclusion" == "success" ]] && emoji="✅"
    [[ "$conclusion" == "failure" ]] && emoji="❌"
    [[ "$conclusion" == "cancelled" ]] && emoji="🚫"

    repo_section+="$emoji  *$name* (#$run_number)\n• *Status:* $status\n• *Conclusión:* $conclusion\n• *Hora:* $created\n• 🔗 <$url>\n\n"
  done

  message+="$repo_section\n"
done

# === Enviar a ClickUp ===
curl -s --request POST \
  --url "https://api.clickup.com/api/v3/workspaces/$CLICKUP_WORKSPACE_ID/chat/channels/$CLICKUP_CHANNEL_ID/messages" \
  --header "Authorization: $CLICKUP_TOKEN" \
  --header "Content-Type: application/json" \
  --data "{
       \"type\": \"message\",
       \"content_format\": \"text/md\",
       \"content\": \"$message\"
     }" >/dev/null

echo "✅ Mensaje enviado a ClickUp."
