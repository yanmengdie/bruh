alter table public.source_posts
  add column if not exists video_url text;
alter table public.feed_items
  add column if not exists video_url text;
