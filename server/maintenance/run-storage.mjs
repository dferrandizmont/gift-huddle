import { readFile } from "node:fs/promises";
import { setTimeout as pause } from "node:timers/promises";
import { pathToFileURL } from "node:url";
import { inventoryObjects } from "./run-retention.mjs";

const MIN_INACTIVE_DAYS = 30;
const DAY_MS = 86_400_000;
// Keep in sync with worker.ts, using the release's UTC date.
const DATED_LISTS_FROM = Date.UTC(2026, 10, 20);
const PLAN_VERSION = 2;
const endpoint = "http://127.0.0.1:8791";
const usage = "Usage: node maintenance/run-storage.mjs usage | purge [--include-legacy] INVENTORY.json INACTIVE_DAYS FROM_UTC BEFORE_UTC | purge [--include-legacy] --apply PLAN.json";
const isTimestamp = (n) => Number.isSafeInteger(n) && n >= 0;

function utcDate(value) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new Error("Use YYYY-MM-DD for UTC dates");
  const time = Date.parse(value);
  if (!isTimestamp(time) || new Date(time).toISOString().slice(0, 10) !== value) throw new Error("Invalid UTC date");
  return time;
}

function validateCriteria(criteria, allowLegacy) {
  const { createdFrom, createdBefore, inactiveBefore, includeLegacy } = criteria ?? {};
  if (!isTimestamp(createdFrom) || !isTimestamp(createdBefore) || createdFrom >= createdBefore ||
      !isTimestamp(inactiveBefore) || inactiveBefore > Date.now() - MIN_INACTIVE_DAYS * DAY_MS) {
    throw new Error("Invalid purge window or inactivity cutoff (minimum 30 days)");
  }
  if ((createdFrom < DATED_LISTS_FROM || includeLegacy === true) && !allowLegacy) {
    throw new Error("This purge window or plan requires --include-legacy");
  }
  if ((includeLegacy !== undefined && includeLegacy !== true) ||
      (createdFrom < DATED_LISTS_FROM && includeLegacy !== true)) throw new Error("Invalid legacy purge criteria");
  return { createdFrom, createdBefore, inactiveBefore, ...(includeLegacy === true ? { includeLegacy } : {}) };
}

function validateCandidates(candidates) {
  if (!Array.isArray(candidates)) throw new Error("Invalid purge candidates");
  const seen = new Set();
  for (const entry of candidates) {
    if (!entry || typeof entry.id !== "string" || !/^[a-f0-9]{64}$/.test(entry.id) || seen.has(entry.id) ||
        (entry.createdAt !== null && !isTimestamp(entry.createdAt)) || !isTimestamp(entry.lastActivity) ||
        !Number.isSafeInteger(entry.version) || entry.version < 1 ||
        !isTimestamp(entry.storedBytes) || entry.hasRecovery !== false || !isTimestamp(entry.pendingInvites)) {
      throw new Error("Invalid or duplicate purge candidate");
    }
    seen.add(entry.id);
  }
  return candidates;
}

async function request(path, fetcher, options) {
  const response = await fetcher(endpoint + path, { ...options, redirect: "error", signal: AbortSignal.timeout(120_000) });
  if (!response.ok) throw new Error("Maintenance RPC failed");
  return response.json();
}

export async function run(args, { fetcher = fetch, read = readFile, sleep = pause, log = console.log, warn = console.error } = {}) {
  if (args.length === 1 && args[0] === "usage") {
    try {
      const result = await request("/storage-occupancy", fetcher);
      if (!isTimestamp(result.reservedBytes) || !isTimestamp(result.ceilingBytes) || result.ceilingBytes === 0 ||
          !Number.isFinite(result.percent) || result.percent < 0) throw new Error();
      log(JSON.stringify(result));
      if (result.percent >= 50) warn(`Storage ledger at ${result.percent.toFixed(2)}% of its ceiling`);
    } catch { throw new Error("Could not read storage occupancy"); }
    return;
  }

  const [command, ...purgeArgs] = args;
  const includeLegacy = purgeArgs[0] === "--include-legacy";
  const positional = includeLegacy ? purgeArgs.slice(1) : purgeArgs;
  const [input, daysOrPlan, from, before] = positional;
  const apply = command === "purge" && input === "--apply" && positional.length === 2;
  if (!apply && (command !== "purge" || positional.length !== 4 || input.startsWith("--") || !/^\d+$/.test(daysOrPlan))) {
    throw new Error(usage);
  }
  let data;
  try { data = JSON.parse(await read(apply ? daysOrPlan : input, "utf8")); }
  catch { throw new Error("Could not read purge inventory or plan"); }
  if (apply && data?.version !== PLAN_VERSION) throw new Error("Invalid purge plan");
  const criteria = validateCriteria(apply ? data.criteria : {
    createdFrom: utcDate(from), createdBefore: utcDate(before),
    inactiveBefore: Date.now() - Number(daysOrPlan) * DAY_MS,
    ...(includeLegacy ? { includeLegacy: true } : {}),
  }, includeLegacy);
  const objects = apply
    ? validateCandidates(data.candidates).map(({ id, createdAt, lastActivity, version, storedBytes, hasRecovery, pendingInvites }) => ({
        id, expected: { createdAt, lastActivity, version, storedBytes, hasRecovery, pendingInvites },
      }))
    : inventoryObjects(data).filter(({ className }) => className === "ListV2Object").map(({ id }) => ({ id }));

  let purged = 0;
  const candidates = [];
  for (let offset = 0; offset < objects.length; offset += 20) {
    const batch = objects.slice(offset, offset + 20);
    try {
      const result = await request("/purge-inactive", fetcher, {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ criteria, objects: batch, ...(apply ? { apply: true } : {}) }),
      });
      if (apply) {
        if (!Number.isSafeInteger(result.purged) || result.purged < 0 || result.purged > batch.length) throw new Error();
        purged += result.purged;
      } else {
        const found = validateCandidates(result.candidates);
        if (found.some(({ id }) => !batch.some((item) => item.id === id))) throw new Error();
        candidates.push(...found);
      }
    } catch { throw new Error(`Stopped at batch offset ${offset}. The same input can be run again.`); }
    if (offset + batch.length < objects.length) await sleep(1000);
  }
  log(JSON.stringify(apply ? { purged, reviewed: objects.length } : { version: PLAN_VERSION, criteria, candidates }, null, 2));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try { await run(process.argv.slice(2)); }
  catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
