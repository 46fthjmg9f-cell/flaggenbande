import { constants } from "node:fs";
import { access, mkdir, readFile, unlink, writeFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { relative, resolve } from "node:path";
import type { AppConfig } from "./config.js";

export const CLOUD_DIRECTORIES = [
  "assets/flags",
  "output",
  "releases",
  "repository-backups",
  "archive",
] as const;

export interface StorageCheckResult {
  readonly cloudRoot: string;
  readonly localCacheDirectory: string;
  readonly status: "local-copy-verified";
  readonly directories: readonly string[];
  readonly remoteSyncVerified: false;
}

export const isPathInside = (parent: string, candidate: string): boolean => {
  const pathFromParent = relative(resolve(parent), resolve(candidate));
  return pathFromParent !== "" && !pathFromParent.startsWith("..") && !pathFromParent.startsWith("/");
};

export const verifyStorage = async (config: AppConfig): Promise<StorageCheckResult> => {
  if (!config.cloudRoot) {
    throw new Error("FLAGGENBANDE_CLOUD_ROOT is required for durable storage.");
  }
  if (isPathInside(config.cloudRoot, config.localCacheDirectory)) {
    throw new Error("The disposable local cache must not be stored inside OneDrive.");
  }
  if (!isPathInside(config.cloudRoot, config.outputDirectory)) {
    throw new Error("FLAGGENBANDE_OUTPUT_DIR must be located inside FLAGGENBANDE_CLOUD_ROOT.");
  }

  await mkdir(config.localCacheDirectory, { recursive: true });
  await access(config.localCacheDirectory, constants.W_OK);

  const directories = CLOUD_DIRECTORIES.map((directory) =>
    resolve(config.cloudRoot as string, directory),
  );
  for (const directory of directories) {
    await mkdir(directory, { recursive: true });
    await access(directory, constants.W_OK);
  }

  const probePath = resolve(config.cloudRoot, `.write-probe-${randomUUID()}`);
  const probeValue = randomUUID();
  try {
    await writeFile(probePath, probeValue, { encoding: "utf8", flag: "wx" });
    const reread = await readFile(probePath, "utf8");
    if (reread !== probeValue) {
      throw new Error("OneDrive write verification returned different content.");
    }
  } finally {
    await unlink(probePath).catch(() => undefined);
  }

  return {
    cloudRoot: config.cloudRoot,
    localCacheDirectory: config.localCacheDirectory,
    status: "local-copy-verified",
    directories,
    remoteSyncVerified: false,
  };
};
