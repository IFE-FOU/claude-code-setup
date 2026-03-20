# Claude Code Setup for IFE

One-command setup for [Claude Code](https://claude.ai/code) with AWS Bedrock on macOS.

## Install

Open Terminal and run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/IFE-FOU/claude-code-setup/main/setup.sh)
```

The script will guide you through each step and ask for confirmation before opening the browser login.

## What it does

| Phase | Action |
|-------|--------|
| 1 | Installs Homebrew, Node.js, AWS CLI, and Claude Code |
| 2 | Writes the IFE AWS SSO profile to `~/.aws/config` |
| 3 | Opens browser login with your IFE Microsoft credentials |
| 4 | Verifies AWS access |
| 5 | Adds required environment variables to your shell config |

## Re-running

The script is safe to re-run at any time — useful for updating Claude Code or refreshing model configuration. It checks what is already installed and only updates what is needed.

## Daily use

Your AWS session lasts 8 hours. Re-authenticate with:

```bash
aws sso login --profile ife
```

Then start Claude Code:

```bash
claude
```

## Requirements

- macOS
- An IFE email address with access granted by your administrator
