# sonar-scan

Fast SonarQube diff & full scan runner for Monorepos and Git projects.

## Features
- **Fast Git Diff Scan**: Scans only untracked/modified/branch-diff files in seconds (`mise scan:diff`).
- **Zero Server Clutter**: Runs against temporary ephemeral keys and deletes them upon completion.
- **Terminal Issue Formatting**: Formats issues cleanly without needing `jq`.
- **Dynamic Project Detection**: Automatically derives project key from `package.json` or folder name.
- **Silent Mode**: Exits with zero output when 0 issues are found (`--silent` / `-s` / `--quiet` / `-q`).

---

## Quick Setup (Per-Project by Default)

From inside your Git project:

```bash
# 1. Clone into your project
git clone git@github.com:inregist/sonar-scan.git .sonar-scan

# 2. Run setup (configures the current project by default)
./.sonar-scan/setup.sh

# 3. Add credentials to .mise.local.toml:
# [env]
# SONAR_HOST_URL = "https://sonar.your-team.com/"
# SONAR_TOKEN = "squ_your_personal_token"
```

The setup script automatically:
- Symlinks `scripts/sonar-scan.ts` -> `.sonar-scan/scripts/sonar-scan.ts`.
- Configures `.mise.toml` with `node = "lts"`, `sonar-scanner-cli = "latest"`, `jq = "latest"`, and `scan:diff`.
- Provisions the tools via Mise.
- Automatically adds `.sonar-scan/`, `.mise.local.toml`, `.scannerwork/`, and `sonar-report.json` to `.gitignore`.

---

## Other Setup Options

### Option B: Shared Workspace Setup (Multi-Project Folder)
If your team keeps multiple projects under a shared parent directory (e.g. `~/work/`):

```bash
git clone git@github.com:inregist/sonar-scan.git ~/work/.sonar-scan
~/work/.sonar-scan/setup.sh --workspace
```
*All sibling projects under `~/work/` will inherit `mise scan:diff` automatically.*

### Option C: Global CLI (Zero Files in Repo)
Install globally to run across any repository on your machine:

```bash
npm install -g github:inregist/sonar-scan
```
Set credentials in your shell profile (`~/.zshrc` or `~/.bashrc`):
```bash
export SONAR_HOST_URL="https://sonar.your-team.com/"
export SONAR_TOKEN="squ_your_personal_token"
```
Then run:
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

- Per-project: `git -C .sonar-scan pull`
- Workspace: `git -C ~/work/.sonar-scan pull`
- Global: `npm install -g github:inregist/sonar-scan@latest`
