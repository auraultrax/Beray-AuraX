-- Aura X / BAI fixes: safe room RPCs and restriction lifecycle.
-- Run once in Supabase SQL Editor on existing deployments.
-- This migration is non-destructive and keeps existing JSONB document records.

create or replace function public.aurax_resolve_room_id(p_room text)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id text;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_room is null or length(trim(p_room)) = 0 or length(p_room) > 120 then
    return null;
  end if;

  select r.id into v_id
  from public.rooms r
  where coalesce(r.data ->> 'deleted', 'false') <> 'true'
    and (r.id = trim(p_room) or lower(coalesce(r.data ->> 'displayName', '')) = lower(trim(p_room)))
  order by case when r.id = trim(p_room) then 0 else 1 end, r.created_at desc
  limit 1;
  return v_id;
end;
$$;

create or replace function public.aurax_join_room(p_room text, p_password text)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_room_id text;
  v_room jsonb;
  v_username text;
  v_is_admin boolean;
  v_restriction jsonb;
  v_has_restriction boolean := false;
  v_until_text text;
  v_now_ms numeric := extract(epoch from clock_timestamp()) * 1000;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  v_username := public.aurax_base_current_username(auth.uid());
  if v_username is null then
    raise exception 'Aura X username not found' using errcode = '42501';
  end if;
  if p_room is null or p_password is null or length(p_room) > 120 or length(p_password) > 256 then
    return false;
  end if;

  select r.id, r.data into v_room_id, v_room
  from public.rooms r
  where r.id = trim(p_room)
     or lower(coalesce(r.data ->> 'displayName', '')) = lower(trim(p_room))
  order by case when r.id = trim(p_room) then 0 else 1 end, r.created_at desc
  limit 1;
  if v_room_id is null or v_room is null then return false; end if;
  if coalesce(v_room ->> 'deleted', 'false') = 'true' then return false; end if;
  -- These flags close access at the system level, even for a room admin.
  if v_room -> 'systemLock' ->> 'locked' = 'true'
     or v_room ->> 'systemLocked' = 'true'
     or v_room ->> 'auracellLocked' = 'true'
     or v_room ->> 'auraCellLocked' = 'true'
     or v_room -> 'auracell' ->> 'locked' = 'true'
     or v_room -> 'auraCell' ->> 'locked' = 'true'
     or v_room -> 'roomAccess' ->> 'systemLocked' = 'true'
     or (v_room -> 'roomAccess' ->> 'locked' = 'true' and coalesce(v_room -> 'roomAccess' ->> 'lockedBy', '') <> '') then
    return false;
  end if;
  if (v_room ->> 'password') is distinct from p_password then return false; end if;

  v_is_admin := public.aurax_base_is_admin(auth.uid());
  if not v_is_admin then
    if v_room -> 'roomAccess' ->> 'locked' = 'true' or v_room ->> 'locked' = 'true' then return false; end if;
    if jsonb_typeof(v_room -> 'restrictedMembers') = 'array' and (v_room -> 'restrictedMembers') ? v_username then return false; end if;

    select r.data into v_restriction from public.restrictions r where r.id = v_username;
    v_has_restriction := found;
    if not v_has_restriction then
      select u.data into v_restriction from public.users u where u.id = v_username;
      v_has_restriction := found;
    end if;
    if v_has_restriction and coalesce(v_restriction ->> 'restricted', 'false') = 'true' then
      v_until_text := nullif(v_restriction ->> 'restrictedUntil', '');
      if v_until_text is null then return false; end if;
      if v_until_text !~ '^[0-9]+([.][0-9]+)?$' then return false; end if;
      if v_until_text::numeric > v_now_ms then return false; end if;
    end if;
  end if;

  if jsonb_typeof(v_room -> 'members') = 'array' and (v_room -> 'members') ? v_username then
    return true;
  end if;
  update public.rooms r
  set data = jsonb_set(
    coalesce(r.data, '{}'::jsonb),
    '{members}',
    case when jsonb_typeof(r.data -> 'members') = 'array'
         then coalesce(r.data -> 'members', '[]'::jsonb) || jsonb_build_array(v_username)
         else jsonb_build_array(v_username)
    end,
    true
  )
  where r.id = v_room_id;
  return found;
