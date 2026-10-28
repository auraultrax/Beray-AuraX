-- ====================================================================
-- CONSOLIDATED SETUP: Aura X on one Supabase project
-- Back up the project before applying this file in Supabase SQL Editor.
-- Ordered migration bundle for a Supabase-only deployment.
-- Then deploy username-login and username-available.
-- ====================================================================

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

do $$
begin
  begin
    drop function if exists public.aurax_is_admin(uuid);
  exception when dependent_objects_still_exist then
    null;
  end;
end $$;
create or replace function public.aurax_is_admin()
returns boolean language sql stable security definer set search_path = public
as $$ select public.aurax_base_is_admin(auth.uid()); $$;
revoke all on function public.aurax_is_admin() from public, anon;
grant execute on function public.aurax_is_admin() to authenticated, service_role;

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
    execute format('create policy %I on public.%I for insert to authenticated with check (public.aurax_base_owns_data(data, id::text))', 'aurax_'||t||'_insert_owner', t);
    execute format('drop policy if exists %I on public.%I', 'aurax_'||t||'_update_owner', t);
    execute format('create policy %I on public.%I for update to authenticated using (public.aurax_base_owns_data(data, id::text)) with check (public.aurax_base_owns_data(data, id::text))', 'aurax_'||t||'_update_owner', t);
    execute format('drop policy if exists %I on public.%I', 'aurax_'||t||'_delete_owner', t);
    execute format('create policy %I on public.%I for delete to authenticated using (public.aurax_base_owns_data(data, id::text))', 'aurax_'||t||'_delete_owner', t);
  end loop;

  foreach t in array array['restrictions','restriction_codes','banned_users','banned_ips','banned_devices','banned_emails'] loop
    execute format('drop policy if exists %I on public.%I', 'aurax_'||t||'_admin_select', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.aurax_base_is_admin(auth.uid()) or public.aurax_base_owns_data(data, id::text))', 'aurax_'||t||'_admin_select', t);
    execute format('drop policy if exists %I on public.%I', 'aurax_'||t||'_admin_write', t);
    execute format('create policy %I on public.%I for all to authenticated using (public.aurax_base_is_admin(auth.uid())) with check (public.aurax_base_is_admin(auth.uid()))', 'aurax_'||t||'_admin_write', t);
  end loop;
end $$;

-- A sanitized view is used for public profile lists. Never expose provider IDs, e-mail, IP/device hashes or consent internals.
-- Eski kurulumlarda public_profiles bir TABLO olarak kalmış olabilir; görünüme çevirmeden önce
-- silmeden yedek adıyla kenara alınır (veri kaybı olmaz).
do $$
begin
  if exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
             where n.nspname = 'public' and c.relname = 'public_profiles' and c.relkind in ('r','p')) then
    if to_regclass('public.public_profiles_eski_tablo') is not null then
      drop table public.public_profiles_eski_tablo;
    end if;
    alter table public.public_profiles rename to public_profiles_eski_tablo;
  end if;
end $$;

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

-- ===== Aura X restrictions + consent =====
-- ============================================================================
-- Aura X: Kısıtlı ban süreleri, kısıtlama kodu saklama ve açık rıza onay kayıtları
-- Supabase Dashboard > SQL Editor bölümünde BİR KEZ çalıştırın.
--
-- Ön koşul: supabase_final_security_setup.sql içindeki public.aurax_base_is_admin(auth.uid())
-- fonksiyonu mevcut olmalıdır (yönetici hesabını tanır).
-- Bu dosya mevcut veriyi silmez; yalnızca yeni tablo/fonksiyon/politika ekler
-- ve restrictions tablosunda yönetici okuma iznini ekler.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1) KISITLAMA KODLARI
--    Doğrulama kodunun düz metni yalnızca yönetici tarafından okunabilir.
--    Kullanıcılar bu tabloya hiçbir şekilde erişemez (RLS: sadece yönetici).
--    Giriş doğrulaması kodun özeti (hash) üzerinden yapılmaya devam eder.
-- ----------------------------------------------------------------------------
create table if not exists public.restriction_codes (
  id text primary key,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.restriction_codes enable row level security;
revoke all on table public.restriction_codes from public, anon;
grant select, insert, update, delete on table public.restriction_codes to authenticated;

drop policy if exists restriction_codes_admin_all on public.restriction_codes;
create policy restriction_codes_admin_all
  on public.restriction_codes for all to authenticated
  using (public.aurax_base_is_admin(auth.uid()))
  with check (public.aurax_base_is_admin(auth.uid()));

create or replace function public.aurax_touch_restriction_codes()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists restriction_codes_touch on public.restriction_codes;
create trigger restriction_codes_touch
  before update on public.restriction_codes
  for each row execute function public.aurax_touch_restriction_codes();

comment on table public.restriction_codes is
  'Yönetici tarafından verilen kısıtlama doğrulama kodlarının düz metni. Yalnızca yönetici okur.';


-- ----------------------------------------------------------------------------
-- 2) KISITLI KULLANICI LİSTESİ
--    Yönetim panelindeki "Kısıtlanan Kullanıcılar" kartı restrictions tablosunu
--    okur. Bu politika yalnızca yöneticiye okuma izni ekler; mevcut izinler
--    değişmez.
-- ----------------------------------------------------------------------------
drop policy if exists restrictions_admin_select on public.restrictions;
create policy restrictions_admin_select
  on public.restrictions for select to authenticated
  using (public.aurax_base_is_admin(auth.uid()));


