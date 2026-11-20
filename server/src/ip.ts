/** Parses an IPv6 text address into 8 groups of 16 bits, or null if it is not one. */
export function expandIpv6(ip: string): number[] | null {
  let text = ip.trim().toLowerCase();
  const zone = text.indexOf("%");
  if (zone >= 0) text = text.slice(0, zone);
  if (!text.includes(":")) return null;

  // Embedded IPv4 in the last 32 bits (::ffff:1.2.3.4).
  const v4 = /^(.*:)(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(text);
  if (v4) {
    const o = [v4[2], v4[3], v4[4], v4[5]].map(Number);
    if (o.some((n) => n > 255)) return null;
    text = `${v4[1]}${((o[0]! << 8) | o[1]!).toString(16)}:${((o[2]! << 8) | o[3]!).toString(16)}`;
  }

  const halves = text.split("::");
  if (halves.length > 2) return null;
  const parse = (s: string): number[] | null => {
    if (s === "") return [];
    const out: number[] = [];
    for (const g of s.split(":")) {
      if (!/^[0-9a-f]{1,4}$/.test(g)) return null;
      out.push(parseInt(g, 16));
    }
    return out;
  };
  const head = parse(halves[0]!);
  const tail = halves.length === 2 ? parse(halves[1]!) : [];
  if (!head || !tail) return null;
  if (halves.length === 1) return head.length === 8 ? head : null;
  const missing = 8 - head.length - tail.length;
  if (missing < 1) return null;
  return [...head, ...new Array<number>(missing).fill(0), ...tail];
}

/**
 * The key used to count a client: the IPv4 address, or the /56 of an IPv6 address
 * (a home connection owns at least a /64, often a /56, so single addresses are free).
 */
export function clientKey(ip: string | null): string {
  if (!ip) return "unknown";
  const groups = expandIpv6(ip);
  if (!groups) return ip.trim();
  // IPv4-mapped (::ffff:a.b.c.d) is an IPv4 client, not a /56 of zeros.
  if (groups.slice(0, 5).every((x) => x === 0) && groups[5] === 0xffff) {
    return `${groups[6]! >> 8}.${groups[6]! & 255}.${groups[7]! >> 8}.${groups[7]! & 255}`;
  }
  const g = (n: number) => n.toString(16).padStart(4, "0");
  return `${g(groups[0]!)}:${g(groups[1]!)}:${g(groups[2]!)}:${g(groups[3]! & 0xff00)}::/56`;
}

/** Additional aggregate budget across the /56 networks of one IPv6 /48. */
export function clientKey48(ip: string | null): string {
  const key = clientKey(ip);
  return key.endsWith("::/56") ? `${key.split(":").slice(0, 3).join(":")}::/48` : key;
}
