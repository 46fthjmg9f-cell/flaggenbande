import { lstat, readFile, realpath, stat } from "node:fs/promises";
import path from "node:path";

import { inspectSvgSafety, sha256 } from "./assets.js";
import {
  EXPECTED_COUNTRY_COUNT,
  FORBIDDEN_STANDARD_CODES,
  UN_MEMBER_ALPHA2_SET,
} from "./constants.js";
import { CountryDataValidationError, type DataValidationIssue } from "./errors.js";
import type {
  CandidateCountry,
  CountryCandidateDatabase,
  ReviewMetadata,
} from "./types.js";

const SUPPORTED_CONTINENTS: ReadonlySet<string> = new Set([
  "africa",
  "asia",
  "europe",
  "north-america",
  "south-america",
  "oceania",
]);

const issue = (code: string, itemPath: string, message: string): DataValidationIssue => ({
  code,
  path: itemPath,
  message,
});

const nonEmpty = (value: string): boolean => value.trim().length > 0 && value === value.normalize("NFC");

const validReview = (
  review: ReviewMetadata,
  itemPath: string,
): readonly DataValidationIssue[] => {
  const issues: DataValidationIssue[] = [];
  const normalizedIssues = review.issues.map((item) => item.trim());
  if (
    normalizedIssues.some((item) => item.length === 0) ||
    new Set(normalizedIssues).size !== normalizedIssues.length
  ) {
    issues.push(issue("invalid_review_issues", `${itemPath}.issues`, "must be non-empty and unique"));
  }
  const hasReviewer = review.reviewedBy !== null && nonEmpty(review.reviewedBy);
  const hasReviewDate = review.reviewedAt !== null && Number.isFinite(Date.parse(review.reviewedAt));
  if (review.status === "pending") {
    if (review.reviewedBy !== null || review.reviewedAt !== null) {
      issues.push(issue("pending_review_metadata", itemPath, "pending review must not have reviewer or date"));
    }
    if (review.issues.length === 0) {
      issues.push(issue("pending_without_issue", `${itemPath}.issues`, "pending review needs a blocking issue"));
    }
  } else {
    if (!hasReviewer || !hasReviewDate) {
      issues.push(issue("missing_review_audit", itemPath, "completed review requires reviewer and valid date"));
    }
    if (review.status === "approved" && review.issues.length > 0) {
      issues.push(issue("approved_with_issues", `${itemPath}.issues`, "approved review must have no issues"));
    }
    if (review.status === "rejected" && review.issues.length === 0) {
      issues.push(issue("rejected_without_issue", `${itemPath}.issues`, "rejected review needs a reason"));
    }
  }
  return issues;
};

const isReviewApproved = (review: ReviewMetadata): boolean =>
  review.status === "approved" &&
  review.reviewedBy !== null &&
  nonEmpty(review.reviewedBy) &&
  review.reviewedAt !== null &&
  Number.isFinite(Date.parse(review.reviewedAt)) &&
  review.issues.length === 0;

const isReleaseReady = (country: CandidateCountry): boolean =>
  isReviewApproved(country.review) &&
  isReviewApproved(country.flag.review) &&
  country.difficulty !== null &&
  country.difficulty.reviewStatus === "approved" &&
  nonEmpty(country.difficulty.rubricVersion) &&
  nonEmpty(country.difficulty.rationale) &&
  country.capitals.length > 0 &&
  country.capitals.filter((capital) => capital.primaryDisplay).length === 1 &&
  country.capitals.some((capital) => capital.acceptedQuizAnswer) &&
  country.capitals.every(
    (capital) =>
      capital.names.de !== null &&
      nonEmpty(capital.names.de) &&
      capital.names.en !== null &&
      nonEmpty(capital.names.en),
  );

