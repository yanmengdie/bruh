create table if not exists public.personas (
  id text primary key,
  x_username text not null unique,
  display_name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.source_posts (
  id text primary key,
  persona_id text not null references public.personas(id),
  source_type text not null default 'x',
  content text not null,
  source_url text,
  topic text,
  importance_score double precision not null default 0.5,
  published_at timestamptz not null,
  ingested_at timestamptz not null default now(),
  raw_author_username text not null,
  raw_payload jsonb not null default '{}'::jsonb
);

create index if not exists idx_source_posts_published_at
  on public.source_posts (published_at desc);

create index if not exists idx_source_posts_persona_published_at
  on public.source_posts (persona_id, published_at desc);

create index if not exists idx_source_posts_ingested_at
  on public.source_posts (ingested_at desc);

alter table public.personas enable row level security;
alter table public.source_posts enable row level security;

insert into public.personas (id, x_username, display_name)
values
  ('musk', 'elonmusk', 'Elon Musk'),
  ('trump', 'realDonaldTrump', 'Donald Trump'),
  ('zuckerberg', 'finkd', 'Mark Zuckerberg')
on conflict (id) do update set
  x_username = excluded.x_username,
  display_name = excluded.display_name;
