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
| 3 | Opens browser login with your IFE Microsoft credentials |
| 4 | Verifies AWS access |
| 5 | Sets required environment variables (persistent) |

**Tools installed:**

| Tool | macOS | Windows |
|------|-------|---------|
| Package manager | Homebrew | winget (built into Windows 10/11) |
| Node.js | `brew install node` | `winget install OpenJS.NodeJS.LTS` |
| AWS CLI | `brew install awscli` | `winget install Amazon.AWSCLI` |
| Claude Code | `npm install -g @anthropic-ai/claude-code` | `npm install -g @anthropic-ai/claude-code` |

---

## Re-running

The script is safe to re-run at any time — useful for updating Claude Code or refreshing model configuration. It checks what is already installed and only updates what is needed.

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
