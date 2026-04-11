import { EDGE_REQUEST_ID_HEADER } from "./observability.ts";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": [
    "authorization",
    "x-client-info",
    "apikey",
    "content-type",
    "x-bruh-client-version",
    "x-bruh-accept-contract",
  ].join(", "),
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Expose-Headers": [
    "x-bruh-server-version",
    "x-bruh-contract",
    "x-bruh-compat-mode",
    EDGE_REQUEST_ID_HEADER,
  ].join(", "),
};
