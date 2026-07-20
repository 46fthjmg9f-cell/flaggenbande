import { readFile } from "node:fs/promises";

import { UN_MEMBER_ALPHA2, UN_MEMBER_ALPHA2_SET } from "./constants.js";
import { CountryDataError } from "./errors.js";
import {
  WIKIDATA_CAPITAL_SCHEMA_VERSION,
  type CapitalRole,
  type WikidataCapitalRecord,
  type WikidataCapitalSnapshot,
  type WikidataCountryCapitalRecord,
  type WikidataLocalizedNames,
} from "./types.js";

const ALLOWED_ROLES: ReadonlySet<string> = new Set<CapitalRole>([
  "official",
  "constitutional",
  "administrative",
  "legislative",
  "judicial",
  "de-facto",
  "seat-of-government",
  "unspecified",
]);

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const normalizedText = (value: unknown, field: string): string => {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new CountryDataError(`${field} must be a non-empty string`);
  }
  return value.normalize("NFC").replace(/\s+/gu, " ").trim();
};

const optionalNormalizedText = (value: unknown, field: string): string | undefined =>
  value === undefined ? undefined : normalizedText(value, field);

const qid = (value: unknown, field: string): string => {
  const normalized = normalizedText(value, field).toUpperCase();
  if (!/^Q[1-9][0-9]*$/u.test(normalized)) {
    throw new CountryDataError(`${field} must be a Wikidata QID`);
  }
  return normalized;
};

const compareQids = (left: string, right: string): number => {
  const leftNumber = BigInt(left.slice(1));
  const rightNumber = BigInt(right.slice(1));
  return leftNumber < rightNumber ? -1 : leftNumber > rightNumber ? 1 : 0;
};

const parseNames = (
  value: unknown,
  field: string,
  requireEnglish: boolean,
): WikidataLocalizedNames => {
  if (!isRecord(value)) {
    throw new CountryDataError(`${field} must be an object`);
  }
  const de = optionalNormalizedText(value.de, `${field}.de`);
  const en = optionalNormalizedText(value.en, `${field}.en`);
  if (requireEnglish && en === undefined) {
    throw new CountryDataError(`${field}.en must be a non-empty string`);
  }
  return {
    ...(de === undefined ? {} : { de }),
    ...(en === undefined ? {} : { en }),
  };
};

const parseCapital = (value: unknown, countryCode: string, index: number): WikidataCapitalRecord => {
  const field = `countries.${countryCode}.capitals[${String(index)}]`;
  if (!isRecord(value)) {
    throw new CountryDataError(`${field} must be an object`);
  }
  const rolesValue = value.roles;
  if (rolesValue !== undefined && !Array.isArray(rolesValue)) {
    throw new CountryDataError(`${field}.roles must be an array`);
  }
  const roles = rolesValue?.map((role) => {
    if (typeof role !== "string" || !ALLOWED_ROLES.has(role)) {
      throw new CountryDataError(`${field}.roles contains an unsupported role`);
    }
    return role as CapitalRole;
  });
  return {
    qid: qid(value.qid, `${field}.qid`),
    names: parseNames(value.names, `${field}.names`, false),
    ...(roles === undefined ? {} : { roles }),
  };
};

const parseCountry = (value: unknown, index: number): WikidataCountryCapitalRecord => {
  const field = `countries[${String(index)}]`;
  if (!isRecord(value)) {
    throw new CountryDataError(`${field} must be an object`);
  }
  const isoAlpha2 = normalizedText(value.isoAlpha2, `${field}.isoAlpha2`).toUpperCase();
  if (!/^[A-Z]{2}$/u.test(isoAlpha2) || !UN_MEMBER_ALPHA2_SET.has(isoAlpha2)) {
    throw new CountryDataError(`${field}.isoAlpha2 is not in the 193-member allowlist`);
  }
  if (!Array.isArray(value.capitals) || value.capitals.length === 0) {
    throw new CountryDataError(`${field}.capitals must contain at least one entry`);
  }
  const capitals = value.capitals.map((capital, capitalIndex) =>
    parseCapital(capital, isoAlpha2, capitalIndex),
  );
  if (new Set(capitals.map((capital) => capital.qid)).size !== capitals.length) {
    throw new CountryDataError(`${field}.capitals contains duplicate QIDs`);
  }
  return {
    isoAlpha2,
    qid: qid(value.qid, `${field}.qid`),
    names: parseNames(value.names, `${field}.names`, true),
    capitals: [...capitals].sort((left, right) => compareQids(left.qid, right.qid)),
  };
};

const assertExactScope = (countries: readonly WikidataCountryCapitalRecord[]): void => {
  const actual = new Set(countries.map((country) => country.isoAlpha2));
  if (actual.size !== countries.length) {
    throw new CountryDataError("Wikidata capital snapshot contains duplicate country codes");
  }
  const missing = UN_MEMBER_ALPHA2.filter((code) => !actual.has(code));
  if (missing.length > 0 || actual.size !== UN_MEMBER_ALPHA2.length) {
    throw new CountryDataError(
      `Wikidata capital snapshot must contain exactly ${String(UN_MEMBER_ALPHA2.length)} countries; missing: ${missing.join(", ") || "none"}`,
    );
  }
};

export const loadWikidataCapitalSnapshot = async (
  filePath: string,
): Promise<WikidataCapitalSnapshot> => {
  let input: unknown;
  try {
    input = JSON.parse(await readFile(filePath, "utf8")) as unknown;
  } catch (error) {
    throw new CountryDataError(`Cannot read Wikidata capital snapshot: ${filePath}`, { cause: error });
  }
  if (!isRecord(input)) {
    throw new CountryDataError("Wikidata capital snapshot must be an object");
  }
  if (input.schemaVersion !== WIKIDATA_CAPITAL_SCHEMA_VERSION) {
    throw new CountryDataError(`Unsupported Wikidata capital schema: ${String(input.schemaVersion)}`);
  }
  if (typeof input.fetchedAt !== "string" || !Number.isFinite(Date.parse(input.fetchedAt))) {
    throw new CountryDataError("Wikidata capital snapshot has invalid fetchedAt");
  }
  if (typeof input.endpoint !== "string" || !input.endpoint.startsWith("https://")) {
    throw new CountryDataError("Wikidata capital snapshot endpoint must use HTTPS");
  }
  if (typeof input.querySha256 !== "string" || !/^[a-f0-9]{64}$/u.test(input.querySha256)) {
    throw new CountryDataError("Wikidata capital snapshot has invalid querySha256");
  }
  if (
    !isRecord(input.license) ||
    input.license.spdx !== "CC0-1.0" ||
    input.license.name !== "Creative Commons CC0 1.0 Universal" ||
    input.license.url !== "https://creativecommons.org/publicdomain/zero/1.0/"
  ) {
    throw new CountryDataError("Wikidata capital snapshot must retain CC0-1.0 metadata");
  }
  if (!Array.isArray(input.countries)) {
    throw new CountryDataError("Wikidata capital snapshot countries must be an array");
  }
  const countries = input.countries.map(parseCountry);
  assertExactScope(countries);
  return {
    schemaVersion: WIKIDATA_CAPITAL_SCHEMA_VERSION,
    fetchedAt: input.fetchedAt,
    endpoint: input.endpoint,
    querySha256: input.querySha256,
    license: {
      spdx: "CC0-1.0",
      name: "Creative Commons CC0 1.0 Universal",
      url: "https://creativecommons.org/publicdomain/zero/1.0/",
    },
    countries: [...countries].sort((left, right) =>
      left.isoAlpha2.localeCompare(right.isoAlpha2, "en"),
    ),
  };
};
