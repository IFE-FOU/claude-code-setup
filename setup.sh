#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# IFE Claude Code Setup
# Installs and configures Claude Code with AWS Bedrock SSO.
# Safe to re-run — updates existing configuration.
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/IFE-AS/<repo>/main/setup.sh)
# ─────────────────────────────────────────────────────────────────────────────

# ── IFE Configuration ─────────────────────────────────────────────────────────
readonly SSO_START_URL="https://d-c3677f1bbd.awsapps.com/start"
readonly SSO_REGION="eu-north-1"
readonly SSO_ACCOUNT_ID="REDACTED_ACCOUNT"
readonly SSO_ROLE_NAME="BedrockUserAccess"
readonly PROFILE="ife"
readonly AWS_REGION_VAL="eu-north-1"
readonly MODEL_SONNET="eu.anthropic.claude-sonnet-4-6"
readonly MODEL_OPUS="eu.anthropic.claude-opus-4-6-v1"
readonly MODEL_HAIKU="eu.anthropic.claude-haiku-4-5-20251001-v1:0"

# ── Output helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

ok()     { echo -e "  ${GREEN}✓${NC}  $1"; }
skip()   { echo -e "  ${YELLOW}↩${NC}  $1"; }
info()   { echo -e "  ${BLUE}→${NC}  $1"; }
fail()   { echo -e "\n  ${RED}✗  ERROR:${NC}  $1\n" >&2; exit 1; }
header() { echo -e "\n${BOLD}${BLUE}┌─ $1${NC}"; }

# ── Intro ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}IFE Claude Code Setup${NC}"
echo -e "──────────────────────────────────────────────────────"
echo -e "  Installs and configures Claude Code with AWS Bedrock."
echo -e "  Safe to re-run — updates existing configuration."
echo -e "──────────────────────────────────────────────────────"
echo ""

# ── Phase 1: Dependencies ─────────────────────────────────────────────────────
header "Phase 1 / 5  —  Dependencies"

# Homebrew
echo ""
if command -v brew &>/dev/null; then
  skip "Homebrew already installed  ($(brew --version 2>/dev/null | head -1))"
else
  info "Installing Homebrew (you may be prompted for your Mac password)..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Add brew to PATH (Apple Silicon puts it in /opt/homebrew)
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -f /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
  ok "Homebrew installed"
fi

# Node.js
if command -v node &>/dev/null; then
  skip "Node.js already installed  ($(node --version))"
else
  info "Installing Node.js..."
  brew install node
  ok "Node.js installed"
fi

# AWS CLI
if command -v aws &>/dev/null; then
  skip "AWS CLI already installed  ($(aws --version 2>&1 | awk '{print $1}'))"
else
  info "Installing AWS CLI..."
  brew install awscli
  ok "AWS CLI installed"
fi

# Claude Code (always run install to pick up latest version)
if command -v claude &>/dev/null; then
  info "Updating Claude Code to latest..."
  npm install -g @anthropic-ai/claude-code
  ok "Claude Code updated"
else
  info "Installing Claude Code..."
  npm install -g @anthropic-ai/claude-code
  ok "Claude Code installed"
fi

# ── Phase 2: AWS Config ───────────────────────────────────────────────────────
header "Phase 2 / 5  —  AWS SSO Configuration"
echo ""

mkdir -p "$HOME/.aws"

info "Writing AWS SSO profile to ~/.aws/config..."

# Use Python to safely update only the ife blocks, leaving other profiles intact
python3 - <<AWSCONFIG_PY
import re, os

path = os.path.expanduser("~/.aws/config")
content = open(path).read() if os.path.exists(path) else ""

# Remove existing ife blocks (leaves all other profiles untouched)
content = re.sub(r'\[sso-session ife\][^\[]*', '', content)
content = re.sub(r'\[profile ife\][^\[]*', '', content)
content = re.sub(r'\n{3,}', '\n\n', content).strip()

new_blocks = """

[sso-session ife]
sso_start_url = ${SSO_START_URL}
sso_region = ${SSO_REGION}
sso_registration_scopes = sso:account:access

[profile ife]
sso_session = ife
sso_account_id = ${SSO_ACCOUNT_ID}
sso_role_name = ${SSO_ROLE_NAME}
region = ${AWS_REGION_VAL}
output = json
"""

