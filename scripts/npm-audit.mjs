#!/usr/bin/env node
// Dependency audit gate: `npm audit --json` filtered through a committed
// allowlist (.audit-allow.json) of advisories that are unpatched upstream
// and accepted as risk. Passthrough vulnerabilities ("depends on
// vulnerable versions of X") are covered when every advisory at the end
// of their `via` chain is allowlisted and unexpired. Exit 1 fails the
// gate on anything else at or above the severity level (default high).
//
//   node scripts/npm-audit.mjs [low|moderate|high|critical]
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const levelArg = process.argv[2] ?? "high";
const ORDER = ["info", "low", "moderate", "high", "critical"];
const threshold = ORDER.indexOf(levelArg);
if (threshold === -1) {
  console.error(`usage: npm-audit.mjs [${ORDER.join("|")}]`);
  process.exit(2);
}

const allowlist = JSON.parse(readFileSync(join(root, ".audit-allow.json"), "utf8"));
const today = new Date().toISOString().slice(0, 10);
const allowed = new Map(
  Object.entries(allowlist).map(([url, meta]) => [
    url,
    { ...meta, expired: Boolean(meta.expires && meta.expires < today) },
  ])
);

// Resolve npm without consulting PATH (SonarCloud S4036): under
// `npm run audit` npm_execpath is npm's own cli.js; standalone, npm
// sits next to the node binary — both are fixed, unwritable locations.
const npmCli = process.env.npm_execpath;
const nodeBin = process.env.npm_node_execpath ?? process.execPath;
const npmBin = join(
  dirname(nodeBin),
  process.platform === "win32" ? "npm.cmd" : "npm"
);
const [cmd, args] = npmCli
  ? [nodeBin, [npmCli, "audit", "--json"]]
  : [npmBin, ["audit", "--json"]];
const { stdout, error } = spawnSync(cmd, args, {
  cwd: root,
  encoding: "utf8",
});
if (error) throw error;
const report = JSON.parse(stdout || "{}");
const vulns = report.vulnerabilities ?? {};

// A vulnerability is covered when every advisory it carries is
// allowlisted (unexpired) and every package it names via strings is
// itself covered.
const coveredCache = new Map();
function covered(name, visiting = new Set()) {
  if (coveredCache.has(name)) return coveredCache.get(name);
  if (visiting.has(name)) return false;
  visiting.add(name);
  const v = vulns[name];
  const urls = v.via.filter((x) => typeof x === "object").map((x) => x.url);
  const deps = v.via.filter((x) => typeof x === "string");
  const ok =
    urls.every((u) => allowed.has(u) && !allowed.get(u).expired) &&
    deps.every((dep) => covered(dep, visiting));
  coveredCache.set(name, ok);
  return ok;
}

const failures = [];
for (const [name, v] of Object.entries(vulns)) {
  const sev = ORDER.indexOf(v.severity);
  if (sev >= threshold && !covered(name)) {
    const urls = v.via.filter((x) => typeof x === "object").map((x) => x.url);
    failures.push(`${name} (${v.severity}) ${urls.join(" ")}`);
  }
}

for (const [url, meta] of allowed) {
  if (meta.expired) {
    console.error(`allowlist entry EXPIRED (${meta.expires}): ${url}`);
    failures.push(`expired allowlist entry ${url}`);
  }
}

if (failures.length) {
  console.error("npm audit gate FAILED:\n  " + failures.join("\n  "));
  process.exit(1);
}
const accepted = allowed.size;
console.log(
  `npm audit gate passed (level=${levelArg}, ${Object.keys(vulns).length} vuln entries, ${accepted} allowlisted)`
);
