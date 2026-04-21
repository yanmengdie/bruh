delete from public.feed_comments
where author_id in ('kobe_bryant');

delete from public.feed_likes
where author_id in ('kobe_bryant');

delete from public.feed_items
where persona_id in ('kobe_bryant');

delete from public.source_posts
where persona_id in ('kobe_bryant');

delete from public.persona_news_scores
where persona_id in ('kobe_bryant');

delete from public.persona_accounts
where persona_id in ('kobe_bryant');

delete from public.personas
where id in ('kobe_bryant');
