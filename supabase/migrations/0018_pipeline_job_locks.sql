create table if not exists public.pipeline_job_locks (
  job_name text primary key,
  owner_id text not null,
  status text not null default 'running',
  locked_at timestamptz not null default timezone('utc', now()),
  expires_at timestamptz not null,
  heartbeat_at timestamptz not null default timezone('utc', now()),
  last_started_at timestamptz not null default timezone('utc', now()),
  last_finished_at timestamptz,
  last_succeeded_at timestamptz,
  last_error text
);

create or replace function public.claim_pipeline_job(
  p_job_name text,
  p_owner_id text,
  p_ttl_seconds integer default 900
)
returns table (
  acquired boolean,
  owner_id text,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  now_ts timestamptz := timezone('utc', now());
  ttl_seconds integer := greatest(coalesce(p_ttl_seconds, 900), 30);
begin
  insert into public.pipeline_job_locks (
    job_name,
    owner_id,
    status,
    locked_at,
    expires_at,
    heartbeat_at,
    last_started_at,
    last_error
  )
  values (
    p_job_name,
    p_owner_id,
    'running',
    now_ts,
    now_ts + make_interval(secs => ttl_seconds),
    now_ts,
    now_ts,
    null
  )
  on conflict (job_name) do update
    set owner_id = excluded.owner_id,
        status = 'running',
        locked_at = now_ts,
        expires_at = now_ts + make_interval(secs => ttl_seconds),
        heartbeat_at = now_ts,
        last_started_at = now_ts,
        last_error = null
  where public.pipeline_job_locks.expires_at <= now_ts
     or public.pipeline_job_locks.status <> 'running';

  return query
  select
    public.pipeline_job_locks.owner_id = p_owner_id as acquired,
    public.pipeline_job_locks.owner_id,
    public.pipeline_job_locks.expires_at
  from public.pipeline_job_locks
  where public.pipeline_job_locks.job_name = p_job_name;
end;
$$;

create or replace function public.complete_pipeline_job(
  p_job_name text,
  p_owner_id text,
  p_succeeded boolean,
  p_error text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  now_ts timestamptz := timezone('utc', now());
begin
  update public.pipeline_job_locks
  set status = case when p_succeeded then 'succeeded' else 'failed' end,
      heartbeat_at = now_ts,
      expires_at = now_ts,
      last_finished_at = now_ts,
      last_succeeded_at = case when p_succeeded then now_ts else last_succeeded_at end,
      last_error = case when p_succeeded then null else left(coalesce(p_error, 'unknown error'), 2000) end
  where job_name = p_job_name
    and owner_id = p_owner_id;
end;
$$;

grant execute on function public.claim_pipeline_job(text, text, integer) to anon, authenticated, service_role;
grant execute on function public.complete_pipeline_job(text, text, boolean, text) to anon, authenticated, service_role;
