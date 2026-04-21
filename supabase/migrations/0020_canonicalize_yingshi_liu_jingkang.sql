insert into public.personas (id, x_username, display_name, is_active)
values ('影石刘靖康', 'persona:影石刘靖康', '影石刘靖康', true)
on conflict (id) do update
set
  x_username = excluded.x_username,
  display_name = excluded.display_name,
  is_active = excluded.is_active;

delete from public.feed_likes existing
using public.feed_likes legacy
where existing.author_id = '影石刘靖康'
  and legacy.author_id = 'liu_jingkang'
  and existing.post_id = legacy.post_id;

update public.feed_comments
set
  author_id = '影石刘靖康',
  author_display_name = '影石刘靖康'
where author_id = 'liu_jingkang';

update public.feed_likes
set
  author_id = '影石刘靖康',
  author_display_name = '影石刘靖康'
where author_id = 'liu_jingkang';

update public.source_posts
set
  persona_id = '影石刘靖康',
  raw_author_username = '影石刘靖康',
  raw_payload = jsonb_set(raw_payload, '{personaId}', to_jsonb('影石刘靖康'::text), true)
where persona_id = 'liu_jingkang';

update public.feed_items
set persona_id = '影石刘靖康'
where persona_id = 'liu_jingkang';

insert into public.persona_news_scores (event_id, persona_id, score, reason_codes, matched_interests, updated_at)
select
  event_id,
  '影石刘靖康' as persona_id,
  score,
  reason_codes,
  matched_interests,
  updated_at
from public.persona_news_scores
where persona_id = 'liu_jingkang'
on conflict (event_id, persona_id) do update
set
  score = greatest(public.persona_news_scores.score, excluded.score),
  reason_codes = (
    select array(
      select distinct item
      from unnest(public.persona_news_scores.reason_codes || excluded.reason_codes) as item
    )
  ),
  matched_interests = (
    select array(
      select distinct item
      from unnest(public.persona_news_scores.matched_interests || excluded.matched_interests) as item
    )
  ),
  updated_at = greatest(public.persona_news_scores.updated_at, excluded.updated_at);

delete from public.persona_news_scores
where persona_id = 'liu_jingkang';

delete from public.persona_accounts
where persona_id = '影石刘靖康'
  and platform = 'x'
  and handle like 'xhs:%';

update public.persona_accounts
set
  persona_id = '影石刘靖康',
  updated_at = now()
where persona_id = 'liu_jingkang';

insert into public.persona_accounts (persona_id, platform, handle, profile_url, is_primary, is_active)
values ('影石刘靖康', 'xiaohongshu', '影石刘靖康', null, true, true)
on conflict (platform, handle) do update
set
  persona_id = excluded.persona_id,
  profile_url = excluded.profile_url,
  is_primary = excluded.is_primary,
  is_active = excluded.is_active,
  updated_at = now();

delete from public.personas
where id = 'liu_jingkang';
