import assert from "node:assert/strict";
import { test } from "node:test";
import { createLogger } from "../src/logger.js";

test("writes deterministic structured JSON records", () => {
  const lines: string[] = [];
  const logger = createLogger(
    "debug",
    (line) => lines.push(line),
    () => new Date("2026-07-20T12:00:00.000Z"),
  );
  logger.info("test.ready", "Ready", { videoId: "flags-0001" });

  assert.equal(lines.length, 1);
  assert.deepEqual(JSON.parse(lines[0] ?? "{}"), {
    timestamp: "2026-07-20T12:00:00.000Z",
    level: "info",
    event: "test.ready",
    message: "Ready",
    context: { videoId: "flags-0001" },
  });
});

test("filters messages below the configured level", () => {
  const lines: string[] = [];
  const logger = createLogger("warn", (line) => lines.push(line));
  logger.debug("test.debug", "Hidden");
  logger.info("test.info", "Hidden");
  logger.warn("test.warn", "Visible");
  assert.equal(lines.length, 1);
});

test("redacts secret-shaped context fields recursively", () => {
  const lines: string[] = [];
  const logger = createLogger("info", (line) => lines.push(line));
  logger.info("test.secret", "Safe", {
    apiKey: "must-not-appear",
    nested: { access_token: "must-not-appear-either", countryCode: "DE" },
  });
  const serialized = lines[0] ?? "";
  assert.doesNotMatch(serialized, /must-not-appear/u);
  assert.match(serialized, /\[REDACTED\]/u);
  assert.match(serialized, /countryCode/u);
});

test("adds stable base context to every event", () => {
  const lines: string[] = [];
  const logger = createLogger(
    "info",
    (line) => lines.push(line),
    () => new Date("2026-07-20T12:00:00.000Z"),
    { mode: "development", runId: "run-1" },
  );
  logger.info("test.context", "Safe");
  assert.deepEqual(JSON.parse(lines[0] ?? "{}").context, {
    mode: "development",
    runId: "run-1",
  });
});
