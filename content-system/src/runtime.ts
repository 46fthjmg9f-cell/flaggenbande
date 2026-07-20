import { fileURLToPath } from "node:url";

export const CONTENT_SYSTEM_VERSION = "0.1.0";
export const CONTENT_SYSTEM_ROOT = fileURLToPath(new URL("..", import.meta.url));
