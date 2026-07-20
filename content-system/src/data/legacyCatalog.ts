import { readFile } from "node:fs/promises";

import { CountryDataError } from "./errors.js";

export interface LegacyCountry {
  readonly code: string;
  readonly germanName: string;
  readonly englishName: string;
  readonly legacyContinent: string;
  readonly legacyCapital: string;
}

const decodeSwiftString = (value: string): string =>
  value
    .replaceAll("\\\"", "\"")
    .replaceAll("\\n", "\n")
    .replaceAll("\\t", "\t")
    .replaceAll("\\\\", "\\")
    .normalize("NFC")
    .trim();

const declarationBody = (source: string, declaration: string): string => {
  const start = source.indexOf(declaration);
  if (start < 0) {
    throw new CountryDataError(`Legacy catalog declaration not found: ${declaration}`);
  }

  const bodyStart = source.indexOf("[", start);
  const end = source.indexOf("\n]", bodyStart);
  if (bodyStart < 0 || end < 0) {
    throw new CountryDataError(`Legacy catalog declaration is malformed: ${declaration}`);
  }

  return source.slice(bodyStart + 1, end);
};

const parseDictionary = (body: string): ReadonlyMap<string, string> => {
  const result = new Map<string, string>();
  const entryPattern = /"((?:[^"\\]|\\.)+)"\s*:\s*"((?:[^"\\]|\\.)*)"/gu;

  for (const match of body.matchAll(entryPattern)) {
    const key = match[1];
    const value = match[2];
    if (key === undefined || value === undefined) {
      continue;
    }
    if (result.has(key)) {
      throw new CountryDataError(`Duplicate legacy dictionary key: ${key}`);
    }
    result.set(key, decodeSwiftString(value));
  }

  return result;
};

export const parseLegacyCatalog = (source: string): readonly LegacyCountry[] => {
  const countryBody = declarationBody(source, "let allCountries: [Country] = [");
  const capitalBody = declarationBody(source, "let capitalByCountryCode: [String: String] = [");
  const englishBody = declarationBody(source, "let countryEnglishNameByCode: [String: String] = [");
  const capitals = parseDictionary(capitalBody);
  const englishNames = parseDictionary(englishBody);
  const countries: LegacyCountry[] = [];
  const seenCodes = new Set<string>();
  const countryPattern = /Country\(code:\s*"((?:[^"\\]|\\.)+)",\s*name:\s*"((?:[^"\\]|\\.)+)",\s*continent:\s*"((?:[^"\\]|\\.)+)"\)/gu;

  for (const match of countryBody.matchAll(countryPattern)) {
    const rawCode = match[1];
    const rawGermanName = match[2];
    const rawContinent = match[3];
    if (rawCode === undefined || rawGermanName === undefined || rawContinent === undefined) {
      continue;
    }

    const code = decodeSwiftString(rawCode);
    if (seenCodes.has(code)) {
      throw new CountryDataError(`Duplicate allCountries code: ${code}`);
    }
    seenCodes.add(code);

    const englishName = englishNames.get(code);
    const legacyCapital = capitals.get(code);
    if (englishName === undefined || englishName.length === 0) {
      throw new CountryDataError(`Missing English legacy name for ${code}`);
    }
    if (legacyCapital === undefined || legacyCapital.length === 0) {
      throw new CountryDataError(`Missing legacy capital for ${code}`);
    }

    countries.push({
      code,
      germanName: decodeSwiftString(rawGermanName),
      englishName,
      legacyContinent: decodeSwiftString(rawContinent),
      legacyCapital,
    });
  }

  if (countries.length === 0) {
    throw new CountryDataError("No allCountries entries found in legacy catalog");
  }

  return countries;
};

export const loadLegacyCatalog = async (path: string): Promise<readonly LegacyCountry[]> =>
  parseLegacyCatalog(await readFile(path, "utf8"));
