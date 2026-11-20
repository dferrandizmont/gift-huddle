import { RpcTarget } from "cloudflare:workers";

/** The list invokes this capability only after authenticating under its lock.
 * Passing a raw stream to RPC can prefetch bytes before authentication. Keeping
 * the reader behind an RPC target prevents even that initial read. */
export class AuthenticatedBody extends RpcTarget {
  constructor(private readonly request: Request) { super(); }
  open(): Request {
    const headers = new Headers();
    for (const name of ["Content-Type", "Content-Length"]) {
      const value = this.request.headers.get(name);
      if (value !== null) headers.set(name, value);
    }
    return new Request("https://internal/body", { method: "PUT", headers, body: this.request.body });
  }
}