-- ----------------------------------------------------------------------------
-- 3) AÇIK RIZA METİN SÜRÜMLERİ (değiştirilemez)
--    Onay metninin TAMAMI burada saklanır. Her sürümün SHA-256 özeti
--    (text_hash) otomatik hesaplanır. Metin değişirse yeni bir sürüm
--    numarası ile yeni satır eklenir; eski satırlar güncellenemez/silinemez.
-- ----------------------------------------------------------------------------
create table if not exists public.consent_versions (
  version text primary key,
  consent_text text not null,
  text_hash text not null check (text_hash ~ '^[0-9a-f]{64}$'),
  published_at timestamptz not null default now(),
  unique (version, text_hash)
);

create or replace function public.aurax_consent_versions_fill_hash()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.text_hash := encode(sha256(convert_to(new.consent_text, 'UTF8')), 'hex');
  return new;
end;
$$;

drop trigger if exists consent_versions_fill_hash on public.consent_versions;
create trigger consent_versions_fill_hash
  before insert on public.consent_versions
  for each row execute function public.aurax_consent_versions_fill_hash();

create or replace function public.aurax_consent_versions_immutable()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Onay metni sürümleri değiştirilemez veya silinemez. Yeni metin için yeni sürüm numarası kullanın.' using errcode = '42501';
end;
$$;

drop trigger if exists consent_versions_no_update_delete on public.consent_versions;
create trigger consent_versions_no_update_delete
  before update or delete on public.consent_versions
  for each row execute function public.aurax_consent_versions_immutable();

alter table public.consent_versions enable row level security;
revoke all on table public.consent_versions from public, anon, authenticated;
grant select on table public.consent_versions to authenticated;

drop policy if exists consent_versions_admin_select on public.consent_versions;
create policy consent_versions_admin_select
  on public.consent_versions for select to authenticated
  using (public.aurax_base_is_admin(auth.uid()));

comment on table public.consent_versions is
  'Açık rıza onay metinlerinin tam hali ve SHA-256 özeti. Değiştirilemez.';

-- Mevcut onay metni (uygulamadaki KVKK_CONSENT_TEXT ile birebir aynıdır).
insert into public.consent_versions (version, consent_text)
values ('aurax-acik-riza-v1', $kvkk$AÇIK RIZA METNİ
Aura Ultra X hesabınızı oluşturmak için aşağıda belirtilen kişisel verilerinizin işlenmesine ilişkin açık rızanız alınmaktadır.

1) İşlenecek veriler: Ad, soyad, kullanıcı adı, doğum tarihi ve bölge bilgisi; kayıt için seçtiğiniz Google veya Apple hesabınızın e-posta adresi ve hesap kimliği. Şifreniz düz metin olarak saklanmaz. Ağ ve cihaz bilgilerinizin güvenlik amaçlı özetleri (hash) kaydedilebilir.
2) Amaçlar: Hesabınızı oluşturmak ve doğrulamak; giriş yapmak; şifre sıfırlama ve şifre değiştirme işlemlerini bu Google/Apple hesabınız üzerinden yürütmek; 15 yaş alt sınırını kontrol etmek; hesap güvenliğini sağlamak; kötüye kullanım ve şikayetleri incelemek; yasal yükümlülüklere uymak.
3) Aktarım: Veriler, kimlik doğrulama ve barındırma hizmeti sağlayıcıları (ör. Google, Apple) aracılığıyla işlenebilir. Yasal bir talep olması hâlinde yetkili kamu kurum ve kuruluşlarıyla paylaşılabilir.
4) Saklama: Verileriniz hesabınız açık olduğu sürece ve ilgili mevzuatın öngördüğü süreler boyunca saklanır. Hesap silme talebiniz, yasal saklama yükümlülükleri saklı kalmak kaydıyla işleme alınır.
5) Haklarınız: KVKK'nın 11. maddesi kapsamında verilerinizin işlenip işlenmediğini öğrenme, düzeltilmesini ve silinmesini isteme, işlenmesine itiraz etme haklarına sahipsiniz.
6) Onay kaydı: Bu onayınız; onaylanan metnin sürüm bilgisi ve özeti, onay tarihi ve saati (saniyeye kadar), hesap kimliğiniz ile güvenlik amaçlı ağ/cihaz özetleri birlikte kayıt altına alınır.
7) Rıza ve hesap zorunluluğu: Açık rızayı vermezseniz ve bir Google veya Apple hesabı bağlamazsanız hesap oluşturulamaz. Onayınızı dilediğiniz zaman geri çekebilirsiniz; geri çekme hesabınızın kapatılmasına yol açabilir.
8) Yaş beyanı: 15 yaşını doldurmuş olduğunuzu beyan edersiniz.$kvkk$)
on conflict (version) do nothing;


