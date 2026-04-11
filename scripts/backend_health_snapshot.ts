#!/usr/bin/env -S deno run --allow-env --allow-net

import { createClient } from "jsr:@supabase/supabase-js@2";
import { resolveSupabaseServiceConfig } from "../supabase/functions/_shared/environment.ts";
import {
  collectBackendHealthSnapshot,
  formatHealthSnapshot,
} from "./backend_health_snapshot_lib.ts";

function printUsage() {
  console.log(`Usage:
  deno run --allow-env --allow-net scripts/backend_health_snapshot.ts [--json] [--strict]

Flags:
  --json     Print machine-readable JSON
  --strict   Exit with code 1 unless overall health is healthy or running
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
  const { deploymentEnvironment, projectUrl, serviceRoleKey } =
    resolveSupabaseServiceConfig();

  const supabase = createClient(projectUrl, serviceRoleKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  });

  const snapshot = await collectBackendHealthSnapshot(supabase, {
    environment: deploymentEnvironment,
    projectUrl,
  });

  if (json) {
    console.log(JSON.stringify(snapshot, null, 2));
  } else {
    console.log(formatHealthSnapshot(snapshot));
  }

  if (strict && !["healthy", "running"].includes(snapshot.overallLevel)) {
    Deno.exit(1);
  }
}

if (import.meta.main) {
  await main();
}
