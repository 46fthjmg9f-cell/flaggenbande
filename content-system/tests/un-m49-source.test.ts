import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

import {
  createUnM49Snapshot,
  parseUnM49OverviewHtml,
  writeUnM49SnapshotAtomically,
} from "../scripts/fetch-un-m49.js";
import { UN_MEMBER_ALPHA2 } from "../src/data/constants.js";
import { loadUnM49Snapshot } from "../src/data/unM49.js";

const overviewHtml = (codes: readonly string[] = UN_MEMBER_ALPHA2): string => `
<html><body><table id = "downloadTableEN"><thead></thead><tbody>
${codes
  .map(
    (code, index) => `<tr>
      <td>001</td><td>World</td><td>150</td><td>Europe</td>
      <td>039</td><td>Southern Europe</td><td></td><td></td>
      <td>Country &amp; ${code}</td><td>${String(index + 1).padStart(3, "0")}</td>
      <td>${code}</td><td>${code}X</td><td></td><td></td><td></td>
    </tr>`,
  )
  .join("\n")}
</tbody></table></body></html>`;

test("parses exactly the fixed 193-member UN M49 scope", () => {
  const countries = parseUnM49OverviewHtml(overviewHtml());
  assert.equal(countries.length, 193);
  assert.equal(countries[0]?.isoAlpha2, "AD");
  assert.equal(countries[0]?.countryOrArea, "Country & AD");
  assert.equal(countries.at(-1)?.isoAlpha2, "ZW");
});

test("rejects incomplete UN M49 source pages", () => {
  assert.throws(
    () => parseUnM49OverviewHtml(overviewHtml(UN_MEMBER_ALPHA2.slice(1))),
    /must contain exactly 193 member states/u,
  );
});

test("creates, writes and reloads one shared UN M49 snapshot contract", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "flaggenbande-un-m49-test-"));
  const snapshotPath = path.join(root, "un-m49.json");
  try {
    const snapshot = createUnM49Snapshot(
      overviewHtml(),
      () => new Date("2026-07-20T12:00:00.000Z"),
    );
    assert.match(snapshot.sourceSha256, /^[a-f0-9]{64}$/u);
    await writeUnM49SnapshotAtomically(snapshotPath, snapshot);
    const loaded = await loadUnM49Snapshot(snapshotPath);
    assert.deepEqual(loaded, snapshot);
    await assert.rejects(
      writeUnM49SnapshotAtomically(snapshotPath, snapshot),
      /will not be overwritten/u,
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("loader rejects duplicate official identifiers", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "flaggenbande-un-m49-duplicate-"));
  const snapshotPath = path.join(root, "un-m49.json");
  try {
    const snapshot = createUnM49Snapshot(
      overviewHtml(),
      () => new Date("2026-07-20T12:00:00.000Z"),
    );
    const countries = snapshot.countries.map((country, index) =>
      index === 1 ? { ...country, m49: snapshot.countries[0]?.m49 ?? country.m49 } : country,
    );
    await writeFile(snapshotPath, `${JSON.stringify({ ...snapshot, countries })}\n`, "utf8");
    await assert.rejects(loadUnM49Snapshot(snapshotPath), /duplicate M49 code/u);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
