delete from public.feed_comments
where author_id in ('zuckerberg')
   or post_id in (
     select id
     from public.source_posts
     where persona_id in ('zuckerberg')
   );
delete from public.feed_likes
where author_id in ('zuckerberg')
   or post_id in (
     select id
     from public.source_posts
     where persona_id in ('zuckerberg')
   );
delete from public.feed_items
where persona_id in ('zuckerberg');
delete from public.source_posts
where persona_id in ('zuckerberg');
delete from public.persona_news_scores
where persona_id in ('zuckerberg');
delete from public.persona_accounts
where persona_id in ('zuckerberg');
delete from public.persona_accounts
where persona_id = 'zhang_peng'
  and platform = 'xiaohongshu'
  and handle = '影石刘靖康';
delete from public.persona_accounts
where persona_id = 'liu_jingkang'
  and platform = 'xiaohongshu'
  and handle <> '影石刘靖康';
insert into public.persona_accounts (persona_id, platform, handle, profile_url, is_primary, is_active)
values ('liu_jingkang', 'xiaohongshu', '影石刘靖康', null, true, true)
on conflict (platform, handle) do update
set
  persona_id = excluded.persona_id,
  profile_url = excluded.profile_url,
  is_primary = excluded.is_primary,
  is_active = excluded.is_active,
  updated_at = now();
update public.personas
set
  is_active = false,
  x_username = 'persona:' || id
where id in ('zuckerberg');