-- ----------------------------------------------------------------------------
-- 4) AÇIK RIZA ONAY KAYITLARI (değiştirilemez log)
--    Her kayıt: kullanıcı adı, hesap kimliği, bağlanan Google/Apple hesabı,
--    onaylanan metnin sürümü ve özeti, SUNUCU zamanı (approved_at, tam
--    hassasiyet), İstanbul saatiyle gün/ay/yıl/saat/dakika/saniye kolonları,
--    istemcinin onay kutusunu işaretlediği an (bilgi amaçlı), ağ/cihaz özetleri.
-- ----------------------------------------------------------------------------
create table if not exists public.consent_logs (
  id bigint generated always as identity primary key,
  username text not null,
  auth_uid uuid not null,
  provider text not null check (provider in ('google', 'apple')),
  consent_version text not null,
  consent_text_hash text not null check (consent_text_hash ~ '^[0-9a-f]{64}$'),
  constraint consent_logs_version_fk
    foreign key (consent_version, consent_text_hash)
    references public.consent_versions (version, text_hash),
  checked_at_client timestamptz,
  approved_at timestamptz not null default now(),
  approved_day smallint,
  approved_month smallint,
  approved_year integer,
  approved_hour smallint,
  approved_minute smallint,
  approved_second smallint,
  approved_text_tr text,
  ip_hash text,
  device_hash text
);

create index if not exists consent_logs_username_idx on public.consent_logs (username, approved_at desc);
create index if not exists consent_logs_auth_uid_idx on public.consent_logs (auth_uid);

create or replace function public.aurax_consent_logs_fill_parts()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_tr timestamp := new.approved_at at time zone 'Europe/Istanbul';
begin
  new.approved_day    := extract(day from v_tr)::smallint;
  new.approved_month  := extract(month from v_tr)::smallint;
  new.approved_year   := extract(year from v_tr)::integer;
  new.approved_hour   := extract(hour from v_tr)::smallint;
  new.approved_minute := extract(minute from v_tr)::smallint;
  new.approved_second := floor(extract(second from v_tr))::smallint;
  new.approved_text_tr := to_char(v_tr, 'DD.MM.YYYY HH24:MI:SS');
  return new;
end;
$$;

drop trigger if exists consent_logs_fill_parts on public.consent_logs;
create trigger consent_logs_fill_parts
  before insert on public.consent_logs
  for each row execute function public.aurax_consent_logs_fill_parts();

alter table public.consent_logs enable row level security;
revoke all on table public.consent_logs from public, anon, authenticated;
grant select on table public.consent_logs to authenticated;

drop policy if exists consent_logs_admin_select on public.consent_logs;
create policy consent_logs_admin_select
  on public.consent_logs for select to authenticated
  using (public.aurax_base_is_admin(auth.uid()));

-- Onay kayıtları değiştirilemez ve silinemez (yasal delil bütünlüğü).
create or replace function public.aurax_consent_logs_immutable()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Açık rıza kayıtları değiştirilemez veya silinemez.' using errcode = '42501';
end;
$$;

drop trigger if exists consent_logs_no_update_delete on public.consent_logs;
create trigger consent_logs_no_update_delete
  before update or delete on public.consent_logs
  for each row execute function public.aurax_consent_logs_immutable();

comment on table public.consent_logs is
  'Açık rıza onay kayıtları: kim, hangi metin sürümünü (özetiyle), hangi Google/Apple hesabıyla, sunucu zamanında (gün/ay/yıl/saat/dakika/saniye) onayladı. Değiştirilemez.';


-- ----------------------------------------------------------------------------
-- 5) ONAY KAYDI RPC'Sİ
--    Kayıt sırasında istemci bu fonksiyonu çağırır. Kullanıcı yalnızca kendi
--    hesap kimliğiyle (auth.uid) kayıt oluşturabilir; metin sürümü ve özeti
--    consent_versions'taki kayıtla birebir eşleşmelidir.
-- ----------------------------------------------------------------------------
create or replace function public.aurax_record_consent(
  p_username text,
  p_consent_version text,
  p_consent_text_hash text,
  p_provider text,
  p_checked_at_client timestamptz default null,
  p_ip_hash text default null,
  p_device_hash text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_id bigint;
  v_now timestamptz := now();
  v_tr text;
begin
  if v_uid is null then
    raise exception 'Oturum bulunamadı.' using errcode = '28000';
  end if;
  if p_username is null or char_length(btrim(p_username)) = 0 or char_length(p_username) > 40 then
    raise exception 'Geçersiz kullanıcı adı.' using errcode = '22023';
  end if;
  -- Kullanıcı adı zaten başka bir hesaba bağlıysa kayıt yazılmaz.
  if exists (
    select 1 from public.users u
    where u.id = p_username
      and coalesce(u.data->>'authUid', '') not in ('', v_uid::text)
  ) then
    raise exception 'Bu kullanıcı adı başka bir hesaba ait.' using errcode = '42501';
  end if;
  if p_provider is null or p_provider not in ('google', 'apple') then
    raise exception 'Geçersiz kayıt yöntemi.' using errcode = '22023';
  end if;
  if p_consent_text_hash is null or p_consent_text_hash !~ '^[0-9a-fA-F]{64}$' then
    raise exception 'Geçersiz onay metni özeti.' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.consent_versions cv
    where cv.version = p_consent_version
      and cv.text_hash = lower(p_consent_text_hash)
  ) then
    raise exception 'Onay metni sürümü bulunamadı veya metin uyuşmuyor.' using errcode = '22023';
  end if;

  insert into public.consent_logs (
    username, auth_uid, provider, consent_version, consent_text_hash,
    checked_at_client, approved_at, ip_hash, device_hash
  )
  values (
    p_username, v_uid, p_provider, p_consent_version, lower(p_consent_text_hash),
    p_checked_at_client, v_now, p_ip_hash, p_device_hash
  )
  returning id, approved_text_tr into v_id, v_tr;

  return jsonb_build_object('id', v_id, 'approved_at', v_now, 'approved_text_tr', v_tr);
