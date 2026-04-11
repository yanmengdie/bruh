create table if not exists public.news_articles (
  id text primary key,
  source_name text not null,
  source_type text not null default 'rss',
  feed_slug text not null,
  title text not null,
  summary text not null,
  article_url text not null unique,
  category text not null,
  interest_tags text[] not null default '{}',
  published_at timestamptz not null,
  fetched_at timestamptz not null default now(),
  importance_score double precision not null default 0.5,
  raw_payload jsonb not null default '{}'::jsonb
);
create table if not exists public.news_events (
  id text primary key,
  event_key text not null unique,
  title text not null,
  summary text not null,
  category text not null,
  interest_tags text[] not null default '{}',
  representative_url text,
  representative_source_name text not null,
  article_count integer not null default 1,
  source_count integer not null default 1,
  importance_score double precision not null default 0.5,
  global_rank integer,
  is_global_top boolean not null default false,
  published_at timestamptz not null,
  updated_at timestamptz not null default now(),
  raw_article_ids text[] not null default '{}'
);
create table if not exists public.news_event_articles (
  event_id text not null references public.news_events(id) on delete cascade,
  article_id text not null references public.news_articles(id) on delete cascade,
  primary key (event_id, article_id)
);
create table if not exists public.persona_news_scores (
  event_id text not null references public.news_events(id) on delete cascade,
  persona_id text not null references public.personas(id) on delete cascade,
  score double precision not null default 0,
  reason_codes text[] not null default '{}',
  matched_interests text[] not null default '{}',
  updated_at timestamptz not null default now(),
  primary key (event_id, persona_id)
);
create index if not exists idx_news_articles_published_at
  on public.news_articles (published_at desc);
create index if not exists idx_news_articles_category_published_at
  on public.news_articles (category, published_at desc);
create index if not exists idx_news_articles_interest_tags
  on public.news_articles using gin (interest_tags);
create index if not exists idx_news_events_published_at
  on public.news_events (published_at desc);
create index if not exists idx_news_events_global_rank
  on public.news_events (global_rank asc nulls last);
create index if not exists idx_news_events_interest_tags
  on public.news_events using gin (interest_tags);
create index if not exists idx_persona_news_scores_persona_score
  on public.persona_news_scores (persona_id, score desc);
alter table public.news_articles enable row level security;
alter table public.news_events enable row level security;
alter table public.news_event_articles enable row level security;
alter table public.persona_news_scores enable row level security;
drop policy if exists "news_articles_public_read" on public.news_articles;
create policy "news_articles_public_read"
  on public.news_articles
  for select
  to anon, authenticated
  using (true);
drop policy if exists "news_events_public_read" on public.news_events;
create policy "news_events_public_read"
  on public.news_events
  for select
  to anon, authenticated
  using (true);
drop policy if exists "news_event_articles_public_read" on public.news_event_articles;
create policy "news_event_articles_public_read"
  on public.news_event_articles
  for select
  to anon, authenticated
  using (true);
drop policy if exists "persona_news_scores_public_read" on public.persona_news_scores;
create policy "persona_news_scores_public_read"
  on public.persona_news_scores
  for select
  to anon, authenticated
  using (true);