end;
$$;

create or replace function public.aurax_admin_list_rooms()
returns table(
  room_id text,
  display_name text,
  owner_username text,
  member_count integer,
  admins jsonb,
  system_locked boolean,
  room_locked boolean
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null or not public.aurax_base_is_admin(auth.uid()) then
    raise exception 'admin only' using errcode = '42501';
  end if;
  return query
  select
    r.id::text,
    coalesce(nullif(r.data ->> 'displayName', ''), r.id)::text,
    coalesce(nullif(r.data ->> 'admin', ''), nullif(r.data ->> 'ownerUsername', ''), nullif(r.data ->> 'creator', ''), '—')::text,
    case when jsonb_typeof(r.data -> 'members') = 'array' then jsonb_array_length(r.data -> 'members') else 0 end,
    case when jsonb_typeof(r.data -> 'admins') = 'array' then r.data -> 'admins' else '[]'::jsonb end,
    (r.data ->> 'systemLocked' = 'true'
      or r.data ->> 'auracellLocked' = 'true'
      or r.data ->> 'auraCellLocked' = 'true'
      or r.data -> 'systemLock' ->> 'locked' = 'true'
      or r.data -> 'auracell' ->> 'locked' = 'true'
      or r.data -> 'auraCell' ->> 'locked' = 'true'
      or r.data -> 'roomAccess' ->> 'systemLocked' = 'true'
      or (r.data -> 'roomAccess' ->> 'locked' = 'true' and coalesce(r.data -> 'roomAccess' ->> 'lockedBy', '') <> '')),
    (r.data -> 'roomAccess' ->> 'locked' = 'true' or r.data ->> 'locked' = 'true')
  from public.rooms r
  where coalesce(r.data ->> 'deleted', 'false') <> 'true'
  order by r.created_at desc;
end;
$$;

create or replace function public.aurax_system_lock_room(p_room text, p_locked boolean, p_reason text default null)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id text;
  v_actor text;
  v_now_ms bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
begin
  if auth.uid() is null or not public.aurax_base_is_admin(auth.uid()) then
    raise exception 'admin only' using errcode = '42501';
  end if;
  if p_room is null or length(trim(p_room)) = 0 then return false; end if;
  v_actor := public.aurax_base_current_username(auth.uid());
  select r.id into v_id from public.rooms r
    where r.id = trim(p_room) or lower(coalesce(r.data ->> 'displayName', '')) = lower(trim(p_room))
    order by case when r.id = trim(p_room) then 0 else 1 end, r.created_at desc limit 1;
  if v_id is null then return false; end if;
  update public.rooms r
  set data = jsonb_set(
    jsonb_set(coalesce(r.data, '{}'::jsonb), '{systemLocked}', to_jsonb(coalesce(p_locked, false)), true),
    '{systemLock}',
    jsonb_build_object(
      'locked', coalesce(p_locked, false),
      'reason', case when p_locked then coalesce(nullif(left(p_reason, 500), ''), 'Yönetici tarafından sistem kilidi') else null end,
      'lockedBy', v_actor,
      'lockedAt', v_now_ms
    ),
    true
  )
  where r.id = v_id;
  return found;
end;
$$;

create or replace function public.aurax_clear_verified_restriction(p_username text, p_code text)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor text;
  v_data jsonb;
  v_found boolean := false;
  v_now_ms bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  v_actor := public.aurax_base_current_username(auth.uid());
  if not public.aurax_base_is_admin(auth.uid()) and (v_actor is null or v_actor <> p_username) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_username is null or p_code !~ '^[0-9]{6}$' then return false; end if;

  select r.data into v_data from public.restrictions r where r.id = p_username;
  v_found := found;
  if not v_found then
    select u.data into v_data from public.users u where u.id = p_username;
    v_found := found;
  end if;
  if not v_found or coalesce(v_data ->> 'restricted', 'false') <> 'true' then return false; end if;
  -- Timed restrictions are never cleared by a code.
  if nullif(v_data ->> 'restrictedUntil', '') is not null then return false; end if;
  if coalesce(v_data ->> 'restrictionCodeHash', '') <> encode(sha256(convert_to(p_code, 'UTF8')), 'hex') then return false; end if;

  update public.restrictions
  set data = coalesce(data, '{}'::jsonb) || jsonb_build_object(
    'restricted', false, 'restrictionCodeHash', null, 'restrictedUntil', null, 'restrictionMode', null,
    'restrictionLiftedAt', v_now_ms, 'restrictionLiftedBy', coalesce(v_actor, 'system')
  )
  where id = p_username;
  update public.users
  set data = coalesce(data, '{}'::jsonb) || jsonb_build_object(
    'restricted', false, 'restrictionCodeHash', null, 'restrictedUntil', null, 'restrictionMode', null,
    'restrictionLiftedAt', v_now_ms, 'restrictionLiftedBy', coalesce(v_actor, 'system')
  )
  where id = p_username;
  delete from public.restriction_codes where id = p_username;
  return true;
end;
$$;

create or replace function public.aurax_clear_expired_restriction(p_username text)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor text;
  v_data jsonb;
  v_found boolean := false;
  v_rest_found boolean := false;
  v_until_text text;
  v_until numeric;
  v_now_ms bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  v_actor := public.aurax_base_current_username(auth.uid());
  if not public.aurax_base_is_admin(auth.uid()) and (v_actor is null or v_actor <> p_username) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_username is null then return false; end if;

  select r.data into v_data from public.restrictions r where r.id = p_username;
  v_rest_found := found;
  if v_rest_found then
    if coalesce(v_data ->> 'restricted', 'false') = 'true' then
      v_until_text := nullif(v_data ->> 'restrictedUntil', '');
      if v_until_text is null or v_until_text !~ '^[0-9]+([.][0-9]+)?$' then return false; end if;
      v_until := v_until_text::numeric;
      if v_until > v_now_ms then return false; end if;
    end if;
  else
    select u.data into v_data from public.users u where u.id = p_username;
    v_found := found;
    if not v_found or coalesce(v_data ->> 'restricted', 'false') <> 'true' then return false; end if;
    v_until_text := nullif(v_data ->> 'restrictedUntil', '');
    if v_until_text is null or v_until_text !~ '^[0-9]+([.][0-9]+)?$' then return false; end if;
    v_until := v_until_text::numeric;
    if v_until > v_now_ms then return false; end if;
  end if;

  update public.restrictions
  set data = coalesce(data, '{}'::jsonb) || jsonb_build_object(
    'restricted', false, 'restrictionCodeHash', null, 'restrictedUntil', null, 'restrictionMode', null,
    'restrictionExpiredAt', v_now_ms
  )
  where id = p_username;
  update public.users
  set data = coalesce(data, '{}'::jsonb) || jsonb_build_object(
    'restricted', false, 'restrictionCodeHash', null, 'restrictedUntil', null, 'restrictionMode', null,
    'restrictionExpiredAt', v_now_ms
  )
  where id = p_username;
  delete from public.restriction_codes where id = p_username;
  return true;
end;
$$;

revoke all on function public.aurax_resolve_room_id(text) from public, anon;
revoke all on function public.aurax_join_room(text, text) from public, anon;
revoke all on function public.aurax_admin_list_rooms() from public, anon;
revoke all on function public.aurax_system_lock_room(text, boolean, text) from public, anon;
revoke all on function public.aurax_clear_verified_restriction(text, text) from public, anon;
revoke all on function public.aurax_clear_expired_restriction(text) from public, anon;
grant execute on function public.aurax_resolve_room_id(text) to authenticated, service_role;
grant execute on function public.aurax_join_room(text, text) to authenticated, service_role;
grant execute on function public.aurax_admin_list_rooms() to authenticated, service_role;
grant execute on function public.aurax_system_lock_room(text, boolean, text) to authenticated, service_role;
grant execute on function public.aurax_clear_verified_restriction(text, text) to authenticated, service_role;
grant execute on function public.aurax_clear_expired_restriction(text) to authenticated, service_role;

notify pgrst, 'reload schema';