const validateCountryShape = (
  country: CandidateCountry,
  index: number,
  sourceIds: ReadonlySet<string>,
): DataValidationIssue[] => {
  const issues: DataValidationIssue[] = [];
  const base = `countries[${String(index)}]`;
  const code = country.codes.isoAlpha2;

  issues.push(...validReview(country.review, `${base}.review`));
  issues.push(...validReview(country.flag.review, `${base}.flag.review`));

  if (!/^[A-Z]{2}$/u.test(code)) {
    issues.push(issue("invalid_alpha2", `${base}.codes.isoAlpha2`, "must be two uppercase letters"));
  }
  if (!/^[A-Z]{3}$/u.test(country.codes.isoAlpha3)) {
    issues.push(issue("invalid_alpha3", `${base}.codes.isoAlpha3`, "must be three uppercase letters"));
  }
  if (!/^\d{3}$/u.test(country.codes.isoNumeric) || country.codes.unM49 !== country.codes.isoNumeric) {
    issues.push(issue("invalid_numeric_code", `${base}.codes`, "ISO numeric and UN M49 must be equal three-digit codes"));
  }
  if (country.id !== `country-${country.codes.isoNumeric}`) {
    issues.push(issue("unstable_id", `${base}.id`, "must be derived from the initial UN M49 code"));
  }
  if (!UN_MEMBER_ALPHA2_SET.has(code) || FORBIDDEN_STANDARD_CODES.has(code)) {
    issues.push(issue("forbidden_scope", `${base}.codes.isoAlpha2`, "is not in the reviewed 193-member allowlist"));
  }
  if (!nonEmpty(country.names.de.display) || !nonEmpty(country.names.de.legacy)) {
    issues.push(issue("invalid_german_name", `${base}.names.de`, "display and legacy names are required and must be NFC"));
  }
  if (!nonEmpty(country.names.en.display) || !nonEmpty(country.names.en.legacy)) {
    issues.push(issue("invalid_english_name", `${base}.names.en`, "display and legacy names are required and must be NFC"));
  }
  if (country.capitals.length === 0) {
    issues.push(issue("missing_capital", `${base}.capitals`, "at least one capital candidate is required"));
  }
  if (country.capitals.filter((capital) => capital.primaryDisplay).length !== 1) {
    issues.push(issue("invalid_primary_capital", `${base}.capitals`, "exactly one primary display capital is required"));
  }
  if (!country.capitals.some((capital) => capital.acceptedQuizAnswer)) {
    issues.push(issue("missing_accepted_capital", `${base}.capitals`, "at least one accepted answer is required"));
  }
  const capitalIds = new Set<string>();
  for (const [capitalIndex, capital] of country.capitals.entries()) {
    if (capitalIds.has(capital.id)) {
      issues.push(issue("duplicate_capital_id", `${base}.capitals[${String(capitalIndex)}].id`, "must be unique per country"));
    }
    capitalIds.add(capital.id);
    if (
      (capital.names.de === null || capital.names.de.trim().length === 0) &&
      (capital.names.en === null || capital.names.en.trim().length === 0)
    ) {
      issues.push(issue("empty_capital", `${base}.capitals[${String(capitalIndex)}]`, "a localized capital value is required"));
    }
    if (
      country.review.status === "approved" &&
      (capital.names.de === null || capital.names.en === null)
    ) {
      issues.push(issue("untranslated_capital", `${base}.capitals[${String(capitalIndex)}].names`, "approved records require German and English capital names"));
    }
    if (!sourceIds.has(capital.sourceId)) {
      issues.push(issue("unknown_capital_source", `${base}.capitals[${String(capitalIndex)}].sourceId`, "must reference database.sources"));
    }
    if (
      (capital.sourceId === "wikidata-capitals" &&
        (capital.sourceEntityId === null || !/^Q[1-9][0-9]*$/u.test(capital.sourceEntityId))) ||
      (capital.sourceId !== "wikidata-capitals" && capital.sourceEntityId !== null)
    ) {
      issues.push(issue("invalid_capital_entity", `${base}.capitals[${String(capitalIndex)}].sourceEntityId`, "must match its source"));
    }
  }
  if (!SUPPORTED_CONTINENTS.has(country.geography.continent) || !/^\d{3}$/u.test(country.geography.region.code)) {
    issues.push(issue("invalid_region", `${base}.geography`, "continent and three-digit UN M49 region are required"));
  }
  if (country.difficulty !== null) {
    if (!Number.isInteger(country.difficulty.level) || country.difficulty.level < 1 || country.difficulty.level > 5) {
      issues.push(issue("invalid_difficulty", `${base}.difficulty.level`, "must be an integer from 1 to 5"));
    }
    if (!nonEmpty(country.difficulty.rubricVersion) || !nonEmpty(country.difficulty.rationale)) {
      issues.push(issue("invalid_difficulty_metadata", `${base}.difficulty`, "rubric version and rationale are required"));
    }
  } else if (country.review.status === "approved") {
    issues.push(issue("missing_difficulty", `${base}.difficulty`, "approved records require reviewed difficulty"));
  }
  if (country.review.status === "approved" && !isReleaseReady(country)) {
    issues.push(issue("incomplete_approval", `${base}.review`, "country approval requires approved flag, difficulty and complete capitals"));
  }
  if (country.eligibility.standardQuiz !== isReleaseReady(country)) {
    issues.push(issue("quiz_approval_mismatch", `${base}.eligibility.standardQuiz`, "must equal the complete release gate"));
  }
  const flagPath = country.flag.relativePath;
  if (
    path.isAbsolute(flagPath) ||
    flagPath.includes("..") ||
    /^[a-z][a-z\d+.-]*:/iu.test(flagPath) ||
    !flagPath.endsWith(".svg")
  ) {
    issues.push(issue("invalid_flag_path", `${base}.flag.relativePath`, "must be a safe local relative SVG path"));
  }
  if (!/^[a-f\d]{64}$/u.test(country.flag.checksum.value)) {
    issues.push(issue("invalid_flag_checksum", `${base}.flag.checksum.value`, "must be a lowercase SHA-256 digest"));
  }
  if (country.flag.license.identifier !== "MIT") {
    issues.push(issue("invalid_flag_license", `${base}.flag.license`, "flag-icons assets must retain their MIT license"));
  }
  if (
    country.flag.sourceId !== "flag-icons-7.5.0" ||
    country.flag.mediaType !== "image/svg+xml" ||
    country.flag.aspectRatio !== "4x3" ||
    country.flag.checksum.algorithm !== "sha256"
  ) {
    issues.push(issue("invalid_flag_contract", `${base}.flag`, "must retain the pinned flag-icons asset contract"));
  }
  if (
    country.flag.license.relativeLicensePath !== "licenses/flag-icons-MIT.txt" ||
    !country.flag.license.attributionRequired ||
    !nonEmpty(country.flag.license.attributionText)
  ) {
    issues.push(issue("invalid_flag_attribution", `${base}.flag.license`, "must retain license path and attribution"));
  }
  const coveredFields = new Set<string>();
  for (const [provenanceIndex, provenance] of country.provenance.entries()) {
    if (provenance.fields.length === 0 || provenance.sourceIds.length === 0) {
      issues.push(issue("empty_provenance", `${base}.provenance[${String(provenanceIndex)}]`, "fields and sourceIds are required"));
    }
    for (const field of provenance.fields) {
      if (!nonEmpty(field)) {
        issues.push(issue("invalid_provenance_field", `${base}.provenance[${String(provenanceIndex)}].fields`, "field names must be non-empty"));
      }
      coveredFields.add(field);
    }
    if (new Set(provenance.sourceIds).size !== provenance.sourceIds.length) {
      issues.push(issue("duplicate_provenance_source", `${base}.provenance[${String(provenanceIndex)}].sourceIds`, "source IDs must be unique"));
    }
    for (const sourceId of provenance.sourceIds) {
      if (!sourceIds.has(sourceId)) {
        issues.push(issue("unknown_provenance_source", `${base}.provenance[${String(provenanceIndex)}].sourceIds`, `unknown source ${sourceId}`));
      }
    }
  }
  for (const requiredField of [
    "codes",
    "names.de.display",
    "names.en.display",
    "names.de.legacy",
    "names.en.legacy",
    "capitals",
    "geography",
    "flag",
  ]) {
    if (!coveredFields.has(requiredField)) {
      issues.push(issue("missing_provenance", `${base}.provenance`, `missing coverage for ${requiredField}`));
    }
  }
  return issues;
};

