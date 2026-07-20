import { randomUUID } from "node:crypto";
import { loadConfig } from "./config.js";
import { createLogger } from "./logger.js";
import { CONTENT_SYSTEM_ROOT, CONTENT_SYSTEM_VERSION } from "./runtime.js";
import { verifyStorage } from "./storage.js";

const main = async (): Promise<void> => {
  const config = loadConfig(process.env, CONTENT_SYSTEM_ROOT);
  const logger = createLogger(config.logLevel, console.log, () => new Date(), {
    mode: config.mode,
    runId: randomUUID(),
    version: CONTENT_SYSTEM_VERSION,
  });
  const result = await verifyStorage(config);
  logger.info(
    "storage.local_copy_verified",
    "Durable OneDrive paths are writable and readable from this Mac.",
    {
      cloudRoot: result.cloudRoot,
      directories: result.directories.length,
      remoteSyncVerified: result.remoteSyncVerified,
      status: result.status,
    },
  );
  logger.warn(
    "storage.remote_sync_unverified",
    "Microsoft cloud synchronization cannot be proven without a cloud API.",
  );
};

main().catch((error: unknown) => {
  createLogger("error").error(
    "storage.doctor_failed",
    error instanceof Error ? error.message : "Unknown storage error.",
  );
  process.exitCode = 1;
});
