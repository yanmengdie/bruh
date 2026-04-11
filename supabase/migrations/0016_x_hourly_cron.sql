create extension if not exists pg_cron;
create extension if not exists pg_net;

insert into public.personas (id, x_username, display_name, is_active)
values
  ('cristiano_ronaldo', 'Cristiano', 'Cristiano Ronaldo', true)
on conflict (id) do update
set
  x_username = excluded.x_username,
  display_name = excluded.display_name,
  is_active = excluded.is_active;

do $$
declare
  ingest_job_id bigint;
  build_job_id bigint;
begin
  select jobid into ingest_job_id
  from cron.job
  where jobname = 'bruh-x-ingest-hourly';

  if ingest_job_id is not null then
    perform cron.unschedule(ingest_job_id);
  end if;

  select jobid into build_job_id
  from cron.job
  where jobname = 'bruh-x-build-hourly';

  if build_job_id is not null then
    perform cron.unschedule(build_job_id);
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
