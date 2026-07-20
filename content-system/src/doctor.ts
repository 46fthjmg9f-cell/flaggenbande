import { access, constants, mkdir } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { loadConfig } from "./config.js";
import { createLogger } from "./logger.js";
import { CONTENT_SYSTEM_ROOT, CONTENT_SYSTEM_VERSION } from "./runtime.js";

interface DoctorCheck {
  readonly name: string;
  readonly passed: boolean;
  readonly detail: string;
}

const main = async (): Promise<void> => {
  const config = loadConfig(process.env, CONTENT_SYSTEM_ROOT);
  const logger = createLogger(config.logLevel, console.log, () => new Date(), {
    mode: config.mode,
    runId: randomUUID(),
    version: CONTENT_SYSTEM_VERSION,
  });
  await mkdir(config.outputDirectory, { recursive: true });

  const nodeMajor = Number(process.versions.node.split(".")[0]);
  const checks: DoctorCheck[] = [
    {
      name: "node-version",
      passed: Number.isInteger(nodeMajor) && nodeMajor >= 22,
      detail: `Node ${process.versions.node}; required >=22`,
    },
    {
      name: "configuration",
      passed: true,
      detail: `${config.mode} configuration loaded`,
    },
  ];

  try {
    await access(config.outputDirectory, constants.W_OK);
    checks.push({ name: "output-directory", passed: true, detail: "writable" });
  } catch {
    checks.push({ name: "output-directory", passed: false, detail: "not writable" });
  }

  for (const check of checks) {
    const context = { check: check.name, detail: check.detail };
    if (check.passed) {
      logger.info("doctor.check_passed", "Environment check passed.", context);
    } else {
      logger.error("doctor.check_failed", "Environment check failed.", context);
    }
  }

  if (checks.some((check) => !check.passed)) {
    process.exitCode = 1;
    return;
  }
  logger.info("doctor.ready", "Content-system environment is ready.", {
    checks: checks.length,
  });
};

main().catch((error: unknown) => {
  createLogger("error").error(
    "doctor.failed",
    error instanceof Error ? error.message : "Unknown doctor error.",
  );
  process.exitCode = 1;
});
