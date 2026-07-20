import { createHash, randomUUID } from "node:crypto";
import { link, lstat, mkdir, unlink, writeFile } from "node:fs/promises";
import { basename, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { UN_MEMBER_ALPHA2, UN_MEMBER_ALPHA2_SET } from "../src/data/constants.js";
import {
  UN_M49_SCHEMA_VERSION,
  type UnM49CountryRecord,
  type UnM49Snapshot,
} from "../src/data/types.js";

export const UN_M49_SOURCE_URL =
  "https://unstats.un.org/unsd/methodology/m49/overview/" as const;

type Clock = () => Date;

const errorMessage = (error: unknown): string =>
  error instanceof Error ? error.message : String(error);

const errorCode = (error: unknown): string | undefined => {
  if (typeof error !== "object" || error === null || Array.isArray(error)) {
    return undefined;
  }
  const code = (error as Record<string, unknown>).code;
  return typeof code === "string" ? code : undefined;
};

const decodeHtml = (value: string): string =>
  value
    .replace(/<!--.*?-->/gsu, "")
    .replace(/<[^>]+>/gu, "")
    .replace(/&#(\d+);/gu, (_match, decimal: string) => String.fromCodePoint(Number(decimal)))
    .replace(/&#x([0-9a-f]+);/giu, (_match, hexadecimal: string) =>
      String.fromCodePoint(Number.parseInt(hexadecimal, 16)),
    )
    .replaceAll("&amp;", "&")
    .replaceAll("&quot;", '"')
    .replaceAll("&#39;", "'")
    .replaceAll("&nbsp;", " ")
    .replace(/\s+/gu, " ")
    .normalize("NFC")
    .trim();

const exactMemberSet = (countries: readonly UnM49CountryRecord[]): void => {
  const codes = new Set(countries.map((country) => country.isoAlpha2));
  const missing = UN_MEMBER_ALPHA2.filter((code) => !codes.has(code));
  if (codes.size !== countries.length || missing.length > 0 || codes.size !== UN_MEMBER_ALPHA2.length) {
    throw new Error(
      `UN M49 source must contain exactly ${String(UN_MEMBER_ALPHA2.length)} member states; missing: ${missing.join(", ") || "none"}.`,
    );
  }
};

export const parseUnM49OverviewHtml = (html: string): readonly UnM49CountryRecord[] => {
  const table = /<table[^>]*id\s*=\s*["']?downloadTableEN["']?[^>]*>([\s\S]*?)<\/table>/iu.exec(
    html,
  )?.[1];
  if (table === undefined) {
    throw new Error("UN M49 page does not contain the English downloadTableEN table.");
  }
  const body = /<tbody[^>]*>([\s\S]*?)<\/tbody>/iu.exec(table)?.[1];
  if (body === undefined) {
    throw new Error("UN M49 English table does not contain a tbody.");
  }
  const countries: UnM49CountryRecord[] = [];
  for (const rowMatch of body.matchAll(/<tr[^>]*>([\s\S]*?)<\/tr>/giu)) {
    const row = rowMatch[1];
    if (row === undefined) {
      continue;
    }
    const cells = [...row.matchAll(/<td[^>]*>([\s\S]*?)<\/td>/giu)].map((match) =>
      decodeHtml(match[1] ?? ""),
    );
    if (cells.length < 12) {
      continue;
    }
    const isoAlpha2 = cells[10] ?? "";
    if (!UN_MEMBER_ALPHA2_SET.has(isoAlpha2)) {
      continue;
    }
    const record: UnM49CountryRecord = {
      isoAlpha2,
      isoAlpha3: cells[11] ?? "",
      m49: cells[9] ?? "",
      countryOrArea: cells[8] ?? "",
      regionCode: cells[2] ?? "",
      regionName: cells[3] ?? "",
      subregionCode: (cells[6] ?? "").length > 0 ? (cells[6] ?? "") : (cells[4] ?? ""),
      subregionName: (cells[7] ?? "").length > 0 ? (cells[7] ?? "") : (cells[5] ?? ""),
    };
    if (
      !/^[A-Z]{3}$/u.test(record.isoAlpha3) ||
      !/^\d{3}$/u.test(record.m49) ||
      !/^\d{3}$/u.test(record.regionCode) ||
      !/^\d{3}$/u.test(record.subregionCode) ||
      record.countryOrArea.length === 0 ||
      record.regionName.length === 0 ||
      record.subregionName.length === 0
    ) {
      throw new Error(`UN M49 row for ${isoAlpha2} is incomplete or malformed.`);
    }
    countries.push(record);
  }
  const sorted = [...countries].sort((left, right) =>
    left.isoAlpha2.localeCompare(right.isoAlpha2, "en"),
  );
  exactMemberSet(sorted);
  return sorted;
};

export const createUnM49Snapshot = (
  html: string,
  clock: Clock = () => new Date(),
): UnM49Snapshot => {
  const fetchedAt = clock();
  if (Number.isNaN(fetchedAt.getTime())) {
    throw new Error("UN M49 snapshot clock returned an invalid date.");
  }
  return {
    schemaVersion: UN_M49_SCHEMA_VERSION,
    fetchedAt: fetchedAt.toISOString(),
    sourceUrl: UN_M49_SOURCE_URL,
    sourceSha256: createHash("sha256").update(html, "utf8").digest("hex"),
    countries: parseUnM49OverviewHtml(html),
  };
};

export const fetchUnM49Overview = async (
  fetchImplementation: typeof fetch = fetch,
  timeoutMilliseconds = 30_000,
): Promise<string> => {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMilliseconds);
  try {
    const response = await fetchImplementation(UN_M49_SOURCE_URL, {
      headers: {
        Accept: "text/html",
        "User-Agent":
          "FlaggenbandeContentSystem/0.2.0 (https://github.com/46fthjmg9f-cell/flaggenbande)",
      },
      signal: controller.signal,
    });
    if (!response.ok) {
      throw new Error(`UN M49 request failed with HTTP ${String(response.status)}.`);
    }
    return await response.text();
  } catch (error) {
    if (controller.signal.aborted || (error instanceof Error && error.name === "AbortError")) {
      throw new Error(`UN M49 request timed out after ${String(timeoutMilliseconds)} ms.`);
    }
    throw error;
  } finally {
    clearTimeout(timeout);
  }
};

const outputExists = async (outputPath: string): Promise<boolean> => {
  try {
    await lstat(outputPath);
    return true;
  } catch (error) {
    if (errorCode(error) === "ENOENT") {
      return false;
    }
    throw error;
  }
};

export const writeUnM49SnapshotAtomically = async (
  outputPath: string,
  snapshot: UnM49Snapshot,
): Promise<void> => {
  const absolute = resolve(outputPath);
  if (await outputExists(absolute)) {
    throw new Error(`Output file already exists and will not be overwritten: ${absolute}`);
  }
  await mkdir(dirname(absolute), { recursive: true });
  const temporary = resolve(
    dirname(absolute),
    `.${basename(absolute)}.${process.pid}.${randomUUID()}.tmp`,
  );
  try {
    await writeFile(temporary, `${JSON.stringify(snapshot, null, 2)}\n`, {
      encoding: "utf8",
      flag: "wx",
      mode: 0o644,
    });
    await link(temporary, absolute);
  } finally {
    await unlink(temporary).catch(() => undefined);
  }
};

export const parseUnM49CliArguments = (
  arguments_: readonly string[],
): { readonly outputPath: string } => {
  if (arguments_.length !== 2 || arguments_[0] !== "--output" || arguments_[1] === undefined) {
    throw new Error("Usage: fetch-un-m49 --output <path>");
  }
  return { outputPath: resolve(arguments_[1]) };
};

export const runUnM49Cli = async (
  arguments_: readonly string[] = process.argv.slice(2),
): Promise<void> => {
  const { outputPath } = parseUnM49CliArguments(arguments_);
  const html = await fetchUnM49Overview();
  const snapshot = createUnM49Snapshot(html);
  await writeUnM49SnapshotAtomically(outputPath, snapshot);
  process.stdout.write(
    `UN M49 snapshot written: ${outputPath} (${String(snapshot.countries.length)} countries)\n`,
  );
};

const isDirectExecution =
  process.argv[1] !== undefined && resolve(process.argv[1]) === fileURLToPath(import.meta.url);

if (isDirectExecution) {
  runUnM49Cli().catch((error: unknown) => {
    process.stderr.write(`[un-m49] ${errorMessage(error)}\n`);
    process.exitCode = 1;
  });
}
