import assert from "node:assert/strict";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import { test } from "node:test";
import { expandHome } from "../src/config.js";
import { isPathInside, verifyStorage } from "../src/storage.js";

test("expands home-prefixed configuration paths", () => {
  assert.equal(expandHome("~/Projects/Flaggenbande", "/Users/test"), "/Users/test/Projects/Flaggenbande");
  assert.equal(expandHome("/tmp/output", "/Users/test"), "/tmp/output");
});

test("recognizes children without accepting the root itself", () => {
  assert.equal(isPathInside("/cloud/root", "/cloud/root/output"), true);
  assert.equal(isPathInside("/cloud/root", "/cloud/root"), false);
  assert.equal(isPathInside("/cloud/root", "/cloud/other"), false);
});

test("verifies a cloud-shaped directory without claiming remote sync", async () => {
  const temporaryRoot = await mkdtemp(resolve(tmpdir(), "flaggenbande-storage-"));
  const cloudRoot = resolve(temporaryRoot, "cloud");
  const result = await verifyStorage({
    mode: "development",
    projectDirectory: temporaryRoot,
    logLevel: "debug",
    outputDirectory: resolve(cloudRoot, "output"),
    localCacheDirectory: resolve(temporaryRoot, "cache"),
    renderConcurrency: 1,
    cloudRoot,
  });
  assert.equal(result.status, "local-copy-verified");
  assert.equal(result.remoteSyncVerified, false);
  assert.equal(result.directories.length, 5);
});
