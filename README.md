# sonar-scan

Fast SonarQube diff & full scan runner for Monorepos and Git projects.

## Features
- **Fast Git Diff Scan**: Scans only untracked/modified/branch-diff files in seconds (`mise scan:diff`).
- **Zero Server Clutter**: Runs against temporary ephemeral keys and deletes them upon completion.
- **Terminal Issue Formatting**: Formats issues cleanly without needing `jq`.
- **Dynamic Project Detection**: Automatically derives project key from `package.json` or folder name.
- **Silent Mode**: Exits with zero output when 0 issues are found (`--silent` / `-s` / `--quiet` / `-q`).

---

## Installation & Setup Options

Choose the setup pattern that fits your team's workflow:

### Option A: Per-Project Setup (Single Repository)
If you only want `sonar-scan` configured in a specific repository:

```bash
# 1. Clone sonar-scan anywhere (e.g. ~/.tools/sonar-scan)
git clone git@github.com:inregist/sonar-scan.git ~/.tools/sonar-scan

# 2. Run setup pointing to your project directory:
~/.tools/sonar-scan/setup.sh --project /path/to/your-project

# 3. Add your credentials to <your-project>/.mise.local.toml:
# [env]
# SONAR_HOST_URL = "https://sonar.your-team.com/"
# SONAR_TOKEN = "squ_your_personal_token"
```
*This configures the scanner, symlinks `scripts/sonar-scan.ts`, and adds `scan:diff` to that project's `.mise.toml`.*

---

### Option B: Multi-Project Workspace Setup (All Projects in a Folder)
If your team organizes repositories under a parent folder (like `~/work/` or `~/projects/`):

```bash
# 1. Clone into your parent directory as .sonar-scan (hidden)
git clone git@github.com:inregist/sonar-scan.git ~/work/.sonar-scan

# 2. Run the setup script (defaults to the parent directory)
~/work/.sonar-scan/setup.sh

# 3. Add credentials to ~/work/.mise.local.toml:
# [env]
# SONAR_HOST_URL = "https://sonar.your-team.com/"
# SONAR_TOKEN = "squ_your_personal_token"
```
*Every current and future repository under `~/work/` automatically inherits `mise scan:diff`.*

---

### Option C: Global CLI (Run Anywhere Without Local Files)
Install once globally on your machine:

```bash
npm install -g github:inregist/sonar-scan
```
Set credentials in your shell profile (`~/.zshrc`, `~/.bashrc`, or `~/.config/mise/config.toml`):
```bash
export SONAR_HOST_URL="https://sonar.your-team.com/"
export SONAR_TOKEN="squ_your_personal_token"
```
Then run in any Git repository:
```bash
sonar-scan --diff
```

---

## Usage

In any configured project:

```bash
# Fast diff scan (only modified & untracked files)
mise scan:diff

# Silent mode (outputs nothing if clean, only lists issues if they exist)
mise scan:diff --silent

# Full scan of the entire repository
mise scan
```

## Updating

When updates are pushed to this repo:
```bash
git -C /path/to/.sonar-scan pull
```
