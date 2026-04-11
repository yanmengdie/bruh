create table if not exists public.persona_accounts (
  id bigint generated always as identity primary key,
  persona_id text not null references public.personas(id) on delete cascade,
  platform text not null,
  handle text not null,
  profile_url text,
  is_primary boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint persona_accounts_platform_handle_key unique (platform, handle)
);
create unique index if not exists idx_persona_accounts_primary_per_platform
  on public.persona_accounts (persona_id, platform)
  where is_primary;
create index if not exists idx_persona_accounts_persona_platform
  on public.persona_accounts (persona_id, platform);
create index if not exists idx_persona_accounts_platform_active
  on public.persona_accounts (platform, is_active);
alter table public.persona_accounts enable row level security;
drop policy if exists "persona_accounts_public_read" on public.persona_accounts;
create policy "persona_accounts_public_read"
  on public.persona_accounts
  for select
  to anon, authenticated
  using (is_active = true);
insert into public.persona_accounts (persona_id, platform, handle, profile_url, is_primary, is_active)
select
  id as persona_id,
  'x' as platform,
  lower(x_username) as handle,
  'https://x.com/' || lower(x_username) as profile_url,
  true as is_primary,
  is_active
from public.personas
where x_username not like 'persona:%'
on conflict (platform, handle) do update
set
  persona_id = excluded.persona_id,
  profile_url = excluded.profile_url,
  is_primary = excluded.is_primary,
  is_active = excluded.is_active,
  updated_at = now();