end;
$$;

revoke all on function public.aurax_record_consent(text, text, text, text, timestamptz, text, text) from public, anon;
grant execute on function public.aurax_record_consent(text, text, text, text, timestamptz, text, text) to authenticated;

comment on function public.aurax_record_consent(text, text, text, text, timestamptz, text, text) is
  'Kayıt sırasında açık rıza onayını sunucu zamanıyla kaydeder. Yalnızca kendi auth.uid değeriyle ve kayıtlı metin sürümüyle yazar.';


-- ----------------------------------------------------------------------------
-- 6) YÖNETİCİ SORGULARI (SQL Editor'de kullanın, örnek)
--
--  Onay kayıtları, tarih ve saat ayrı kolonlarda (İstanbul saati):
--    select username, provider, consent_version,
--           approved_day as gun, approved_month as ay, approved_year as yil,
--           approved_hour as saat, approved_minute as dakika, approved_second as saniye,
--           approved_text_tr, approved_at, checked_at_client
--    from public.consent_logs
--    order by approved_at desc;
--
--  Bir kaydın onayladığı tam metin:
--    select cv.consent_text
--    from public.consent_logs cl
--    join public.consent_versions cv
--      on cv.version = cl.consent_version and cv.text_hash = cl.consent_text_hash
--    where cl.id = 1;
--
--  Bir kullanıcının kısıtlama kodu (yalnızca yönetici):
--    select id, data->>'code' as kod from public.restriction_codes where id = 'kullanici_adi';
-- ----------------------------------------------------------------------------

-- ===== Aura X signup =====
-- ============================================================================
-- Aura X: KAYIT TAMAMLAMA (atomik)   —   supabase_aura_signup_setup.sql
-- Supabase Dashboard > SQL Editor bölümünde BİR KEZ çalıştırın (tekrar çalıştırmak zararsızdır).
--
-- Ön koşul: supabase_aura_restriction_consent_setup.sql daha önce çalıştırılmış olmalı
-- (consent_versions ve consent_logs tabloları orada oluşur). Mevcut hiçbir veriyi silmez
-- veya değiştirmez; yalnızca tek bir yeni fonksiyon ekler.
--
-- Ne yapar?
--   Kullanıcı "Kayıt Ol"a bastığında istemci bu fonksiyonu TEK çağrıyla çalıştırır ve şunlar
--   AYNI İŞLEMDE (hepsi ya da hiçbiri) Supabase'e yazılır:
--     1) KVKK açık rıza kaydı  -> consent_logs   (SUNUCU saatiyle, İstanbul: GG.AA.YYYY SS:DD:SS;
--                                                  gün/ay/yıl/saat/dakika/saniye ayrı kolonlarda da)
--     2) Kullanıcı profili     -> users          (KVKK onay zamanı profilde de yazılır)
--     3) Hesap bağlantısı      -> account_links
--   Sağlayıcı (Google/Apple) ve e-posta istemciden alınmaz; Supabase Auth kaydından okunur.
--   Yaş (15+), bölge, kullanıcı adı biçimi/benzersizliği ve onay metni özeti sunucuda doğrulanır.
--
-- Hata kodları (istemcide Türkçe gösterilir):
--   AX001 kullanıcı adı alınmış   AX002 hesap zaten bağlı   AX003 doğum tarihi/yaş
--   AX004 bölge geçersiz          AX005 ad/soyad/kullanıcı adı biçimi   AX006 ayrılmış ad
--   AX007 onay metni uyuşmuyor    AX008 oturum/sağlayıcı sorunu
-- ============================================================================

do $$
begin
  if to_regclass('public.users') is null or to_regclass('public.account_links') is null then
    raise exception 'public.users / public.account_links tabloları bulunamadı. Önce temel kurulum SQL dosyalarını çalıştırın.';
  end if;
  if to_regclass('public.consent_logs') is null or to_regclass('public.consent_versions') is null then
    raise exception 'Önce supabase_aura_restriction_consent_setup.sql dosyasını çalıştırın (consent_logs / consent_versions yok).';
  end if;
end
$$;


