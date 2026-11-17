/** Only a checked request URL can authorize the local workerd bypass. */
export function localhostRequest(request: Request): boolean {
  return ["localhost", "127.0.0.1", "[::1]"].includes(new URL(request.url).hostname);
}

/** workerd has no jurisdiction implementation. Alarms/internal RPCs without
 * request-local proof always keep EU, even if LOCAL_DEV was deployed by mistake.
 * Never infer local mode from a failed RPC or persist proof between requests. */
export function euNamespace<T extends { jurisdiction(j: "eu"): T }>(ns: T, env: { LOCAL_DEV?: string }, localRequest = false): T {
  return env.LOCAL_DEV === "true" && localRequest ? ns : ns.jurisdiction("eu");
}
