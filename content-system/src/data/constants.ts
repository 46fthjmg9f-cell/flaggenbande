import type { IsoAlpha2 } from "./types.js";

export const EXPECTED_COUNTRY_COUNT = 193 as const;

export const UN_MEMBER_ALPHA2 = [
  "AD", "AE", "AF", "AG", "AL", "AM", "AO", "AR", "AT", "AU", "AZ",
  "BA", "BB", "BD", "BE", "BF", "BG", "BH", "BI", "BJ", "BN", "BO",
  "BR", "BS", "BT", "BW", "BY", "BZ", "CA", "CD", "CF", "CG", "CH",
  "CI", "CL", "CM", "CN", "CO", "CR", "CU", "CV", "CY", "CZ", "DE",
  "DJ", "DK", "DM", "DO", "DZ", "EC", "EE", "EG", "ER", "ES", "ET",
  "FI", "FJ", "FM", "FR", "GA", "GB", "GD", "GE", "GH", "GM", "GN",
  "GQ", "GR", "GT", "GW", "GY", "HN", "HR", "HT", "HU", "ID", "IE",
  "IL", "IN", "IQ", "IR", "IS", "IT", "JM", "JO", "JP", "KE", "KG",
  "KH", "KI", "KM", "KN", "KP", "KR", "KW", "KZ", "LA", "LB", "LC",
  "LI", "LK", "LR", "LS", "LT", "LU", "LV", "LY", "MA", "MC", "MD",
  "ME", "MG", "MH", "MK", "ML", "MM", "MN", "MR", "MT", "MU", "MV",
  "MW", "MX", "MY", "MZ", "NA", "NE", "NG", "NI", "NL", "NO", "NP",
  "NR", "NZ", "OM", "PA", "PE", "PG", "PH", "PK", "PL", "PT", "PW",
  "PY", "QA", "RO", "RS", "RU", "RW", "SA", "SB", "SC", "SD", "SE",
  "SG", "SI", "SK", "SL", "SM", "SN", "SO", "SR", "SS", "ST", "SV",
  "SY", "SZ", "TD", "TG", "TH", "TJ", "TL", "TM", "TN", "TO", "TR",
  "TT", "TV", "TZ", "UA", "UG", "US", "UY", "UZ", "VC", "VE", "VN",
  "VU", "WS", "YE", "ZA", "ZM", "ZW",
] as const satisfies readonly IsoAlpha2[];

export const UN_MEMBER_ALPHA2_SET: ReadonlySet<string> = new Set(UN_MEMBER_ALPHA2);

export const FORBIDDEN_STANDARD_CODES: ReadonlySet<string> = new Set([
  "AB",
  "CK",
  "EH",
  "GB-ENG",
  "GB-NIR",
  "GB-SCT",
  "GB-WLS",
  "NC",
  "NU",
  "OS",
  "PS",
  "SLD",
  "TW",
  "VA",
  "XK",
]);
