-- Bruh Backend Schema
-- Consolidated from Supabase migrations

CREATE TABLE IF NOT EXISTS personas (
  id TEXT PRIMARY KEY,
  x_username TEXT NOT NULL UNIQUE,
  display_name TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS persona_accounts (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  persona_id TEXT NOT NULL REFERENCES personas(id) ON DELETE CASCADE,
  platform TEXT NOT NULL,
  handle TEXT NOT NULL,
  profile_url TEXT,
  is_primary BOOLEAN NOT NULL DEFAULT FALSE,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(platform, handle)
);

CREATE TABLE IF NOT EXISTS source_posts (
  id TEXT PRIMARY KEY,
  persona_id TEXT NOT NULL REFERENCES personas(id),
  source_type TEXT NOT NULL DEFAULT 'x',
  content TEXT NOT NULL,
  source_url TEXT,
  topic TEXT,
  importance_score DOUBLE PRECISION NOT NULL DEFAULT 0.5,
  published_at TIMESTAMPTZ NOT NULL,
  ingested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  raw_author_username TEXT NOT NULL DEFAULT '',
  raw_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  media_urls TEXT[] NOT NULL DEFAULT '{}',
  video_url TEXT
);

CREATE TABLE IF NOT EXISTS feed_items (
  id TEXT PRIMARY KEY,
  source_post_id TEXT NOT NULL UNIQUE REFERENCES source_posts(id) ON DELETE CASCADE,
  persona_id TEXT NOT NULL REFERENCES personas(id),
  content TEXT NOT NULL,
  source_type TEXT NOT NULL DEFAULT 'x',
  source_url TEXT,
  topic TEXT,
  importance_score DOUBLE PRECISION NOT NULL DEFAULT 0.5,
  published_at TIMESTAMPTZ NOT NULL,
  delivered_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  media_urls TEXT[] NOT NULL DEFAULT '{}',
  video_url TEXT
);

CREATE TABLE IF NOT EXISTS feed_comments (
  id TEXT PRIMARY KEY,
  post_id TEXT NOT NULL,
  author_id TEXT NOT NULL,
  author_type TEXT NOT NULL CHECK (author_type IN ('persona', 'viewer')),
  author_display_name TEXT NOT NULL,
  content TEXT NOT NULL,
  reason_code TEXT NOT NULL DEFAULT 'topic_match',
  in_reply_to_comment_id TEXT REFERENCES feed_comments(id) ON DELETE SET NULL,
  generation_mode TEXT NOT NULL DEFAULT 'seed' CHECK (generation_mode IN ('seed', 'reply', 'viewer')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS feed_likes (
  id TEXT PRIMARY KEY,
  post_id TEXT NOT NULL,
  author_id TEXT NOT NULL,
  author_type TEXT NOT NULL CHECK (author_type IN ('persona', 'viewer')),
  author_display_name TEXT NOT NULL,
  reason_code TEXT NOT NULL DEFAULT 'close_tie',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(post_id, author_id)
);

CREATE TABLE IF NOT EXISTS news_articles (
  id TEXT PRIMARY KEY,
  source_name TEXT NOT NULL,
  source_type TEXT NOT NULL DEFAULT 'rss',
  feed_slug TEXT NOT NULL,
  title TEXT NOT NULL,
  summary TEXT NOT NULL,
  article_url TEXT NOT NULL UNIQUE,
  category TEXT NOT NULL,
  interest_tags TEXT[] NOT NULL DEFAULT '{}',
  published_at TIMESTAMPTZ NOT NULL,
  fetched_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  importance_score DOUBLE PRECISION NOT NULL DEFAULT 0.5,
  raw_payload JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS news_events (
  id TEXT PRIMARY KEY,
  event_key TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL,
  summary TEXT NOT NULL,
  category TEXT NOT NULL,
  interest_tags TEXT[] NOT NULL DEFAULT '{}',
  representative_url TEXT,
  representative_source_name TEXT NOT NULL,
  article_count INTEGER NOT NULL DEFAULT 1,
  source_count INTEGER NOT NULL DEFAULT 1,
  importance_score DOUBLE PRECISION NOT NULL DEFAULT 0.5,
  global_rank INTEGER,
  is_global_top BOOLEAN NOT NULL DEFAULT FALSE,
  published_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  raw_article_ids TEXT[] NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS news_event_articles (
  event_id TEXT NOT NULL REFERENCES news_events(id) ON DELETE CASCADE,
  article_id TEXT NOT NULL REFERENCES news_articles(id) ON DELETE CASCADE,
  PRIMARY KEY(event_id, article_id)
);

CREATE TABLE IF NOT EXISTS persona_news_scores (
  event_id TEXT NOT NULL REFERENCES news_events(id) ON DELETE CASCADE,
  persona_id TEXT NOT NULL REFERENCES personas(id) ON DELETE CASCADE,
  score DOUBLE PRECISION NOT NULL DEFAULT 0,
  reason_codes TEXT[] NOT NULL DEFAULT '{}',
  matched_interests TEXT[] NOT NULL DEFAULT '{}',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY(event_id, persona_id)
);

CREATE TABLE IF NOT EXISTS pipeline_job_locks (
  job_name TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'running',
  locked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,
  heartbeat_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_finished_at TIMESTAMPTZ,
  last_succeeded_at TIMESTAMPTZ,
  last_error TEXT
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_source_posts_published_at ON source_posts(published_at DESC);
CREATE INDEX IF NOT EXISTS idx_source_posts_persona_published_at ON source_posts(persona_id, published_at DESC);
CREATE INDEX IF NOT EXISTS idx_feed_items_published_at ON feed_items(published_at DESC);
CREATE INDEX IF NOT EXISTS idx_feed_items_persona_published_at ON feed_items(persona_id, published_at DESC);
CREATE INDEX IF NOT EXISTS idx_feed_comments_post_created ON feed_comments(post_id, created_at ASC);
CREATE INDEX IF NOT EXISTS idx_feed_likes_post_created ON feed_likes(post_id, created_at ASC);
CREATE INDEX IF NOT EXISTS idx_news_events_global_rank ON news_events(global_rank ASC NULLS LAST);
CREATE INDEX IF NOT EXISTS idx_persona_news_scores_persona_score ON persona_news_scores(persona_id, score DESC);

-- Seed default personas
INSERT INTO personas (id, x_username, display_name) VALUES
  ('trump', 'realdonaldtrump', '特离谱'),
  ('musk', 'elonmusk', '马期克'),
  ('sam_altman', 'sama', '凹凸曼'),
  ('zhang_peng', 'geekpark', '张鹏'),
  ('lei_jun', 'leijun', '田车'),
  ('luo_yonghao', 'luoyonghaoniuhulu', '老罗'),
  ('justin_sun', 'justinsuntron', '孙割'),
  ('kim_kardashian', 'kimkardashian', 'Kim Kardashian'),
  ('papi', 'xiaopapi', 'Hahi酱'),
  ('cristiano_ronaldo', 'Cristiano', 'Cristiano Ronaldo')
ON CONFLICT (id) DO NOTHING;
