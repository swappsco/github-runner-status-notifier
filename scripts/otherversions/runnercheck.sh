#!/bin/bash

# === CONFIGURACIÓN ===
GITHUB_TOKEN="GHTOKEN"
REPO_OWNER="swappsco"
REPOS=("zuckermanlaw" "idk" "dejusticia" "ncarb" "wp-swappscom" "wp-facialart" "wp-facialartdentalforum" )

# === CONFIGURACIÓN CLICKUP ===
CLICKUP_TOKEN="CLICKUPTOKEN"
CLICKUP_WORKSPACE_ID="ID_WORKSPACE"
CLICKUP_CHANNEL_ID="CHANNEL_ID"

# =============================
# VERIFICAR RUNNER
# =============================
RUNNER_NAME_PREFIX="self-hosted-linux"

RESPONSE=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/orgs/$REPO_OWNER/actions/runners")
echo "📡 Respuesta de GitHub API:"
echo "$RESPONSE"
# =============================
# ANALIZAR RESPUESTA
# =============================
if echo "$RESPONSE" | jq -e \
  --arg prefix "$RUNNER_NAME_PREFIX" \
  '.runners[] | select((.name | startswith($prefix)) and (.status == "online"))' >/dev/null; then
  STATUS="activo ✅"
else
  STATUS="inactivo ❌"
fi

# =============================
# FORMAR MENSAJE
# =============================
CLICKUP_RUNNER_MSG="🖥️ El runner \`$RUNNER_NAME_PREFIX\` está *$STATUS*."

# =============================
# ENVIAR MENSAJE A CLICKUP
# =============================
curl -s -X POST "https://api.clickup.com/api/v3/workspaces/$CLICKUP_WORKSPACE_ID/chat/channels/$CLICKUP_CHANNEL_ID/messages" \
  -H "Authorization: $CLICKUP_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  --data "{
    \"type\": \"message\",
    \"content_format\": \"text/md\",
    \"content\": \"$CLICKUP_RUNNER_MSG\"
  }" >/dev/null

echo "📨 Mensaje de estado del runner enviado a ClickUp."
echo "$CLICKUP_RUNNER_MSG"
