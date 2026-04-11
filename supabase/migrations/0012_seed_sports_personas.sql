insert into public.personas (id, x_username, display_name, is_active)
values
  ('cristiano_ronaldo', 'cristiano', 'Cristiano Ronaldo', true),
  ('kobe_bryant', 'persona:kobe_bryant', 'Kobe Bryant', true)
on conflict (id) do update
set
  x_username = excluded.x_username,
  display_name = excluded.display_name,
  is_active = excluded.is_active;
insert into public.persona_accounts (persona_id, platform, handle, profile_url, is_primary, is_active)
values
  ('cristiano_ronaldo', 'x', 'cristiano', 'https://x.com/cristiano', true, true)
on conflict (platform, handle) do update
set
  persona_id = excluded.persona_id,
  profile_url = excluded.profile_url,
  is_primary = excluded.is_primary,
  is_active = excluded.is_active,
  updated_at = now();
