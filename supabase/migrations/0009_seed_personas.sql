insert into public.personas (id, x_username, display_name, is_active)
values
  ('trump', 'realdonaldtrump', 'Donald Trump', true),
  ('musk', 'elonmusk', 'Elon Musk', true),
  ('zuckerberg', 'finkd', 'Mark Zuckerberg', true),
  ('sam_altman', 'sama', 'Sam Altman', true),
  ('zhang_peng', 'persona:zhang_peng', '张鹏', true),
  ('lei_jun', 'leijun', '雷军', true),
  ('liu_jingkang', 'persona:liu_jingkang', '刘靖康', true),
  ('luo_yonghao', 'persona:luo_yonghao', '罗永浩', true),
  ('justin_sun', 'justinsuntron', '孙宇晨', true),
  ('kim_kardashian', 'kimkardashian', 'Kim Kardashian', true),
  ('papi', 'persona:papi', 'papi酱', true)
on conflict (id) do update
set
  display_name = excluded.display_name,
  is_active = excluded.is_active;
