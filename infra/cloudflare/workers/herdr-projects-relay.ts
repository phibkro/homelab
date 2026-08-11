import { DurableObject } from "cloudflare:workers";

type RelayRequest = {
  id: string;
  method: string;
  headers: Record<string, string>;
  body: string;
};

type RelayResponse = {
  id: string;
  status: number;
  headers: Record<string, string>;
  body: string;
};

interface Env {
  RelaySession: DurableObjectNamespace<RelaySession>;
  RELAY_TOKEN: string;
}

const allowedMethods = new Set(["GET", "POST", "DELETE"]);
const forwardedRequestHeaders = [
  "accept",
  "content-type",
  "last-event-id",
  "mcp-protocol-version",
  "mcp-session-id",
] as const;

const sameToken = async (provided: string | null, expected: string) => {
  if (!provided) return false;
  const encoder = new TextEncoder();
  const [left, right] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(provided)),
    crypto.subtle.digest("SHA-256", encoder.encode(expected)),
  ]);
  const leftBytes = new Uint8Array(left);
  const rightBytes = new Uint8Array(right);
  let different = leftBytes.length ^ rightBytes.length;
  for (let index = 0; index < leftBytes.length; index += 1) {
    different |= leftBytes[index]! ^ rightBytes[index]!;
  }
  return different === 0;
};

export class RelaySession extends DurableObject<Env> {
  private readonly pending = new Map<
    string,
    {
      resolve: (response: RelayResponse) => void;
      reject: (error: Error) => void;
      timeout: ReturnType<typeof setTimeout>;
    }
  >();

  async fetch(request: Request): Promise<Response> {
    if (request.headers.get("upgrade")?.toLowerCase() !== "websocket") {
      return new Response("WebSocket upgrade required", { status: 426 });
    }
    for (const socket of this.ctx.getWebSockets("connector")) {
      socket.close(1012, "connector replaced");
    }
    const pair = new WebSocketPair();
    this.ctx.acceptWebSocket(pair[1], ["connector"]);
    return new Response(null, { status: 101, webSocket: pair[0] });
  }

  connected(): boolean {
    return this.ctx.getWebSockets("connector").some((socket) => socket.readyState === 1);
  }

  async forward(request: Omit<RelayRequest, "id">): Promise<RelayResponse> {
    const socket = this.ctx
      .getWebSockets("connector")
      .find((candidate) => candidate.readyState === 1);
    if (!socket) throw new Error("workstation connector unavailable");

    const id = crypto.randomUUID();
    const response = new Promise<RelayResponse>((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error("workstation connector timed out"));
      }, 95_000);
      this.pending.set(id, { resolve, reject, timeout });
    });
    socket.send(JSON.stringify({ id, ...request } satisfies RelayRequest));
    return response;
  }

  webSocketMessage(_socket: WebSocket, message: string | ArrayBuffer): void {
    try {
      const response = JSON.parse(
        typeof message === "string" ? message : new TextDecoder().decode(message),
      ) as Partial<RelayResponse>;
      if (typeof response.id !== "string") return;
      const pending = this.pending.get(response.id);
      if (!pending) return;
      clearTimeout(pending.timeout);
      this.pending.delete(response.id);
      pending.resolve(response as RelayResponse);
    } catch (error) {
      console.error(JSON.stringify({ event: "relay_invalid_response", error: String(error) }));
    }
  }

  webSocketClose(_socket: WebSocket, code: number, reason: string): void {
    const error = new Error(`workstation connector closed (${code}: ${reason})`);
    for (const [id, pending] of this.pending) {
      clearTimeout(pending.timeout);
      pending.reject(error);
      this.pending.delete(id);
    }
  }
}

const session = (env: Env) => env.RelaySession.getByName("projects");

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/relay/connect") {
      if (!(await sameToken(request.headers.get("x-relay-token"), env.RELAY_TOKEN))) {
        return new Response("Unauthorized", { status: 401 });
      }
      return session(env).fetch(request);
    }
    if (url.pathname === "/healthz") {
      return Response.json({ connected: await session(env).connected() });
    }
    if (url.pathname !== "/mcp") return new Response("Not found", { status: 404 });
    if (!(await sameToken(request.headers.get("authorization"), `Bearer ${env.RELAY_TOKEN}`))) {
      return new Response("Unauthorized", { status: 401 });
    }
    if (!allowedMethods.has(request.method)) {
      return new Response("Method not allowed", { status: 405 });
    }

    const body = request.method === "POST" ? await request.text() : "";
    if (body.length > 1_048_576) return new Response("Request too large", { status: 413 });
    const headers: Record<string, string> = {};
    for (const name of forwardedRequestHeaders) {
      const value = request.headers.get(name);
      if (value) headers[name] = value;
    }

    try {
      const response = await session(env).forward({ method: request.method, headers, body });
      return new Response(response.body, {
        status: response.status,
        headers: response.headers,
      });
    } catch (error) {
      console.error(JSON.stringify({ event: "relay_forward_failed", error: String(error) }));
      return Response.json({ error: "workstation connector unavailable" }, { status: 503 });
    }
  },
};
