# sonar-scan

Fast SonarQube diff & full scan runner for Monorepos and Git projects.

## Features
- **Fast Git Diff Scan**: Scans only untracked/modified/branch-diff files in seconds (`mise scan:diff`).
- **Zero Server Clutter**: Runs against temporary ephemeral keys and deletes them upon completion.
- **Terminal Issue Formatting**: Formats issues cleanly without needing `jq`.
- **Dynamic Project Detection**: Automatically derives project key from `package.json` or folder name.
- **Silent Mode**: Exits with zero output when 0 issues are found (`--silent` / `-s` / `--quiet` / `-q`).

## Team Setup (Run Once)

```bash
# 1. Clone into your work directory as .sonar-scan (hidden)
git clone git@github.com:inregist/sonar-scan.git ~/work/.sonar-scan

# 2. Run the setup script to symlink and configure ~/work/.mise.toml
~/work/.sonar-scan/setup.sh

# 3. Configure credentials in ~/work/.mise.local.toml:
# [env]
# SONAR_HOST_URL = "https://sonar.your-team.com/"
# SONAR_TOKEN = "squ_your_personal_token"
```

## Usage

In any repository or subproject under `~/work/`:

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
git -C ~/work/.sonar-scan pull
```