create or replace function public.aurax_complete_signup(
  p_username          text,
  p_first_name        text,
  p_last_name         text,
  p_birth_date        date,
  p_region            text,
  p_consent_version   text,
  p_consent_text_hash text,
  p_checked_at_client timestamptz default null,
  p_ip_hash           text default null,
  p_device_hash       text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid := auth.uid();
  v_username  text := btrim(coalesce(p_username, ''));
  v_first     text := btrim(coalesce(p_first_name, ''));
  v_last      text := btrim(coalesce(p_last_name, ''));
  v_email     text;
  v_provider  text;
  v_now       timestamptz := now();
  v_today     date := (now() at time zone 'Europe/Istanbul')::date;
  v_ms        bigint := (extract(epoch from now()) * 1000)::bigint;
  v_log_id    bigint;
  v_stamp     text;
  v_edu_username_taken boolean := false;
begin
  -- 1) Oturum ve sağlayıcı (Auth kaydından; istemciye güvenilmez)
  if v_uid is null then
    raise exception 'Oturum bulunamadı. Google/Apple hesabınızı yeniden seçip tekrar deneyin.' using errcode = 'AX008';
  end if;

  select au.email, coalesce(au.raw_app_meta_data ->> 'provider', '')
    into v_email, v_provider
  from auth.users au
  where au.id = v_uid;

  if v_provider not in ('google', 'apple') then
    raise exception 'Kayıt yalnızca Google veya Apple hesabıyla yapılabilir.' using errcode = 'AX008';
  end if;
  if v_email is null or btrim(v_email) = '' then
    raise exception 'Seçtiğiniz hesapta e-posta bilgisi bulunamadı. Başka bir hesapla deneyin.' using errcode = 'AX008';
  end if;

  -- 2) Biçim doğrulamaları
  if char_length(v_username) < 1 or char_length(v_username) > 40 or v_username ~ '[<>"''`&]' then
    raise exception 'Kullanıcı adı 1-40 karakter olmalı ve <, >, ", '', `, & karakterlerini içermemelidir.' using errcode = 'AX005';
  end if;
  if lower(v_username) = lower('A_UR_A_XX') then
    raise exception 'Bu kullanıcı adı sistem tarafından ayrılmıştır.' using errcode = 'AX006';
  end if;
  if char_length(v_first) < 1 or char_length(v_first) > 60
     or char_length(v_last) < 1 or char_length(v_last) > 60
     or v_first ~ '[<>"''`&]' or v_last ~ '[<>"''`&]' then
    raise exception 'Ad ve soyad 1-60 karakter olmalı ve <, >, ", '', `, & karakterlerini içermemelidir.' using errcode = 'AX005';
  end if;

  if p_birth_date is null or p_birth_date > v_today or p_birth_date < date '1900-01-01' then
    raise exception 'Geçerli bir doğum tarihi girin.' using errcode = 'AX003';
  end if;
  if date_part('year', age(v_today, p_birth_date)) < 15 then
    raise exception 'Aura Ultra X''e kayıt olabilmek için 15 yaşını doldurmuş olmanız gerekmektedir.' using errcode = 'AX003';
  end if;

  if p_region is null or p_region not in
     ('Türkiye', 'Avrupa', 'Asya', 'Kuzey Amerika', 'Güney Amerika', 'Afrika', 'Okyanusya', 'Orta Doğu') then
    raise exception 'Geçerli bir bölge seçin.' using errcode = 'AX004';
  end if;

  -- 3) Açık rıza metni: istemcinin onayladığı metin, Supabase'deki sürümle birebir aynı olmalı
  if p_consent_text_hash is null
     or p_consent_text_hash !~ '^[0-9a-fA-F]{64}$'
     or not exists (
       select 1 from public.consent_versions cv
       where cv.version = p_consent_version
         and cv.text_hash = lower(p_consent_text_hash)
     ) then
    raise exception 'Onay metni Supabase''teki sürümle uyuşmuyor. supabase_aura_restriction_consent_setup.sql dosyasını çalıştırdığınızdan emin olun.' using errcode = 'AX007';
  end if;

  -- 4) Benzersizlik (büyük/küçük harf fark etmeksizin) ve hesap bağlantısı
  if exists (select 1 from public.users u where lower(u.id::text) = lower(v_username)) then
    raise exception 'Bu kullanıcı adı önceden alınmış.' using errcode = 'AX001';
  end if;
  if exists (select 1 from public.account_links l where l.id::text = v_uid::text)
     or exists (select 1 from public.users u where coalesce(u.data ->> 'authUid', '') = v_uid::text) then
    raise exception 'Bu Google/Apple hesabı zaten bir Aura X hesabına bağlı. Giriş yapın.' using errcode = 'AX002';
  end if;

  -- 5) Açık rıza kaydı (sunucu saati; gün/ay/yıl/saat/dakika/saniye kolonlarını tetikleyici doldurur)
  insert into public.consent_logs (
    username, auth_uid, provider, consent_version, consent_text_hash,
    checked_at_client, approved_at, ip_hash, device_hash
  )
  values (
    v_username, v_uid, v_provider, p_consent_version, lower(p_consent_text_hash),
    p_checked_at_client, v_now, p_ip_hash, p_device_hash
  )
  returning id, approved_text_tr into v_log_id, v_stamp;

  -- 6) Kullanıcı profili (istemcinin eskiden yazdığı alanlarla aynı yapı + KVKK onay zamanı)
  begin
    insert into public.users (id, data)
    values (
      v_username,
      jsonb_build_object(
        'username',    v_username,
        'firstName',   v_first,
        'lastName',    v_last,
        'displayName', v_first || ' ' || v_last,
        'region',      p_region,
        'birthDate',   to_char(p_birth_date, 'YYYY-MM-DD'),
        'authUid',     v_uid::text,
        'authEmail',   v_email,
        'googleUid',   case when v_provider = 'google' then v_uid::text end,
        'googleEmail', case when v_provider = 'google' then v_email end,
        'appleUid',    case when v_provider = 'apple'  then v_uid::text end,
        'appleEmail',  case when v_provider = 'apple'  then v_email end,
        'authProvider', v_provider,
        'ipHash',      p_ip_hash,
        'deviceHash',  p_device_hash,
        'createdAt',   v_ms,
        'lastSeenAt',  v_ms,
        'restricted',  false,
        'banned',      false,
        'votes',       0,
        'followers',   '[]'::jsonb,
        'following',   '[]'::jsonb,
        'verified',    false,
        'special',     false,
        'avatarUrl',   null,
        'avatarPath',  null,
        'role',        'user',
        'kvkkApproved',       true,
        'kvkkApprovedAt',     v_stamp,
        'kvkkConsentVersion', p_consent_version,
        'kvkkConsentLogId',   v_log_id
      )
    );
  exception when unique_violation then
    raise exception 'Bu kullanıcı adı önceden alınmış.' using errcode = 'AX001';
  end;

  -- 7) Hesap bağlantısı
  insert into public.account_links (id, data)
  values (
    v_uid::text,
    jsonb_build_object(
      'username',  v_username,
      'authUid',   v_uid::text,
      'googleUid', case when v_provider = 'google' then v_uid::text end,
      'appleUid',  case when v_provider = 'apple'  then v_uid::text end,
      'createdAt', v_ms
    )
  )
  on conflict (id) do update set data = excluded.data;

  return jsonb_build_object(
    'username',         v_username,
    'approved_at',      v_now,
    'approved_text_tr', v_stamp,
    'consent_log_id',   v_log_id
  );
