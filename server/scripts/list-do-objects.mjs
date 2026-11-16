import { writeFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

const hex32 = /^[a-f0-9]{32}$/;
const hex64 = /^[a-f0-9]{64}$/;

/** Read-only API pagination. Never log a response body or token, never retry implicitly. */
export async function listObjects(accountId, namespaceId, token, fetcher = fetch) {
  if (!hex32.test(accountId) || !hex32.test(namespaceId) || !token) throw new Error("Invalid account, namespace or missing API token");
  const ids = new Set(), cursors = new Set();
  let cursor;
  do {
    const url = new URL(`https://api.cloudflare.com/client/v4/accounts/${accountId}/workers/durable_objects/namespaces/${namespaceId}/objects`);
    url.searchParams.set("limit", "1000");
    if (cursor) url.searchParams.set("cursor", cursor);
    const response = await fetcher(url, {
      headers: { Authorization: `Bearer ${token}` },
      redirect: "error",
      signal: AbortSignal.timeout(30_000),
    });
    if (!response.ok) throw new Error(`Object listing failed (HTTP ${response.status}); no retry or output file`);
    const page = await response.json();
    if (page.success !== true || !Array.isArray(page.result)) throw new Error("Invalid object-list response");
    for (const row of page.result) {
      if (typeof row?.id !== "string" || !hex64.test(row.id)) throw new Error("Invalid object ID in API response");
      ids.add(row.id); // Include empty objects as well; the RPC leaves them empty.
    }
    // Cloudflare's DurableObjectsCursorPaginationAfter uses cursors.after.
    cursor = page.result_info?.cursors?.after ?? page.result_info?.cursor;
    if (cursor != null && typeof cursor !== "string") throw new Error("Invalid pagination cursor");
    if (cursor && cursors.has(cursor)) throw new Error("Repeated pagination cursor; listing incomplete");
    if (cursor) cursors.add(cursor);
  } while (cursor);
  return [...ids].sort();
}

export async function main(args, token = process.env.CLOUDFLARE_API_TOKEN) {
  const [accountId, listsNamespace, recoveriesNamespace, output] = args;
  if (args.length !== 4 || !output || listsNamespace === recoveriesNamespace) {
    throw new Error("Usage: node scripts/list-do-objects.mjs ACCOUNT_ID LISTS_NAMESPACE_ID RECOVERIES_NAMESPACE_ID OUTPUT.json");
  }
  // Finish both enumerations before writing anything; exclusive creation avoids clobbering a completed inventory.
  const lists = await listObjects(accountId, listsNamespace, token);
  const recoveries = await listObjects(accountId, recoveriesNamespace, token);
  const inventory = {
    version: 1, scriptName: "gift-huddle-sync", jurisdiction: "eu", accountId,
    namespaces: {
      ListV2Object: { namespaceId: listsNamespace, ids: lists },
      RecoveryLocatorObject: { namespaceId: recoveriesNamespace, ids: recoveries },
    },
  };
  await writeFile(output, `${JSON.stringify(inventory, null, 2)}\n`, { flag: "wx", mode: 0o600 });
  console.log(`Inventory written: ${lists.length} lists, ${recoveries.length} recovery locators`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2)).catch(() => {
    console.error("Inventory failed. Check arguments, API access and pagination; no automatic retry. Token and API responses are never printed.");
    process.exitCode = 1;
  });
}
