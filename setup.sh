#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${PWD}"

# If running directly from inside .sonar-scan, default to parent directory
if [ "$TARGET_DIR" = "$SCRIPT_DIR" ]; then
  TARGET_DIR="$(dirname "$SCRIPT_DIR")"
fi

MODE="project"

usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  -p, --project <DIR>    Install into a specific project directory (default: current project)"
  echo "  -w, --workspace [DIR]  Install into parent workspace for all sibling projects"
  echo "  -h, --help             Show this help message"
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--project)
      if [ -z "${2:-}" ]; then
        echo "Error: --project requires a directory argument"
        exit 1
      fi
      TARGET_DIR="$(cd "$2" && pwd)"
      MODE="project"
      shift 2
      ;;
    -w|--workspace)
      MODE="workspace"
      if [ -n "${2:-}" ] && [[ ! "$2" =~ ^- ]]; then
        TARGET_DIR="$(cd "$2" && pwd)"
        shift 2
      else
        TARGET_DIR="$(dirname "$SCRIPT_DIR")"
        shift
      fi
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Error: Unknown argument: $1"
      usage
      ;;
  esac
done

if [ "$MODE" = "workspace" ]; then
  echo "Configuring SonarQube scanner for workspace: $TARGET_DIR (all subprojects)..."
else
  echo "Configuring SonarQube scanner for project: $TARGET_DIR..."
fi

# 1. Create scripts folder and symlink
mkdir -p "$TARGET_DIR/scripts"
ln -sf "$SCRIPT_DIR/scripts/sonar-scan.ts" "$TARGET_DIR/scripts/sonar-scan.ts"
echo "✓ Symlinked $TARGET_DIR/scripts/sonar-scan.ts -> $SCRIPT_DIR/scripts/sonar-scan.ts"

# 2. Configure target .mise.toml
TARGET_MISE="$TARGET_DIR/.mise.toml"
if [ ! -f "$TARGET_MISE" ]; then
  cp "$SCRIPT_DIR/.mise.toml" "$TARGET_MISE"
  echo "✓ Created $TARGET_MISE from template"
else
  # Ensure tools section has node = "lts" if not already present
  if ! grep -q 'node' "$TARGET_MISE"; then
    if grep -q '\[tools\]' "$TARGET_MISE"; then
      sed -i '/\[tools\]/a node = "lts"' "$TARGET_MISE"
    else
      printf '[tools]\nnode = "lts"\n\n' | cat - "$TARGET_MISE" > "$TARGET_MISE.tmp" && mv "$TARGET_MISE.tmp" "$TARGET_MISE"
    fi
    echo "✓ Added node = \"lts\" to $TARGET_MISE"
  fi

  # Ensure sonar-scanner-cli is in tools
  if ! grep -q 'sonar-scanner-cli' "$TARGET_MISE"; then
    sed -i '/\[tools\]/a sonar-scanner-cli = "latest"' "$TARGET_MISE"
  fi

  # Ensure jq is in tools
  if ! grep -q 'jq' "$TARGET_MISE"; then
    sed -i '/\[tools\]/a jq = "latest"' "$TARGET_MISE"
    echo "✓ Added jq = \"latest\" to $TARGET_MISE"
  fi

  # Ensure scan tasks are present
  if ! grep -q 'sonar-scan' "$TARGET_MISE"; then
    cat << 'EOF' >> "$TARGET_MISE"

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
    echo "✓ Added scan tasks to $TARGET_MISE"
  fi
fi

# 3. Ensure Node, scanner, and jq are installed
if command -v mise >/dev/null 2>&1; then
  echo "Ensuring node (lts), sonar-scanner-cli, and jq are provisioned via mise..."
  mise -C "$TARGET_DIR" install -q
  echo "✓ Mise tools ready:"
  echo "  - node: $(mise -C "$TARGET_DIR" exec -- node --version 2>/dev/null || echo 'installed')"
  echo "  - jq:   $(mise -C "$TARGET_DIR" exec -- jq --version 2>/dev/null || echo 'installed')"
elif command -v node >/dev/null 2>&1; then
  echo "✓ Found system node: $(node --version)"
else
  echo "⚠ Neither mise nor node found. Please install node (LTS) or mise."
fi

# 4. Check for personal credentials
TARGET_LOCAL_MISE="$TARGET_DIR/.mise.local.toml"
has_creds() {
  ([ -n "${SONAR_TOKEN:-}" ] && [ -n "${SONAR_HOST_URL:-}" ]) || \
  ([ -f "$TARGET_LOCAL_MISE" ] && grep -q 'SONAR_TOKEN' "$TARGET_LOCAL_MISE" && grep -q 'SONAR_HOST_URL' "$TARGET_LOCAL_MISE") || \
  ([ -f "$TARGET_MISE" ] && grep -q 'SONAR_TOKEN' "$TARGET_MISE" && grep -q 'SONAR_HOST_URL' "$TARGET_MISE")
}

if ! has_creds; then
  echo ""
  if [ -t 0 ]; then
    read -r -p "Enter SONAR_HOST_URL (e.g. https://sonar.example.com): " input_url
    read -r -p "Enter personal SONAR_TOKEN (or press enter to skip): " input_token
    if [ -n "$input_url" ] || [ -n "$input_token" ]; then
      cat << EOF >> "$TARGET_LOCAL_MISE"

[env]
EOF
      [ -n "$input_url" ] && echo "SONAR_HOST_URL = \"$input_url\"" >> "$TARGET_LOCAL_MISE"
      [ -n "$input_token" ] && echo "SONAR_TOKEN = \"$input_token\"" >> "$TARGET_LOCAL_MISE"
      echo "✓ Saved credentials to $TARGET_LOCAL_MISE"
    else
      echo "ℹ Skipping credentials. Remember to set them in $TARGET_LOCAL_MISE"
    fi
  else
    if [ ! -f "$TARGET_LOCAL_MISE" ]; then
      cp "$SCRIPT_DIR/.mise.local.toml.example" "$TARGET_LOCAL_MISE"
      echo "✓ Created $TARGET_LOCAL_MISE template (fill in your credentials)"
    fi
  fi
else
  echo "✓ Sonar credentials found."
fi

# 5. Automatically ensure project gitignore rules
TARGET_GITIGNORE="$TARGET_DIR/.gitignore"
if [ -f "$TARGET_GITIGNORE" ] && [ "$MODE" = "project" ]; then
  for rule in ".sonar-scan" ".mise.local.toml" ".scannerwork" "sonar-report.json"; do
    if ! grep -q "^$rule" "$TARGET_GITIGNORE"; then
      echo "$rule" >> "$TARGET_GITIGNORE"
    fi
  done
  echo "✓ Verified .gitignore rules in $TARGET_DIR"
fi

echo "✓ Setup complete! You can run 'mise scan:diff' in $TARGET_DIR."
