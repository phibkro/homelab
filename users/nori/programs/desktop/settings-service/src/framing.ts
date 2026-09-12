/* runtime-adapter: one bounded JSON frame per half-closed Unix socket direction. */
import type { Socket } from "node:net";
import { DesktopSettingsError } from "./contracts.ts";

export const maxFrameBytes = 64 * 1024;

export function encodeFrame(value: unknown): Buffer {
  const body = Buffer.from(JSON.stringify(value), "utf8");
  if (body.byteLength > maxFrameBytes) {
    throw new DesktopSettingsError("invalid_request", "IPC frame exceeds the 64 KiB limit");
  }
  const frame = Buffer.allocUnsafe(4 + body.byteLength);
  frame.writeUInt32BE(body.byteLength, 0);
  body.copy(frame, 4);
  return frame;
}

/** Read a bounded frame. Public ingress guarantees a second frame is never dispatched. */
export function readFrame(socket: Socket): Promise<string> {
  const { promise, reject, resolve } = Promise.withResolvers<string>();
  let bytes = Buffer.alloc(0);
  let expected: number | undefined;
  let settled = false;

  const finish = (action: () => void) => {
    if (settled) return;
    settled = true;
    socket.off("data", onData);
    socket.off("end", onEnd);
    socket.off("error", onError);
    action();
  };
  const fail = (message: string) =>
    finish(() => reject(new DesktopSettingsError("invalid_request", message)));
  const onError = (cause: Error) =>
    finish(() => reject(new DesktopSettingsError("unavailable", `IPC connection failed: ${cause.message}`)));
  const onData = (chunk: Buffer) => {
    bytes = Buffer.concat([bytes, chunk]);
    if (expected === undefined && bytes.byteLength >= 4) {
      expected = bytes.readUInt32BE(0);
      if (expected > maxFrameBytes) {
        fail("IPC frame exceeds the 64 KiB limit");
        return;
      }
    }
    if (expected !== undefined && bytes.byteLength === 4 + expected) {
      finish(() => resolve(bytes.subarray(4).toString("utf8")));
      return;
    }
    if (expected !== undefined && bytes.byteLength > 4 + expected) {
      fail("IPC connection contains trailing frames");
    }
  };
  const onEnd = () => {
    if (expected === undefined || bytes.byteLength !== 4 + expected) {
      fail(`IPC connection ended before one complete frame (${bytes.byteLength} bytes received)`);
    }
  };

  socket.on("data", onData);
  socket.once("end", onEnd);
  socket.once("error", onError);
  return promise;
}

export function writeFrame(socket: Socket, value: unknown): void {
  socket.write(encodeFrame(value));
}

export function endFrame(socket: Socket, value: unknown): void {
  writeFrame(socket, value);
  socket.end();
}
