-- Aura X base schema for a new Supabase project.
-- Run this BEFORE supabase_aura_restriction_consent_setup.sql and supabase_aura_signup_setup.sql.
-- Uses the same JSONB document shape expected by supabase-bridge.js.

create extension if not exists pgcrypto;

create or replace function public.aurax_base_touch_updated_at()
returns trigger language plpgsql set search_path = public as $$
begin
  new.updated_at := now();
  if new.created_at is null then new.created_at := now(); end if;
  return new;
end;
$$;

-- All Aura X application documents use the same {id, data} structure.
do $$
declare t text;
begin
  foreach t in array array[
    'users','account_links','posts','rooms','statuses','notifications','reports','announcements','votes',
    'restrictions','restriction_codes','banned_users','banned_ips','banned_devices','banned_emails',
    'push_tokens','ad_impressions','room_messages','comments','likes','follows','messages','direct_messages',
    'room_members','room_drawings','stories','story_likes','story_views','user_settings','blocks','reactions'
  ] loop
    execute format('create table if not exists public.%I (id text primary key, data jsonb not null default ''{}''::jsonb, created_at timestamptz not null default now(), updated_at timestamptz not null default now())', t);
    execute format('alter table public.%I add column if not exists data jsonb not null default ''{}''::jsonb', t);
    execute format('alter table public.%I add column if not exists created_at timestamptz not null default now()', t);
    execute format('alter table public.%I add column if not exists updated_at timestamptz not null default now()', t);
    execute format('drop trigger if exists %I on public.%I', 'aurax_touch_' || t, t);
    execute format('create trigger %I before insert or update on public.%I for each row execute function public.aurax_base_touch_updated_at()', 'aurax_touch_' || t, t);
    execute format('alter table public.%I enable row level security', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
  end loop;
end $$;

create or replace function public.aurax_base_is_admin(p_uid uuid default auth.uid())
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.users u
    where u.data ->> 'authUid' = p_uid::text
      and lower(coalesce(u.data ->> 'role','')) = 'admin'
  );
$$;

create or replace function public.aurax_base_current_username(p_uid uuid default auth.uid())
returns text
language sql stable security definer set search_path = public
as $$
  select coalesce(
    (select l.data ->> 'username' from public.account_links l where l.id = p_uid::text limit 1),
    (select u.id from public.users u where u.data ->> 'authUid' = p_uid::text limit 1)
  );
$$;

-- Compatibility names used by the existing Aura X SQL policies and UI.
create or replace function public.aurax_current_username()
returns text language sql stable security definer set search_path = public
as $$ select public.aurax_base_current_username(auth.uid()); $$;
revoke all on function public.aurax_current_username() from public, anon;
grant execute on function public.aurax_current_username() to authenticated, service_role;

create or replace function public.aurax_network_banned(p_ip_hash text default '', p_device_hash text default '')
returns boolean language sql stable security definer set search_path = public
as $$
  select
    (nullif(p_ip_hash,'') is not null and exists (
      select 1 from public.banned_ips b
      where b.id = p_ip_hash or b.data ->> 'ipHash' = p_ip_hash or b.data ->> 'hash' = p_ip_hash
    ))
    or (nullif(p_device_hash,'') is not null and exists (
      select 1 from public.banned_devices b
      where b.id = p_device_hash or b.data ->> 'deviceHash' = p_device_hash or b.data ->> 'hash' = p_device_hash
    ));
$$;
revoke all on function public.aurax_network_banned(text,text) from public, anon;
grant execute on function public.aurax_network_banned(text,text) to authenticated, service_role;