const validateAsset = async (
  country: CandidateCountry,
  index: number,
  stagingDirectory: string,
): Promise<readonly DataValidationIssue[]> => {
  const base = `countries[${String(index)}].flag`;
  const target = path.resolve(stagingDirectory, ...country.flag.relativePath.split("/"));
  const root = path.resolve(stagingDirectory) + path.sep;
  if (!target.startsWith(root)) {
    return [issue("asset_escape", `${base}.relativePath`, "asset resolves outside staging directory")];
  }
  try {
    const [bytes, fileStat, linkStat, resolvedRoot, resolvedTarget] = await Promise.all([
      readFile(target),
      stat(target),
      lstat(target),
      realpath(stagingDirectory),
      realpath(target),
    ]);
    const issues: DataValidationIssue[] = [];
    if (!fileStat.isFile() || linkStat.isSymbolicLink()) {
      issues.push(issue("invalid_asset_type", `${base}.relativePath`, "asset must be a regular non-symlink file"));
    }
    if (!resolvedTarget.startsWith(`${resolvedRoot}${path.sep}`)) {
      issues.push(issue("asset_escape", `${base}.relativePath`, "resolved asset escapes staging directory"));
    }
    if (fileStat.size !== country.flag.byteSize) {
      issues.push(issue("asset_size_mismatch", `${base}.byteSize`, "does not match local asset"));
    }
    if (sha256(bytes) !== country.flag.checksum.value) {
      issues.push(issue("asset_checksum_mismatch", `${base}.checksum.value`, "does not match local asset"));
    }
    for (const safetyIssue of inspectSvgSafety(bytes.toString("utf8"))) {
      issues.push(issue("unsafe_svg", `${base}.relativePath`, safetyIssue));
    }
    return issues;
  } catch {
    return [issue("missing_asset", `${base}.relativePath`, "local asset is missing or unreadable")];
  }
};

