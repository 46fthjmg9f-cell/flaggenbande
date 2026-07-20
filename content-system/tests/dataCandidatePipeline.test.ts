import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  CountryDataError,
  generateCountryCandidates,
  validateCountryCandidateDatabase,
} from "../src/data/index.js";
import { UN_MEMBER_ALPHA2 } from "../src/data/constants.js";
import type {
  CountryCandidateDatabase,
  WikidataCountryCapitalRecord,
} from "../src/data/types.js";
import { createCapitalSnapshot } from "../scripts/fetch-wikidata-capitals.js";

const CONTENT_ROOT = fileURLToPath(new URL("..", import.meta.url));
const REPOSITORY_ROOT = path.resolve(CONTENT_ROOT, "..");
const CATALOG_PATH = path.join(REPOSITORY_ROOT, "SpassmitFlaggen", "FlagCatalog.swift");
const CLDR_CORE_ROOT = path.join(CONTENT_ROOT, "node_modules", "cldr-core");
const CLDR_NAMES_ROOT = path.join(CONTENT_ROOT, "node_modules", "cldr-localenames-full");
const FLAG_ICONS_ROOT = path.join(CONTENT_ROOT, "node_modules", "flag-icons");
const GENERATED_AT = "2026-07-20T12:00:00.000Z";

const makeTemp = (): Promise<string> => mkdtemp(path.join(tmpdir(), "flaggenbande-data-test-"));

const completeCapitalRecords = (): readonly WikidataCountryCapitalRecord[] =>
  UN_MEMBER_ALPHA2.map((code, index) => {
    const sequence = index + 1;
    const isGermany = code === "DE";
    return {
      isoAlpha2: code,
      qid: `Q${String(100_000 + sequence)}`,
      names: {
        ...(isGermany ? { de: "Deutschland" } : {}),
        en: isGermany ? "Germany" : `Country ${code}`,
      },
      capitals: [
        {
          qid: isGermany ? "Q64" : `Q${String(200_000 + sequence)}`,
          names: {
            ...(isGermany ? { de: "Berlin" } : {}),
            en: isGermany ? "Berlin" : `Capital ${code}`,
          },
        },
      ],
    };
  });

const options = (stagingDirectory: string, overrides: Record<string, string> = {}) => ({
  legacyCatalogPath: overrides.legacyCatalogPath ?? CATALOG_PATH,
  cldrCoreRoot: CLDR_CORE_ROOT,
  cldrLocaleNamesRoot: CLDR_NAMES_ROOT,
  flagIconsRoot: FLAG_ICONS_ROOT,
  stagingDirectory,
  datasetVersion: "0.2.0-test.1",
  generatedAt: GENERATED_AT,
  ...(overrides.wikidataCapitalSnapshotPath === undefined
    ? {}
    : { wikidataCapitalSnapshotPath: overrides.wikidataCapitalSnapshotPath }),
});

