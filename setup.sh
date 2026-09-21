#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$(dirname "$SCRIPT_DIR")"

echo "Configuring SonarQube scanner for $WORK_DIR..."

# 1. Create scripts folder and symlink
mkdir -p "$WORK_DIR/scripts"
ln -sf "$SCRIPT_DIR/scripts/sonar-scan.ts" "$WORK_DIR/scripts/sonar-scan.ts"
echo "✓ Symlinked $WORK_DIR/scripts/sonar-scan.ts -> $SCRIPT_DIR/scripts/sonar-scan.ts"

# 2. Configure ~/work/.mise.toml
WORK_MISE="$WORK_DIR/.mise.toml"
if [ ! -f "$WORK_MISE" ]; then
  cp "$SCRIPT_DIR/.mise.toml" "$WORK_MISE"
  echo "✓ Created $WORK_MISE from template"
else
  # Ensure tools section has node = "lts" if not already present
  if ! grep -q 'node' "$WORK_MISE"; then
    if grep -q '\[tools\]' "$WORK_MISE"; then
      sed -i '/\[tools\]/a node = "lts"' "$WORK_MISE"
    else
      printf '[tools]\nnode = "lts"\n\n' | cat - "$WORK_MISE" > "$WORK_MISE.tmp" && mv "$WORK_MISE.tmp" "$WORK_MISE"
    fi
    echo "✓ Added node = \"lts\" to $WORK_MISE"
  fi

  # Ensure sonar-scanner-cli is in tools
  if ! grep -q 'sonar-scanner-cli' "$WORK_MISE"; then
    sed -i '/\[tools\]/a sonar-scanner-cli = "latest"' "$WORK_MISE"
  fi

  # Ensure jq is in tools
  if ! grep -q 'jq' "$WORK_MISE"; then
    sed -i '/\[tools\]/a jq = "latest"' "$WORK_MISE"
    echo "✓ Added jq = \"latest\" to $WORK_MISE"
  fi

  # Ensure scan tasks are present
  if ! grep -q 'sonar-scan' "$WORK_MISE"; then
    cat << 'EOF' >> "$WORK_MISE"

[tasks."scan:diff"]
description = "Fast SonarQube diff scan on current repo"
dir = "{{cwd}}"
quiet = true
run = "node {{config_root}}/scripts/sonar-scan.ts --diff"

[tasks.scan]
description = "Full SonarQube scan on current repo"
dir = "{{cwd}}"
quiet = true
run = "node {{config_root}}/scripts/sonar-scan.ts"
EOF
    echo "✓ Added scan tasks to $WORK_MISE"
  fi
fi

# 3. Ensure Node, scanner, and jq are installed
if command -v mise >/dev/null 2>&1; then
  echo "Ensuring node (lts), sonar-scanner-cli, and jq are provisioned via mise..."
  mise -C "$WORK_DIR" install -q
  echo "✓ Mise tools ready:"
  echo "  - node: $(mise -C "$WORK_DIR" exec -- node --version 2>/dev/null || echo 'installed')"
  echo "  - jq:   $(mise -C "$WORK_DIR" exec -- jq --version 2>/dev/null || echo 'installed')"
elif command -v node >/dev/null 2>&1; then
  echo "✓ Found system node: $(node --version)"
else
  echo "⚠ Neither mise nor node found. Please install node (LTS) or mise."
fi

# 4. Check for personal credentials
WORK_LOCAL_MISE="$WORK_DIR/.mise.local.toml"
has_creds() {
  ([ -n "${SONAR_TOKEN:-}" ] && [ -n "${SONAR_HOST_URL:-}" ]) || \
  ([ -f "$WORK_LOCAL_MISE" ] && grep -q 'SONAR_TOKEN' "$WORK_LOCAL_MISE" && grep -q 'SONAR_HOST_URL' "$WORK_LOCAL_MISE") || \
  ([ -f "$WORK_MISE" ] && grep -q 'SONAR_TOKEN' "$WORK_MISE" && grep -q 'SONAR_HOST_URL' "$WORK_MISE")
}

if ! has_creds; then
  echo ""
  if [ -t 0 ]; then
    read -r -p "Enter SONAR_HOST_URL (or press enter to skip): " input_url
    read -r -p "Enter personal SONAR_TOKEN (or press enter to skip): " input_token
    if [ -n "$input_url" ] || [ -n "$input_token" ]; then
      cat << EOF >> "$WORK_LOCAL_MISE"

[env]
EOF
      [ -n "$input_url" ] && echo "SONAR_HOST_URL = \"$input_url\"" >> "$WORK_LOCAL_MISE"
      [ -n "$input_token" ] && echo "SONAR_TOKEN = \"$input_token\"" >> "$WORK_LOCAL_MISE"
      echo "✓ Saved credentials to $WORK_LOCAL_MISE"
    else
      echo "ℹ Skipping credentials. Remember to set them in $WORK_LOCAL_MISE"
    fi
  else
    if [ ! -f "$WORK_LOCAL_MISE" ]; then
      cp "$SCRIPT_DIR/.mise.local.toml.example" "$WORK_LOCAL_MISE"
      echo "✓ Created $WORK_LOCAL_MISE template (fill in your credentials)"
    fi
  fi
else
  echo "✓ Sonar credentials found."
fi

echo "✓ Setup complete! You can run 'mise scan:diff' from any project under $WORK_DIR."
