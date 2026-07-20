import type { LogLevel } from "./config.js";

const LEVEL_WEIGHT: Readonly<Record<LogLevel, number>> = {
  debug: 10,
  info: 20,
  warn: 30,
  error: 40,
};

export interface LogRecord {
  readonly timestamp: string;
  readonly level: LogLevel;
  readonly event: string;
  readonly message: string;
  readonly context?: Readonly<Record<string, unknown>>;
}

export interface Logger {
  readonly debug: (event: string, message: string, context?: Readonly<Record<string, unknown>>) => void;
  readonly info: (event: string, message: string, context?: Readonly<Record<string, unknown>>) => void;
  readonly warn: (event: string, message: string, context?: Readonly<Record<string, unknown>>) => void;
  readonly error: (event: string, message: string, context?: Readonly<Record<string, unknown>>) => void;
}

const SENSITIVE_FIELD = /(api[-_]?key|authorization|credential|password|private[-_]?key|secret|token)/iu;

const redact = (value: unknown, fieldName?: string): unknown => {
  if (fieldName && SENSITIVE_FIELD.test(fieldName)) {
    return "[REDACTED]";
  }
  if (Array.isArray(value)) {
    return value.map((entry) => redact(entry));
  }
  if (typeof value === "object" && value !== null) {
    return Object.fromEntries(
      Object.entries(value).map(([key, entry]) => [key, redact(entry, key)]),
    );
  }
  return value;
};

export const createLogger = (
  minimumLevel: LogLevel,
  sink: (serialized: string) => void = console.log,
  clock: () => Date = () => new Date(),
  baseContext: Readonly<Record<string, unknown>> = {},
): Logger => {
  const write = (
    level: LogLevel,
    event: string,
    message: string,
    context?: Readonly<Record<string, unknown>>,
  ): void => {
    if (LEVEL_WEIGHT[level] < LEVEL_WEIGHT[minimumLevel]) {
      return;
    }
    const mergedContext = { ...baseContext, ...context };
    const base: LogRecord = {
      timestamp: clock().toISOString(),
      level,
      event,
      message,
      ...(Object.keys(mergedContext).length > 0
        ? { context: redact(mergedContext) as Readonly<Record<string, unknown>> }
        : {}),
    };
    sink(JSON.stringify(base));
  };

  return {
    debug: (event, message, context) => write("debug", event, message, context),
    info: (event, message, context) => write("info", event, message, context),
    warn: (event, message, context) => write("warn", event, message, context),
    error: (event, message, context) => write("error", event, message, context),
  };
};
