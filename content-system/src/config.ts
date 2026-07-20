import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { isAbsolute, resolve } from "node:path";

export const APP_MODES = ["development", "production"] as const;
export const LOG_LEVELS = ["debug", "info", "warn", "error"] as const;

export type AppMode = (typeof APP_MODES)[number];
export type LogLevel = (typeof LOG_LEVELS)[number];

interface FileConfig {
  readonly logLevel: LogLevel;
  readonly outputDirectory: string;
  readonly localCacheDirectory: string;
  readonly renderConcurrency: number;
}

export interface AppConfig extends FileConfig {
  readonly mode: AppMode;
  readonly projectDirectory: string;
  readonly cloudRoot?: string;
}

const isAppMode = (value: string): value is AppMode =>
  APP_MODES.some((mode) => mode === value);

const isLogLevel = (value: string): value is LogLevel =>
  LOG_LEVELS.some((level) => level === value);

const requiredString = (value: unknown, field: string): string => {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`Configuration field "${field}" must be a non-empty string.`);
  }
  return value.trim();
};

const positiveInteger = (value: unknown, field: string): number => {
  if (!Number.isInteger(value) || Number(value) < 1) {
    throw new Error(`Configuration field "${field}" must be a positive integer.`);
  }
  return Number(value);
};

const parseFileConfig = (value: unknown): FileConfig => {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error("The mode configuration must be a JSON object.");
  }
  const record = value as Record<string, unknown>;
  const logLevel = requiredString(record.logLevel, "logLevel");
  if (!isLogLevel(logLevel)) {
    throw new Error(`Unsupported log level: ${logLevel}.`);
  }
  return {
    logLevel,
    outputDirectory: requiredString(record.outputDirectory, "outputDirectory"),
    localCacheDirectory: requiredString(record.localCacheDirectory, "localCacheDirectory"),
    renderConcurrency: positiveInteger(record.renderConcurrency, "renderConcurrency"),
  };
};

export const expandHome = (value: string, userHome: string = homedir()): string => {
  if (value === "~") {
    return userHome;
  }
  if (value.startsWith("~/")) {
    return resolve(userHome, value.slice(2));
  }
  return value;
};

const resolveProjectPath = (projectDirectory: string, value: string): string =>
  isAbsolute(expandHome(value))
    ? expandHome(value)
    : resolve(projectDirectory, expandHome(value));

export const loadConfig = (
  environment: NodeJS.ProcessEnv = process.env,
  projectDirectory: string = process.cwd(),
): AppConfig => {
  const rawMode = environment.FLAGGENBANDE_MODE?.trim() || "development";
  if (!isAppMode(rawMode)) {
    throw new Error(
      `FLAGGENBANDE_MODE must be one of: ${APP_MODES.join(", ")}. Received: ${rawMode}.`,
    );
  }

  const configPath = resolve(projectDirectory, "config", rawMode, "app.json");
  let parsed: unknown;
  try {
    parsed = JSON.parse(readFileSync(configPath, "utf8")) as unknown;
  } catch (error) {
    throw new Error(
      `Could not load configuration ${configPath}: ${error instanceof Error ? error.message : "Unknown error"}`,
    );
  }
  const fileConfig = parseFileConfig(parsed);
  const rawLogLevel = environment.FLAGGENBANDE_LOG_LEVEL?.trim() || fileConfig.logLevel;
  if (!isLogLevel(rawLogLevel)) {
    throw new Error(`Unsupported FLAGGENBANDE_LOG_LEVEL: ${rawLogLevel}.`);
  }
  const outputDirectory = environment.FLAGGENBANDE_OUTPUT_DIR?.trim() || fileConfig.outputDirectory;
  const localCacheDirectory =
    environment.FLAGGENBANDE_LOCAL_CACHE_DIR?.trim() || fileConfig.localCacheDirectory;
  const rawCloudRoot = environment.FLAGGENBANDE_CLOUD_ROOT?.trim();

  return {
    mode: rawMode,
    projectDirectory: resolve(projectDirectory),
    logLevel: rawLogLevel,
    outputDirectory: resolveProjectPath(projectDirectory, outputDirectory),
    localCacheDirectory: resolveProjectPath(projectDirectory, localCacheDirectory),
    renderConcurrency: fileConfig.renderConcurrency,
    ...(rawCloudRoot
      ? { cloudRoot: resolveProjectPath(projectDirectory, rawCloudRoot) }
      : {}),
  };
};