end;
$$;

revoke all on function public.aurax_complete_signup(text, text, text, date, text, text, text, timestamptz, text, text) from public, anon;
grant execute on function public.aurax_complete_signup(text, text, text, date, text, text, text, timestamptz, text, text) to authenticated;

comment on function public.aurax_complete_signup(text, text, text, date, text, text, text, timestamptz, text, text) is
  'Kayıt sonunda KVKK onay logu + kullanıcı profili + hesap bağlantısını tek işlemde yazar. Sağlayıcı/e-posta Auth kaydından okunur.';

-- PostgREST şema önbelleğini yenile (yeni fonksiyon hemen görünsün)
notify pgrst, 'reload schema';


-- ----------------------------------------------------------------------------
-- KONTROL SORGULARI (SQL Editor'de, kayıttan sonra)
--
--  KVKK onayları: gün / ay / yıl / saat / dakika / saniye ayrı ve birleşik (İstanbul saati):
--    select username, provider,
--           approved_day as gg, approved_month as aa, approved_year as yyyy,
--           approved_hour as ss, approved_minute as dd, approved_second as sn,
--           approved_text_tr,            -- örn. 24.10.2026 14:03:09
--           approved_at                  -- sunucu zamanı (UTC, tam hassasiyet)
--    from public.consent_logs order by approved_at desc;
--
--  Profilde de aynı zaman damgası:
--    select id, data->>'kvkkApprovedAt' as kvkk_onay, data->>'kvkkConsentVersion' as surum
--    from public.users order by updated_at desc limit 20;
-- ----------------------------------------------------------------------------

-- ===== Aura X status policies =====
-- Aura X: Hikâye paylaşma + takipçiye özel görüntüleme izinlerinin birleştirilmiş düzeltmesi.
-- Supabase SQL Editor'de bir kez çalıştırın. Mevcut hikâye verisini silmez.

create or replace function public.aurax_can_view_status(p_owner text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    p_owner = public.aurax_base_current_username(auth.uid())
    or exists (
      select 1
      from public.users viewer
      where viewer.id = public.aurax_base_current_username(auth.uid())
        and coalesce(viewer.data->'following', '[]'::jsonb) ? p_owner
    ),
    false
  );
$$;

revoke all on function public.aurax_can_view_status(text) from public, anon;
grant execute on function public.aurax_can_view_status(text) to authenticated;

alter table public.statuses enable row level security;
grant select, insert, update, delete on public.statuses to authenticated;

drop policy if exists statuses_select_authenticated on public.statuses;
create policy statuses_select_authenticated on public.statuses
for select to authenticated using (public.aurax_can_view_status(id));

drop policy if exists statuses_insert_own on public.statuses;
create policy statuses_insert_own on public.statuses
for insert to authenticated with check (id = public.aurax_base_current_username(auth.uid()));

drop policy if exists statuses_update_own on public.statuses;
create policy statuses_update_own on public.statuses
for update to authenticated using (id = public.aurax_base_current_username(auth.uid()))
with check (id = public.aurax_base_current_username(auth.uid()));

drop policy if exists statuses_delete_own on public.statuses;
create policy statuses_delete_own on public.statuses
for delete to authenticated using (id = public.aurax_base_current_username(auth.uid()));

-- Medya yüklemesini sadece kendi kullanıcı adıyla başlayan dosya yollarına izin vererek sınırla.
drop policy if exists aurax_media_insert on storage.objects;
create policy aurax_media_insert on storage.objects
for insert to authenticated
with check (
  bucket_id = 'media'
  and (
    public.aurax_base_is_admin(auth.uid())
    or name like ('avatars/' || public.aurax_base_current_username(auth.uid()) || '_%')
    or name like ('postImages/' || public.aurax_base_current_username(auth.uid()) || '_%')
    or name like ('postVideos/' || public.aurax_base_current_username(auth.uid()) || '_%')
    or name like ('statusImages/' || public.aurax_base_current_username(auth.uid()) || '_%')
    or name like ('statusVideos/' || public.aurax_base_current_username(auth.uid()) || '_%')
    or name like ('stickers/' || public.aurax_base_current_username(auth.uid()) || '/%')
    or name like ('room-media/%/' || public.aurax_base_current_username(auth.uid()) || '_%')
  )
);

comment on function public.aurax_can_view_status(text) is
  'Hikâyeler yalnızca sahibi ve hikâye sahibini takip eden Aura X kullanıcılarına görünür.';

-- ===== Aura X story / emoji =====
-- Aura X: Hikâye görünürlüğü/beğenisi ve medya yükleme izinleri
-- Önce `supabase_final_security_setup.sql` dosyasını çalıştırdıktan sonra bu yamayı çalıştırın.
-- Çalışma biçimi: sadece hikâye SELECT politikasını daraltır ve yeni medya yollarına INSERT izni ekler.

create or replace function public.aurax_can_view_status(p_owner text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    p_owner = public.aurax_base_current_username(auth.uid())
    or exists (
      select 1
      from public.users viewer
      where viewer.id = public.aurax_base_current_username(auth.uid())
        and coalesce(viewer.data->'following', '[]'::jsonb) ? p_owner
    ),
    false
  );
$$;

revoke all on function public.aurax_can_view_status(text) from public, anon;
grant execute on function public.aurax_can_view_status(text) to authenticated;

drop policy if exists statuses_select_authenticated on public.statuses;
create policy statuses_select_authenticated
  on public.statuses for select to authenticated
  using (public.aurax_can_view_status(id));

create or replace function public.aurax_toggle_status_like(p_status_owner text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor text;
  v_data jsonb;
  v_likes jsonb;
  v_liked boolean;
  v_exp bigint;
begin
  v_actor := public.aurax_base_current_username(auth.uid());
  if v_actor is null or v_actor = '' then
    raise exception 'Aura X oturumu bulunamadı.' using errcode = '28000';
  end if;
  if p_status_owner is null or p_status_owner = '' or p_status_owner = v_actor then
    raise exception 'Bu hikâye beğenilemez.' using errcode = '22023';
  end if;
  if not public.aurax_can_view_status(p_status_owner) then
    raise exception 'Bu hikâyeyi görmek için kullanıcıyı takip etmelisiniz.' using errcode = '42501';
  end if;

  select s.data into v_data
  from public.statuses s
  where s.id = p_status_owner
  for update;
  if not found then
    raise exception 'Hikâye bulunamadı.' using errcode = 'P0002';
  end if;

  v_exp := case
    when coalesce(v_data->>'expiresAt', '') ~ '^[0-9]+$' then (v_data->>'expiresAt')::bigint
    when coalesce(v_data->>'createdAt', '') ~ '^[0-9]+$' then (v_data->>'createdAt')::bigint + 86400000
    else 0
  end;
  if v_exp <= (extract(epoch from pg_catalog.clock_timestamp()) * 1000)::bigint then
    raise exception 'Bu hikâyenin süresi dolmuş.' using errcode = '22023';
  end if;

  v_likes := case when pg_catalog.jsonb_typeof(v_data->'likes') = 'array' then v_data->'likes' else '[]'::jsonb end;
  select exists (
    select 1 from pg_catalog.jsonb_array_elements_text(v_likes) as item(value)
    where item.value = v_actor
  ) into v_liked;

  if v_liked then
    select coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(item.value)), '[]'::jsonb)
      into v_likes
    from pg_catalog.jsonb_array_elements_text(v_likes) as item(value)
    where item.value <> v_actor;
  else
    v_likes := v_likes || pg_catalog.jsonb_build_array(v_actor);
  end if;

  update public.statuses
  set data = pg_catalog.jsonb_set(coalesce(data, '{}'::jsonb), '{likes}', v_likes, true),
      updated_at = pg_catalog.now()
  where id = p_status_owner;

  return pg_catalog.jsonb_build_object('liked', not v_liked, 'likes', v_likes);
