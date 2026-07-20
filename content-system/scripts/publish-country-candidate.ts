import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";

import { loadConfig } from "../src/config.js";
import { publishCountryDataCandidate } from "../src/release/publishImmutableCandidate.js";
import { verifyStorage } from "../src/storage.js";

interface CliArguments {
  readonly datasetVersion: string;
  readonly generatedAt: string;
  readonly wikidataSnapshotPath: string;
  readonly unM49SnapshotPath: string;
}

const executeFile = promisify(execFile);

const errorMessage = (error: unknown): string =>
  error instanceof Error ? error.message : String(error);

export const parseCandidateCliArguments = (arguments_: readonly string[]): CliArguments => {
  const values = new Map<string, string>();
  for (let index = 0; index < arguments_.length; index += 2) {
    const key = arguments_[index];
    const value = arguments_[index + 1];
    if (
      key === undefined ||
      value === undefined ||
      ![
        "--dataset-version",
        "--generated-at",
        "--wikidata-snapshot",
        "--un-m49-snapshot",
      ].includes(key)
    ) {
      throw new Error(
        "Usage: --dataset-version <semver> --generated-at <ISO> --wikidata-snapshot <path> --un-m49-snapshot <path>",
      );
    }
    if (values.has(key)) {
      throw new Error(`Argument may only be supplied once: ${key}`);
    }
    values.set(key, value);
  }
  const required = (key: string): string => {
    const value = values.get(key);
    if (value === undefined || value.trim().length === 0) {
      throw new Error(`Missing required argument: ${key}`);
    }
    return value;
  };
  return {
    datasetVersion: required("--dataset-version"),
    generatedAt: required("--generated-at"),
    wikidataSnapshotPath: path.resolve(required("--wikidata-snapshot")),
    unM49SnapshotPath: path.resolve(required("--un-m49-snapshot")),
  };
};

export const runCandidateCli = async (
  arguments_: readonly string[] = process.argv.slice(2),
): Promise<void> => {
  const cli = parseCandidateCliArguments(arguments_);
  const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
  const contentRoot = path.resolve(scriptDirectory, "..");
  const repositoryRoot = path.resolve(contentRoot, "..");
  const config = loadConfig(process.env, contentRoot);
  await verifyStorage(config);
  if (config.cloudRoot === undefined) {
    throw new Error("FLAGGENBANDE_CLOUD_ROOT is required for candidate publication.");
  }
  const packageJson = JSON.parse(
    await readFile(path.join(contentRoot, "package.json"), "utf8"),
  ) as { readonly version?: unknown };
  if (typeof packageJson.version !== "string") {
    throw new Error("package.json version is missing.");
  }
  const gitCommit = (await executeFile("git", ["rev-parse", "HEAD"], { cwd: repositoryRoot })).stdout.trim();
  const result = await publishCountryDataCandidate({
    cloudRoot: config.cloudRoot,
    localCacheDirectory: config.localCacheDirectory,
    legacyCatalogPath: path.join(repositoryRoot, "SpassmitFlaggen", "FlagCatalog.swift"),
    cldrCoreRoot: path.join(contentRoot, "node_modules", "cldr-core"),
    cldrLocaleNamesRoot: path.join(contentRoot, "node_modules", "cldr-localenames-full"),
    flagIconsRoot: path.join(contentRoot, "node_modules", "flag-icons"),
    datasetVersion: cli.datasetVersion,
    generatedAt: cli.generatedAt,
    wikidataCapitalSnapshotPath: cli.wikidataSnapshotPath,
    unM49SnapshotPath: cli.unM49SnapshotPath,
    generatorVersion: packageJson.version,
    gitCommit,
  });
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
};

const isDirectExecution =
  process.argv[1] !== undefined && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);

if (isDirectExecution) {
  runCandidateCli().catch((error: unknown) => {
    process.stderr.write(`[country-candidate] ${errorMessage(error)}\n`);
    process.exitCode = 1;
  });
}
