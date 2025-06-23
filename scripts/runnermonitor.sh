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

# === CONFIGURACIÓN GLOBAL ===
RUNNER_NAME_PREFIX="self-hosted-linux"
FAILURE_TIME_WINDOW_MINUTES=10
STATE_FILE="/tmp/github_actions_monitor_state.json"

# Inicializar el archivo de estado si no existe
initialize_state_file() {
	if [[ ! -f "$STATE_FILE" ]]; then
		echo '{
			"runner": {
				"last_status": null,
				"notified_down": false,
				"notified_up": false
			},
			"queued": {
				"last_count": 0,
				"notified": false
			},
			"failed": {
				"last_count": 0,
				"notified": false
			}
		}' > "$STATE_FILE"
	fi
}

# Leer el estado anterior
read_state() {
	jq -c '.' "$STATE_FILE"
}

# Actualizar el estado
update_state() {
	local new_state="$1"
	echo "$new_state" > "$STATE_FILE"
}

check_runner_status() {
	echo "========== Date & time $(date '+%Y-%m-%d %H:%M:%S') =========="
	echo "📡 Verificando estado del runner..."

	local current_status="offline"
	RESPONSE=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
		-H "Accept: application/vnd.github+json" \
		"https://api.github.com/orgs/$REPO_OWNER/actions/runners")

	# Validar que la respuesta sea válida y contenga el campo .runners
	if ! echo "$RESPONSE" | jq -e '.runners' >/dev/null 2>&1; then
		echo "⚠️ No se pudo obtener información del runner."
		notify_authentication_failure "verificación del estado del runner"
		return 1
	fi

	RUNNER_ONLINE=$(echo "$RESPONSE" | jq -e \
		--arg prefix "$RUNNER_NAME_PREFIX" \
		'.runners[] | select((.name | startswith($prefix)) and (.status == "online"))')

	if [[ -n "$RUNNER_ONLINE" ]]; then
		echo -e "🚦✅ Runner $RUNNER_NAME_PREFIX está activo.\n"
		current_status="online"
	else
		echo -e "🚦❌ Runner $RUNNER_NAME_PREFIX está inactivo.\n"
	fi

	# Leer estado anterior
	local state=$(read_state)
	local last_status=$(echo "$state" | jq -r '.runner.last_status')
	local notified_down=$(echo "$state" | jq -r '.runner.notified_down')
	local notified_up=$(echo "$state" | jq -r '.runner.notified_up')

	# Determinar qué mensaje enviar (si corresponde)
	local message=""
	if [[ "$current_status" == "offline" && "$notified_down" == "false" ]]; then
		message="🖥️ El runner \`$RUNNER_NAME_PREFIX\` está *inactivo ❌*."
		# Actualizar estado
		state=$(echo "$state" | jq '.runner.notified_down = true | .runner.notified_up = false')
	elif [[ "$current_status" == "online" && "$last_status" == "offline" && "$notified_up" == "false" ]]; then
		message="🖥️ El runner \`$RUNNER_NAME_PREFIX\` está *activo nuevamente ✅*."
		# Actualizar estado
		state=$(echo "$state" | jq '.runner.notified_up = true | .runner.notified_down = false')
	fi

	# Actualizar el estado actual
	state=$(echo "$state" | jq --arg status "$current_status" '.runner.last_status = $status')
	update_state "$state"

	# Enviar mensaje si corresponde
	if [[ -n "$message" ]]; then
		send_clickup_message "$message"
	fi

	return $([[ "$current_status" == "online" ]])
}

