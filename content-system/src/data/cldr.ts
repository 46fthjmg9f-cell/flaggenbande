import { readFile } from "node:fs/promises";
import path from "node:path";

import { CountryDataError } from "./errors.js";
import type { Continent } from "./types.js";

interface CldrCodeMapping {
  readonly _numeric?: string;
  readonly _alpha3?: string;
}

interface CldrContainmentEntry {
  readonly _contains?: readonly string[];
}

export interface CldrCountryData {
  readonly alpha3: string;
  readonly numeric: string;
  readonly nameDe: string;
  readonly nameEn: string;
  readonly continent: Continent;
  readonly regionCode: string;
  readonly regionNameDe: string;
  readonly regionNameEn: string;
}

export interface LoadedCldrData {
  readonly countryByAlpha2: ReadonlyMap<string, CldrCountryData>;
}

const asRecord = (value: unknown, description: string): Record<string, unknown> => {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new CountryDataError(`Expected object at ${description}`);
  }
  return value as Record<string, unknown>;
};

const readJson = async (filePath: string): Promise<unknown> => {
  try {
    return JSON.parse(await readFile(filePath, "utf8")) as unknown;
  } catch (error) {
    throw new CountryDataError(`Cannot read CLDR JSON: ${filePath}`, { cause: error });
  }
};

const territoryNames = (value: unknown, locale: "de" | "en"): Record<string, string> => {
  const main = asRecord(asRecord(value, "root").main, "main");
  const language = asRecord(main[locale], `main.${locale}`);
  const displayNames = asRecord(language.localeDisplayNames, `main.${locale}.localeDisplayNames`);
  const territories = asRecord(displayNames.territories, `main.${locale}.localeDisplayNames.territories`);
  const names: Record<string, string> = {};
  for (const [key, item] of Object.entries(territories)) {
    if (typeof item === "string") {
      names[key] = item.normalize("NFC").trim();
    }
  }
  return names;
};

const assignRegions = (
  containment: Readonly<Record<string, CldrContainmentEntry>>,
): ReadonlyMap<string, { readonly continent: Continent; readonly regionCode: string }> => {
  const result = new Map<string, { readonly continent: Continent; readonly regionCode: string }>();

  const visit = (node: string, continent: Continent, regionCode: string | null): void => {
    const children = containment[node]?._contains;
    if (children === undefined) {
      return;
    }
    for (const child of children) {
      if (/^[A-Z]{2}$/u.test(child)) {
        if (regionCode !== null) {
          result.set(child, { continent, regionCode });
        }
      } else if (/^\d{3}$/u.test(child)) {
        const nextContinent = node === "019" && child === "005" ? "south-america" : continent;
        visit(child, nextContinent, child);
      }
    }
  };

  visit("002", "africa", null);
  visit("142", "asia", null);
  visit("150", "europe", null);
  visit("009", "oceania", null);
  visit("019", "north-america", null);
  return result;
};

export const loadCldrData = async (
  cldrCoreRoot: string,
  cldrLocaleNamesRoot: string,
): Promise<LoadedCldrData> => {
  const [mappingJson, containmentJson, namesDeJson, namesEnJson] = await Promise.all([
    readJson(path.join(cldrCoreRoot, "supplemental", "codeMappings.json")),
    readJson(path.join(cldrCoreRoot, "supplemental", "territoryContainment.json")),
    readJson(path.join(cldrLocaleNamesRoot, "main", "de", "territories.json")),
    readJson(path.join(cldrLocaleNamesRoot, "main", "en", "territories.json")),
  ]);

  const supplementalMappings = asRecord(asRecord(mappingJson, "mapping root").supplemental, "supplemental");
  const rawMappings = asRecord(supplementalMappings.codeMappings, "supplemental.codeMappings");
  const mappings = rawMappings as Readonly<Record<string, CldrCodeMapping>>;
  const supplementalContainment = asRecord(
    asRecord(containmentJson, "containment root").supplemental,
    "supplemental",
  );
  const containment = asRecord(
    supplementalContainment.territoryContainment,
    "supplemental.territoryContainment",
  ) as Readonly<Record<string, CldrContainmentEntry>>;
  const namesDe = territoryNames(namesDeJson, "de");
  const namesEn = territoryNames(namesEnJson, "en");
  const regions = assignRegions(containment);
  const countryByAlpha2 = new Map<string, CldrCountryData>();

  for (const [alpha2, mapping] of Object.entries(mappings)) {
    const alpha3 = mapping._alpha3;
    const numeric = mapping._numeric;
    const nameDe = namesDe[alpha2];
    const nameEn = namesEn[alpha2];
    const region = regions.get(alpha2);
    if (
      /^[A-Z]{2}$/u.test(alpha2) &&
      alpha3 !== undefined &&
      numeric !== undefined &&
      nameDe !== undefined &&
      nameEn !== undefined &&
      region !== undefined
    ) {
      const regionNameDe = namesDe[region.regionCode];
      const regionNameEn = namesEn[region.regionCode];
      if (regionNameDe === undefined || regionNameEn === undefined) {
        throw new CountryDataError(`Missing CLDR region name for ${region.regionCode}`);
      }
      countryByAlpha2.set(alpha2, {
        alpha3,
        numeric,
        nameDe,
        nameEn,
        continent: region.continent,
        regionCode: region.regionCode,
        regionNameDe,
        regionNameEn,
      });
    }
  }

  return { countryByAlpha2 };
};
