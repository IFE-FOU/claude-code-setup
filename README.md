# Claude Code Setup for IFE

One-command setup for [Claude Code](https://claude.ai/code) with AWS Bedrock on macOS and Windows.

---

## Install

### macOS

Open Terminal and run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/IFE-FOU/claude-code-setup/main/setup.sh)
```

### Windows

Open PowerShell and run:

```powershell
irm https://raw.githubusercontent.com/IFE-FOU/claude-code-setup/main/setup.ps1 | iex
```

> If you see an execution policy error, run this first:
> ```powershell
> Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
> ```

---

## What it does

| Phase | Action |
|-------|--------|
| 1 | Installs required tools (see below) |
| 2 | Writes the IFE AWS SSO profile to `~/.aws/config` |
| 3 | Opens browser login with your IFE Microsoft credentials (skipped if already logged in) |
| 4 | Verifies AWS access |

After that, start `claude` and complete Bedrock setup once — choose **3rd-party platform → Amazon Bedrock** (or run `/setup-bedrock`), then select the `ife` profile. Claude Code auto-detects your region and which models your account can invoke.

**Tools installed:**

| Tool | macOS | Windows |
|------|-------|---------|
| Package manager | Homebrew | winget (built into Windows 10/11) |
| Node.js | `brew install node` | `winget install OpenJS.NodeJS.LTS` |
| AWS CLI | `brew install awscli` | `winget install Amazon.AWSCLI` |
| Claude Code | `npm install -g @anthropic-ai/claude-code` | `npm install -g @anthropic-ai/claude-code` |

---

## Re-running

The script is idempotent — safe to re-run at any time. It checks what is already installed/configured and only updates what is out of date, skipping the browser login if your AWS session is still valid.

---

## Daily use

Your AWS session lasts 8 hours. Re-authenticate with:

```bash
aws sso login --profile ife
```

Then start Claude Code:

```bash
claude
```

---

## Requirements

- macOS or Windows 10/11
- An IFE email address with access granted by your administrator