with open(path, 'w') as f:
    f.write((content + new_blocks).strip() + "\n")
AWSCONFIG_PY

ok "AWS config written (~/.aws/config)"

# ── Phase 3: SSO Login ────────────────────────────────────────────────────────
header "Phase 3 / 5  —  SSO Login"

echo ""
echo -e "  ${BOLD}A browser window will open for you to log in with your${NC}"
echo -e "  ${BOLD}IFE Microsoft credentials.${NC}"
echo -e "  Return here after completing authentication in the browser."
echo ""
read -rp "  Press Enter to open the browser login... "
echo ""

aws sso login --profile "$PROFILE"

# ── Phase 4: Verification ─────────────────────────────────────────────────────
header "Phase 4 / 5  —  Verifying Access"
echo ""

if IDENTITY=$(aws sts get-caller-identity --profile "$PROFILE" 2>/dev/null); then
  ACCOUNT=$(echo "$IDENTITY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['Account'])")
  ARN=$(echo "$IDENTITY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['Arn'])")
  ok "Authenticated as: $ARN"
  ok "Account: $ACCOUNT"
else
  fail "Authentication failed. Please re-run the script and complete the browser login."
fi

# ── Phase 5: Shell Config ─────────────────────────────────────────────────────
header "Phase 5 / 5  —  Shell Environment Variables"
echo ""

# Detect shell config file
case "$(basename "$SHELL")" in
  zsh)  SHELL_RC="$HOME/.zshrc" ;;
  bash) SHELL_RC="$HOME/.bash_profile" ;;
  *)    SHELL_RC="$HOME/.profile" ;;
esac

info "Shell: $(basename "$SHELL")  →  $SHELL_RC"

touch "$SHELL_RC"

# Write the env block to a temp file (avoids heredoc quoting issues)
TMPBLOCK=$(mktemp)
cat > "$TMPBLOCK" <<ENVBLOCK
# --- IFE Claude Code BEGIN ---
export CLAUDE_CODE_USE_BEDROCK=1
export AWS_PROFILE=${PROFILE}
export AWS_REGION=${AWS_REGION_VAL}
export ANTHROPIC_MODEL=${MODEL_SONNET}
export ANTHROPIC_DEFAULT_SONNET_MODEL=${MODEL_SONNET}
export ANTHROPIC_DEFAULT_OPUS_MODEL=${MODEL_OPUS}
export ANTHROPIC_DEFAULT_HAIKU_MODEL=${MODEL_HAIKU}
export CLAUDE_CODE_SUBAGENT_MODEL=${MODEL_SONNET}
# --- IFE Claude Code END ---
ENVBLOCK

# Use Python to insert or replace the block in the shell config
python3 - "$SHELL_RC" "$TMPBLOCK" <<'SHELLRC_PY'
import sys, re

rc_path   = sys.argv[1]
block_path = sys.argv[2]

with open(block_path) as f:
    new_block = f.read().strip()

with open(rc_path) as f:
    content = f.read()

if "IFE Claude Code BEGIN" in content:
    content = re.sub(
        r'# --- IFE Claude Code BEGIN ---.*?# --- IFE Claude Code END ---',
        new_block,
        content,
        flags=re.DOTALL
    )
    print("updated")
else:
    content = content.rstrip() + "\n\n" + new_block + "\n"
    print("added")
SHELLRC_PY

rm "$TMPBLOCK"

ok "Environment variables written to $SHELL_RC"

# Reload the config in the current shell session
set +u
# shellcheck disable=SC1090
source "$SHELL_RC" 2>/dev/null || true
set -u

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${GREEN}  Setup complete!${NC}"
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  Start Claude Code:"
echo -e "    ${BOLD}claude${NC}"
echo ""
echo -e "  Your session lasts ${BOLD}8 hours${NC}. To re-authenticate:"
echo -e "    ${BOLD}aws sso login --profile ife${NC}"
echo ""
echo -e "  ${YELLOW}Note:${NC} Open a new terminal window (or run the command below)"
echo -e "  to ensure the environment variables are active:"
echo -e "    ${BOLD}source $SHELL_RC${NC}"
echo ""