end;
$$;

revoke all on function public.aurax_toggle_status_like(text) from public, anon;
grant execute on function public.aurax_toggle_status_like(text) to authenticated;

-- Medya yolunu kullanıcıya bağla. Herkes hikâye/oda medyası adına istediği yolu yükleyemesin.
drop policy if exists aurax_media_insert on storage.objects;
create policy aurax_media_insert on storage.objects
for insert to authenticated
with check (
  bucket_id = 'media'
  and (
    public.aurax_base_is_admin(auth.uid())
    or name like ('avatars/' || public.aurax_base_current_username(auth.uid()) || '_%')
    or name like ('postImages/' || public.aurax_base_current_username(auth.uid()) || '_%')
    or name like ('postVideos/' || public.aurax_base_current_username(auth.uid()) || '_%')
    or name like ('statusImages/' || public.aurax_base_current_username(auth.uid()) || '_%')
    or name like ('statusVideos/' || public.aurax_base_current_username(auth.uid()) || '_%')
    or name like ('stickers/' || public.aurax_base_current_username(auth.uid()) || '/%')
    or name like ('room-media/%/' || public.aurax_base_current_username(auth.uid()) || '_%')
  )
);

comment on function public.aurax_can_view_status(text) is
  'Aura X hikâyeleri yalnızca sahibi ve hikâye sahibini takip eden kullanıcılar için okunabilir.';
