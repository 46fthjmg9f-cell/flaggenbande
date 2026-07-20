export const COUNTRY_SCHEMA_VERSION = "1.0.0" as const;
export const REVIEW_QUEUE_SCHEMA_VERSION = "1.0.0" as const;
export const WIKIDATA_CAPITAL_SCHEMA_VERSION = "1.0.0" as const;
export const UN_M49_SCHEMA_VERSION = "1.0.0" as const;

export type IsoAlpha2 = Uppercase<string>;
export type CountryId = `country-${string}`;
export type ReviewStatus = "pending" | "approved" | "rejected";
export type DifficultyLevel = 1 | 2 | 3 | 4 | 5;
export type Continent =
  | "africa"
  | "asia"
  | "europe"
  | "north-america"
  | "south-america"
  | "oceania";

export type CapitalRole =
  | "official"
  | "constitutional"
  | "administrative"
  | "legislative"
  | "judicial"
  | "de-facto"
  | "seat-of-government"
  | "unspecified";

export interface LocalizedCandidateName {
  readonly display: string;
  readonly legacy: string;
}

export interface CandidateCapital {
  readonly id: string;
  readonly names: {
    readonly de: string | null;
    readonly en: string | null;
  };
  readonly roles: readonly CapitalRole[];
  readonly primaryDisplay: boolean;
  readonly acceptedQuizAnswer: boolean;
  readonly sourceId: string;
  readonly sourceEntityId: string | null;
}

export interface DifficultyAssessment {
  readonly level: DifficultyLevel;
  readonly rubricVersion: string;
  readonly rationale: string;
  readonly reviewStatus: ReviewStatus;
}

export interface ReviewMetadata {
  readonly status: ReviewStatus;
  readonly reviewedBy: string | null;
  readonly reviewedAt: string | null;
  readonly issues: readonly string[];
}

export interface CandidateFlagAsset {
  readonly assetId: string;
  readonly version: 1;
  readonly relativePath: string;
  readonly mediaType: "image/svg+xml";
  readonly aspectRatio: "4x3";
  readonly byteSize: number;
  readonly checksum: {
    readonly algorithm: "sha256";
    readonly value: string;
  };
  readonly sourceId: "flag-icons-7.5.0";
  readonly license: {
    readonly identifier: "MIT";
    readonly name: "MIT License";
    readonly relativeLicensePath: "licenses/flag-icons-MIT.txt";
    readonly attributionRequired: true;
    readonly attributionText: "Copyright (c) 2013 Panayiotis Lipiridis";
  };
  readonly review: ReviewMetadata;
}

export interface FieldProvenance {
  readonly fields: readonly string[];
  readonly sourceIds: readonly string[];
}

export interface CandidateCountry {
  readonly id: CountryId;
  readonly recordVersion: 1;
  readonly eligibility: {
    readonly status: "un-member";
    readonly standardQuiz: boolean;
  };
  readonly codes: {
    readonly isoAlpha2: IsoAlpha2;
    readonly isoAlpha3: string;
    readonly isoNumeric: string;
    readonly unM49: string;
  };
  readonly names: {
    readonly de: LocalizedCandidateName;
    readonly en: LocalizedCandidateName;
  };
  readonly capitals: readonly CandidateCapital[];
  readonly geography: {
    readonly continent: Continent;
    readonly region: {
      readonly scheme: "UN_M49";
      readonly code: string;
      readonly names: {
        readonly de: string;
        readonly en: string;
      };
    };
  };
  readonly difficulty: DifficultyAssessment | null;
  readonly flag: CandidateFlagAsset;
  readonly provenance: readonly FieldProvenance[];
  readonly review: ReviewMetadata;
}

export interface DatasetSource {
  readonly id: string;
  readonly kind:
    | "legacy-catalog"
    | "cldr"
    | "flag-assets"
    | "un-m49-snapshot"
    | "wikidata-snapshot";
  readonly title: string;
  readonly version: string;
  readonly locator: string;
  readonly retrievedAt: string;
  readonly license: string;
}

