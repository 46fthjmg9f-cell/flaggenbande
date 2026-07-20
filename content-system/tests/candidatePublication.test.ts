import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { createCapitalSnapshot } from "../scripts/fetch-wikidata-capitals.js";
import { loadCldrData } from "../src/data/cldr.js";
import { UN_MEMBER_ALPHA2 } from "../src/data/constants.js";
import {
  publishCountryDataCandidate,
  verifyCountryDataCandidate,
} from "../src/release/publishImmutableCandidate.js";
import type { UnM49Snapshot, WikidataCountryCapitalRecord } from "../src/data/types.js";

const CONTENT_ROOT = fileURLToPath(new URL("..", import.meta.url));
const REPOSITORY_ROOT = path.resolve(CONTENT_ROOT, "..");
const CLDR_CORE_ROOT = path.join(CONTENT_ROOT, "node_modules", "cldr-core");
const CLDR_NAMES_ROOT = path.join(CONTENT_ROOT, "node_modules", "cldr-localenames-full");
const GENERATED_AT = "2026-07-20T12:00:00.000Z";

const createSources = async (root: string): Promise<{
  readonly wikidataPath: string;
  readonly unM49Path: string;
}> => {
  const wikidataPath = path.join(root, "wikidata.json");
  const unM49Path = path.join(root, "un-m49.json");
  const wikidataCountries: readonly WikidataCountryCapitalRecord[] = UN_MEMBER_ALPHA2.map(
    (code, index) => ({
      isoAlpha2: code,
      qid: `Q${String(100_000 + index)}`,
      names: { en: `Country ${code}` },
      capitals: [
        {
          qid: `Q${String(200_000 + index)}`,
          names: { de: `Hauptstadt ${code}`, en: `Capital ${code}` },
        },
      ],
    }),
  );
  const cldr = await loadCldrData(CLDR_CORE_ROOT, CLDR_NAMES_ROOT);
  const unM49Countries = UN_MEMBER_ALPHA2.map((code) => {
    const country = cldr.countryByAlpha2.get(code);
    assert.ok(country);
    return {
      isoAlpha2: code,
      isoAlpha3: country.alpha3,
      m49: country.numeric,
      countryOrArea: country.nameEn,
      regionCode: country.continent === "africa" ? "002" : "001",
      regionName: country.continent,
      subregionCode: country.regionCode,
      subregionName: country.regionNameEn,
    };
  });
  const unM49Snapshot: UnM49Snapshot = {
    schemaVersion: "1.0.0",
    fetchedAt: GENERATED_AT,
    sourceUrl: "https://unstats.un.org/unsd/methodology/m49/overview/",
    sourceSha256: "0".repeat(64),
    countries: unM49Countries,
  };
  await Promise.all([
    writeFile(
      wikidataPath,
      `${JSON.stringify(createCapitalSnapshot(wikidataCountries, () => new Date(GENERATED_AT)))}\n`,
      "utf8",
    ),
    writeFile(unM49Path, `${JSON.stringify(unM49Snapshot)}\n`, "utf8"),
  ]);
  return { wikidataPath, unM49Path };
};

test("publishes an immutable, re-read and checksummed country candidate", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "flaggenbande-publication-test-"));
  try {
    const sources = await createSources(root);
    const options = {
      cloudRoot: path.join(root, "cloud"),
      localCacheDirectory: path.join(root, "cache"),
      legacyCatalogPath: path.join(REPOSITORY_ROOT, "SpassmitFlaggen", "FlagCatalog.swift"),
      cldrCoreRoot: CLDR_CORE_ROOT,
      cldrLocaleNamesRoot: CLDR_NAMES_ROOT,
      flagIconsRoot: path.join(CONTENT_ROOT, "node_modules", "flag-icons"),
      datasetVersion: "0.2.0-candidate.test.1",
      generatedAt: GENERATED_AT,
      wikidataCapitalSnapshotPath: sources.wikidataPath,
      unM49SnapshotPath: sources.unM49Path,
      generatorVersion: "0.2.0",
      gitCommit: "a".repeat(40),
    } as const;
    const result = await publishCountryDataCandidate(options);
    assert.equal(result.remoteSyncVerified, false);
    assert.match(result.releaseDirectory, /releases\/country-data\/candidates\/0\.2\.0-candidate\.test\.1$/u);
    assert.equal((await verifyCountryDataCandidate(result.releaseDirectory)).treeSha256, result.treeSha256);
    assert.match(await readFile(path.join(result.releaseDirectory, "SHA256SUMS"), "utf8"), /release-manifest\.json/u);
    await assert.rejects(
      publishCountryDataCandidate(options),
      /already exists and is immutable/u,
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("detects payload tampering after publication", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "flaggenbande-publication-tamper-"));
  try {
    const sources = await createSources(root);
    const result = await publishCountryDataCandidate({
      cloudRoot: path.join(root, "cloud"),
      localCacheDirectory: path.join(root, "cache"),
      legacyCatalogPath: path.join(REPOSITORY_ROOT, "SpassmitFlaggen", "FlagCatalog.swift"),
      cldrCoreRoot: CLDR_CORE_ROOT,
      cldrLocaleNamesRoot: CLDR_NAMES_ROOT,
      flagIconsRoot: path.join(CONTENT_ROOT, "node_modules", "flag-icons"),
      datasetVersion: "0.2.0-candidate.test.2",
      generatedAt: GENERATED_AT,
      wikidataCapitalSnapshotPath: sources.wikidataPath,
      unM49SnapshotPath: sources.unM49Path,
      generatorVersion: "0.2.0",
      gitCommit: "b".repeat(40),
    });
    await writeFile(
      path.join(result.releaseDirectory, "dataset", "country-candidates.v1.json"),
      "tampered\n",
      "utf8",
    );
    await assert.rejects(
      verifyCountryDataCandidate(result.releaseDirectory),
      /do not match release-manifest/u,
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
