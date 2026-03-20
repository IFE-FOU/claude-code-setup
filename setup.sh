#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# IFE Claude Code Setup
# Installs and configures Claude Code with AWS Bedrock SSO.
# Safe to re-run — updates existing configuration.
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/IFE-FOU/claude-code-setup/main/setup.sh)
# ─────────────────────────────────────────────────────────────────────────────

# ── IFE Configuration ─────────────────────────────────────────────────────────
readonly SSO_START_URL="https://d-c3677f1bbd.awsapps.com/start"
readonly SSO_REGION="eu-north-1"
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
echo ""

# Homebrew
if command -v brew &>/dev/null; then
  skip "Homebrew already installed  ($(brew --version 2>/dev/null | head -1))"
else
  info "Installing Homebrew (you may be prompted for your Mac password)..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -f /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
  ok "Homebrew installed"
fi

# Ensure Homebrew is in PATH for the current session and shell config
# (Homebrew's installer may not write to the shell config in all cases)
BREW_SHELLENV=""
if [[ -f /opt/homebrew/bin/brew ]]; then
  BREW_SHELLENV='eval "$(/opt/homebrew/bin/brew shellenv)"'
elif [[ -f /usr/local/bin/brew ]]; then
  BREW_SHELLENV='eval "$(/usr/local/bin/brew shellenv)"'
fi

if [[ -n "$BREW_SHELLENV" ]]; then
  eval "$BREW_SHELLENV"
  # Detect shell config to write to (same logic as Phase 5, needed early for npm)
  case "$(basename "$SHELL")" in
    zsh)  _EARLY_RC="$HOME/.zshrc" ;;
    bash) _EARLY_RC="$HOME/.bash_profile" ;;
    *)    _EARLY_RC="$HOME/.profile" ;;
  esac
  if ! grep -q "brew shellenv" "$_EARLY_RC" 2>/dev/null; then
    echo "" >> "$_EARLY_RC"
    echo "# Homebrew" >> "$_EARLY_RC"
    echo "$BREW_SHELLENV" >> "$_EARLY_RC"
    ok "Homebrew added to $_EARLY_RC"
  fi
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

# ── Phase 2: AWS SSO Session Config ───────────────────────────────────────────
header "Phase 2 / 5  —  AWS SSO Configuration"
echo ""

mkdir -p "$HOME/.aws"

info "Writing AWS SSO session to ~/.aws/config..."

# Write only the sso-session block — profile is completed after login (Phase 3)
python3 - <<AWSCONFIG_PY
import re, os

path = os.path.expanduser("~/.aws/config")
content = open(path).read() if os.path.exists(path) else ""

# Remove existing ife blocks (leaves all other profiles untouched)
content = re.sub(r'\[sso-session ife\][^\[]*', '', content)
content = re.sub(r'\[profile ife\][^\[]*', '', content)
content = re.sub(r'\n{3,}', '\n\n', content).strip()

new_block = """

[sso-session ife]
sso_start_url = ${SSO_START_URL}
sso_region = ${SSO_REGION}
sso_registration_scopes = sso:account:access
"""

with open(path, 'w') as f:
    f.write((content + new_block).strip() + "\n")
AWSCONFIG_PY

ok "SSO session written (~/.aws/config)"

# ── Phase 3: SSO Login ────────────────────────────────────────────────────────
header "Phase 3 / 5  —  SSO Login"

echo ""
echo -e "  ${BOLD}A browser window will open for you to log in with your${NC}"
echo -e "  ${BOLD}IFE Microsoft credentials.${NC}"
echo -e "  Return here after completing authentication in the browser."
echo ""
read -rp "  Press Enter to open the browser login... "
echo ""

aws sso login --sso-session "$PROFILE"

# Discover account ID from the SSO token cache — no hardcoded account ID needed
info "Detecting your AWS account..."

ACCESS_TOKEN=$(python3 - <<'TOKEN_PY'
import json, os, glob

cache_dir = os.path.expanduser("~/.aws/sso/cache")
files = sorted(glob.glob(os.path.join(cache_dir, "*.json")), key=os.path.getmtime, reverse=True)
for f in files:
    try:
        data = json.load(open(f))
        if "accessToken" in data:
            print(data["accessToken"])
            break
    except Exception:
        pass
TOKEN_PY
)

if [[ -z "$ACCESS_TOKEN" ]]; then
  fail "Could not find SSO token after login. Please re-run the script."
fi

ACCOUNT_ID=$(aws sso list-accounts \
  --access-token "$ACCESS_TOKEN" \
  --region "$SSO_REGION" \
  --query "accountList[0].accountId" \
  --output text)

if [[ -z "$ACCOUNT_ID" || "$ACCOUNT_ID" == "None" ]]; then
  fail "No AWS accounts found for your user. Please check your access with your administrator."
fi

ok "Account detected: $ACCOUNT_ID"

# Write the complete profile now that we have the account ID
python3 - <<PROFILE_PY
import re, os

path = os.path.expanduser("~/.aws/config")
content = open(path).read() if os.path.exists(path) else ""

content = re.sub(r'\[profile ife\][^\[]*', '', content)
content = re.sub(r'\n{3,}', '\n\n', content).strip()

profile_block = """

[profile ife]
sso_session = ife
sso_account_id = ${ACCOUNT_ID}
sso_role_name = ${SSO_ROLE_NAME}
region = ${AWS_REGION_VAL}
output = json
"""

with open(path, 'w') as f:
    f.write((content + profile_block).strip() + "\n")
PROFILE_PY

ok "AWS profile written (~/.aws/config)"

# ── Phase 4: Verification ─────────────────────────────────────────────────────
header "Phase 4 / 5  —  Verifying Access"
echo ""

if IDENTITY=$(aws sts get-caller-identity --profile "$PROFILE" 2>/dev/null); then
  ARN=$(echo "$IDENTITY" | python3 -c "import sys,json; print(json.load(sys.stdin)['Arn'])")
  ok "Authenticated as: $ARN"
  ok "Account: $ACCOUNT_ID"
else
  fail "Authentication failed. Please re-run the script and complete the browser login."
fi

# ── Phase 5: Shell Config ─────────────────────────────────────────────────────
header "Phase 5 / 5  —  Shell Environment Variables"
echo ""

case "$(basename "$SHELL")" in
  zsh)  SHELL_RC="$HOME/.zshrc" ;;
  bash) SHELL_RC="$HOME/.bash_profile" ;;
  *)    SHELL_RC="$HOME/.profile" ;;
esac

info "Shell: $(basename "$SHELL")  →  $SHELL_RC"

touch "$SHELL_RC"

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

python3 - "$SHELL_RC" "$TMPBLOCK" <<'SHELLRC_PY'
import sys, re

rc_path    = sys.argv[1]
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
else:
    content = content.rstrip() + "\n\n" + new_block + "\n"

with open(rc_path, 'w') as f:
    f.write(content)
SHELLRC_PY

rm "$TMPBLOCK"

ok "Environment variables written to $SHELL_RC"

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
