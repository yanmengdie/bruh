alter table public.source_posts
  add column if not exists media_urls text[] not null default '{}'::text[];

alter table public.feed_items
  add column if not exists media_urls text[] not null default '{}'::text[];