check_queued_workflows() {
	echo "🚦 Buscando workflows en cola..."
	local current_queued=0
	local queued_details=""

	for repo in "${REPOS[@]}"; do
		echo "🔍 Repositorio: $repo"

		response=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
			-H "Accept: application/vnd.github+json" \
			"https://api.github.com/repos/$REPO_OWNER/$repo/actions/runs?per_page=10")

		# Validar respuesta
		if ! echo "$response" | jq -e '.workflow_runs' >/dev/null 2>&1; then
			echo "⚠️ No se pudo obtener workflows de $repo."
			notify_authentication_failure "verificación de workflows en cola"
			return 1
		fi

		queued=$(echo "$response" | jq -r '[.workflow_runs[] | select(.status == "queued")] | length')
		if [[ -n "$queued" && "$queued" -gt 0 ]]; then
			current_queued=$((current_queued + queued))
			details=$(echo "$response" | jq -r '.workflow_runs[] | select(.status == "queued") | "• \(.name) - \(.html_url)"')
			queued_details+="📦 $repo ($queued)\n$details\n"
			echo -e "👀 El proyecto: $repo tiene $queued workflows encolados 👀\n"
		fi
	done

	# Leer estado anterior
	local state=$(read_state)
	local last_count=$(echo "$state" | jq -r '.queued.last_count')
	local notified=$(echo "$state" | jq -r '.queued.notified')

	# Determinar qué mensaje enviar (si corresponde)
	local message=""
	if [[ "$current_queued" -gt 0 && "$notified" == "false" ]]; then
		message="⚠️ *Workflows en cola detectados:* ($current_queued)\n$queued_details"
		# Actualizar estado
		state=$(echo "$state" | jq '.queued.notified = true')
	elif [[ "$current_queued" -eq 0 && "$last_count" -gt 0 ]]; then
		message="✅ *Ya no hay workflows en cola*"
		# Actualizar estado
		state=$(echo "$state" | jq '.queued.notified = false')
	fi

	# Actualizar el estado actual
	state=$(echo "$state" | jq --argjson count "$current_queued" '.queued.last_count = $count')
	update_state "$state"

	# Enviar mensaje si corresponde
	if [[ -n "$message" ]]; then
		send_clickup_message "$message"
	fi

	return $([[ "$current_queued" -eq 0 ]])
}

check_failed_workflows_recent() {
	echo "❌ Verificando workflows fallidos en los últimos $FAILURE_TIME_WINDOW_MINUTES minutos..."
	local now_epoch=$(date +%s)
	local window_seconds=$((FAILURE_TIME_WINDOW_MINUTES * 60))
	local current_failed=0
	local failed_details=""

	for repo in "${REPOS[@]}"; do
		response=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
			-H "Accept: application/vnd.github+json" \
			"https://api.github.com/repos/$REPO_OWNER/$repo/actions/runs?per_page=10")

		# Validar respuesta
		if ! echo "$response" | jq -e '.workflow_runs' >/dev/null 2>&1; then
			echo "⚠️ No se pudo obtener workflows fallidos de $repo."
			notify_authentication_failure "verificación de workflows fallidos"
			return 1
		fi

		repo_failed=0
		while IFS=$'\t' read -r name run_number status conclusion branch created_at html_url; do
			created_epoch=$(date -d "$created_at" +%s 2>/dev/null)
			if [[ -n "$created_epoch" && $((now_epoch - created_epoch)) -le $window_seconds && "$conclusion" == "failure" ]]; then
				repo_failed=$((repo_failed + 1))
				failed_details+="📦 $repo\n> $name (#$run_number) en \`$branch\`\n> $created_at\n> 🔗 $html_url\n"
			fi
		done < <(echo "$response" | jq -r '.workflow_runs[] | [.name, .run_number, .status, .conclusion, .head_branch, .created_at, .html_url] | @tsv')

		if [[ "$repo_failed" -gt 0 ]]; then
			current_failed=$((current_failed + repo_failed))
			echo -e "❌ El proyecto: $repo tiene $repo_failed workflows fallidos\n"
		fi
	done

	# Leer estado anterior
	local state=$(read_state)
	local last_count=$(echo "$state" | jq -r '.failed.last_count')
	local notified=$(echo "$state" | jq -r '.failed.notified')

	# Solo notificar si hay fallos y no se había notificado antes
	if [[ "$current_failed" -gt 0 && "$notified" == "false" ]]; then
		send_clickup_message "❌ *Workflows fallidos recientemente:* ($current_failed)\n$failed_details"
		# Actualizar estado
		state=$(echo "$state" | jq '.failed.notified = true | .failed.last_count = $current_failed' --argjson current_failed "$current_failed")
		update_state "$state"
	elif [[ "$current_failed" -eq 0 && "$last_count" -gt 0 ]]; then
		# Resetear el estado de notificación si ya no hay fallos
		state=$(echo "$state" | jq '.failed.notified = false | .failed.last_count = 0')
		update_state "$state"
	fi

	return $([[ "$current_failed" -eq 0 ]])
}

send_clickup_message() {
	local content="$1"
	echo -e "\n📤 Enviando mensaje a ClickUp:\n$content\n"
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

notify_authentication_failure() {
	local context="$1"
	send_clickup_message "🚫 *Fallo de autenticación con GitHub API durante:* $context\nRevise si el token ha expirado o es inválido."
}

main() {
	initialize_state_file

	check_runner_status
	check_queued_workflows
	check_failed_workflows_recent
}

echo ""
main