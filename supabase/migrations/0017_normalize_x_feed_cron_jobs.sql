create extension if not exists pg_cron;
create extension if not exists pg_net;

do $$
declare
  ingest_legacy_job_id bigint;
  build_legacy_job_id bigint;
  ingest_hourly_job_id bigint;
  build_hourly_job_id bigint;
begin
  select jobid into ingest_legacy_job_id
  from cron.job
  where jobname = 'bruh-x-ingest-10min';

  if ingest_legacy_job_id is not null then
    perform cron.unschedule(ingest_legacy_job_id);
  end if;

  select jobid into build_legacy_job_id
  from cron.job
  where jobname = 'bruh-feed-build-10min';

  if build_legacy_job_id is not null then
    perform cron.unschedule(build_legacy_job_id);
  end if;

  select jobid into ingest_hourly_job_id
  from cron.job
  where jobname = 'bruh-x-ingest-hourly';

  if ingest_hourly_job_id is not null then
    perform cron.unschedule(ingest_hourly_job_id);
  end if;

  select jobid into build_hourly_job_id
  from cron.job
  where jobname = 'bruh-x-build-hourly';

  if build_hourly_job_id is not null then
    perform cron.unschedule(build_hourly_job_id);
  end if;
end $$;

select cron.schedule(
  'bruh-x-ingest-hourly',
  '50 * * * *',
  $$
    select
      net.http_post(
        url := 'https://mrxctelezutprdeemqla.supabase.co/functions/v1/ingest-x-posts',
        headers := '{"Content-Type":"application/json"}'::jsonb,
        body := '{"limitPerUser":5}'::jsonb
      ) as request_id;
  $$
);

select cron.schedule(
  'bruh-x-build-hourly',
  '55 * * * *',
  $$
    select
      net.http_post(
        url := 'https://mrxctelezutprdeemqla.supabase.co/functions/v1/build-feed',
        headers := '{"Content-Type":"application/json"}'::jsonb,
        body := '{"limit":300}'::jsonb
      ) as request_id;
  $$
);
