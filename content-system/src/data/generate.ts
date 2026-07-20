import { createHash } from "node:crypto";
import { copyFile, mkdir, readdir, readFile, stat, writeFile } from "node:fs/promises";
import path from "node:path";

import { copyVerifiedFlag } from "./assets.js";
import { loadCldrData } from "./cldr.js";
import { EXPECTED_COUNTRY_COUNT, FORBIDDEN_STANDARD_CODES, UN_MEMBER_ALPHA2_SET } from "./constants.js";
import { CountryDataError } from "./errors.js";
import { loadLegacyCatalog } from "./legacyCatalog.js";
import {
  COUNTRY_SCHEMA_VERSION,
  REVIEW_QUEUE_SCHEMA_VERSION,
  type CandidateCapital,
  type CandidateCountry,
  type CountryCandidateDatabase,
  type CountryDataGenerationManifest,
  type CountryDataGenerationResult,
  type CountryDataGeneratorOptions,
  type CountryReviewQueue,
  type DatasetSource,
  type GeneratedFileRecord,
  type IsoAlpha2,
  type ReviewQueueItem,
  type UnM49Snapshot,
  type WikidataCapitalRecord,
  type WikidataCapitalSnapshot,
} from "./types.js";
import { assertValidCountryCandidateDatabase } from "./validate.js";
import { loadUnM49Snapshot } from "./unM49.js";
import { loadWikidataCapitalSnapshot } from "./wikidata.js";

const json = (value: unknown): string => `${JSON.stringify(value, null, 2)}\n`;

const normalizeComparison = (value: string): string =>
  value.normalize("NFKD").replaceAll(/\p{Diacritic}/gu, "").toLocaleLowerCase("en").replaceAll(/[^a-z\d]/gu, "");

const ensureEmptyStagingDirectory = async (directory: string): Promise<void> => {
  await mkdir(directory, { recursive: true });
  const existing = await readdir(directory);
  if (existing.length > 0) {
    throw new CountryDataError(`Staging directory must be empty: ${directory}`);
  }
};

const validateGenerationMetadata = (options: CountryDataGeneratorOptions): void => {
  if (!/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/u.test(options.datasetVersion)) {
    throw new CountryDataError("datasetVersion must be semantic version syntax");
  }
  if (!Number.isFinite(Date.parse(options.generatedAt))) {
    throw new CountryDataError("generatedAt must be a valid ISO date-time");
  }
};

const capitalFromWikidata = (
  countryId: string,
  inputs: readonly WikidataCapitalRecord[],
  legacyCapital: string,
): readonly CandidateCapital[] =>
  inputs.map((capital, index) => ({
    id: `${countryId}-capital-${String(index + 1).padStart(2, "0")}`,
    names: {
      de: capital.names.de ?? (inputs.length === 1 ? legacyCapital : null),
      en: capital.names.en ?? null,
    },
    roles: capital.roles ?? ["unspecified"],
    primaryDisplay: index === 0,
    acceptedQuizAnswer: true,
    sourceId: "wikidata-capitals",
    sourceEntityId: capital.qid,
  }));