export interface CountryCandidateDatabase {
  readonly kind: "flaggenbande-country-candidates";
  readonly schemaVersion: typeof COUNTRY_SCHEMA_VERSION;
  readonly datasetVersion: string;
  readonly generatedAt: string;
  readonly scope: {
    readonly kind: "un-member-states";
    readonly expectedCount: 193;
  };
  readonly sources: readonly DatasetSource[];
  readonly countries: readonly CandidateCountry[];
}

export interface ReviewQueueItem {
  readonly countryId: CountryId;
  readonly isoAlpha2: IsoAlpha2;
  readonly countryNameDe: string;
  readonly countryNameEn: string;
  readonly capitalSummary: string;
  readonly flagRelativePath: string;
  readonly status: "pending";
  readonly issues: readonly string[];
}

export interface CountryReviewQueue {
  readonly kind: "flaggenbande-country-review-queue";
  readonly schemaVersion: typeof REVIEW_QUEUE_SCHEMA_VERSION;
  readonly datasetVersion: string;
  readonly generatedAt: string;
  readonly items: readonly ReviewQueueItem[];
}

export interface WikidataLocalizedNames {
  readonly de?: string;
  readonly en?: string;
}

export interface WikidataCapitalRecord {
  readonly qid: string;
  readonly names: WikidataLocalizedNames;
  readonly roles?: readonly CapitalRole[];
}

export interface WikidataCountryCapitalRecord {
  readonly isoAlpha2: string;
  readonly qid: string;
  readonly names: WikidataLocalizedNames;
  readonly capitals: readonly WikidataCapitalRecord[];
}

export interface WikidataCapitalSnapshot {
  readonly schemaVersion: typeof WIKIDATA_CAPITAL_SCHEMA_VERSION;
  readonly fetchedAt: string;
  readonly endpoint: string;
  readonly querySha256: string;
  readonly license: {
    readonly spdx: "CC0-1.0";
    readonly name: "Creative Commons CC0 1.0 Universal";
    readonly url: "https://creativecommons.org/publicdomain/zero/1.0/";
  };
  readonly countries: readonly WikidataCountryCapitalRecord[];
}

export interface UnM49CountryRecord {
  readonly isoAlpha2: string;
  readonly isoAlpha3: string;
  readonly m49: string;
  readonly countryOrArea: string;
  readonly regionCode: string;
  readonly regionName: string;
  readonly subregionCode: string;
  readonly subregionName: string;
}

export interface UnM49Snapshot {
  readonly schemaVersion: typeof UN_M49_SCHEMA_VERSION;
  readonly fetchedAt: string;
  readonly sourceUrl: "https://unstats.un.org/unsd/methodology/m49/overview/";
  readonly sourceSha256: string;
  readonly countries: readonly UnM49CountryRecord[];
}

export interface CountryDataGeneratorOptions {
  readonly legacyCatalogPath: string;
  readonly cldrCoreRoot: string;
  readonly cldrLocaleNamesRoot: string;
  readonly flagIconsRoot: string;
  readonly stagingDirectory: string;
  readonly datasetVersion: string;
  readonly generatedAt: string;
  readonly wikidataCapitalSnapshotPath?: string;
  readonly unM49SnapshotPath?: string;
}

export interface GeneratedFileRecord {
  readonly relativePath: string;
  readonly byteSize: number;
  readonly sha256: string;
}

export interface CountryDataGenerationManifest {
  readonly schemaVersion: "1.0.0";
  readonly datasetVersion: string;
  readonly generatedAt: string;
  readonly files: readonly GeneratedFileRecord[];
}

export interface CountryDataGenerationResult {
  readonly database: CountryCandidateDatabase;
  readonly reviewQueue: CountryReviewQueue;
  readonly manifest: CountryDataGenerationManifest;
  readonly databasePath: string;
  readonly reviewQueuePath: string;
  readonly contactSheetPath: string;
  readonly manifestPath: string;
}
