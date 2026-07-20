import { createHash, randomUUID } from "node:crypto";
import {
  cp,
  lstat,
  mkdir,
  readFile,
  readdir,
  rename,
  rm,
  writeFile,
} from "node:fs/promises";
import path from "node:path";

import { generateCountryCandidates } from "../data/generate.js";
import { CountryDataError } from "../data/errors.js";
import type { CountryDataGeneratorOptions, GeneratedFileRecord } from "../data/types.js";

export interface CountryCandidatePublicationOptions
  extends Omit<CountryDataGeneratorOptions, "stagingDirectory"> {
  readonly cloudRoot: string;
  readonly localCacheDirectory: string;
  readonly generatorVersion: string;
  readonly gitCommit: string;
}

export interface CountryCandidateReleaseManifest {
  readonly schemaVersion: "1.0.0";
  readonly kind: "flaggenbande-country-data-candidate-release";
  readonly releaseId: string;
  readonly datasetVersion: string;
  readonly generatedAt: string;
  readonly status: "candidate";
  readonly immutable: true;
  readonly remoteSyncVerified: false;
  readonly generator: {
    readonly package: "@flaggenbande/content-system";
    readonly version: string;
    readonly gitCommit: string;
  };
  readonly files: readonly GeneratedFileRecord[];
  readonly treeSha256: string;
}

export interface CountryCandidatePublicationResult {
  readonly releaseDirectory: string;
  readonly manifestPath: string;
  readonly datasetVersion: string;
  readonly fileCount: number;
  readonly treeSha256: string;
  readonly remoteSyncVerified: false;
}

const json = (value: unknown): string => `${JSON.stringify(value, null, 2)}\n`;

const sha256 = (bytes: Uint8Array | string): string =>
  createHash("sha256").update(bytes).digest("hex");

const exists = async (target: string): Promise<boolean> => {
  try {
    await lstat(target);
    return true;
  } catch (error) {
    if (
      typeof error === "object" &&
      error !== null &&
      "code" in error &&
      error.code === "ENOENT"
    ) {
      return false;
    }
    throw error;
  }
};

const validateOptions = (options: CountryCandidatePublicationOptions): void => {
  if (!/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/u.test(options.datasetVersion)) {
    throw new CountryDataError("datasetVersion must use semantic version syntax");
  }
  if (!Number.isFinite(Date.parse(options.generatedAt))) {
    throw new CountryDataError("generatedAt must be a valid ISO date-time");
  }
  if (!/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/u.test(options.generatorVersion)) {
    throw new CountryDataError("generatorVersion must use semantic version syntax");
  }
  if (!/^[a-f0-9]{7,64}$/u.test(options.gitCommit)) {
    throw new CountryDataError("gitCommit must be a hexadecimal Git object ID");
  }
  for (const [field, value] of [
    ["cloudRoot", options.cloudRoot],
    ["localCacheDirectory", options.localCacheDirectory],
    ["wikidataCapitalSnapshotPath", options.wikidataCapitalSnapshotPath],
    ["unM49SnapshotPath", options.unM49SnapshotPath],
  ] as const) {
    if (value === undefined || !path.isAbsolute(value)) {
      throw new CountryDataError(`${field} must be an absolute path`);
    }
  }
};

const listFiles = async (root: string, current = root): Promise<readonly GeneratedFileRecord[]> => {
  const entries = await readdir(current, { withFileTypes: true });
  const records: GeneratedFileRecord[] = [];
  for (const entry of entries.sort((left, right) => left.name.localeCompare(right.name, "en"))) {
    const absolute = path.join(current, entry.name);
    const entryStat = await lstat(absolute);
    if (entryStat.isSymbolicLink()) {
      throw new CountryDataError(`Release package must not contain symlinks: ${absolute}`);
    }
    if (entryStat.isDirectory()) {
      records.push(...(await listFiles(root, absolute)));
      continue;
    }
    if (!entryStat.isFile()) {
      throw new CountryDataError(`Release package contains unsupported file type: ${absolute}`);
    }
    const bytes = await readFile(absolute);
    records.push({
      relativePath: path.relative(root, absolute).split(path.sep).join("/"),
      byteSize: entryStat.size,
      sha256: sha256(bytes),
    });
  }
  return records;
};

const normalizedRecords = (records: readonly GeneratedFileRecord[]): readonly GeneratedFileRecord[] =>
  [...records].sort((left, right) => left.relativePath.localeCompare(right.relativePath, "en"));