const buildSources = (
  generatedAt: string,
  unM49Snapshot: UnM49Snapshot | null,
  snapshot: WikidataCapitalSnapshot | null,
): readonly DatasetSource[] => [
  {
    id: "legacy-flag-catalog",
    kind: "legacy-catalog",
    title: "Flaggenbande FlagCatalog.swift review seed",
    version: "repository-snapshot",
    locator: "SpassmitFlaggen/FlagCatalog.swift",
    retrievedAt: generatedAt,
    license: "project-internal",
  },
  {
    id: "cldr-48.2.0",
    kind: "cldr",
    title: "Unicode CLDR country names, code mappings and territory containment",
    version: "48.2.0",
    locator: "npm:cldr-core@48.2.0+npm:cldr-localenames-full@48.2.0",
    retrievedAt: generatedAt,
    license: "Unicode-3.0",
  },
  ...(unM49Snapshot === null
    ? []
    : [
        {
          id: "un-m49-overview",
          kind: "un-m49-snapshot" as const,
          title: "UN Statistics Division M49 overview snapshot",
          version: unM49Snapshot.schemaVersion,
          locator: unM49Snapshot.sourceUrl,
          retrievedAt: unM49Snapshot.fetchedAt,
          license: "official-public-reference",
        },
      ]),
  {
    id: "flag-icons-7.5.0",
    kind: "flag-assets",
    title: "flag-icons 4x3 SVG assets",
    version: "7.5.0",
    locator: "npm:flag-icons@7.5.0",
    retrievedAt: generatedAt,
    license: "MIT",
  },
  ...(snapshot === null
    ? []
    : [
        {
          id: "wikidata-capitals",
          kind: "wikidata-snapshot" as const,
          title: "Offline Wikidata capital snapshot",
          version: snapshot.schemaVersion,
          locator: snapshot.endpoint,
          retrievedAt: snapshot.fetchedAt,
          license: "CC0-1.0",
        },
      ]),
];

const reviewIssues = (
  legacyGermanName: string,
  legacyEnglishName: string,
  cldrGermanName: string,
  cldrEnglishName: string,
  legacyCapital: string,
  capitals: readonly CandidateCapital[],
): readonly string[] => {
  const issues = new Set<string>(["difficulty_unassigned", "flag_visual_review_required"]);
  if (normalizeComparison(legacyGermanName) !== normalizeComparison(cldrGermanName)) {
    issues.add("legacy_cldr_german_name_mismatch");
  }
  if (normalizeComparison(legacyEnglishName) !== normalizeComparison(cldrEnglishName)) {
    issues.add("legacy_cldr_english_name_mismatch");
  }
  if (capitals.some((capital) => capital.names.de === null || capital.names.en === null)) {
    issues.add("capital_translation_review_required");
  }
  const capitalMatchesLegacy = capitals.some((capital) =>
    [capital.names.de, capital.names.en]
      .filter((name): name is string => name !== null)
      .some((name) => normalizeComparison(name) === normalizeComparison(legacyCapital)),
  );
  if (!capitalMatchesLegacy) {
    issues.add("legacy_wikidata_capital_conflict");
  }
  return [...issues].sort();
};

const copySourceSnapshots = async (
  options: CountryDataGeneratorOptions,
): Promise<void> => {
  const sourcesDirectory = path.join(options.stagingDirectory, "sources");
  await mkdir(sourcesDirectory, { recursive: true });
  const copies: Promise<void>[] = [];
  if (options.unM49SnapshotPath !== undefined) {
    copies.push(
      copyFile(options.unM49SnapshotPath, path.join(sourcesDirectory, "un-m49.v1.json")).then(
        () => undefined,
      ),
    );
  }
  if (options.wikidataCapitalSnapshotPath !== undefined) {
    copies.push(
      copyFile(
        options.wikidataCapitalSnapshotPath,
        path.join(sourcesDirectory, "wikidata-capitals.v1.json"),
      ).then(() => undefined),
    );
  }
  await Promise.all(copies);
};

const escapeHtml = (value: string): string =>
  value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");

const contactSheetHtml = (database: CountryCandidateDatabase): string => `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Flaggenbande flag review ${escapeHtml(database.datasetVersion)}</title>
  <style>
    body{font-family:system-ui,sans-serif;margin:24px;background:#f4f6f8;color:#111}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:12px}.card{background:white;border:1px solid #ccd2d8;border-radius:8px;padding:10px}.card img{display:block;width:100%;aspect-ratio:4/3;object-fit:contain;border:1px solid #eee}.code{font:700 12px ui-monospace,monospace}.name{font-size:12px;margin-top:6px}.pending{color:#8a5a00;font-size:11px}
  </style>
</head>
<body>
  <h1>Flag review — ${escapeHtml(database.datasetVersion)}</h1>
  <p>${String(database.countries.length)} candidates · all pending human review</p>
  <main class="grid">
${database.countries
  .map(
    (country) => `    <article class="card"><img src="../${escapeHtml(country.flag.relativePath)}" alt="${escapeHtml(country.names.en.display)} flag"><div class="code">${escapeHtml(country.codes.isoAlpha2)} · ${escapeHtml(country.id)}</div><div class="name">${escapeHtml(country.names.de.display)} / ${escapeHtml(country.names.en.display)}</div><div class="pending">PENDING</div></article>`,
  )
  .join("\n")}
  </main>
</body>
</html>
`;

