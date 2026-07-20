import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import {
  assertExactMemberCountrySet,
  createCapitalSnapshot,
  fetchCurrentCapitalBindings,
  normalizeCapitalBindings,
  parseCliArguments,
  parseSparqlResponse,
  SNAPSHOT_SCHEMA_VERSION,
  WIKIDATA_CAPITALS_QUERY,
  WIKIDATA_ENDPOINT,
  writeSnapshotAtomically,
  type WikidataCapitalBinding,
} from "../scripts/fetch-wikidata-capitals.js";

const sparqlValue = (type: "literal" | "uri", value: string): Record<string, string> => ({
  type,
  value,
});

const sparqlRow = (values: {
  readonly iso2: string;
  readonly countryQid: string;
  readonly countryDe: string;
  readonly countryEn: string;
  readonly capitalQid: string;
  readonly capitalDe: string;
  readonly capitalEn: string;
}): Record<string, Record<string, string>> => ({
  iso2: sparqlValue("literal", values.iso2),
  country: sparqlValue("uri", `http://www.wikidata.org/entity/${values.countryQid}`),
  countryLabelDe: sparqlValue("literal", values.countryDe),
  countryLabelEn: sparqlValue("literal", values.countryEn),
  capital: sparqlValue("uri", `http://www.wikidata.org/entity/${values.capitalQid}`),
  capitalLabelDe: sparqlValue("literal", values.capitalDe),
  capitalLabelEn: sparqlValue("literal", values.capitalEn),
});

const validResponse = JSON.stringify({
  head: { vars: [] },
  results: {
    bindings: [
      sparqlRow({
        iso2: "ZA",
        countryQid: "Q258",
        countryDe: "Südafrika",
        countryEn: "South Africa",
        capitalQid: "Q5465",
        capitalDe: "Kapstadt",
        capitalEn: "Cape Town",
      }),
      sparqlRow({
        iso2: "DE",
        countryQid: "Q183",
        countryDe: "  Deutschland ",
        countryEn: "Germany",
        capitalQid: "Q64",
        capitalDe: "Berlin",
        capitalEn: "Berlin",
      }),
      sparqlRow({
        iso2: "ZA",
        countryQid: "Q258",
        countryDe: "Südafrika",
        countryEn: "South Africa",
        capitalQid: "Q3926",
        capitalDe: "Pretoria",
        capitalEn: "Pretoria",
      }),
      sparqlRow({
        iso2: "DE",
        countryQid: "Q183",
        countryDe: "  Deutschland ",
        countryEn: "Germany",
        capitalQid: "Q64",
        capitalDe: "Berlin",
        capitalEn: "Berlin",
      }),
    ],
  },
});

const normalizedFixture = () => normalizeCapitalBindings(parseSparqlResponse(validResponse));

test("parses and deterministically normalizes offline SPARQL results", () => {
  const countries = normalizedFixture();

  assert.deepEqual(
    countries.map((country) => country.isoAlpha2),
    ["DE", "ZA"],
  );
  assert.equal(countries[0]?.names.de, "Deutschland");
  assert.deepEqual(
    countries[1]?.capitals.map((capital) => capital.qid),
    ["Q3926", "Q5465"],
  );
  assert.equal(countries[0]?.capitals.length, 1, "duplicate bindings must be removed");
});

test("rejects malformed JSON and malformed SPARQL result shapes", () => {
  assert.throws(() => parseSparqlResponse("not-json"), /not valid JSON/u);
  assert.throws(
    () => parseSparqlResponse(JSON.stringify({ results: {} })),
    /results\.bindings/u,
  );
});

test("rejects malformed required bindings", () => {
  const malformed = JSON.stringify({
    results: {
      bindings: [
        {
          ...sparqlRow({
            iso2: "DE",
            countryQid: "Q183",
            countryDe: "Deutschland",
            countryEn: "Germany",
            capitalQid: "Q64",
            capitalDe: "Berlin",
            capitalEn: "Berlin",
          }),
          capital: sparqlValue("uri", "https://example.com/Q64"),
        },
      ],
    },
  });

  assert.throws(() => parseSparqlResponse(malformed), /invalid capital entity URI/u);
});