test("generates a deterministic offline 193-country pending-review candidate bundle", async () => {
  const firstRoot = await makeTemp();
  const secondRoot = await makeTemp();
  try {
    const first = await generateCountryCandidates(options(firstRoot));
    const second = await generateCountryCandidates(options(secondRoot));
    assert.equal(first.database.countries.length, 193);
    assert.equal(first.reviewQueue.items.length, 193);
    assert.ok(first.database.countries.every((country) => country.review.status === "pending"));
    assert.ok(first.database.countries.every((country) => !country.eligibility.standardQuiz));
    assert.ok(first.database.countries.every((country) => country.flag.relativePath.startsWith("assets/flags/")));
    assert.deepEqual(first.database, second.database);
    assert.deepEqual(first.manifest, second.manifest);
    const contactSheet = await readFile(first.contactSheetPath, "utf8");
    assert.match(contactSheet, /193 candidates/u);
    assert.doesNotMatch(contactSheet, /https?:\/\//u);
  } finally {
    await Promise.all([rm(firstRoot, { recursive: true, force: true }), rm(secondRoot, { recursive: true, force: true })]);
  }
});

test("passes one shared fetcher snapshot contract into generation while retaining fail-closed review", async () => {
  const root = await makeTemp();
  const staging = path.join(root, "staging");
  const snapshotPath = path.join(root, "wikidata-capitals.json");
  try {
    const snapshot = createCapitalSnapshot(
      completeCapitalRecords(),
      () => new Date(GENERATED_AT),
    );
    await writeFile(snapshotPath, `${JSON.stringify(snapshot)}\n`, "utf8");
    const result = await generateCountryCandidates(
      options(staging, { wikidataCapitalSnapshotPath: snapshotPath }),
    );
    const germany = result.database.countries.find((country) => country.codes.isoAlpha2 === "DE");
    assert.ok(germany);
    assert.equal(germany.capitals[0]?.names.en, "Berlin");
    assert.equal(germany.capitals[0]?.sourceId, "wikidata-capitals");
    assert.equal(germany.capitals[0]?.sourceEntityId, "Q64");
    assert.equal(germany.review.status, "pending");
    assert.equal(germany.eligibility.standardQuiz, false);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("rejects an incomplete provided Wikidata snapshot instead of silently using legacy capitals", async () => {
  const root = await makeTemp();
  const staging = path.join(root, "staging");
  const snapshotPath = path.join(root, "wikidata-capitals.json");
  try {
    const snapshot = createCapitalSnapshot(
      completeCapitalRecords().slice(1),
      () => new Date(GENERATED_AT),
    );
    await writeFile(snapshotPath, `${JSON.stringify(snapshot)}\n`, "utf8");
    await assert.rejects(
      generateCountryCandidates(options(staging, { wikidataCapitalSnapshotPath: snapshotPath })),
      (error: unknown) =>
        error instanceof CountryDataError && /must contain exactly 193 countries/u.test(error.message),
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("fails closed when a legacy country has no capital candidate", async () => {
  const root = await makeTemp();
  const catalogFixture = path.join(root, "FlagCatalog.swift");
  const staging = path.join(root, "staging");
  try {
    const catalog = await readFile(CATALOG_PATH, "utf8");
    await writeFile(catalogFixture, catalog.replace('"AF": "Kabul", ', ""), "utf8");
    await assert.rejects(
      generateCountryCandidates(options(staging, { legacyCatalogPath: catalogFixture })),
      (error: unknown) => error instanceof CountryDataError && /Missing legacy capital for AF/u.test(error.message),
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("detects checksum-correct but active SVG content", async () => {
  const root = await makeTemp();
  try {
    const result = await generateCountryCandidates(options(root));
    const country = result.database.countries[0];
    assert.ok(country);
    const assetPath = path.join(root, ...country.flag.relativePath.split("/"));
    const malicious = Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>');
    await writeFile(assetPath, malicious);
    const modifiedCountry = {
      ...country,
      flag: {
        ...country.flag,
        byteSize: malicious.byteLength,
        checksum: {
          algorithm: "sha256" as const,
          value: createHash("sha256").update(malicious).digest("hex"),
        },
      },
    };
    const modifiedDatabase: CountryCandidateDatabase = {
      ...result.database,
      countries: [modifiedCountry, ...result.database.countries.slice(1)],
    };
    const issues = await validateCountryCandidateDatabase(modifiedDatabase, root);
    assert.ok(issues.some((validationIssue) => validationIssue.code === "unsafe_svg"));
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("does not make a country quiz-eligible from country approval alone", async () => {
  const root = await makeTemp();
  try {
    const result = await generateCountryCandidates(options(root));
    const country = result.database.countries[0];
    assert.ok(country);
    const mutated: CountryCandidateDatabase = {
      ...result.database,
      countries: [
        {
          ...country,
          eligibility: { ...country.eligibility, standardQuiz: true },
          review: {
            status: "approved",
            reviewedBy: "reviewer@example.test",
            reviewedAt: GENERATED_AT,
            issues: [],
          },
        },
        ...result.database.countries.slice(1),
      ],
    };
    const issues = await validateCountryCandidateDatabase(mutated, root);
    assert.ok(issues.some((validationIssue) => validationIssue.code === "incomplete_approval"));
    assert.ok(issues.some((validationIssue) => validationIssue.code === "quiz_approval_mismatch"));
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("accepts quiz eligibility only after country, flag, difficulty and capitals are approved", async () => {
  const root = await makeTemp();
  try {
    const result = await generateCountryCandidates(options(root));
    const country = result.database.countries[0];
    assert.ok(country);
    const approvedReview = {
      status: "approved" as const,
      reviewedBy: "reviewer@example.test",
      reviewedAt: GENERATED_AT,
      issues: [],
    };
    const approvedCountry = {
      ...country,
      eligibility: { ...country.eligibility, standardQuiz: true },
      capitals: country.capitals.map((capital) => ({
        ...capital,
        names: {
          de: capital.names.de ?? "Reviewed capital",
          en: capital.names.en ?? capital.names.de ?? "Reviewed capital",
        },
      })),
      difficulty: {
        level: 1 as const,
        rubricVersion: "difficulty-rubric-v1",
        rationale: "Reviewed starter flag.",
        reviewStatus: "approved" as const,
      },
      flag: { ...country.flag, review: approvedReview },
      review: approvedReview,
    };
    const database: CountryCandidateDatabase = {
      ...result.database,
      countries: [approvedCountry, ...result.database.countries.slice(1)],
    };
    const issues = await validateCountryCandidateDatabase(database, root);
    assert.equal(issues.length, 0);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("blocks a missing local license file", async () => {
  const root = await makeTemp();
  try {
    const result = await generateCountryCandidates(options(root));
    await rm(path.join(root, "licenses", "flag-icons-MIT.txt"));
    const issues = await validateCountryCandidateDatabase(result.database, root);
    assert.ok(issues.some((validationIssue) => validationIssue.code === "missing_license"));
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