const copyLicenseFiles = async (options: CountryDataGeneratorOptions): Promise<void> => {
  const licenseDirectory = path.join(options.stagingDirectory, "licenses");
  await mkdir(licenseDirectory, { recursive: true });
  const [flagLicense, cldrLicense] = await Promise.all([
    readFile(path.join(options.flagIconsRoot, "LICENSE"), "utf8"),
    readFile(path.join(options.cldrCoreRoot, "LICENSE"), "utf8"),
  ]);
  await Promise.all([
    writeFile(path.join(licenseDirectory, "flag-icons-MIT.txt"), flagLicense, "utf8"),
    writeFile(path.join(licenseDirectory, "cldr-Unicode-3.0.txt"), cldrLicense, "utf8"),
  ]);
};

const listFiles = async (root: string, current = root): Promise<readonly string[]> => {
  const entries = await readdir(current, { withFileTypes: true });
  const result: string[] = [];
  for (const entry of entries.sort((left, right) => left.name.localeCompare(right.name, "en"))) {
    const absolute = path.join(current, entry.name);
    if (entry.isDirectory()) {
      result.push(...(await listFiles(root, absolute)));
    } else if (entry.isFile()) {
      result.push(path.relative(root, absolute).split(path.sep).join("/"));
    }
  }
  return result;
};

const createManifest = async (
  stagingDirectory: string,
  datasetVersion: string,
  generatedAt: string,
): Promise<CountryDataGenerationManifest> => {
  const files: GeneratedFileRecord[] = [];
  for (const relativePath of await listFiles(stagingDirectory)) {
    if (relativePath === "manifest.json") {
      continue;
    }
    const absolute = path.join(stagingDirectory, ...relativePath.split("/"));
    const [bytes, fileStat] = await Promise.all([readFile(absolute), stat(absolute)]);
    files.push({
      relativePath,
      byteSize: fileStat.size,
      sha256: createHash("sha256").update(bytes).digest("hex"),
    });
  }
  return {
    schemaVersion: "1.0.0",
    datasetVersion,
    generatedAt,
    files,
  };
};

