# 🖥️ GitHub Runner & Workflow Monitor

This Bash script checks the status of a GitHub self-hosted runner and analyzes GitHub Actions workflows across multiple repositories. If issues are detected, it sends alerts to a ClickUp chat channel.

---

## 🔧 Configuration

The script relies on environment variables declared at the top:

- `GITHUB_TOKEN`: GitHub PAT with repository and actions scope.
- `REPO_OWNER`: GitHub org or user.
- `REPOS`: List of repositories to monitor.
- `CLICKUP_TOKEN`: ClickUp API token.
- `CLICKUP_WORKSPACE_ID`: Target ClickUp workspace ID.
- `CLICKUP_CHANNEL_ID`: ClickUp chat channel ID.
- `RUNNER_NAME_PREFIX`: Prefix used to identify the runner.
- `FAILURE_TIME_WINDOW_MINUTES`: Time window to check for recent workflow failures.

---

## 🚀 What It Does

### 1. Check Runner Status

Uses the GitHub API to list runners for the organization and checks if any runner matching `RUNNER_NAME_PREFIX` is online.

### 2. Detect Queued Workflows

Queries the latest workflow runs for each repository and flags any workflows with status `queued`.

### 3. Detect Recent Failed Workflows

Filters workflow runs that:
- Have status `completed`
- Have conclusion `failure`
- Were created within the last X minutes

### 4. Notify via ClickUp

For any failure, queue, or offline runner, a Markdown-formatted message is sent to ClickUp using their Chat API.

---


### ⚙️ Technical Overview

#### 1. **Runner Availability Check**
- **API Endpoint:** `GET /orgs/{org}/actions/runners`
- **Logic:**
  - Filters runners whose names start with a configured prefix (e.g. `self-hosted-linux`).
  - Matches runners with `.status == "online"`.
  - If no matching online runner is found, a warning is sent to ClickUp.
- **Tooling:** Uses `jq` to parse and filter JSON output from GitHub's API.

#### 2. **Queued Workflows Detection**
- **API Endpoint:** `GET /repos/{owner}/{repo}/actions/runs?per_page=10`
- **Logic:**
  - Loops through all listed repositories (`REPOS` array).
  - Scans the latest 10 workflow runs per repo.
  - Extracts workflows with `.status == "queued"`.
  - Aggregates and formats the output per repository.
  - Sends a message to ClickUp if any queued workflows are found.

#### 3. **Recent Failed Workflows**
- **API Endpoint:** `GET /repos/{owner}/{repo}/actions/runs?per_page=10`
- **Logic:**
  - Calculates current epoch time and compares with `.created_at` timestamps.
  - Filters runs where `.conclusion == "failure"` and the run occurred within the last **X minutes** (configurable via `FAILURE_TIME_WINDOW_MINUTES`).
  - Outputs metadata: workflow name, number, branch, time, and a link.
  - Sends alert to ClickUp if recent failures are found.

#### 4. **ClickUp Message Dispatch**
- **API Endpoint:** `POST /api/v3/workspaces/{workspace_id}/chat/channels/{channel_id}/messages`
- **Payload Format:**
  - Markdown (`content_format: "text/md"`)
  - Authenticated with a ClickUp token.
- **Behavior:**
  - Sends one message per detected issue (offline runner, queued workflows, or failures).
  - Messages are concise, readable, and actionable.

---

## 🧪 Example Output

- Runner status: `✅ active` or `❌ inactive`
- Queued workflows:
  ```
  📦 zuckermanlaw
  • deploy - https://github.com/...
  ```
- Failed workflows:
  ```
  📦 dejusticia
  > deploy (#123) on `main`
  > 2025-06-15 10:43:21
  > 🔗 https://github.com/...
  ```

---

## 📦 Dependencies

- `curl`
- `jq`
- Bash 4+

---

## Creating the Access Token (PAT) to Query Self-hosted Runners

Before executing the workflow, a **Personal Access Token (PAT)** was manually created from:

🔗 [https://github.com/settings/personal-access-tokens](https://github.com/settings/personal-access-tokens)

This token was generated following the **principle of least privilege**, meaning it includes **only the strictly necessary permissions** to query the status of runners within the organization.

### Required Scopes

According to the [official GitHub Actions documentation](https://docs.github.com/actions/using-github-hosted-runners/about-github-hosted-runners), the following scopes are required:

- ✅ `read:org` → To read organization settings.
- ✅ `read:actions` → To access runner status.
- ✅ `read:user` → Implicit in many cases.
- ✅ `metadata` → Required for API access.

> ⚠️ **This token does not have write permissions or the ability to modify settings**, making it **safe to use** in this read-only context.

---

## 🧠 State Tracking and Notification Logic

### 🗂️ State Persistence via Temporary File

The script uses a temporary JSON file (`$STATE_FILE`) to persist the **last known state** of each monitored component between runs. This enables intelligent alerting and prevents redundant notifications.

The stored state includes: the status of the runner (last known state, whether it was already reported as inactive, and whether its recovery was already notified), queued workflows (previous count and whether it was already notified), and failed workflows (previous count and whether it was already notified).

---

### 🔔 Notification Logic

Each component has tailored alerting behavior to ensure clarity without spam:

- **Runner:**  
  - Sends a notification only when the runner transitions from online → offline or offline → online.
- **Queued Workflows:**  
  - Notifies the first time workflows are detected in queue.  
  - Sends a recovery message when the queue clears.
- **Failed Workflows:**  
  - Notifies only once when failures are detected within the configured time window.

This logic ensures that alerts are **meaningful and state-aware**, avoiding unnecessary repetition.

---

### 🛡️ GitHub API Error Handling

An additional validation layer was implemented to detect errors in GitHub API responses.

Previously, if the API call failed (e.g., due to an invalid or expired token), the script could **mistakenly interpret the runner as offline** or return malformed data. Now, the script:

- Checks if the API response contains the expected structure.
- Aborts processing if the response is invalid.
- Sends a dedicated alert to ClickUp indicating that **authentication failed or the API call was unsuccessful**.

This prevents false alarms and improves observability in the case of access or token-related issues.

---

## Documentation and reference

Documentation & References

- GitHub REST API – Self-hosted Runners:
  https://docs.github.com/en/rest/actions/self-hosted-runners?apiVersion=2022-11-28#list-self-hosted-runners-for-a-repository
  https://docs.github.com/en/rest/actions/self-hosted-runners?apiVersion=2022-11-28#list-self-hosted-runners-for-an-organization

- GitHub REST API – Repositories:
  https://docs.github.com/en/rest/repos/repos

- ClickUp API – Create Workspace Audit Log (Chat Message):
  https://developer.clickup.com/reference/createworkspaceauditlog

---

## 📝 License

This script is licensed under the GNU General Public License v3.0.
See [LICENSE](LICENSE) for details.
