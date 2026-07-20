import assert from "node:assert/strict";
import { resolve } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { loadConfig } from "../src/config.js";

const projectDirectory = resolve(fileURLToPath(new URL("..", import.meta.url)));

test("loads reproducible development defaults", () => {
  const config = loadConfig({}, projectDirectory);
  assert.equal(config.mode, "development");
  assert.equal(config.logLevel, "debug");
  assert.equal(config.renderConcurrency, 1);
  assert.equal(config.outputDirectory, resolve(projectDirectory, "output"));
});

test("loads production mode with safe fixed defaults", () => {
  const config = loadConfig({ FLAGGENBANDE_MODE: "production" }, projectDirectory);
  assert.equal(config.mode, "production");
  assert.equal(config.logLevel, "info");
  assert.equal(config.renderConcurrency, 2);
});

test("environment may override non-secret runtime paths and log level", () => {
  const config = loadConfig(
    {
      FLAGGENBANDE_MODE: "development",
      FLAGGENBANDE_LOG_LEVEL: "warn",
      FLAGGENBANDE_OUTPUT_DIR: "./custom-output",
    },
    projectDirectory,
  );
  assert.equal(config.logLevel, "warn");
  assert.equal(config.outputDirectory, resolve(projectDirectory, "custom-output"));
});

test("rejects unknown runtime modes", () => {
  assert.throws(
    () => loadConfig({ FLAGGENBANDE_MODE: "experimental" }, projectDirectory),
    /FLAGGENBANDE_MODE must be one of/u,
  );
});
