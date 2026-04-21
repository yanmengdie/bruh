delete from public.persona_accounts
where platform = 'weibo'
  and persona_id in ('zhang_peng', 'lei_jun', 'luo_yonghao', 'papi');

insert into public.persona_accounts (
  persona_id,
  platform,
  handle,
  profile_url,
  is_primary,
  is_active
)
values
  ('zhang_peng', 'weibo', 'geekpark', 'https://weibo.com/geekpark', true, true),
  ('lei_jun', 'weibo', 'leijun', 'https://weibo.com/leijun', true, true),
  ('luo_yonghao', 'weibo', 'luoyonghaoniuhulu', 'https://weibo.com/luoyonghaoniuhulu', true, true),
  ('papi', 'weibo', 'xiaopapi', 'https://weibo.com/xiaopapi', true, true)
on conflict (platform, handle) do update
set
  persona_id = excluded.persona_id,
  profile_url = excluded.profile_url,
  is_primary = excluded.is_primary,
  is_active = excluded.is_active,
  updated_at = now();
