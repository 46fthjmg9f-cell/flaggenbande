import { mkdir } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { loadConfig } from "./config.js";
import { createLogger } from "./logger.js";
import { CONTENT_SYSTEM_ROOT, CONTENT_SYSTEM_VERSION } from "./runtime.js";

const main = async (): Promise<void> => {
  const config = loadConfig(process.env, CONTENT_SYSTEM_ROOT);
  const logger = createLogger(config.logLevel, console.log, () => new Date(), {
    mode: config.mode,
    runId: randomUUID(),
    version: CONTENT_SYSTEM_VERSION,
  });
  await mkdir(config.outputDirectory, { recursive: true });
  logger.info("system.ready", "Flaggenbande content-system foundation is ready.", {
    renderConcurrency: config.renderConcurrency,
    outputDirectory: config.outputDirectory,
  });
};

main().catch((error: unknown) => {
  const logger = createLogger("error");
  logger.error(
    "system.start_failed",
    error instanceof Error ? error.message : "Unknown startup error.",
  );
  process.exitCode = 1;
});
