#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# IFE Claude Code Setup
# Installs dependencies and configures AWS Bedrock SSO access.
# Idempotent — safe to re-run any time; only changes what's out of date.
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
echo -e "  Installs dependencies and configures AWS Bedrock SSO."
echo -e "  Idempotent — safe to re-run any time."
echo -e "──────────────────────────────────────────────────────"
echo ""

# ── Phase 1: Dependencies ─────────────────────────────────────────────────────
header "Phase 1 / 4  —  Dependencies"
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
  else
    skip "Homebrew already configured in $_EARLY_RC"
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

# Claude Code
if command -v claude &>/dev/null; then
  CURRENT_VERSION=$(claude --version 2>/dev/null | awk '{print $1}')
  LATEST_VERSION=$(npm view @anthropic-ai/claude-code version 2>/dev/null || echo "")
  if [[ -n "$LATEST_VERSION" && "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
    skip "Claude Code already up to date  (v$CURRENT_VERSION)"
  else
    info "Updating Claude Code ($CURRENT_VERSION → ${LATEST_VERSION:-latest})..."
    npm install -g @anthropic-ai/claude-code
    ok "Claude Code updated"
  fi
else
  info "Installing Claude Code..."
  npm install -g @anthropic-ai/claude-code
  ok "Claude Code installed"
fi

# ── Phase 2: AWS SSO Session Config ───────────────────────────────────────────
header "Phase 2 / 4  —  AWS SSO Configuration"
echo ""

mkdir -p "$HOME/.aws"

# Writes/updates only the [sso-session ife] block, leaving all other profiles
# and sessions untouched. Skips the write entirely if already up to date.
SSO_BLOCK_RESULT=$(python3 - <<PYEOF
import re, os

path = os.path.expanduser("~/.aws/config")
content = open(path).read() if os.path.exists(path) else ""

new_block = """[sso-session ife]
sso_start_url = ${SSO_START_URL}
sso_region = ${SSO_REGION}
sso_registration_scopes = sso:account:access"""

existing_match = re.search(r'\[sso-session ife\][^\[]*', content)
existing_block = existing_match.group(0).strip() if existing_match else None

if existing_block == new_block:
    print("skip")
else:
    stripped = re.sub(r'\[sso-session ife\][^\[]*', '', content)
    stripped = re.sub(r'\n{3,}', '\n\n', stripped).strip()
    with open(path, 'w') as f:
        f.write((stripped + "\n\n" + new_block).strip() + "\n")
    print("wrote")
PYEOF
)

if [[ "$SSO_BLOCK_RESULT" == "skip" ]]; then
  skip "SSO session already up to date (~/.aws/config)"
else
  ok "SSO session written (~/.aws/config)"
fi

# ── Phase 3: SSO Login & Account Verification ─────────────────────────────────
header "Phase 3 / 4  —  SSO Login"
echo ""

ACCOUNT_ID=""
if IDENTITY=$(aws sts get-caller-identity --profile "$PROFILE" 2>/dev/null); then
  ARN=$(echo "$IDENTITY" | python3 -c "import sys,json; print(json.load(sys.stdin)['Arn'])")
  ACCOUNT_ID=$(echo "$IDENTITY" | python3 -c "import sys,json; print(json.load(sys.stdin)['Account'])")
  skip "Already authenticated as: $ARN"
else
  echo -e "  ${BOLD}A browser window will open for you to log in with your${NC}"
  echo -e "  ${BOLD}IFE Microsoft credentials.${NC}"
  echo -e "  Return here after completing authentication in the browser."
  echo ""
  read -rp "  Press Enter to open the browser login... "
  echo ""

  aws sso login --sso-session "$PROFILE"

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
fi

# Writes/updates only the [profile ife] block. Skips the write if already
# up to date (e.g. re-running after the session above was already valid).
PROFILE_BLOCK_RESULT=$(python3 - <<PYEOF
import re, os

path = os.path.expanduser("~/.aws/config")
content = open(path).read() if os.path.exists(path) else ""

new_block = """[profile ife]
sso_session = ife
sso_account_id = ${ACCOUNT_ID}
sso_role_name = ${SSO_ROLE_NAME}
region = ${AWS_REGION_VAL}
output = json"""

existing_match = re.search(r'\[profile ife\][^\[]*', content)
existing_block = existing_match.group(0).strip() if existing_match else None

if existing_block == new_block:
    print("skip")
else:
    stripped = re.sub(r'\[profile ife\][^\[]*', '', content)
    stripped = re.sub(r'\n{3,}', '\n\n', stripped).strip()
    with open(path, 'w') as f:
        f.write((stripped + "\n\n" + new_block).strip() + "\n")
    print("wrote")
PYEOF
)

if [[ "$PROFILE_BLOCK_RESULT" == "skip" ]]; then
  skip "AWS profile already up to date (~/.aws/config)"
else
  ok "AWS profile written (~/.aws/config)"
fi

if ! IDENTITY=$(aws sts get-caller-identity --profile "$PROFILE" 2>/dev/null); then
  fail "Authentication failed. Please re-run the script and complete the browser login."
fi
ok "Verified access — account: $ACCOUNT_ID"

# ── Phase 4: Claude Code Bedrock Setup ────────────────────────────────────────
header "Phase 4 / 4  —  Claude Code Bedrock Setup"
echo ""
echo -e "  AWS access is ready. Claude Code configures Bedrock itself —"
echo -e "  it auto-detects your profile/region and lists the models"
echo -e "  your account can actually invoke."
echo ""
echo -e "  Run:"
echo -e "    ${BOLD}claude${NC}"
echo -e "  then, on first launch, choose ${BOLD}3rd-party platform → Amazon Bedrock${NC}"
echo -e "  (or run ${BOLD}/setup-bedrock${NC} inside an existing session)."
echo -e "  Select the ${BOLD}${PROFILE}${NC} profile when prompted."
echo ""

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${GREEN}  AWS setup complete!${NC}"
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  Your session lasts ${BOLD}8 hours${NC}. To re-authenticate later:"
echo -e "    ${BOLD}aws sso login --profile ife${NC}"
echo ""
echo -e "  (or just re-run this script — it will skip everything"
echo -e "  that's already up to date)"
echo ""