create or replace function public.aurax_is_admin(p_uid uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public
as $$ select public.aurax_base_is_admin(p_uid); $$;
revoke all on function public.aurax_is_admin(uuid) from public, anon;
grant execute on function public.aurax_is_admin(uuid) to authenticated, service_role;

create or replace function public.aurax_base_owns_data(p_data jsonb, p_id text default null)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.aurax_base_is_admin(auth.uid())
    or coalesce(p_data ->> 'authUid','') = auth.uid()::text
    or coalesce(p_data ->> 'uid','') = auth.uid()::text
    or coalesce(p_data ->> 'userId','') = auth.uid()::text
    or coalesce(p_data ->> 'ownerId','') = auth.uid()::text
    or coalesce(p_data ->> 'createdByUid','') = auth.uid()::text
    or coalesce(p_data ->> 'senderId','') = auth.uid()::text
    or coalesce(p_data ->> 'recipientId','') = auth.uid()::text
    or (public.aurax_base_current_username(auth.uid()) is not null and (
      coalesce(p_data ->> 'username','') = public.aurax_base_current_username(auth.uid())
      or coalesce(p_data ->> 'owner','') = public.aurax_base_current_username(auth.uid())
      or coalesce(p_data ->> 'createdBy','') = public.aurax_base_current_username(auth.uid())
      or coalesce(p_data ->> 'author','') = public.aurax_base_current_username(auth.uid())
      or coalesce(p_data ->> 'sender','') = public.aurax_base_current_username(auth.uid())
      or coalesce(p_data ->> 'recipient','') = public.aurax_base_current_username(auth.uid())
      or coalesce(p_data ->> 'user','') = public.aurax_base_current_username(auth.uid())
      or coalesce(p_id,'') = public.aurax_base_current_username(auth.uid())
    ));
$$;

-- users: a user may read their own full profile; admins can read all profiles.
drop policy if exists aurax_users_select_self_admin on public.users;
create policy aurax_users_select_self_admin on public.users for select to authenticated
  using (data ->> 'authUid' = auth.uid()::text or public.aurax_base_is_admin(auth.uid()));
drop policy if exists aurax_users_insert_self_admin on public.users;
create policy aurax_users_insert_self_admin on public.users for insert to authenticated
  with check ((data ->> 'authUid' = auth.uid()::text) or public.aurax_base_is_admin(auth.uid()));
drop policy if exists aurax_users_update_self_admin on public.users;
create policy aurax_users_update_self_admin on public.users for update to authenticated
  using (data ->> 'authUid' = auth.uid()::text or public.aurax_base_is_admin(auth.uid()))
  with check ((data ->> 'authUid' = auth.uid()::text) or public.aurax_base_is_admin(auth.uid()));
drop policy if exists aurax_users_delete_self_admin on public.users;
create policy aurax_users_delete_self_admin on public.users for delete to authenticated
  using (data ->> 'authUid' = auth.uid()::text or public.aurax_base_is_admin(auth.uid()));

-- account_links are private account-to-provider mappings.
drop policy if exists aurax_account_links_select_owner on public.account_links;
create policy aurax_account_links_select_owner on public.account_links for select to authenticated
  using (id = auth.uid()::text or public.aurax_base_is_admin(auth.uid()));
drop policy if exists aurax_account_links_insert_owner on public.account_links;
create policy aurax_account_links_insert_owner on public.account_links for insert to authenticated
  with check (id = auth.uid()::text or public.aurax_base_is_admin(auth.uid()));
drop policy if exists aurax_account_links_update_owner on public.account_links;
create policy aurax_account_links_update_owner on public.account_links for update to authenticated
  using (id = auth.uid()::text or public.aurax_base_is_admin(auth.uid()))
  with check (id = auth.uid()::text or public.aurax_base_is_admin(auth.uid()));
drop policy if exists aurax_account_links_delete_owner on public.account_links;
create policy aurax_account_links_delete_owner on public.account_links for delete to authenticated
  using (id = auth.uid()::text or public.aurax_base_is_admin(auth.uid()));

-- Authenticated users may see ordinary social content; writes must match the session owner or admin.
do $$
declare t text;
begin
  foreach t in array array['posts','rooms','statuses','notifications','reports','announcements','votes','push_tokens','ad_impressions','room_messages','comments','likes','follows','messages','direct_messages','room_members','room_drawings','stories','story_likes','story_views','user_settings','blocks','reactions'] loop
    execute format('drop policy if exists %I on public.%I', 'aurax_'||t||'_select_auth', t);
    execute format('create policy %I on public.%I for select to authenticated using (true)', 'aurax_'||t||'_select_auth', t);
    execute format('drop policy if exists %I on public.%I', 'aurax_'||t||'_insert_owner', t);
    execute format('create policy %I on public.%I for insert to authenticated with check (public.aurax_base_owns_data(data, id))', 'aurax_'||t||'_insert_owner', t);
    execute format('drop policy if exists %I on public.%I', 'aurax_'||t||'_update_owner', t);
    execute format('create policy %I on public.%I for update to authenticated using (public.aurax_base_owns_data(data, id)) with check (public.aurax_base_owns_data(data, id))', 'aurax_'||t||'_update_owner', t);
    execute format('drop policy if exists %I on public.%I', 'aurax_'||t||'_delete_owner', t);
    execute format('create policy %I on public.%I for delete to authenticated using (public.aurax_base_owns_data(data, id))', 'aurax_'||t||'_delete_owner', t);
  end loop;

  foreach t in array array['restrictions','restriction_codes','banned_users','banned_ips','banned_devices','banned_emails'] loop
    execute format('drop policy if exists %I on public.%I', 'aurax_'||t||'_admin_select', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.aurax_base_is_admin(auth.uid()) or public.aurax_base_owns_data(data, id))', 'aurax_'||t||'_admin_select', t);
    execute format('drop policy if exists %I on public.%I', 'aurax_'||t||'_admin_write', t);
    execute format('create policy %I on public.%I for all to authenticated using (public.aurax_base_is_admin(auth.uid())) with check (public.aurax_base_is_admin(auth.uid()))', 'aurax_'||t||'_admin_write', t);
  end loop;
end $$;

-- A sanitized view is used for public profile lists. Never expose provider IDs, e-mail, IP/device hashes or consent internals.
create or replace view public.public_profiles as
select id,
       (data - array[
         'authUid','authEmail','email','googleUid','googleEmail','appleUid','appleEmail',
         'ipHash','deviceHash','restrictionCodeHash','kvkkConsentLogId','birthDate'
       ]::text[]) as data,
       updated_at
from public.users;
grant select on public.public_profiles to authenticated;

create or replace function public.aurax_username_available(p_username text)
returns boolean language plpgsql stable security definer set search_path = public
as $$
declare
  v_username text := lower(btrim(coalesce(p_username,'')));
  v_taken boolean := false;
begin
  if char_length(v_username) < 1 or char_length(v_username) > 40 or v_username = lower('A_UR_A_XX') then
    return false;
  end if;
  if exists (select 1 from public.users u where lower(u.id) = v_username) then
    return false;
  end if;
  -- Education's table is created later in the consolidated setup. Dynamic SQL lets
  -- this function also work if the Aura X base migration is run before Education exists.
  if to_regclass('public.education_records') is not null then
    execute 'select exists (select 1 from public.education_records er where er.collection_name = ''usernameClaims'' and lower(er.id) = $1)'
      into v_taken using v_username;
    if v_taken then return false; end if;
  end if;
  return true;
end;
$$;
revoke all on function public.aurax_username_available(text) from public;
grant execute on function public.aurax_username_available(text) to authenticated, service_role;

-- Trusted Edge Functions use this to map a public username to the existing Supabase Auth identity.
-- It exposes only the minimum fields needed for username/password sign-in and is not callable by browsers.
create or replace function public.aurax_lookup_username_login(p_username text)
returns jsonb language sql stable security definer set search_path = public
as $$
  select jsonb_build_object(
    'username', u.id,
    'authUid', u.data ->> 'authUid',
    'authEmail', u.data ->> 'authEmail'
  )
  from public.users u
  where lower(u.id) = lower(btrim(coalesce(p_username,'')))
  limit 1;
$$;
revoke all on function public.aurax_lookup_username_login(text) from public, anon, authenticated;
grant execute on function public.aurax_lookup_username_login(text) to service_role;

create or replace function public.aurax_resolve_oauth_username(p_provider text default 'email')
returns text language plpgsql stable security definer set search_path = public
as $$
declare v_username text;
begin
  if auth.uid() is null then return null; end if;
  select l.data ->> 'username' into v_username
  from public.account_links l where l.id = auth.uid()::text limit 1;
  if v_username is null then
    select u.id into v_username from public.users u where u.data ->> 'authUid' = auth.uid()::text limit 1;
  end if;
  return v_username;
end;
$$;
revoke all on function public.aurax_resolve_oauth_username(text) from public;
grant execute on function public.aurax_resolve_oauth_username(text) to authenticated;

create or replace function public.aurax_get_linked_profile()
returns jsonb language sql stable security definer set search_path = public
as $$
  select jsonb_build_object(
    'username', u.id,
    'displayName', coalesce(u.data ->> 'displayName', concat_ws(' ',u.data ->> 'firstName',u.data ->> 'lastName')),
    'firstName', u.data ->> 'firstName',
    'lastName', u.data ->> 'lastName',
    'authEmail', u.data ->> 'authEmail',
    'role', u.data ->> 'role',
    'avatarUrl', u.data ->> 'avatarUrl'
  )
  from public.users u where auth.uid() is not null and u.data ->> 'authUid' = auth.uid()::text limit 1;
$$;
revoke all on function public.aurax_get_linked_profile() from public;
grant execute on function public.aurax_get_linked_profile() to authenticated;

create or replace function public.aurax_record_login_seen(p_ip_hash text default null, p_device_hash text default null)
returns boolean language plpgsql security definer set search_path = public
as $$
declare v_count integer;
begin
  if auth.uid() is null then return false; end if;
  update public.users u
  set data = u.data || jsonb_build_object(
    'lastSeenAt', (extract(epoch from clock_timestamp()) * 1000)::bigint,
    'ipHash', p_ip_hash,
    'deviceHash', p_device_hash
  )
  where u.data ->> 'authUid' = auth.uid()::text;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;
revoke all on function public.aurax_record_login_seen(text,text) from public;
grant execute on function public.aurax_record_login_seen(text,text) to authenticated;

notify pgrst, 'reload schema';
