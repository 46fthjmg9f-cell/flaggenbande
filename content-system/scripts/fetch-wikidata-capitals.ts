import { createHash, randomUUID } from "node:crypto";
import { link, lstat, mkdir, unlink, writeFile } from "node:fs/promises";
import { basename, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { UN_MEMBER_ALPHA2, UN_MEMBER_ALPHA2_SET } from "../src/data/constants.js";
import {
  WIKIDATA_CAPITAL_SCHEMA_VERSION,
  type WikidataCapitalRecord,
  type WikidataCapitalSnapshot,
  type WikidataCountryCapitalRecord,
  type WikidataLocalizedNames,
} from "../src/data/types.js";

export const WIKIDATA_ENDPOINT = "https://query.wikidata.org/sparql";
export const SNAPSHOT_SCHEMA_VERSION = WIKIDATA_CAPITAL_SCHEMA_VERSION;

const WIKIDATA_MEMBER_VALUES = UN_MEMBER_ALPHA2.map((code) => `"${code}"`).join(" ");

export const WIKIDATA_CAPITALS_QUERY = `
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX wd: <http://www.wikidata.org/entity/>
PREFIX wdt: <http://www.wikidata.org/prop/direct/>

SELECT DISTINCT
  ?country
  ?iso2
  ?countryLabelDe
  ?countryLabelEn
  ?capital
  ?capitalLabelDe
  ?capitalLabelEn
WHERE {
  VALUES ?iso2 { ${WIKIDATA_MEMBER_VALUES} }

  ?country wdt:P297 ?iso2 ;
    wdt:P36 ?capital .

  FILTER(
    EXISTS { ?country wdt:P463 wd:Q1065 }
    || (?iso2 = "DK" && ?country = wd:Q35)
  )

  OPTIONAL {
    ?country rdfs:label ?countryLabelDe .
    FILTER(LANG(?countryLabelDe) = "de")
  }
  ?country rdfs:label ?countryLabelEn .
  FILTER(LANG(?countryLabelEn) = "en")
  OPTIONAL {
    ?capital rdfs:label ?capitalLabelDe .
    FILTER(LANG(?capitalLabelDe) = "de")
  }
  OPTIONAL {
    ?capital rdfs:label ?capitalLabelEn .
    FILTER(LANG(?capitalLabelEn) = "en")
  }
}
ORDER BY ?iso2 ?country ?capital
`.trim();

export interface WikidataCapitalBinding {
  readonly isoAlpha2: string;
  readonly countryQid: string;
  readonly countryNames: WikidataLocalizedNames;
  readonly capitalQid: string;
  readonly capitalNames: WikidataLocalizedNames;
}

export type Clock = () => Date;

interface FetchCapitalsOptions {
  readonly endpoint?: string;
  readonly fetchImplementation?: typeof fetch;
  readonly timeoutMilliseconds?: number;
}

interface MutableCountryRecord {
  readonly isoAlpha2: string;
  readonly qid: string;
  readonly names: WikidataLocalizedNames;
  readonly capitals: Map<string, WikidataCapitalRecord>;
}

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const errorMessage = (error: unknown): string =>
  error instanceof Error ? error.message : String(error);

const errorCode = (error: unknown): string | undefined => {
  if (!isRecord(error)) {
    return undefined;
  }
  return typeof error.code === "string" ? error.code : undefined;
};

const bindingValue = (
  binding: Record<string, unknown>,
  field: string,
  expectedType: "literal" | "uri",
  rowNumber: number,
): string => {
  const value = binding[field];
  if (!isRecord(value) || value.type !== expectedType || typeof value.value !== "string") {
    throw new Error(
      `Wikidata response row ${rowNumber} has an invalid or missing "${field}" binding.`,
    );
  }
  return value.value;
};

const optionalBindingValue = (
  binding: Record<string, unknown>,
  field: string,
  expectedType: "literal" | "uri",
  rowNumber: number,
): string | undefined => {
  const value = binding[field];
  if (value === undefined) {
    return undefined;
  }
  if (!isRecord(value) || value.type !== expectedType || typeof value.value !== "string") {
    throw new Error(`Wikidata response row ${rowNumber} has an invalid "${field}" binding.`);
  }
  return value.value;
};

const qidFromEntityUri = (value: string, field: string, rowNumber: number): string => {
  const match = /^https?:\/\/www\.wikidata\.org\/entity\/(Q[1-9][0-9]*)$/u.exec(value);
  if (match?.[1] === undefined) {
    throw new Error(`Wikidata response row ${rowNumber} has an invalid ${field} entity URI.`);
  }
  return match[1];
};

const normalizeText = (value: string, field: string): string => {
  const normalized = value.normalize("NFC").replace(/\s+/gu, " ").trim();
  if (normalized.length === 0) {
    throw new Error(`Wikidata field "${field}" must not be empty.`);
  }
  return normalized;
};

const normalizeIsoAlpha2 = (value: string): string => {
  const normalized = value.trim().toUpperCase();
  if (!/^[A-Z]{2}$/u.test(normalized)) {
    throw new Error(`Invalid ISO alpha-2 code received from Wikidata: "${value}".`);
  }
  return normalized;
};

const normalizeQid = (value: string, field: string): string => {
  const normalized = value.trim().toUpperCase();
  if (!/^Q[1-9][0-9]*$/u.test(normalized)) {
    throw new Error(`Invalid Wikidata QID for ${field}: "${value}".`);
  }
  return normalized;
};

const compareText = (left: string, right: string): number =>
  left < right ? -1 : left > right ? 1 : 0;

const compareQids = (left: string, right: string): number => {
  const leftNumber = BigInt(left.slice(1));
  const rightNumber = BigInt(right.slice(1));
  return leftNumber < rightNumber ? -1 : leftNumber > rightNumber ? 1 : 0;
};

const sameNames = (left: WikidataLocalizedNames, right: WikidataLocalizedNames): boolean =>
  left.de === right.de && left.en === right.en;

export const parseSparqlResponse = (responseText: string): readonly WikidataCapitalBinding[] => {
  let parsed: unknown;
  try {
    parsed = JSON.parse(responseText) as unknown;
  } catch (error) {
    throw new Error(`Wikidata response is not valid JSON: ${errorMessage(error)}`);
  }

  if (!isRecord(parsed) || !isRecord(parsed.results) || !Array.isArray(parsed.results.bindings)) {
    throw new Error('Wikidata response JSON is missing the "results.bindings" array.');
  }

  return parsed.results.bindings.map((candidate: unknown, index: number) => {
    const rowNumber = index + 1;
    if (!isRecord(candidate)) {
      throw new Error(`Wikidata response row ${rowNumber} must be an object.`);
    }

    const countryNameDe = optionalBindingValue(candidate, "countryLabelDe", "literal", rowNumber);
    const capitalNameDe = optionalBindingValue(candidate, "capitalLabelDe", "literal", rowNumber);
    const capitalNameEn = optionalBindingValue(candidate, "capitalLabelEn", "literal", rowNumber);
    return {
      isoAlpha2: bindingValue(candidate, "iso2", "literal", rowNumber),
      countryQid: qidFromEntityUri(
        bindingValue(candidate, "country", "uri", rowNumber),
        "country",
        rowNumber,
      ),
      countryNames: {
        ...(countryNameDe === undefined ? {} : { de: countryNameDe }),
        en: bindingValue(candidate, "countryLabelEn", "literal", rowNumber),
      },
      capitalQid: qidFromEntityUri(
        bindingValue(candidate, "capital", "uri", rowNumber),
        "capital",
        rowNumber,
      ),
      capitalNames: {
        ...(capitalNameDe === undefined ? {} : { de: capitalNameDe }),
        ...(capitalNameEn === undefined ? {} : { en: capitalNameEn }),
      },
    };
  });
};

export const normalizeCapitalBindings = (
  bindings: readonly WikidataCapitalBinding[],
): readonly WikidataCountryCapitalRecord[] => {
  if (bindings.length === 0) {
    throw new Error("Wikidata returned no capital records.");
  }

  const countriesByIso = new Map<string, MutableCountryRecord>();

  for (const binding of bindings) {
    const isoAlpha2 = normalizeIsoAlpha2(binding.isoAlpha2);
    const countryQid = normalizeQid(binding.countryQid, "country");
    if (binding.countryNames.en === undefined) {
      throw new Error(`Wikidata country ${isoAlpha2} is missing its English label.`);
    }
    const countryNames: WikidataLocalizedNames = {
      ...(binding.countryNames.de === undefined
        ? {}
        : { de: normalizeText(binding.countryNames.de, "countryNames.de") }),
      en: normalizeText(binding.countryNames.en, "countryNames.en"),
    };
    const capitalQid = normalizeQid(binding.capitalQid, "capital");
    const capitalNames: WikidataLocalizedNames = {
      ...(binding.capitalNames.de === undefined
        ? {}
        : { de: normalizeText(binding.capitalNames.de, "capitalNames.de") }),
      ...(binding.capitalNames.en === undefined
        ? {}
        : { en: normalizeText(binding.capitalNames.en, "capitalNames.en") }),
    };

    const existingCountry = countriesByIso.get(isoAlpha2);
    if (existingCountry !== undefined && existingCountry.qid !== countryQid) {
      throw new Error(
        `ISO alpha-2 code ${isoAlpha2} maps to multiple Wikidata countries: ${existingCountry.qid} and ${countryQid}.`,
      );
    }
    if (existingCountry !== undefined && !sameNames(existingCountry.names, countryNames)) {
      throw new Error(`Wikidata returned conflicting localized names for ${isoAlpha2}.`);
    }

    const country = existingCountry ?? {
      isoAlpha2,
      qid: countryQid,
      names: countryNames,
      capitals: new Map<string, WikidataCapitalRecord>(),
    };
    if (existingCountry === undefined) {
      countriesByIso.set(isoAlpha2, country);
    }

    const existingCapital = country.capitals.get(capitalQid);
    if (existingCapital !== undefined && !sameNames(existingCapital.names, capitalNames)) {
      throw new Error(
        `Wikidata returned conflicting localized names for capital ${capitalQid}.`,
      );
    }
    country.capitals.set(capitalQid, { qid: capitalQid, names: capitalNames });
  }

  return [...countriesByIso.values()]
    .sort(
      (left, right) =>
        compareText(left.isoAlpha2, right.isoAlpha2) || compareQids(left.qid, right.qid),
    )
    .map((country) => ({
      isoAlpha2: country.isoAlpha2,
      qid: country.qid,
      names: country.names,
      capitals: [...country.capitals.values()].sort((left, right) =>
        compareQids(left.qid, right.qid),
      ),
    }));
};

export const assertExactMemberCountrySet = (
  countries: readonly WikidataCountryCapitalRecord[],
): void => {
  const seen = new Set<string>();
  for (const country of countries) {
    if (!UN_MEMBER_ALPHA2_SET.has(country.isoAlpha2)) {
      throw new Error(`Wikidata snapshot contains non-member code ${country.isoAlpha2}.`);
    }
    if (seen.has(country.isoAlpha2)) {
      throw new Error(`Wikidata snapshot contains duplicate code ${country.isoAlpha2}.`);
    }
    seen.add(country.isoAlpha2);
  }
  const missing = UN_MEMBER_ALPHA2.filter((code) => !seen.has(code));
  if (missing.length > 0 || seen.size !== UN_MEMBER_ALPHA2.length) {
    throw new Error(
      `Wikidata snapshot must contain exactly ${String(UN_MEMBER_ALPHA2.length)} member states; missing: ${missing.join(", ") || "none"}.`,
    );
  }
};

export const createCapitalSnapshot = (
  countries: readonly WikidataCountryCapitalRecord[],
  clock: Clock = () => new Date(),
  endpoint: string = WIKIDATA_ENDPOINT,
): WikidataCapitalSnapshot => {
  if (countries.length === 0) {
    throw new Error("Cannot create an empty Wikidata capital snapshot.");
  }
  const fetchedAt = clock();
  if (Number.isNaN(fetchedAt.getTime())) {
    throw new Error("Snapshot clock returned an invalid date.");
  }

  return {
    schemaVersion: SNAPSHOT_SCHEMA_VERSION,
    fetchedAt: fetchedAt.toISOString(),
    endpoint,
    querySha256: createHash("sha256").update(WIKIDATA_CAPITALS_QUERY, "utf8").digest("hex"),
    license: {
      spdx: "CC0-1.0",
      name: "Creative Commons CC0 1.0 Universal",
      url: "https://creativecommons.org/publicdomain/zero/1.0/",
    },
    countries,
  };
};

export const fetchCurrentCapitalBindings = async (
  options: FetchCapitalsOptions = {},
): Promise<readonly WikidataCapitalBinding[]> => {
  const endpoint = options.endpoint ?? WIKIDATA_ENDPOINT;
  const fetchImplementation = options.fetchImplementation ?? fetch;
  const timeoutMilliseconds = options.timeoutMilliseconds ?? 30_000;
  if (!Number.isInteger(timeoutMilliseconds) || timeoutMilliseconds < 1) {
    throw new Error("Wikidata timeout must be a positive integer in milliseconds.");
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMilliseconds);
  const requestUrl = new URL(endpoint);
  requestUrl.searchParams.set("query", WIKIDATA_CAPITALS_QUERY);
  requestUrl.searchParams.set("format", "json");
  let response: Response;
  try {
    response = await fetchImplementation(requestUrl, {
      method: "GET",
      headers: {
        Accept: "application/sparql-results+json",
        "User-Agent":
          "FlaggenbandeContentSystem/0.2.0 (https://github.com/46fthjmg9f-cell/flaggenbande)",
      },
      signal: controller.signal,
    });
  } catch (error) {
    if (controller.signal.aborted || (error instanceof Error && error.name === "AbortError")) {
      throw new Error(`Wikidata request timed out after ${timeoutMilliseconds} ms.`);
    }
    throw new Error(`Wikidata request failed: ${errorMessage(error)}`);
  } finally {
    clearTimeout(timeout);
  }

  if (!response.ok) {
    const statusText = response.statusText.trim();
    throw new Error(
      `Wikidata request failed with HTTP ${response.status}${statusText.length > 0 ? ` ${statusText}` : ""}.`,
    );
  }

  let responseText: string;
  try {
    responseText = await response.text();
  } catch (error) {
    throw new Error(`Could not read Wikidata response: ${errorMessage(error)}`);
  }
  return parseSparqlResponse(responseText);
};

const assertOutputDoesNotExist = async (outputPath: string): Promise<void> => {
  try {
    await lstat(outputPath);
  } catch (error) {
    if (errorCode(error) === "ENOENT") {
      return;
    }
    throw error;
  }
  throw new Error(`Output file already exists and will not be overwritten: ${outputPath}`);
};

const removeTemporaryFile = async (temporaryPath: string): Promise<void> => {
  try {
    await unlink(temporaryPath);
  } catch (error) {
    if (errorCode(error) !== "ENOENT") {
      throw error;
    }
  }
};

export const writeSnapshotAtomically = async (
  outputPath: string,
  snapshot: WikidataCapitalSnapshot,
): Promise<void> => {
  const absoluteOutputPath = resolve(outputPath);
  await assertOutputDoesNotExist(absoluteOutputPath);
  await mkdir(dirname(absoluteOutputPath), { recursive: true });

  const temporaryPath = resolve(
    dirname(absoluteOutputPath),
    `.${basename(absoluteOutputPath)}.${process.pid}.${randomUUID()}.tmp`,
  );
  const serialized = `${JSON.stringify(snapshot, null, 2)}\n`;

  try {
    await writeFile(temporaryPath, serialized, { encoding: "utf8", flag: "wx", mode: 0o644 });
    try {
      await link(temporaryPath, absoluteOutputPath);
    } catch (error) {
      if (errorCode(error) === "EEXIST") {
        throw new Error(
          `Output file already exists and will not be overwritten: ${absoluteOutputPath}`,
        );
      }
      throw new Error(
        `Could not atomically publish Wikidata snapshot ${absoluteOutputPath}: ${errorMessage(error)}`,
      );
    }
  } finally {
    await removeTemporaryFile(temporaryPath);
  }
};

export const parseCliArguments = (arguments_: readonly string[]): { readonly outputPath: string } => {
  let outputPath: string | undefined;
  for (let index = 0; index < arguments_.length; index += 1) {
    const argument = arguments_[index];
    if (argument === "--output") {
      const value = arguments_[index + 1];
      if (value === undefined || value.startsWith("--")) {
        throw new Error("--output requires a file path.");
      }
      if (outputPath !== undefined) {
        throw new Error("--output may only be supplied once.");
      }
      outputPath = value;
      index += 1;
      continue;
    }
    throw new Error(`Unknown argument: ${argument ?? ""}`);
  }
  if (outputPath === undefined || outputPath.trim().length === 0) {
    throw new Error("Missing required argument: --output <path>.");
  }
  return { outputPath: resolve(outputPath) };
};

export const runCli = async (arguments_: readonly string[] = process.argv.slice(2)): Promise<void> => {
  const { outputPath } = parseCliArguments(arguments_);
  const bindings = await fetchCurrentCapitalBindings();
  const countries = normalizeCapitalBindings(bindings);
  assertExactMemberCountrySet(countries);
  const snapshot = createCapitalSnapshot(countries);
  await writeSnapshotAtomically(outputPath, snapshot);
  process.stdout.write(
    `Wikidata capital snapshot written: ${outputPath} (${countries.length} countries)\n`,
  );
};

const isDirectExecution =
  process.argv[1] !== undefined && resolve(process.argv[1]) === fileURLToPath(import.meta.url);

if (isDirectExecution) {
  runCli().catch((error: unknown) => {
    process.stderr.write(`[wikidata-capitals] ${errorMessage(error)}\n`);
    process.exitCode = 1;
  });
}
