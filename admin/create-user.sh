#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# IFE Claude Code — Create User
# Creates an SSO user and assigns Bedrock access.
#
# Usage:
#   ./create-user.sh <email>
#
# Example:
#   ./create-user.sh fornavn.etternavn@ife.no
# ─────────────────────────────────────────────────────────────────────────────

# ── IFE AWS Config ────────────────────────────────────────────────────────────
readonly INSTANCE_ARN="arn:aws:sso:::instance/REDACTED_ACCOUNT_INSTANCE"
readonly IDENTITY_STORE_ID="d-c3677f1bbd"
readonly ACCOUNT_ID="REDACTED_ACCOUNT"
readonly PERMISSION_SET_ARN="arn:aws:sso:::permissionSet/REDACTED_ACCOUNT_INSTANCE/REDACTED_ACCOUNT_PERMSET"
readonly AWS_PROFILE="${AWS_PROFILE:-ife-admin}"

# ── Output helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC}  $1"; }
skip() { echo -e "  ${YELLOW}↩${NC}  $1"; }
info() { echo -e "  →  $1"; }
fail() { echo -e "\n  ${RED}✗  ERROR:${NC}  $1\n" >&2; exit 1; }

# ── Input validation ──────────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
  echo -e "Usage: $0 <email>"
  echo -e "Example: $0 fornavn.etternavn@ife.no"
  exit 1
fi

EMAIL="$1"

if [[ ! "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
  fail "Invalid email address: $EMAIL"
fi

# ── Parse name from email ─────────────────────────────────────────────────────
# Handles first.last@domain.no → Given=First, Family=Last
LOCAL_PART="${EMAIL%%@*}"
IFS='.' read -ra PARTS <<< "$LOCAL_PART"

capitalize() {
  echo "$(tr '[:lower:]' '[:upper:]' <<< "${1:0:1}")${1:1}"
}

GIVEN=$(capitalize "${PARTS[0]}")

if [[ ${#PARTS[@]} -ge 2 ]]; then
  # Join remaining parts with space for multi-part family names
  FAMILY_PARTS=("${PARTS[@]:1}")
  FAMILY=$(IFS=' '; echo "${FAMILY_PARTS[*]}" | while read -ra W; do
    for w in "${W[@]}"; do capitalize "$w"; done
  done | tr '\n' ' ' | xargs)
else
  FAMILY="$GIVEN"
  GIVEN=""
fi

DISPLAY_NAME="$GIVEN $FAMILY"

echo ""
echo -e "${BOLD}Creating IFE Claude Code user${NC}"
echo -e "──────────────────────────────────────────────────────"
echo -e "  Email:   $EMAIL"
echo -e "  Name:    $DISPLAY_NAME"
echo -e "  Profile: $AWS_PROFILE"
echo -e "──────────────────────────────────────────────────────"
echo ""

# ── Check if user already exists ─────────────────────────────────────────────
info "Checking if user already exists..."

EXISTING_USER=$(aws identitystore list-users \
  --identity-store-id "$IDENTITY_STORE_ID" \
  --filters "AttributePath=UserName,AttributeValue=$EMAIL" \
  --query "Users[0].UserId" \
  --output text \
  --profile "$AWS_PROFILE" 2>/dev/null || echo "None")

if [[ "$EXISTING_USER" != "None" && -n "$EXISTING_USER" ]]; then
  skip "User already exists (ID: $EXISTING_USER)"
  USER_ID="$EXISTING_USER"
else
  info "Creating SSO user..."
  USER_ID=$(aws identitystore create-user \
    --identity-store-id "$IDENTITY_STORE_ID" \
    --user-name "$EMAIL" \
    --name "FamilyName=$FAMILY,GivenName=$GIVEN,Formatted=$DISPLAY_NAME" \
    --display-name "$DISPLAY_NAME" \
    --emails "Value=$EMAIL,Type=work,Primary=true" \
    --query "UserId" \
    --output text \
    --profile "$AWS_PROFILE")
  ok "User created (ID: $USER_ID)"
fi

# ── Check if assignment already exists ───────────────────────────────────────
info "Checking permission set assignment..."

EXISTING_ASSIGNMENT=$(aws sso-admin list-account-assignments \
  --instance-arn "$INSTANCE_ARN" \
  --account-id "$ACCOUNT_ID" \
  --permission-set-arn "$PERMISSION_SET_ARN" \
  --query "AccountAssignments[?PrincipalId=='$USER_ID'] | [0].PrincipalId" \
  --output text \
  --profile "$AWS_PROFILE" 2>/dev/null || echo "None")

if [[ "$EXISTING_ASSIGNMENT" != "None" && -n "$EXISTING_ASSIGNMENT" ]]; then
  skip "Permission set already assigned"
else
  info "Assigning BedrockUserAccess permission set..."

  REQUEST_ID=$(aws sso-admin create-account-assignment \
    --instance-arn "$INSTANCE_ARN" \
    --target-id "$ACCOUNT_ID" \
    --target-type AWS_ACCOUNT \
    --permission-set-arn "$PERMISSION_SET_ARN" \
    --principal-type USER \
    --principal-id "$USER_ID" \
    --query "AccountAssignmentCreationStatus.RequestId" \
    --output text \
    --profile "$AWS_PROFILE")

  # Wait for assignment to complete
  for i in {1..10}; do
    STATUS=$(aws sso-admin describe-account-assignment-creation-status \
      --instance-arn "$INSTANCE_ARN" \
      --account-assignment-creation-request-id "$REQUEST_ID" \
      --query "AccountAssignmentCreationStatus.Status" \
      --output text \
      --profile "$AWS_PROFILE")

    if [[ "$STATUS" == "SUCCEEDED" ]]; then
      ok "BedrockUserAccess assigned"
      break
    elif [[ "$STATUS" == "FAILED" ]]; then
      fail "Assignment failed. Check the AWS console for details."
    fi

    sleep 2
  done
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  Done! $DISPLAY_NAME ($EMAIL) is ready.${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  Send the user the setup instructions:"
echo -e "    ${BOLD}macOS:${NC}   bash <(curl -fsSL https://raw.githubusercontent.com/IFE-FOU/claude-code-setup/main/setup.sh)"
echo -e "    ${BOLD}Windows:${NC} irm https://raw.githubusercontent.com/IFE-FOU/claude-code-setup/main/setup.ps1 | iex"
echo ""