export const generateCountryCandidates = async (
  options: CountryDataGeneratorOptions,
): Promise<CountryDataGenerationResult> => {
  validateGenerationMetadata(options);
  await ensureEmptyStagingDirectory(options.stagingDirectory);
  const [legacyCountries, cldr, unM49Snapshot, snapshot] = await Promise.all([
    loadLegacyCatalog(options.legacyCatalogPath),
    loadCldrData(options.cldrCoreRoot, options.cldrLocaleNamesRoot),
    options.unM49SnapshotPath === undefined
      ? Promise.resolve(null)
      : loadUnM49Snapshot(options.unM49SnapshotPath),
    options.wikidataCapitalSnapshotPath === undefined
      ? Promise.resolve(null)
      : loadWikidataCapitalSnapshot(options.wikidataCapitalSnapshotPath),
  ]);

  if (legacyCountries.length !== EXPECTED_COUNTRY_COUNT) {
    throw new CountryDataError(`allCountries must contain exactly ${String(EXPECTED_COUNTRY_COUNT)} entries`);
  }
  const legacyCodes = new Set(legacyCountries.map((country) => country.code));
  for (const code of legacyCodes) {
    if (!UN_MEMBER_ALPHA2_SET.has(code) || FORBIDDEN_STANDARD_CODES.has(code)) {
      throw new CountryDataError(`Forbidden or non-member code in allCountries: ${code}`);
    }
  }
  for (const code of UN_MEMBER_ALPHA2_SET) {
    if (!legacyCodes.has(code)) {
      throw new CountryDataError(`Missing UN member in allCountries: ${code}`);
    }
  }

  const unM49ByCode = new Map(
    (unM49Snapshot?.countries ?? []).map((country) => [country.isoAlpha2, country] as const),
  );
  const wikidataByCode = new Map(
    (snapshot?.countries ?? []).map((country) => [country.isoAlpha2, country] as const),
  );

  const countries: CandidateCountry[] = [];
  for (const legacy of [...legacyCountries].sort((left, right) => left.code.localeCompare(right.code, "en"))) {
    const cldrCountry = cldr.countryByAlpha2.get(legacy.code);
    if (cldrCountry === undefined) {
      throw new CountryDataError(`Missing CLDR country data for ${legacy.code}`);
    }
    const unM49Country = unM49ByCode.get(legacy.code);
    if (
      unM49Country !== undefined &&
      (unM49Country.isoAlpha3 !== cldrCountry.alpha3 || unM49Country.m49 !== cldrCountry.numeric)
    ) {
      throw new CountryDataError(`UN M49 and CLDR code conflict for ${legacy.code}`);
    }
    if (
      unM49Country !== undefined &&
      unM49Country.subregionCode !== cldrCountry.regionCode
    ) {
      throw new CountryDataError(`UN M49 and CLDR region conflict for ${legacy.code}`);
    }
    const numericCode = unM49Country?.m49 ?? cldrCountry.numeric;
    const countryId = `country-${numericCode}` as const;
    const wikidataCountry = wikidataByCode.get(legacy.code);
    const snapshotCapitals = wikidataCountry?.capitals;
    const capitals: readonly CandidateCapital[] =
      snapshotCapitals === undefined
        ? [
            {
              id: `${countryId}-capital-01`,
              names: { de: legacy.legacyCapital, en: null },
              roles: ["unspecified"],
              primaryDisplay: true,
              acceptedQuizAnswer: true,
              sourceId: "legacy-flag-catalog",
              sourceEntityId: null,
            },
          ]
        : capitalFromWikidata(countryId, snapshotCapitals, legacy.legacyCapital);
    if (
      capitals.length === 0 ||
      capitals.every((capital) => capital.names.de === null && capital.names.en === null)
    ) {
      throw new CountryDataError(`No capital candidate for ${legacy.code}`);
    }
    const copiedFlag = await copyVerifiedFlag(
      options.flagIconsRoot,
      legacy.code,
      countryId,
      options.stagingDirectory,
    );
    const issues = reviewIssues(
      legacy.germanName,
      legacy.englishName,
      cldrCountry.nameDe,
      cldrCountry.nameEn,
      legacy.legacyCapital,
      capitals,
    );
    countries.push({
      id: countryId,
      recordVersion: 1,
      eligibility: { status: "un-member", standardQuiz: false },
      codes: {
        isoAlpha2: legacy.code as IsoAlpha2,
        isoAlpha3: unM49Country?.isoAlpha3 ?? cldrCountry.alpha3,
        isoNumeric: numericCode,
        unM49: numericCode,
      },
      names: {
        de: { display: cldrCountry.nameDe, legacy: legacy.germanName },
        en: { display: cldrCountry.nameEn, legacy: legacy.englishName },
      },
      capitals,
      geography: {
        continent: cldrCountry.continent,
        region: {
          scheme: "UN_M49",
          code: unM49Country?.subregionCode ?? cldrCountry.regionCode,
          names: {
            de: cldrCountry.regionNameDe,
            en: unM49Country?.subregionName ?? cldrCountry.regionNameEn,
          },
        },
      },
      difficulty: null,
      flag: {
        assetId: `flag-${countryId}-v1`,
        version: 1,
        relativePath: copiedFlag.relativePath,
        mediaType: "image/svg+xml",
        aspectRatio: "4x3",
        byteSize: copiedFlag.byteSize,
        checksum: { algorithm: "sha256", value: copiedFlag.sha256 },
        sourceId: "flag-icons-7.5.0",
        license: {
          identifier: "MIT",
          name: "MIT License",
          relativeLicensePath: "licenses/flag-icons-MIT.txt",
          attributionRequired: true,
          attributionText: "Copyright (c) 2013 Panayiotis Lipiridis",
        },
        review: { status: "pending", reviewedBy: null, reviewedAt: null, issues: ["visual_review_required"] },
      },
      provenance: [
        {
          fields: ["names.de.legacy", "names.en.legacy"],
          sourceIds: ["legacy-flag-catalog"],
        },
        {
          fields: ["names.de.display", "names.en.display"],
          sourceIds: ["cldr-48.2.0"],
        },
        {
          fields: ["codes", "geography"],
          sourceIds: [unM49Country === undefined ? "cldr-48.2.0" : "un-m49-overview"],
        },
        {
          fields: ["capitals"],
          sourceIds: [
            ...(snapshotCapitals === undefined ? [] : ["wikidata-capitals"]),
            ...(snapshotCapitals === undefined ||
            snapshotCapitals.some((capital) => capital.names.de === undefined)
              ? ["legacy-flag-catalog"]
              : []),
          ],
        },
        { fields: ["flag"], sourceIds: ["flag-icons-7.5.0"] },
      ],
      review: { status: "pending", reviewedBy: null, reviewedAt: null, issues },
    });
  }

  const database: CountryCandidateDatabase = {
    kind: "flaggenbande-country-candidates",
    schemaVersion: COUNTRY_SCHEMA_VERSION,
    datasetVersion: options.datasetVersion,
    generatedAt: options.generatedAt,
    scope: { kind: "un-member-states", expectedCount: EXPECTED_COUNTRY_COUNT },
    sources: buildSources(options.generatedAt, unM49Snapshot, snapshot),
    countries,
  };
  const reviewItems: ReviewQueueItem[] = countries.map((country) => ({
    countryId: country.id,
    isoAlpha2: country.codes.isoAlpha2,
    countryNameDe: country.names.de.display,
    countryNameEn: country.names.en.display,
    capitalSummary: country.capitals
      .map((capital) => capital.names.en ?? capital.names.de ?? "MISSING")
      .join(" / "),
    flagRelativePath: country.flag.relativePath,
    status: "pending",
    issues: country.review.issues,
  }));
  const reviewQueue: CountryReviewQueue = {
    kind: "flaggenbande-country-review-queue",
    schemaVersion: REVIEW_QUEUE_SCHEMA_VERSION,
    datasetVersion: options.datasetVersion,
    generatedAt: options.generatedAt,
    items: reviewItems,
  };

  const reviewDirectory = path.join(options.stagingDirectory, "review");
  await mkdir(reviewDirectory, { recursive: true });
  await Promise.all([copyLicenseFiles(options), copySourceSnapshots(options)]);
  const databasePath = path.join(options.stagingDirectory, "country-candidates.v1.json");
  const reviewQueuePath = path.join(reviewDirectory, "review-queue.v1.json");
  const contactSheetPath = path.join(reviewDirectory, "flag-contact-sheet.html");
  const manifestPath = path.join(options.stagingDirectory, "manifest.json");
  await Promise.all([
    writeFile(databasePath, json(database), "utf8"),
    writeFile(reviewQueuePath, json(reviewQueue), "utf8"),
    writeFile(contactSheetPath, contactSheetHtml(database), "utf8"),
  ]);
  await assertValidCountryCandidateDatabase(database, options.stagingDirectory);
  const manifest = await createManifest(options.stagingDirectory, options.datasetVersion, options.generatedAt);
  await writeFile(manifestPath, json(manifest), "utf8");
  return {
    database,
    reviewQueue,
    manifest,
    databasePath,
    reviewQueuePath,
    contactSheetPath,
    manifestPath,
  };
};