const recordsEqual = (
  left: readonly GeneratedFileRecord[],
  right: readonly GeneratedFileRecord[],
): boolean => JSON.stringify(normalizedRecords(left)) === JSON.stringify(normalizedRecords(right));

const treeHash = (records: readonly GeneratedFileRecord[]): string =>
  sha256(
    normalizedRecords(records)
      .map((record) => `${record.sha256} ${String(record.byteSize)} ${record.relativePath}\n`)
      .join(""),
  );

const parseManifest = (value: unknown): CountryCandidateReleaseManifest => {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new CountryDataError("Release manifest must be an object");
  }
  const candidate = value as Partial<CountryCandidateReleaseManifest>;
  if (
    candidate.schemaVersion !== "1.0.0" ||
    candidate.kind !== "flaggenbande-country-data-candidate-release" ||
    candidate.status !== "candidate" ||
    candidate.immutable !== true ||
    candidate.remoteSyncVerified !== false ||
    typeof candidate.datasetVersion !== "string" ||
    typeof candidate.generatedAt !== "string" ||
    typeof candidate.releaseId !== "string" ||
    typeof candidate.treeSha256 !== "string" ||
    !Array.isArray(candidate.files) ||
    typeof candidate.generator !== "object" ||
    candidate.generator === null
  ) {
    throw new CountryDataError("Release manifest has an invalid contract");
  }
  return candidate as CountryCandidateReleaseManifest;
};

export const verifyCountryDataCandidate = async (
  releaseDirectory: string,
): Promise<CountryCandidatePublicationResult> => {
  const manifestPath = path.join(releaseDirectory, "release-manifest.json");
  const sumsPath = path.join(releaseDirectory, "SHA256SUMS");
  let manifest: CountryCandidateReleaseManifest;
  try {
    manifest = parseManifest(JSON.parse(await readFile(manifestPath, "utf8")) as unknown);
  } catch (error) {
    throw new CountryDataError(`Cannot validate release manifest at ${manifestPath}`, { cause: error });
  }
  const datasetRecords = (await listFiles(path.join(releaseDirectory, "dataset"))).map((record) => ({
    ...record,
    relativePath: `dataset/${record.relativePath}`,
  }));
  if (!recordsEqual(datasetRecords, manifest.files)) {
    throw new CountryDataError("Published dataset files do not match release-manifest.json");
  }
  if (treeHash(datasetRecords) !== manifest.treeSha256) {
    throw new CountryDataError("Published dataset tree hash does not match release-manifest.json");
  }
  const manifestBytes = await readFile(manifestPath);
  const expectedSums = [
    ...normalizedRecords(datasetRecords).map((record) => `${record.sha256}  ${record.relativePath}`),
    `${sha256(manifestBytes)}  release-manifest.json`,
  ].join("\n") + "\n";
  if ((await readFile(sumsPath, "utf8")) !== expectedSums) {
    throw new CountryDataError("Published SHA256SUMS does not match the release payload");
  }
  const allFiles = await listFiles(releaseDirectory);
  if (allFiles.length !== datasetRecords.length + 2) {
    throw new CountryDataError("Published release contains unexpected files");
  }
  return {
    releaseDirectory,
    manifestPath,
    datasetVersion: manifest.datasetVersion,
    fileCount: datasetRecords.length,
    treeSha256: manifest.treeSha256,
    remoteSyncVerified: false,
  };
};

