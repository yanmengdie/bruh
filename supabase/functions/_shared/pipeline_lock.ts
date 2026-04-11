import type { SupabaseClient } from "jsr:@supabase/supabase-js@2"

type ClaimRow = {
  acquired: boolean
  owner_id: string
  expires_at: string
}

export type PipelineJobClaim = {
  acquired: boolean
  ownerId: string
  currentOwnerId: string
  expiresAt: string
}

export async function claimPipelineJob(
  supabase: SupabaseClient,
  jobName: string,
  ttlSeconds: number,
): Promise<PipelineJobClaim> {
  const ownerId = crypto.randomUUID()
  const { data, error } = await supabase.rpc("claim_pipeline_job", {
    p_job_name: jobName,
    p_owner_id: ownerId,
    p_ttl_seconds: ttlSeconds,
  })

  if (error) {
    throw new Error(`Failed to claim pipeline job ${jobName}: ${error.message}`)
  }

  const row = Array.isArray(data) ? data[0] as ClaimRow | undefined : undefined
  if (!row) {
    throw new Error(`Pipeline job ${jobName} returned no claim row`)
  }

  return {
    acquired: row.acquired,
    ownerId,
    currentOwnerId: row.owner_id,
    expiresAt: row.expires_at,
  }
}

export async function completePipelineJob(
  supabase: SupabaseClient,
  jobName: string,
  ownerId: string,
  succeeded: boolean,
  errorMessage?: string,
) {
  const { error } = await supabase.rpc("complete_pipeline_job", {
    p_job_name: jobName,
    p_owner_id: ownerId,
    p_succeeded: succeeded,
    p_error: errorMessage ?? null,
  })

  if (error) {
    throw new Error(`Failed to complete pipeline job ${jobName}: ${error.message}`)
  }
}