comment on function public.aurax_toggle_status_like(text) is
  'Aura X hikâye beğenisini sunucuda atomik olarak aç/kapatır.';

-- ===== Aura X push notifications =====
-- Aura X: tarayıcı Web Push abonelikleri
-- Bu dosyayı Supabase SQL Editor'de bir kez çalıştırın. Uygulama push aboneliğini push_tokens.data içinde saklar.

create table if not exists public.push_tokens (
  id text primary key,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.push_tokens enable row level security;
grant select, insert, update, delete on public.push_tokens to authenticated;

drop policy if exists aurax_push_tokens_select_own on public.push_tokens;
create policy aurax_push_tokens_select_own on public.push_tokens
for select to authenticated
using (data->>'username' = public.aurax_base_current_username(auth.uid()) or public.aurax_base_is_admin(auth.uid()));

drop policy if exists aurax_push_tokens_insert_own on public.push_tokens;
create policy aurax_push_tokens_insert_own on public.push_tokens
for insert to authenticated
with check (data->>'username' = public.aurax_base_current_username(auth.uid()) or public.aurax_base_is_admin(auth.uid()));

drop policy if exists aurax_push_tokens_update_own on public.push_tokens;
create policy aurax_push_tokens_update_own on public.push_tokens
for update to authenticated
using (data->>'username' = public.aurax_base_current_username(auth.uid()) or public.aurax_base_is_admin(auth.uid()))
with check (data->>'username' = public.aurax_base_current_username(auth.uid()) or public.aurax_base_is_admin(auth.uid()));

drop policy if exists aurax_push_tokens_delete_own on public.push_tokens;
create policy aurax_push_tokens_delete_own on public.push_tokens
for delete to authenticated
using (data->>'username' = public.aurax_base_current_username(auth.uid()) or public.aurax_base_is_admin(auth.uid()));

comment on table public.push_tokens is 'Aura X web push subscriptions keyed by subscription hash; private key is stored only in Edge Function secrets.';

-- ===== BAI usage (legacy database identifiers retained) =====
-- BAI günlük kullanım sayacı
-- Supabase Dashboard > SQL Editor bölümünde yalnızca bir kez çalıştırın.
-- Sayaçlar UTC takvim gününe göre tutulur. Mesaj içerikleri bu tabloya kaydedilmez.

create table if not exists public.aurai_usage_daily (
  user_id uuid not null,
  usage_date date not null,
  feature text not null check (feature in ('chat', 'search', 'global')),
  request_count integer not null default 0 check (request_count >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, usage_date, feature)
);

alter table public.aurai_usage_daily enable row level security;
revoke all on table public.aurai_usage_daily from public, anon, authenticated;
grant select, insert, update, delete on table public.aurai_usage_daily to service_role;

-- Önceki sürümde tek parametreli bir fonksiyon oluşturulmuş olabileceği için kaldırılır.
-- Yeni fonksiyon, chat/search sayaçlarını birbirinden ayırır ve ayrıca ortak global sayacı tutar.
drop function if exists public.aurai_bump(uuid);
drop function if exists public.aurai_bump(uuid, text);

create function public.aurai_bump(p_user uuid, p_feature text default 'chat')
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_count integer;
  v_today date := (now() at time zone 'utc')::date;
begin
  if p_user is null then
    raise exception 'p_user cannot be null';
  end if;
  if p_feature not in ('chat', 'search', 'global') then
    raise exception 'invalid AURAI usage feature';
  end if;

  insert into public.aurai_usage_daily (user_id, usage_date, feature, request_count, updated_at)
  values (p_user, v_today, p_feature, 1, now())
  on conflict (user_id, usage_date, feature)
  do update set
    request_count = aurai_usage_daily.request_count + 1,
    updated_at = now()
  returning request_count into v_count;

  -- Global sayaç gün içindeki ilk isteği aldıysa eski kayıtları temizle; tablo zamanla sınırsız büyümesin.
  if p_feature = 'global' and v_count = 1 then
    delete from public.aurai_usage_daily where usage_date < v_today - 35;
  end if;

  return v_count;
end;
$$;

revoke all on function public.aurai_bump(uuid, text) from public, anon, authenticated;
grant execute on function public.aurai_bump(uuid, text) to service_role;

comment on table public.aurai_usage_daily is 'BAI günlük istek sayaçları; kullanıcı mesajları içermez.';
comment on function public.aurai_bump(uuid, text) is 'Yalnızca service_role tarafından çağrılan atomik günlük kullanım sayacı.';

notify pgrst, 'reload schema';
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