test("rejects conflicting country identities for one ISO code", () => {
  const bindings: readonly WikidataCapitalBinding[] = [
    {
      isoAlpha2: "DE",
      countryQid: "Q183",
      countryNames: { de: "Deutschland", en: "Germany" },
      capitalQid: "Q64",
      capitalNames: { de: "Berlin", en: "Berlin" },
    },
    {
      isoAlpha2: "DE",
      countryQid: "Q999",
      countryNames: { de: "Deutschland", en: "Germany" },
      capitalQid: "Q64",
      capitalNames: { de: "Berlin", en: "Berlin" },
    },
  ];

  assert.throws(() => normalizeCapitalBindings(bindings), /multiple Wikidata countries/u);
});

test("creates reproducible snapshot metadata with an injected clock", () => {
  const snapshot = createCapitalSnapshot(
    normalizedFixture(),
    () => new Date("2026-07-20T12:34:56.000Z"),
  );

  assert.equal(snapshot.schemaVersion, SNAPSHOT_SCHEMA_VERSION);
  assert.equal(snapshot.fetchedAt, "2026-07-20T12:34:56.000Z");
  assert.equal(snapshot.endpoint, WIKIDATA_ENDPOINT);
  assert.match(snapshot.querySha256, /^[a-f0-9]{64}$/u);
  assert.equal(snapshot.license.spdx, "CC0-1.0");
  assert.match(WIKIDATA_CAPITALS_QUERY, /wdt:P36/u);
  assert.match(WIKIDATA_CAPITALS_QUERY, /VALUES \?iso2/u);
  assert.match(WIKIDATA_CAPITALS_QUERY, /"DK"/u);
  assert.match(WIKIDATA_CAPITALS_QUERY, /wd:Q1065/u);
  assert.match(WIKIDATA_CAPITALS_QUERY, /wd:Q35/u);
  assert.match(WIKIDATA_CAPITALS_QUERY, /OPTIONAL/u);
});

test("blocks partial country sets before a production snapshot is written", () => {
  assert.throws(
    () => assertExactMemberCountrySet(normalizedFixture()),
    /must contain exactly 193 member states/u,
  );
});

test("requires exactly one --output argument", () => {
  assert.throws(() => parseCliArguments([]), /Missing required argument/u);
  assert.throws(() => parseCliArguments(["--output"]), /requires a file path/u);
  assert.throws(
    () => parseCliArguments(["--output", "one.json", "--output", "two.json"]),
    /only be supplied once/u,
  );
  assert.match(parseCliArguments(["--output", "snapshot.json"]).outputPath, /snapshot\.json$/u);
});

test("writes snapshots atomically and never overwrites an existing file", async () => {
  const directory = await mkdtemp(join(tmpdir(), "flaggenbande-wikidata-test-"));
  const outputPath = join(directory, "capital-snapshot.json");
  const snapshot = createCapitalSnapshot(
    normalizedFixture(),
    () => new Date("2026-07-20T12:34:56.000Z"),
  );

  try {
    await writeSnapshotAtomically(outputPath, snapshot);
    const firstContent = await readFile(outputPath, "utf8");
    assert.deepEqual(JSON.parse(firstContent) as unknown, snapshot);

    await assert.rejects(
      writeSnapshotAtomically(outputPath, snapshot),
      /will not be overwritten/u,
    );
    assert.equal(await readFile(outputPath, "utf8"), firstContent);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("reports HTTP, JSON and timeout failures without network access", async () => {
  const httpFailure: typeof fetch = async () =>
    new Response("unavailable", { status: 503, statusText: "Service Unavailable" });
  await assert.rejects(
    fetchCurrentCapitalBindings({ fetchImplementation: httpFailure }),
    /HTTP 503 Service Unavailable/u,
  );

  const invalidJson: typeof fetch = async () => new Response("not-json", { status: 200 });
  await assert.rejects(
    fetchCurrentCapitalBindings({ fetchImplementation: invalidJson }),
    /not valid JSON/u,
  );

  const aborted: typeof fetch = async () => {
    throw new DOMException("aborted", "AbortError");
  };
  await assert.rejects(
    fetchCurrentCapitalBindings({ fetchImplementation: aborted, timeoutMilliseconds: 10 }),
    /timed out after 10 ms/u,
  );
});

test("does not use network in this test suite", async () => {
  const responseFile = join(tmpdir(), `flaggenbande-offline-${process.pid}.json`);
  await writeFile(responseFile, validResponse, "utf8");
  try {
    const parsed = parseSparqlResponse(await readFile(responseFile, "utf8"));
    assert.equal(parsed.length, 4);
  } finally {
    await rm(responseFile, { force: true });
  }
});
