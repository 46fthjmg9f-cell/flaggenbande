import { fileURLToPath } from "node:url";

export const CONTENT_SYSTEM_VERSION = "0.2.0";
export const CONTENT_SYSTEM_ROOT = fileURLToPath(new URL("..", import.meta.url));
