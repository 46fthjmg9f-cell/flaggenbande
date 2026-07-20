export interface DataValidationIssue {
  readonly code: string;
  readonly path: string;
  readonly message: string;
}

export class CountryDataError extends Error {
  public constructor(message: string, options?: ErrorOptions) {
    super(message, options);
    this.name = "CountryDataError";
  }
}

export class CountryDataValidationError extends CountryDataError {
  public readonly issues: readonly DataValidationIssue[];

  public constructor(issues: readonly DataValidationIssue[]) {
    super(
      `Country candidate validation failed with ${String(issues.length)} issue(s): ${issues
        .slice(0, 5)
        .map((issue) => `${issue.path}: ${issue.message}`)
        .join("; ")}`,
    );
    this.name = "CountryDataValidationError";
    this.issues = issues;
  }
}