export const publishCountryDataCandidate = async (
  options: CountryCandidatePublicationOptions,
): Promise<CountryCandidatePublicationResult> => {
  validateOptions(options);
  const releaseRoot = path.join(options.cloudRoot, "releases", "country-data");
  const finalDirectory = path.join(releaseRoot, "candidates", options.datasetVersion);
  const locksDirectory = path.join(releaseRoot, ".locks");
  const lockDirectory = path.join(locksDirectory, `${options.datasetVersion}.lock`);
  const incomingRoot = path.join(releaseRoot, ".incoming");
  const runId = randomUUID();
  const incomingDirectory = path.join(incomingRoot, `${options.datasetVersion}-${runId}`);
  const stagingRoot = path.join(options.localCacheDirectory, "release-staging", runId);
  const firstDirectory = path.join(stagingRoot, "first");
  const secondDirectory = path.join(stagingRoot, "second");
  const packageDirectory = path.join(stagingRoot, "package");
  let lockAcquired = false;

  await Promise.all([
    mkdir(locksDirectory, { recursive: true }),
    mkdir(incomingRoot, { recursive: true }),
    mkdir(path.dirname(finalDirectory), { recursive: true }),
    mkdir(path.dirname(stagingRoot), { recursive: true }),
  ]);
  await mkdir(stagingRoot);
  try {
    try {
      await mkdir(lockDirectory);
      lockAcquired = true;
      await writeFile(
        path.join(lockDirectory, "owner.json"),
        json({ runId, datasetVersion: options.datasetVersion, startedAt: new Date().toISOString() }),
        { encoding: "utf8", flag: "wx" },
      );
    } catch (error) {
      throw new CountryDataError(`Candidate release is already locked: ${options.datasetVersion}`, {
        cause: error,
      });
    }
    if (await exists(finalDirectory)) {
      throw new CountryDataError(`Candidate release already exists and is immutable: ${finalDirectory}`);
    }

    const generationOptions: Omit<CountryDataGeneratorOptions, "stagingDirectory"> = {
      legacyCatalogPath: options.legacyCatalogPath,
      cldrCoreRoot: options.cldrCoreRoot,
      cldrLocaleNamesRoot: options.cldrLocaleNamesRoot,
      flagIconsRoot: options.flagIconsRoot,
      datasetVersion: options.datasetVersion,
      generatedAt: options.generatedAt,
      ...(options.wikidataCapitalSnapshotPath === undefined
        ? {}
        : { wikidataCapitalSnapshotPath: options.wikidataCapitalSnapshotPath }),
      ...(options.unM49SnapshotPath === undefined
        ? {}
        : { unM49SnapshotPath: options.unM49SnapshotPath }),
    };
    await generateCountryCandidates({ ...generationOptions, stagingDirectory: firstDirectory });
    await generateCountryCandidates({ ...generationOptions, stagingDirectory: secondDirectory });
    const [firstFiles, secondFiles] = await Promise.all([
      listFiles(firstDirectory),
      listFiles(secondDirectory),
    ]);
    if (!recordsEqual(firstFiles, secondFiles)) {
      throw new CountryDataError("Two candidate generations were not byte-identical");
    }

    const datasetDirectory = path.join(packageDirectory, "dataset");
    await mkdir(packageDirectory, { recursive: true });
    await cp(firstDirectory, datasetDirectory, { recursive: true, force: false, errorOnExist: true });
    const releaseFiles = normalizedRecords(firstFiles).map((record) => ({
      ...record,
      relativePath: `dataset/${record.relativePath}`,
    }));
    const releaseManifest: CountryCandidateReleaseManifest = {
      schemaVersion: "1.0.0",
      kind: "flaggenbande-country-data-candidate-release",
      releaseId: `country-data@${options.datasetVersion}`,
      datasetVersion: options.datasetVersion,
      generatedAt: options.generatedAt,
      status: "candidate",
      immutable: true,
      remoteSyncVerified: false,
      generator: {
        package: "@flaggenbande/content-system",
        version: options.generatorVersion,
        gitCommit: options.gitCommit,
      },
      files: releaseFiles,
      treeSha256: treeHash(releaseFiles),
    };
    const manifestPath = path.join(packageDirectory, "release-manifest.json");
    await writeFile(manifestPath, json(releaseManifest), { encoding: "utf8", flag: "wx" });
    const manifestBytes = await readFile(manifestPath);
    const sums = [
      ...releaseFiles.map((record) => `${record.sha256}  ${record.relativePath}`),
      `${sha256(manifestBytes)}  release-manifest.json`,
    ].join("\n") + "\n";
    await writeFile(path.join(packageDirectory, "SHA256SUMS"), sums, {
      encoding: "utf8",
      flag: "wx",
    });

    await cp(packageDirectory, incomingDirectory, {
      recursive: true,
      force: false,
      errorOnExist: true,
    });
    await verifyCountryDataCandidate(incomingDirectory);
    await rename(incomingDirectory, finalDirectory);
    const result = await verifyCountryDataCandidate(finalDirectory);
    await rm(stagingRoot, { recursive: true });
    return result;
  } catch (error) {
    throw error;
  } finally {
    if (lockAcquired) {
      await rm(lockDirectory, { recursive: true }).catch(() => undefined);
    }
  }
};
