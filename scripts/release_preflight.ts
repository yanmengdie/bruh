#!/usr/bin/env -S deno run --allow-env --allow-net

import { createClient } from "jsr:@supabase/supabase-js@2";
import { resolveSupabaseServiceConfig } from "../supabase/functions/_shared/environment.ts";
import {
  collectReleasePreflightSnapshot,
  formatReleasePreflight,
} from "./release_preflight_lib.ts";

function printUsage() {
  console.log(`Usage:
  deno run --allow-env --allow-net scripts/release_preflight.ts [--json] [--strict]

Flags:
  --json     Print machine-readable JSON
  --strict   Exit with code 1 unless the full preflight passes
  --help     Show this message`);
}

async function main() {
  const args = new Set(Deno.args);
  if (args.has("--help")) {
    printUsage();
    return;
  }

  const strict = args.has("--strict");
  const json = args.has("--json");

  let supabase = null;
  let projectUrl: string | null = null;

  try {
    const config = resolveSupabaseServiceConfig();
    projectUrl = config.projectUrl;
    supabase = createClient(config.projectUrl, config.serviceRoleKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
      },
    });
  } catch {
    supabase = null;
  }

  const snapshot = await collectReleasePreflightSnapshot(supabase, {
    projectUrl,
  });

  if (json) {
    console.log(JSON.stringify(snapshot, null, 2));
  } else {
    console.log(formatReleasePreflight(snapshot));
  }

  if (strict && snapshot.overallLevel !== "pass") {
    Deno.exit(1);
  }
}

if (import.meta.main) {
  await main();
}