const validateLicenseFile = async (
  database: CountryCandidateDatabase,
  stagingDirectory: string,
): Promise<readonly DataValidationIssue[]> => {
  const licensePath = database.countries[0]?.flag.license.relativeLicensePath;
  if (licensePath === undefined) {
    return [issue("missing_license", "countries", "flag license metadata is missing")];
  }
  if (path.isAbsolute(licensePath) || licensePath.includes("..")) {
    return [issue("invalid_license_path", "countries[0].flag.license.relativeLicensePath", "must be a safe relative path")];
  }
  const absolute = path.resolve(stagingDirectory, ...licensePath.split("/"));
  try {
    const [bytes, linkStat, resolvedRoot, resolvedLicense] = await Promise.all([
      readFile(absolute),
      lstat(absolute),
      realpath(stagingDirectory),
      realpath(absolute),
    ]);
    const issues: DataValidationIssue[] = [];
    if (linkStat.isSymbolicLink() || !linkStat.isFile()) {
      issues.push(issue("invalid_license_type", "countries[0].flag.license.relativeLicensePath", "license must be a regular non-symlink file"));
    }
    if (!resolvedLicense.startsWith(`${resolvedRoot}${path.sep}`)) {
      issues.push(issue("license_escape", "countries[0].flag.license.relativeLicensePath", "resolved license escapes staging directory"));
    }
    if (bytes.length === 0) {
      issues.push(issue("empty_license", "countries[0].flag.license.relativeLicensePath", "license file must not be empty"));
    }
    return issues;
  } catch {
    return [issue("missing_license", "countries[0].flag.license.relativeLicensePath", "license file is missing or unreadable")];
  }
};

export const validateCountryCandidateDatabase = async (
  database: CountryCandidateDatabase,
  stagingDirectory: string,
): Promise<readonly DataValidationIssue[]> => {
  const issues: DataValidationIssue[] = [];
  if (database.countries.length !== EXPECTED_COUNTRY_COUNT) {
    issues.push(issue("country_count", "countries", `must contain exactly ${String(EXPECTED_COUNTRY_COUNT)} records`));
  }
  const sourceIds = new Set<string>();
  for (const [sourceIndex, source] of database.sources.entries()) {
    if (sourceIds.has(source.id)) {
      issues.push(issue("duplicate_source", `sources[${String(sourceIndex)}].id`, `duplicate source ${source.id}`));
    }
    sourceIds.add(source.id);
    if (
      !nonEmpty(source.id) ||
      !nonEmpty(source.title) ||
      !nonEmpty(source.version) ||
      !nonEmpty(source.locator) ||
      !nonEmpty(source.license) ||
      !Number.isFinite(Date.parse(source.retrievedAt))
    ) {
      issues.push(issue("invalid_source", `sources[${String(sourceIndex)}]`, "source metadata must be complete"));
    }
  }
  const uniqueFields: Array<[string, (country: CandidateCountry) => string]> = [
    ["id", (country) => country.id],
    ["alpha2", (country) => country.codes.isoAlpha2],
    ["alpha3", (country) => country.codes.isoAlpha3],
    ["numeric", (country) => country.codes.isoNumeric],
  ];
  for (const [label, select] of uniqueFields) {
    const seen = new Set<string>();
    for (const [index, country] of database.countries.entries()) {
      const value = select(country);
      if (seen.has(value)) {
        issues.push(issue(`duplicate_${label}`, `countries[${String(index)}]`, `duplicate ${label}: ${value}`));
      }
      seen.add(value);
    }
  }
  const actualCodes: ReadonlySet<string> = new Set(
    database.countries.map((country) => country.codes.isoAlpha2),
  );
  for (const expectedCode of UN_MEMBER_ALPHA2_SET) {
    if (!actualCodes.has(expectedCode)) {
      issues.push(issue("missing_member", "countries", `missing UN member code ${expectedCode}`));
    }
  }
  for (const [index, country] of database.countries.entries()) {
    issues.push(...validateCountryShape(country, index, sourceIds));
  }
  const assetResults = await Promise.all(
    database.countries.map((country, index) => validateAsset(country, index, stagingDirectory)),
  );
  for (const assetIssues of assetResults) {
    issues.push(...assetIssues);
  }
  issues.push(...(await validateLicenseFile(database, stagingDirectory)));
  return issues;
};

export const assertValidCountryCandidateDatabase = async (
  database: CountryCandidateDatabase,
  stagingDirectory: string,
): Promise<void> => {
  const issues = await validateCountryCandidateDatabase(database, stagingDirectory);
  if (issues.length > 0) {
    throw new CountryDataValidationError(issues);
  }
};
