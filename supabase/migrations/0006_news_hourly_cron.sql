create extension if not exists pg_cron;
create extension if not exists pg_net;

do $$
declare
  ingest_job_id bigint;
  build_job_id bigint;
begin
  select jobid into ingest_job_id
  from cron.job
  where jobname = 'bruh-news-ingest-hourly';

  if ingest_job_id is not null then
    perform cron.unschedule(ingest_job_id);
  end if;

  select jobid into build_job_id
  from cron.job
  where jobname = 'bruh-news-build-hourly';

  if build_job_id is not null then
    perform cron.unschedule(build_job_id);
  end if;
end $$;

select cron.schedule(
  'bruh-news-ingest-hourly',
  '3 * * * *',
  $$
    select
      net.http_post(
        url := 'https://mrxctelezutprdeemqla.supabase.co/functions/v1/ingest-top-news',
        headers := '{"Content-Type":"application/json"}'::jsonb,
        body := '{"timeoutMs":12000}'::jsonb
      ) as request_id;
  $$
);

select cron.schedule(
  'bruh-news-build-hourly',
  '8 * * * *',
  $$
    select
      net.http_post(
        url := 'https://mrxctelezutprdeemqla.supabase.co/functions/v1/build-news-events',
        headers := '{"Content-Type":"application/json"}'::jsonb,
        body := '{"lookbackHours":72}'::jsonb
      ) as request_id;
  $$
);
