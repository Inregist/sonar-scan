#!/usr/bin/env node
import { execSync, spawnSync } from "node:child_process";
import { existsSync, readFileSync, statSync } from "node:fs";
import { writeFile } from "node:fs/promises";
import { basename, extname, resolve } from "node:path";
import process from "node:process";

interface SonarIssue {
  severity?: string;
  type?: string;
  rule?: string;
  component?: string;
  line?: number;
  message?: string;
}

function getProjectKey(): string {
  if (process.env.SONAR_PROJECT_KEY) return process.env.SONAR_PROJECT_KEY;
  try {
    const pkgPath = resolve(process.cwd(), "package.json");
    if (existsSync(pkgPath)) {
      const pkg = JSON.parse(readFileSync(pkgPath, "utf-8")) as { name?: string };
      if (pkg.name) return pkg.name.replace(/^@[^/]+\//, "");
    }
  } catch {}
  return basename(process.cwd());
}

const baseProjectKey = getProjectKey();
const outputFile = "sonar-report.json";
const hostUrl = process.env.SONAR_HOST_URL?.replace(/\/$/, "");
const token = process.env.SONAR_TOKEN;

if (!hostUrl || !token) {
  console.error("Error: SONAR_HOST_URL and SONAR_TOKEN must be configured in mise.");
  process.exit(1);
}

const args = process.argv.slice(2);
const exportOnly = args.includes("--export-only");
const printJson = args.includes("--json");
const strict = args.includes("--strict");
const verbose = args.includes("--verbose") || args.includes("-v") || args.includes("--summary");
const isSilent = !verbose && ["--silent", "--quiet", "--quite", "-q", "-s"].some((f) => args.includes(f));
const persist = args.includes("--keep") || args.includes("--persist");
const isDiffMode = args.includes("--diff");

function getCurrentBranch(): string {
  try {
    return execSync("/usr/bin/git rev-parse --abbrev-ref HEAD", { encoding: "utf-8", stdio: ["ignore", "pipe", "ignore"] })
      .trim().replace(/[^a-zA-Z0-9_.-]/g, "-");
  } catch {
    return "local";
  }
}

function getBaseBranch(): string {
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === "--base" || a === "--against" || a === "--target") {
      if (args[i + 1] && !args[i + 1].startsWith("-")) return args[i + 1];
    }
    if (a.startsWith("--base=") || a.startsWith("--against=") || a.startsWith("--target=")) {
      const val = a.split("=")[1];
      if (val) return val;
    }
    if (a.startsWith("--diff=") && a.split("=")[1]) return a.split("=")[1];
  }
  if (process.env.SONAR_BASE_BRANCH?.trim()) return process.env.SONAR_BASE_BRANCH.trim();
  try {
    const ref = execSync("/usr/bin/git symbolic-ref refs/remotes/origin/HEAD", {
      encoding: "utf-8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
    const branch = ref.replace(/^refs\/remotes\/origin\//, "");
    if (branch) return branch;
  } catch {}
  return "main";
}

function getChangedFiles(branchName: string, baseBranch: string): string[] {
  const runGit = (gitArgs: string) => {
    try {
      return execSync(`/usr/bin/git ${gitArgs}`, { encoding: "utf-8", stdio: ["ignore", "pipe", "ignore"] })
        .split("\n").map((f) => f.trim()).filter(Boolean);
    } catch {
      return [];
    }
  };

  const files = new Set([
    ...runGit("ls-files --others --exclude-standard"),
    ...runGit("diff --name-only HEAD"),
  ]);

  if (branchName && branchName !== "local") {
    let diff = runGit(`diff --name-only origin/${baseBranch}...HEAD`);
    if (!diff.length && branchName !== baseBranch) diff = runGit(`diff --name-only ${baseBranch}...HEAD`);
    if (!diff.length) {
      const u = runGit("rev-parse --abbrev-ref --symbolic-full-name @{u}")[0];
      if (u) diff = runGit(`diff --name-only ${u}..HEAD`);
    }
    for (const f of diff) files.add(f);
  }
  const ignored = new Set([
    ".lock", ".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico",
    ".svg", ".woff", ".woff2", ".ttf", ".pdf", ".zip", ".gz",
  ]);
  return Array.from(files).filter((f) => {
    if (f.endsWith("pnpm-lock.yaml") || f.endsWith("routeTree.gen.ts") || !existsSync(f)) return false;
    try {
      if (!statSync(f).isFile()) return false;
    } catch {
      return false;
    }
    return !ignored.has(extname(f).toLowerCase());
  });
}

const branch = getCurrentBranch();
const isEphemeral = !persist && !exportOnly;
const projectKey = isEphemeral ? `${baseProjectKey}:${branch}-${Date.now()}` : baseProjectKey;
const basicAuth = Buffer.from(`${token}:`).toString("base64");
const headers = { Authorization: `Basic ${basicAuth}`, Accept: "application/json" };

async function deleteServerProject(key: string): Promise<void> {
  try {
    await fetch(`${hostUrl}/api/projects/delete?project=${encodeURIComponent(key)}`, {
      method: "POST",
      headers,
    });
  } catch {}
}

const baseBranch = getBaseBranch();
const changedFiles = isDiffMode ? getChangedFiles(branch, baseBranch) : [];
if (isDiffMode && changedFiles.length === 0) {
  if (printJson) {
    console.log(
      JSON.stringify({ projectKey: baseProjectKey, branch, totalIssues: 0, issues: [] }, null, 2),
    );
  } else if (!isSilent) {
    console.log("✓ No new or changed files detected in git.");
  }
  process.exit(0);
}

let scannerExitCode: number | null = 0;
if (!exportOnly) {
  if (!printJson && !isSilent) {
    console.log(
      isDiffMode
        ? `Starting SonarQube diff scan (${changedFiles.length} changed file(s) vs ${baseBranch}) [${baseProjectKey}]...`
        : `Starting SonarQube scan (branch: ${branch}) [${baseProjectKey}]...`,
    );
  }

  const scannerArgs = [
    `-Dsonar.projectKey=${projectKey}`,
    `-Dsonar.projectName=${baseProjectKey} (${branch})`,
    "-Dsonar.qualitygate.wait=true",
  ];
  const TEST_PATTERNS = "**/*.test.*,**/*.spec.*,**/test/**,**/tests/**";
  const DEFAULT_EXCL = `**/node_modules/**,**/dist/**,**/build/**,**/.wrangler/**,**/coverage/**,**/.tanstack/**,**/routeTree.gen.ts,${TEST_PATTERNS}`;
  let props = "";
  if (existsSync("sonar-project.properties")) {
    try { props = readFileSync("sonar-project.properties", "utf-8"); } catch {}
  }
  const has = (flag: string, re: RegExp) => args.some((a) => a.startsWith(flag)) || re.test(props);
  if (!has("-Dsonar.sources=", /^\s*sonar\.sources\s*=/m)) scannerArgs.push("-Dsonar.sources=.");
  if (!has("-Dsonar.tests=", /^\s*sonar\.tests\s*=/m)) {
    scannerArgs.push("-Dsonar.tests=.", `-Dsonar.test.inclusions=${TEST_PATTERNS}`);
  }
  if (!has("-Dsonar.exclusions=", /^\s*sonar\.exclusions\s*=/m)) scannerArgs.push(`-Dsonar.exclusions=${DEFAULT_EXCL}`);
  if (isDiffMode && changedFiles.length > 0)
    scannerArgs.push(`-Dsonar.inclusions=${changedFiles.join(",")}`);
  const skip = new Set([
    "--export-only", "--json", "--strict", "--keep", "--persist", "--verbose",
    "-v", "--diff", "--quiet", "--quite", "-q", "--silent", "-s", "--summary",
    "--base", "--against", "--target",
  ]);
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (skip.has(a)) {
      if ((a === "--base" || a === "--against" || a === "--target") && i + 1 < args.length && !args[i + 1].startsWith("-")) i++;
      continue;
    }
    if (a.startsWith("--base=") || a.startsWith("--against=") || a.startsWith("--target=") || a.startsWith("--diff=")) continue;
    scannerArgs.push(a);
  }

  function findScannerBinary(): string {
    const custom = process.env.SONAR_SCANNER_BIN;
    if (custom && existsSync(custom)) return custom;
    for (const dir of (process.env.PATH ?? "").split(":")) {
      const candidate = dir ? resolve(dir, "sonar-scanner") : "";
      if (candidate && existsSync(candidate)) return candidate;
    }
    return "sonar-scanner";
  }

  const scannerBin = findScannerBinary();
  const scanner = spawnSync(scannerBin, scannerArgs, {
    stdio: verbose ? "inherit" : ["ignore", "ignore", "inherit"],
  });

  scannerExitCode = scanner.status;
  if (scannerExitCode !== 0 && scannerExitCode !== 3) {
    if (isEphemeral) await deleteServerProject(projectKey);
    console.error(`SonarScanner failed with exit code ${scannerExitCode ?? 1}`);
    process.exit(scannerExitCode ?? 1);
  }
}

if (!printJson && !isSilent) console.log("Fetching analysis results from server...");

function formatIssue(it: SonarIssue): string {
  const line = typeof it.line === "number" ? `:${it.line}` : "";
  return `  [${it.severity ?? "UNKNOWN"}] ${it.type ?? "ISSUE"} ${it.rule ?? ""} in ${it.component ?? ""}${line} -> ${it.message ?? ""}`;
}

try {
  const encKey = encodeURIComponent(projectKey);
  const [qgRes, measuresRes] = await Promise.all([
    fetch(`${hostUrl}/api/qualitygates/project_status?projectKey=${encKey}`, { headers }),
    fetch(
      `${hostUrl}/api/measures/component?component=${encKey}&metricKeys=bugs,vulnerabilities,code_smells,security_hotspots,coverage,duplicated_lines_density`,
      { headers },
    ),
  ]);

  const qgData = (await qgRes.json()) as { projectStatus?: { status?: string } };
  const measuresData = (await measuresRes.json()) as {
    component?: { measures?: Array<{ metric: string; value: string }> };
  };

  let page = 1;
  const allIssues: SonarIssue[] = [];
  let totalIssues = 0;

  while (true) {
    const res = await fetch(
      `${hostUrl}/api/issues/search?componentKeys=${encKey}&ps=500&p=${page}`,
      { headers },
    );
    if (!res.ok) break;
    const data = (await res.json()) as { total?: number; issues?: SonarIssue[] };
    totalIssues = data.total ?? 0;
    const raw = data.issues ?? [];
    for (const it of raw) {
      const comp = typeof it.component === "string" ? it.component.split(":").pop() : it.component;
      allIssues.push({ ...it, component: comp });
    }
    if (allIssues.length >= totalIssues || raw.length === 0) break;
    page++;
  }

  const measures = measuresData.component?.measures ?? [];
  const report = {
    projectKey: baseProjectKey,
    branch,
    diffMode: isDiffMode,
    scannedFiles: isDiffMode ? changedFiles : "all",
    generatedAt: new Date().toISOString(),
    serverUrl: hostUrl,
    qualityGate: qgData.projectStatus ?? null,
    measures,
    totalIssues,
    issues: allIssues,
  };

  await writeFile(resolve(process.cwd(), outputFile), JSON.stringify(report, null, 2), "utf-8");

  if (printJson) {
    console.log(JSON.stringify(report, null, 2));
  } else if (isSilent) {
    for (const it of allIssues) console.log(formatIssue(it));
  } else {
    const getM = (name: string) => measures.find((m) => m.metric === name)?.value ?? "-";
    console.log(
      `\n✓ SonarQube report written to: ${outputFile}\n  Project         : ${baseProjectKey}\n  Quality Gate    : ${qgData.projectStatus?.status ?? "UNKNOWN"}\n  Bugs            : ${getM("bugs")}\n  Vulnerabilities : ${getM("vulnerabilities")}\n  Code Smells     : ${getM("code_smells")}\n  Coverage        : ${getM("coverage")}%\n  Duplication     : ${getM("duplicated_lines_density")}%\n  Total Issues    : ${totalIssues}`,
    );
    if (allIssues.length > 0) {
      console.log("\nIssues:");
      for (const it of allIssues) console.log(formatIssue(it));
    }
  }
} finally {
  if (isEphemeral) {
    await deleteServerProject(projectKey);
    if (!printJson && !isSilent) console.log("✓ Disposed temporary project from SonarQube server.");
  }
}

if (strict && scannerExitCode === 3) process.exit(3);
