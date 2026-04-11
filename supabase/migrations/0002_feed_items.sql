create table if not exists public.feed_items (
  id text primary key,
  source_post_id text not null unique references public.source_posts(id) on delete cascade,
  persona_id text not null references public.personas(id),
  content text not null,
  source_type text not null default 'x',
  source_url text,
  topic text,
  importance_score double precision not null default 0.5,
  published_at timestamptz not null,
  delivered_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists idx_feed_items_published_at
  on public.feed_items (published_at desc);
create index if not exists idx_feed_items_persona_published_at
  on public.feed_items (persona_id, published_at desc);
alter table public.feed_items enable row level security;
drop policy if exists "feed_items_public_read" on public.feed_items;
create policy "feed_items_public_read"
  on public.feed_items
  for select
  to anon, authenticated
  using (true);
