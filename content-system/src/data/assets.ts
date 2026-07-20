import { createHash } from "node:crypto";
import { copyFile, mkdir, readFile, stat } from "node:fs/promises";
import path from "node:path";

import { CountryDataError } from "./errors.js";

const BLOCKED_SVG_ELEMENT = /<(?:script|foreignObject|iframe|object|embed|audio|video)\b/iu;
const EVENT_HANDLER = /\son[a-z]+\s*=/iu;
const ACTIVE_CONTENT = /javascript\s*:|<!DOCTYPE|<!ENTITY/iu;
const HREF = /(?:href|xlink:href)\s*=\s*["']([^"']+)["']/giu;
const CSS_URL = /url\(\s*["']?([^)'"\s]+)["']?\s*\)/giu;

export const sha256 = (bytes: Uint8Array): string => createHash("sha256").update(bytes).digest("hex");

export const inspectSvgSafety = (svg: string): readonly string[] => {
  const issues: string[] = [];
  if (!/<svg\b/iu.test(svg)) {
    issues.push("missing_svg_root");
  }
  if (BLOCKED_SVG_ELEMENT.test(svg)) {
    issues.push("blocked_svg_element");
  }
  if (EVENT_HANDLER.test(svg)) {
    issues.push("event_handler");
  }
  if (ACTIVE_CONTENT.test(svg)) {
    issues.push("active_content");
  }
  for (const match of svg.matchAll(HREF)) {
    const target = match[1];
    if (target !== undefined && !target.startsWith("#")) {
      issues.push("external_href");
      break;
    }
  }
  for (const match of svg.matchAll(CSS_URL)) {
    const target = match[1];
    if (target !== undefined && !target.startsWith("#")) {
      issues.push("external_css_url");
      break;
    }
  }
  const withoutNamespace = svg.replaceAll(
    /xmlns(?::[a-z][\w.-]*)?=["']http:\/\/www\.w3\.org\/[^"']+["']/giu,
    "",
  );
  if (/https?:\/\/|data:/iu.test(withoutNamespace)) {
    issues.push("remote_or_embedded_url");
  }
  return [...new Set(issues)];
};

export interface CopiedFlagAsset {
  readonly relativePath: string;
  readonly byteSize: number;
  readonly sha256: string;
}

export const copyVerifiedFlag = async (
  flagIconsRoot: string,
  alpha2: string,
  countryId: string,
  stagingDirectory: string,
): Promise<CopiedFlagAsset> => {
  const source = path.join(flagIconsRoot, "flags", "4x3", `${alpha2.toLowerCase()}.svg`);
  const relativePath = path.posix.join("assets", "flags", `${countryId}.svg`);
  const destination = path.join(stagingDirectory, ...relativePath.split("/"));
  let bytes: Buffer;
  try {
    bytes = await readFile(source);
  } catch (error) {
    throw new CountryDataError(`Missing local flag-icons asset for ${alpha2}`, { cause: error });
  }
  const safetyIssues = inspectSvgSafety(bytes.toString("utf8"));
  if (safetyIssues.length > 0) {
    throw new CountryDataError(`Unsafe SVG for ${alpha2}: ${safetyIssues.join(", ")}`);
  }
  await mkdir(path.dirname(destination), { recursive: true });
  await copyFile(source, destination);
  const copiedStat = await stat(destination);
  return {
    relativePath,
    byteSize: copiedStat.size,
    sha256: sha256(bytes),
  };
};
