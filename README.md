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
