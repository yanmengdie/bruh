create or replace function public.run_backend_retention_cleanup(
  p_source_post_days integer default 30,
  p_news_days integer default 14,
  p_pipeline_lock_days integer default 30
)
returns table (
  source_posts_deleted bigint,
  news_events_deleted bigint,
  news_articles_deleted bigint,
  pipeline_job_locks_deleted bigint
)
language plpgsql
security definer
set search_path = public
as $$
declare
  now_ts timestamptz := timezone('utc', now());
  source_cutoff timestamptz := now_ts - make_interval(days => greatest(coalesce(p_source_post_days, 30), 1));
  news_cutoff timestamptz := now_ts - make_interval(days => greatest(coalesce(p_news_days, 14), 1));
  lock_cutoff timestamptz := now_ts - make_interval(days => greatest(coalesce(p_pipeline_lock_days, 30), 1));
  deleted_source_posts bigint := 0;
  deleted_news_events bigint := 0;
  deleted_news_articles bigint := 0;
  deleted_pipeline_job_locks bigint := 0;
begin
  delete from public.news_events
  where published_at < news_cutoff;
  get diagnostics deleted_news_events = row_count;

  delete from public.news_articles
  where published_at < news_cutoff;
  get diagnostics deleted_news_articles = row_count;

  delete from public.source_posts
  where published_at < source_cutoff;
  get diagnostics deleted_source_posts = row_count;

  delete from public.pipeline_job_locks
  where status <> 'running'
    and coalesce(last_finished_at, expires_at, heartbeat_at, locked_at) < lock_cutoff;
  get diagnostics deleted_pipeline_job_locks = row_count;

  return query
  select
    deleted_source_posts,
    deleted_news_events,
    deleted_news_articles,
    deleted_pipeline_job_locks;
end;
$$;

grant execute on function public.run_backend_retention_cleanup(integer, integer, integer) to service_role;
