# Infinite RDP Session with Tailscale

Persistent Windows RDP environment using GitHub Actions with automatic session chaining for infinite uptime.

## Quick Start

### 1. Configure Secrets

Add these secrets to your GitHub repository (`Settings > Secrets > Actions`):

| Secret | Description | How to Get |
|--------|-------------|------------|
| `TAILSCALE_AUTHKEY` | Tailscale authentication key | [Tailscale Admin](https://login.tailscale.com/admin/settings/keys) - Create reusable key |
| `RDP_PASSWORD` | Password for RDP login | Choose a strong password |
| `GH_PAT` | GitHub Personal Access Token | [Create token](https://github.com/settings/tokens) with `repo` and `workflow` scopes |

### 2. Start a Session

1. Go to **Actions** tab in your repository
2. Select **Manual Chain Trigger** workflow
3. Click **Run workflow**
4. Wait ~3 minutes for the session to start

### 3. Connect

1. Open workflow logs to find your Tailscale IP
2. Connect via RDP client:
   - **Address**: `<tailscale-ip>:3389` or `gh-rdp-<session-id>:3389`
   - **Username**: `rdpuser`
   - **Password**: Your `RDP_PASSWORD` secret

## How It Works

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Session #1     │────>│  Session #2     │────>│  Session #3     │
│  (5.5 hours)    │     │  (5.5 hours)    │     │  (5.5 hours)    │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        │                       │                       │
        └───── Tailscale IP remains constant ───────────┘
```

1. Each session runs for ~5.5 hours (GitHub's limit is 6h)
2. At 5h 15m, it triggers the next session via `repository_dispatch`
3. The same Tailscale hostname is reused, so your IP stays constant
4. Sessions overlap briefly to ensure no downtime

## Files

```
.github/workflows/
├── rdp-session.yml      # Main RDP workflow
├── trigger-rdp.yml      # Manual trigger/stop
└── monitor-session.yml  # Session monitoring

scripts/
├── setup.ps1            # Local setup helper
└── persist-session.ps1  # Save/restore session data
```

## Tailscale Setup

### 1. Configure ACL Policy (Optional but Recommended)

Go to [Admin Console > Access Controls](https://login.tailscale.com/admin/acls) and add:

```json
{
  "tagOwners": {
    "tag:github-runner": ["autogroup:admin"]
  },
  "acls": [
    {
      "action": "accept",
      "src": ["autogroup:members"],
      "dst": ["tag:github-runner:3389"]
    }
  ]
}
```

### 2. Generate Auth Key

1. Go to [Tailscale Admin Console](https://login.tailscale.com/admin/settings/keys)
2. Click **Generate auth key**
3. Settings:
   - **Reusable**: Yes (required for chaining)
   - **Ephemeral**: No (keeps device in network)
   - **Pre-approved**: Yes (only shown if Device Approval is enabled)
   - **Tags**: `tag:github-runner`
   - **Expiration**: 90 days
4. Copy the key and add as `TAILSCALE_AUTHKEY` secret

> **Note**: If you don't see "Pre-approved", Device Approval is disabled and devices auto-join anyway.

See [DEVICE_APPROVAL.md](DEVICE_APPROVAL.md) for multi-user approval strategies.

## Session Management

### Stop a Session
- Run **Manual Chain Trigger** with `stop_session: true`
- Or cancel the running workflow in Actions tab

### Monitor Sessions
- The **Session Monitor** workflow runs every 30 minutes
- Shows active sessions and statistics

### Persist Data Across Chains

Data is **automatically persisted** across session chains:

**Auto-saved directories** (every 30 minutes + before chain):
- `C:\Users\rdpuser\projects`
- `C:\Users\rdpuser\Documents`
- `C:\Users\rdpuser\Desktop`
- `C:\Users\rdpuser\.ssh`
- `C:\Users\rdpuser\.gitconfig`
- `C:\Users\rdpuser\.vscode`
- `C:\Users\rdpuser\AppData\Roaming\*` (app settings)

Data is stored as GitHub Actions artifacts and restored when the next chain starts.

> **Note**: Artifacts are retained for 7 days. If no session runs for 7 days, data is lost.

### Installing Custom Apps (like Moltbot)

**Apps are reinstalled each chain, but settings are preserved.**

1. Edit `.github/workflows/rdp-session.yml`
2. Find the `Install Custom Apps` step
3. Add your installer:

```yaml
- name: Install Custom Apps
  shell: pwsh
  run: |
    # Moltbot example
    $url = "https://example.com/moltbot-setup.exe"
    Invoke-WebRequest -Uri $url -OutFile "$env:TEMP\moltbot.exe" -UseBasicParsing
    Start-Process -FilePath "$env:TEMP\moltbot.exe" -ArgumentList "/S" -Wait
```

4. Add Moltbot's settings folder to persist list (in the `Setup auto-save` step):

```powershell
`$appDataToSave = @(
    "`$appData\Roaming\Moltbot",  # Add this line
    # ... other folders
)
```

**How it works:**
```
Chain 1: Install Moltbot → Configure it → Settings saved to AppData
Chain 2: Reinstall Moltbot → Restore settings from artifact → Ready!
```

## Installed Software

Each session comes with:
- Git
- VS Code
- Node.js
- Python 3
- 7-Zip
- Chocolatey (for additional packages)

Install more via: `choco install <package> -y`

## Limitations

- GitHub Actions has a 6-hour job limit (we use 5.5h)
- Free tier: 2,000 minutes/month for private repos
- Public repos: Unlimited minutes
- Concurrent sessions depend on your GitHub plan

## Troubleshooting

### Can't connect via Tailscale
1. Ensure your local machine is on Tailscale
2. Check the workflow logs for the Tailscale IP
3. Verify the auth key hasn't expired

### Session not chaining
1. Check `GH_PAT` has correct permissions
2. Look for errors in the "Schedule chain trigger" step
3. Verify the scheduled task was created

### RDP connection refused
1. Wait 2-3 minutes after session starts
2. Verify you're using the correct password
3. Check Windows Firewall in the runner
