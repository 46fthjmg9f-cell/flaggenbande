import { readFile } from "node:fs/promises";

import { UN_MEMBER_ALPHA2, UN_MEMBER_ALPHA2_SET } from "./constants.js";
import { CountryDataError } from "./errors.js";
import {
  UN_M49_SCHEMA_VERSION,
  type UnM49CountryRecord,
  type UnM49Snapshot,
} from "./types.js";

const SOURCE_URL = "https://unstats.un.org/unsd/methodology/m49/overview/" as const;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const text = (value: unknown, field: string, pattern?: RegExp): string => {
  if (typeof value !== "string") {
    throw new CountryDataError(`${field} must be a string`);
  }
  const normalized = value.normalize("NFC").replace(/\s+/gu, " ").trim();
  if (normalized.length === 0 || (pattern !== undefined && !pattern.test(normalized))) {
    throw new CountryDataError(`${field} has an invalid value`);
  }
  return normalized;
};

const parseCountry = (value: unknown, index: number): UnM49CountryRecord => {
  const field = `countries[${String(index)}]`;
  if (!isRecord(value)) {
    throw new CountryDataError(`${field} must be an object`);
  }
  const isoAlpha2 = text(value.isoAlpha2, `${field}.isoAlpha2`, /^[A-Z]{2}$/u);
  if (!UN_MEMBER_ALPHA2_SET.has(isoAlpha2)) {
    throw new CountryDataError(`${field}.isoAlpha2 is outside the 193-member allowlist`);
  }
  return {
    isoAlpha2,
    isoAlpha3: text(value.isoAlpha3, `${field}.isoAlpha3`, /^[A-Z]{3}$/u),
    m49: text(value.m49, `${field}.m49`, /^\d{3}$/u),
    countryOrArea: text(value.countryOrArea, `${field}.countryOrArea`),
    regionCode: text(value.regionCode, `${field}.regionCode`, /^\d{3}$/u),
    regionName: text(value.regionName, `${field}.regionName`),
    subregionCode: text(value.subregionCode, `${field}.subregionCode`, /^\d{3}$/u),
    subregionName: text(value.subregionName, `${field}.subregionName`),
  };
};

export const loadUnM49Snapshot = async (filePath: string): Promise<UnM49Snapshot> => {
  let input: unknown;
  try {
    input = JSON.parse(await readFile(filePath, "utf8")) as unknown;
  } catch (error) {
    throw new CountryDataError(`Cannot read UN M49 snapshot: ${filePath}`, { cause: error });
  }
  if (!isRecord(input)) {
    throw new CountryDataError("UN M49 snapshot must be an object");
  }
  if (input.schemaVersion !== UN_M49_SCHEMA_VERSION) {
    throw new CountryDataError(`Unsupported UN M49 schema: ${String(input.schemaVersion)}`);
  }
  if (typeof input.fetchedAt !== "string" || !Number.isFinite(Date.parse(input.fetchedAt))) {
    throw new CountryDataError("UN M49 snapshot has invalid fetchedAt");
  }
  if (input.sourceUrl !== SOURCE_URL) {
    throw new CountryDataError("UN M49 snapshot has an unexpected sourceUrl");
  }
  if (typeof input.sourceSha256 !== "string" || !/^[a-f0-9]{64}$/u.test(input.sourceSha256)) {
    throw new CountryDataError("UN M49 snapshot has invalid sourceSha256");
  }
  if (!Array.isArray(input.countries)) {
    throw new CountryDataError("UN M49 snapshot countries must be an array");
  }
  const countries = input.countries.map(parseCountry);
  const actual = new Set(countries.map((country) => country.isoAlpha2));
  const alpha3 = new Set(countries.map((country) => country.isoAlpha3));
  const m49 = new Set(countries.map((country) => country.m49));
  const missing = UN_MEMBER_ALPHA2.filter((code) => !actual.has(code));
  if (actual.size !== countries.length || missing.length > 0 || actual.size !== UN_MEMBER_ALPHA2.length) {
    throw new CountryDataError(
      `UN M49 snapshot must contain exactly ${String(UN_MEMBER_ALPHA2.length)} unique countries; missing: ${missing.join(", ") || "none"}`,
    );
  }
  if (alpha3.size !== countries.length) {
    throw new CountryDataError("UN M49 snapshot contains a duplicate ISO alpha-3 code");
  }
  if (m49.size !== countries.length) {
    throw new CountryDataError("UN M49 snapshot contains a duplicate M49 code");
  }
  return {
    schemaVersion: UN_M49_SCHEMA_VERSION,
    fetchedAt: input.fetchedAt,
    sourceUrl: SOURCE_URL,
    sourceSha256: input.sourceSha256,
    countries: [...countries].sort((left, right) =>
      left.isoAlpha2.localeCompare(right.isoAlpha2, "en"),
    ),
  };
};
