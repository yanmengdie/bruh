delete from public.feed_comments
where author_id in ('liu_jingkang', '影石刘靖康')
   or post_id in (
     select id
     from public.source_posts
     where persona_id in ('liu_jingkang', '影石刘靖康')
   );

delete from public.feed_likes
where author_id in ('liu_jingkang', '影石刘靖康')
   or post_id in (
     select id
     from public.source_posts
     where persona_id in ('liu_jingkang', '影石刘靖康')
   );

delete from public.feed_items
where persona_id in ('liu_jingkang', '影石刘靖康');

delete from public.source_posts
where persona_id in ('liu_jingkang', '影石刘靖康');

delete from public.persona_news_scores
where persona_id in ('liu_jingkang', '影石刘靖康');

delete from public.persona_accounts
where persona_id in ('liu_jingkang', '影石刘靖康')
   or (platform = 'xiaohongshu' and handle = '影石刘靖康');

delete from public.personas
where id in ('liu_jingkang', '影石刘靖康');
