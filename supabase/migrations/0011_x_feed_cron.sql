create extension if not exists pg_cron;
create extension if not exists pg_net;
do $$
declare
  ingest_job_id bigint;
  build_job_id bigint;
begin
  select jobid into ingest_job_id
  from cron.job
  where jobname = 'bruh-x-ingest-10min';

  if ingest_job_id is not null then
    perform cron.unschedule(ingest_job_id);
  end if;

  select jobid into build_job_id
  from cron.job
  where jobname = 'bruh-feed-build-10min';

  if build_job_id is not null then
    perform cron.unschedule(build_job_id);
  end if;
end $$;
select cron.schedule(
  'bruh-x-ingest-10min',
  '0,10,20,30,40,50 * * * *',
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
  'bruh-feed-build-10min',
  '5,15,25,35,45,55 * * * *',
  $$
    select
      net.http_post(
        url := 'https://mrxctelezutprdeemqla.supabase.co/functions/v1/build-feed',
        headers := '{"Content-Type":"application/json"}'::jsonb,
        body := '{"limit":200}'::jsonb
      ) as request_id;
  $$
);
