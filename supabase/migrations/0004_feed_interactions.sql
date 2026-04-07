create table if not exists public.feed_comments (
  id text primary key,
  post_id text not null,
  author_id text not null,
  author_type text not null check (author_type in ('persona', 'viewer')),
  author_display_name text not null,
  content text not null,
  reason_code text not null default 'topic_match',
  in_reply_to_comment_id text references public.feed_comments(id) on delete set null,
  generation_mode text not null default 'seed' check (generation_mode in ('seed', 'reply', 'viewer')),
  created_at timestamptz not null default now()
);

create table if not exists public.feed_likes (
  id text primary key,
  post_id text not null,
  author_id text not null,
  author_type text not null check (author_type in ('persona', 'viewer')),
  author_display_name text not null,
  reason_code text not null default 'close_tie',
  created_at timestamptz not null default now(),
  unique (post_id, author_id)
);

create index if not exists idx_feed_comments_post_created
  on public.feed_comments (post_id, created_at asc);

create index if not exists idx_feed_comments_reply_to
  on public.feed_comments (in_reply_to_comment_id);

create index if not exists idx_feed_likes_post_created
  on public.feed_likes (post_id, created_at asc);

alter table public.feed_comments enable row level security;
alter table public.feed_likes enable row level security;

drop policy if exists "feed_comments_public_read" on public.feed_comments;
create policy "feed_comments_public_read"
  on public.feed_comments
  for select
  to anon, authenticated
  using (true);

drop policy if exists "feed_likes_public_read" on public.feed_likes;
create policy "feed_likes_public_read"
  on public.feed_likes
  for select
  to anon, authenticated
  using (true);
