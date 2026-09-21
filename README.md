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

Choose the setup pattern that fits your workflow:

### Option A: Per-Project via Package Manager *(Cleanest for Single Projects)*
Install directly into your repository as a development dependency without cloning anything extra:

```bash
cd your-project
pnpm add -D github:inregist/sonar-scan
# or: npm install -D github:inregist/sonar-scan
```

Add the scripts to your `package.json`:
```json
{
  "scripts": {
    "scan:diff": "sonar-scan --diff",
    "scan": "sonar-scan"
  }
}
```

Add your credentials to `.mise.local.toml` or `.env.local`:
```toml
[env]
SONAR_HOST_URL = "https://sonar.your-team.com/"
SONAR_TOKEN = "squ_your_personal_token"
```

---

### Option B: Workspace Setup *(Shared Across Projects in a Folder)*
If your team keeps multiple repositories under a parent folder (e.g. `~/work/` or `~/projects/`):

```bash
# 1. Clone into your parent directory
git clone git@github.com:inregist/sonar-scan.git ~/work/.sonar-scan

# 2. Run the setup script
~/work/.sonar-scan/setup.sh

# 3. Add your credentials to ~/work/.mise.local.toml:
# [env]
# SONAR_HOST_URL = "https://sonar.your-team.com/"
# SONAR_TOKEN = "squ_your_personal_token"
```
*Every current and future repository under that folder automatically inherits `mise scan:diff`.*

---

### Option C: Global CLI *(Zero Repo Files)*
Install globally on your machine to use across any Git repository:

```bash
npm install -g github:inregist/sonar-scan
```

Configure credentials once in your shell profile (`~/.zshrc`, `~/.bashrc`, or `~/.config/mise/config.toml`):
```bash
export SONAR_HOST_URL="https://sonar.your-team.com/"
export SONAR_TOKEN="squ_your_personal_token"
```

Run in any Git repository:
```bash
sonar-scan --diff
```

---

## Usage

In any configured project:

```bash
# Fast diff scan (only modified & untracked files)
mise scan:diff
# (or if using npm scripts: pnpm scan:diff)

# Silent mode (outputs nothing if clean, only lists issues if they exist)
mise scan:diff --silent

# Full scan of the entire repository
mise scan
```

## Updating

- If installed via workspace: `git -C ~/work/.sonar-scan pull`
- If installed via package manager: `pnpm update @inregist/sonar-scan`
- If installed globally: `npm install -g github:inregist/sonar-scan@latest`
