import { describe, expect, test } from "bun:test";
import { parseVsockHandshake } from "./firecracker-environment-launcher.ts";

describe("Firecracker VSOCK handshake", () => {
  test("accepts the observed positive decimal connection id", () => {
    expect(parseVsockHandshake("OK 1073741825")).toBe("1073741825");
  });

  test("rejects errors, zero, and extra fields", () => {
    for (const frame of [
      "OK -1",
      "OK 1073741825 extra",
      "ERR 1073741825",
      "OK 1073741825\nPAYLOAD",
      "",
    ]) {
      expect(() => parseVsockHandshake(frame)).toThrow("invalid Firecracker VSOCK handshake");
    }
  });
});
