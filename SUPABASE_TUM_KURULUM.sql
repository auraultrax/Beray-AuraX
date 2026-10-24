-- ====================================================================
-- CONSOLIDATED SETUP: Aura X + Beray Education on one Supabase project
-- Back up the project before applying this file in Supabase SQL Editor.
-- Ordered migration bundle for a Supabase-only deployment.
-- Then deploy username-login, username-available and education-actions.
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

-- ===== Aura X restrictions + consent =====
-- ============================================================================
-- Aura X: Kısıtlı ban süreleri, kısıtlama kodu saklama ve açık rıza onay kayıtları
-- Supabase Dashboard > SQL Editor bölümünde BİR KEZ çalıştırın.
--
-- Ön koşul: supabase_final_security_setup.sql içindeki public.aurax_is_admin()
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
  using (public.aurax_is_admin())
  with check (public.aurax_is_admin());

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
  using (public.aurax_is_admin());


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
  using (public.aurax_is_admin());

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
  using (public.aurax_is_admin());

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
  if to_regclass('public.education_records') is not null then
    execute 'select exists (select 1 from public.education_records er where er.collection_name = ''usernameClaims'' and lower(er.id) = $1)'
      into v_edu_username_taken using lower(v_username);
    if v_edu_username_taken then
      raise exception 'Bu kullanıcı adı Eğitim platformunda önceden alınmış.' using errcode = 'AX001';
    end if;
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
    p_owner = public.aurax_current_username()
    or exists (
      select 1
      from public.users viewer
      where viewer.id = public.aurax_current_username()
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
for insert to authenticated with check (id = public.aurax_current_username());

drop policy if exists statuses_update_own on public.statuses;
create policy statuses_update_own on public.statuses
for update to authenticated using (id = public.aurax_current_username())
with check (id = public.aurax_current_username());

drop policy if exists statuses_delete_own on public.statuses;
create policy statuses_delete_own on public.statuses
for delete to authenticated using (id = public.aurax_current_username());

-- Medya yüklemesini sadece kendi kullanıcı adıyla başlayan dosya yollarına izin vererek sınırla.
drop policy if exists aurax_media_insert on storage.objects;
create policy aurax_media_insert on storage.objects
for insert to authenticated
with check (
  bucket_id = 'media'
  and (
    public.aurax_is_admin()
    or name like ('avatars/' || public.aurax_current_username() || '_%')
    or name like ('postImages/' || public.aurax_current_username() || '_%')
    or name like ('postVideos/' || public.aurax_current_username() || '_%')
    or name like ('statusImages/' || public.aurax_current_username() || '_%')
    or name like ('statusVideos/' || public.aurax_current_username() || '_%')
    or name like ('stickers/' || public.aurax_current_username() || '/%')
    or name like ('room-media/%/' || public.aurax_current_username() || '_%')
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
    p_owner = public.aurax_current_username()
    or exists (
      select 1
      from public.users viewer
      where viewer.id = public.aurax_current_username()
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
  v_actor := public.aurax_current_username();
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
    public.aurax_is_admin()
    or name like ('avatars/' || public.aurax_current_username() || '_%')
    or name like ('postImages/' || public.aurax_current_username() || '_%')
    or name like ('postVideos/' || public.aurax_current_username() || '_%')
    or name like ('statusImages/' || public.aurax_current_username() || '_%')
    or name like ('statusVideos/' || public.aurax_current_username() || '_%')
    or name like ('stickers/' || public.aurax_current_username() || '/%')
    or name like ('room-media/%/' || public.aurax_current_username() || '_%')
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
using (data->>'username' = public.aurax_current_username() or public.aurax_is_admin());

drop policy if exists aurax_push_tokens_insert_own on public.push_tokens;
create policy aurax_push_tokens_insert_own on public.push_tokens
for insert to authenticated
with check (data->>'username' = public.aurax_current_username() or public.aurax_is_admin());

drop policy if exists aurax_push_tokens_update_own on public.push_tokens;
create policy aurax_push_tokens_update_own on public.push_tokens
for update to authenticated
using (data->>'username' = public.aurax_current_username() or public.aurax_is_admin())
with check (data->>'username' = public.aurax_current_username() or public.aurax_is_admin());

drop policy if exists aurax_push_tokens_delete_own on public.push_tokens;
create policy aurax_push_tokens_delete_own on public.push_tokens
for delete to authenticated
using (data->>'username' = public.aurax_current_username() or public.aurax_is_admin());

comment on table public.push_tokens is 'Aura X web push subscriptions keyed by subscription hash; private key is stored only in Edge Function secrets.';

-- ===== AURAI usage =====
-- AURAI günlük kullanım sayacı
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

comment on table public.aurai_usage_daily is 'AURAI günlük istek sayaçları; kullanıcı mesajları içermez.';
comment on function public.aurai_bump(uuid, text) is 'Yalnızca service_role tarafından çağrılan atomik günlük kullanım sayacı.';

-- ===== Education profile, records, safe grading and point sharing =====
-- Beray Eğitim + Aura X ortak Supabase kurulumu.
-- Önce Aura X paketindeki supabase_aura_base_setup.sql çalıştırılmalı.
-- Bu dosya eğitim profillerini, veri tablolarını ve RLS politikalarını hazırlar.

create extension if not exists pgcrypto;

create table if not exists public.education_records (
  collection_name text not null,
  id text not null,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (collection_name, id)
);
create index if not exists education_records_collection_updated_idx
  on public.education_records (collection_name, updated_at desc);
create index if not exists education_records_data_gin_idx
  on public.education_records using gin (data jsonb_path_ops);

-- Answer keys are private: they are never readable directly by browser clients.
create table if not exists public.education_test_answer_keys (
  test_id text primary key,
  answers jsonb not null,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.education_touch_updated_at()
returns trigger language plpgsql set search_path = public as $$
begin
  new.updated_at := now();
  if new.created_at is null then new.created_at := now(); end if;
  return new;
end;
$$;
drop trigger if exists education_records_touch_updated_at on public.education_records;
create trigger education_records_touch_updated_at before insert or update on public.education_records
for each row execute function public.education_touch_updated_at();
drop trigger if exists education_answer_keys_touch_updated_at on public.education_test_answer_keys;
create trigger education_answer_keys_touch_updated_at before insert or update on public.education_test_answer_keys
for each row execute function public.education_touch_updated_at();

create or replace function public.education_current_role(p_uid uuid default auth.uid())
returns text language sql stable security definer set search_path = public
as $$
  select coalesce(r.data ->> 'role', 'student')
  from public.education_records r
  where r.collection_name = 'users' and r.id = p_uid::text
  limit 1;
$$;
create or replace function public.education_is_teacher_or_admin(p_uid uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public
as $$ select public.education_current_role(p_uid) in ('teacher','admin'); $$;
create or replace function public.education_is_admin(p_uid uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public
as $$ select public.education_current_role(p_uid) = 'admin'; $$;

-- Prevent self-service changes to protected profile values (points, role, achievements).
create or replace function public.education_guard_profile_fields()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.collection_name = 'users'
     and old.collection_name = 'users'
     and auth.uid() is not null
     and coalesce(auth.role(), '') = 'authenticated'
     and old.id = auth.uid()::text then
    if new.data ->> 'role' is distinct from old.data ->> 'role'
       or new.data ->> 'points' is distinct from old.data ->> 'points'
       or new.data -> 'completedTests' is distinct from old.data -> 'completedTests'
       or new.data -> 'completedLessons' is distinct from old.data -> 'completedLessons' then
      raise exception 'Rol, puan ve tamamlanma alanları yalnızca güvenli sunucu işlemleriyle değiştirilebilir.' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists education_guard_profile_fields_trigger on public.education_records;
create trigger education_guard_profile_fields_trigger before update on public.education_records
for each row execute function public.education_guard_profile_fields();

alter table public.education_records enable row level security;
alter table public.education_test_answer_keys enable row level security;
grant select, insert, update, delete on public.education_records to authenticated;
grant all on public.education_records to service_role;
grant all on public.education_test_answer_keys to service_role;
revoke all on public.education_test_answer_keys from anon, authenticated;

-- Read access: teaching content is visible to signed-in students. User data and results are restricted.
drop policy if exists education_records_select on public.education_records;
create policy education_records_select on public.education_records for select to authenticated using (
  (collection_name = 'users' and (id = auth.uid()::text or public.education_is_teacher_or_admin()))
  or (collection_name in ('courses','lessons','tests','announcements','meetings'))
  or (collection_name = 'results' and (data ->> 'studentId' = auth.uid()::text or public.education_is_teacher_or_admin()))
  or (collection_name = 'notifications' and data ->> 'userId' = auth.uid()::text)
  or (collection_name = 'usernameClaims')
  or (collection_name in ('followRequests','friendships','pointTransfers') and (
      data ->> 'fromUid' = auth.uid()::text or data ->> 'toUid' = auth.uid()::text
      or data -> 'members' ? auth.uid()::text
  ))
);

-- A new user can create only their own student profile. Existing profiles can edit non-protected fields.
drop policy if exists education_records_insert on public.education_records;
create policy education_records_insert on public.education_records for insert to authenticated with check (
  (collection_name = 'users' and id = auth.uid()::text and coalesce(data ->> 'role','student') = 'student')
  or (collection_name = 'usernameClaims' and data ->> 'ownerUidHash' = encode(digest(auth.uid()::text, 'sha256'),'hex'))
  or (collection_name in ('courses','lessons','tests','announcements','meetings') and public.education_is_teacher_or_admin()
      and (public.education_is_admin() or data ->> 'teacherId' = auth.uid()::text))
);
drop policy if exists education_records_update on public.education_records;
create policy education_records_update on public.education_records for update to authenticated
using (
  (collection_name = 'users' and id = auth.uid()::text)
  or (collection_name = 'usernameClaims' and data ->> 'ownerUidHash' = encode(digest(auth.uid()::text, 'sha256'),'hex'))
  or (collection_name in ('courses','lessons','tests','announcements','meetings') and public.education_is_teacher_or_admin()
      and (public.education_is_admin() or data ->> 'teacherId' = auth.uid()::text))
)
with check (
  (collection_name = 'users' and id = auth.uid()::text and data ->> 'role' = public.education_current_role())
  or (collection_name = 'usernameClaims' and data ->> 'ownerUidHash' = encode(digest(auth.uid()::text, 'sha256'),'hex'))
  or (collection_name in ('courses','lessons','tests','announcements','meetings') and public.education_is_teacher_or_admin()
      and (public.education_is_admin() or data ->> 'teacherId' = auth.uid()::text))
);
drop policy if exists education_records_delete on public.education_records;
create policy education_records_delete on public.education_records for delete to authenticated using (
  (collection_name = 'users' and id = auth.uid()::text)
  or (collection_name = 'usernameClaims' and data ->> 'ownerUidHash' = encode(digest(auth.uid()::text, 'sha256'),'hex'))
  or (collection_name in ('courses','lessons','tests','announcements','meetings') and public.education_is_teacher_or_admin()
      and (public.education_is_admin() or data ->> 'teacherId' = auth.uid()::text))
);

-- Seed education profiles for existing Aura X/Supabase Auth accounts. Aura X identities use the same auth.uid().
insert into public.education_records (collection_name, id, data)
select 'users', au.id::text,
  jsonb_build_object(
    'uid', au.id::text,
    'name', coalesce(ax.data ->> 'displayName', au.raw_user_meta_data ->> 'full_name', au.raw_user_meta_data ->> 'name', split_part(coalesce(au.email,''),'@',1), 'Öğrenci'),
    'email', coalesce(au.email, ax.data ->> 'authEmail', ''),
    'username', coalesce(ax.id, ''),
    'usernameLower', lower(coalesce(ax.id, '')),
    'auraxUsername', coalesce(ax.id, ''),
    'provider', case when ax.id is null then 'supabase' else 'aurax' end,
    'role', case when lower(coalesce(ax.id,'')) = lower('A_UR_A_XX') and lower(coalesce(ax.data ->> 'role','')) = 'admin' then 'admin' else 'student' end,
    'points', 0,
    'completedLessons', '[]'::jsonb,
    'completedTests', '[]'::jsonb,
    'avatarId', 'owl-blue',
    'createdAt', to_jsonb(extract(epoch from au.created_at)::bigint * 1000)
  )
from auth.users au
left join lateral (
  select u.id, u.data from public.users u where u.data ->> 'authUid' = au.id::text limit 1
) ax on true
on conflict (collection_name, id) do nothing;

-- If an earlier SQL attempt already created the Education profile as a student,
-- safely carry over only the reserved Aura X system-admin identity.
update public.education_records er
set data = jsonb_set(er.data, '{role}', to_jsonb('admin'::text), true), updated_at = now()
from public.users ax
where er.collection_name = 'users'
  and er.id = ax.data ->> 'authUid'
  and lower(ax.id) = lower('A_UR_A_XX')
  and lower(coalesce(ax.data ->> 'role','')) = 'admin'
  and coalesce(er.data ->> 'role','student') = 'student';

-- Future Auth accounts receive a default education profile. The frontend can safely enrich it after login.
create or replace function public.education_create_profile_for_auth_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_username text := lower(btrim(coalesce(new.raw_user_meta_data ->> 'username','')));
  v_name text := coalesce(nullif(btrim(new.raw_user_meta_data ->> 'display_name'),''), nullif(btrim(new.raw_user_meta_data ->> 'full_name'),''), nullif(btrim(new.raw_user_meta_data ->> 'name'),''), split_part(coalesce(new.email,''),'@',1), 'Öğrenci');
  v_claim_rows integer;
begin
  if v_username <> '' then
    if v_username !~ '^[a-z0-9._-]{3,24}$' then
      raise exception 'Kullanıcı adı 3–24 karakter olmalı; yalnızca harf, sayı, nokta, tire ve alt çizgi kullanılabilir.' using errcode = '22023';
    end if;
    if exists (select 1 from public.users au where lower(au.id) = v_username) then
      raise exception 'Bu kullanıcı adı Aura X üzerinde zaten kullanılıyor.' using errcode = '23505';
    end if;
    if exists (select 1 from public.education_records er where er.collection_name = 'usernameClaims' and lower(er.id) = v_username and coalesce(er.data ->> 'ownerUidHash','') <> encode(digest(new.id::text,'sha256'),'hex')) then
      raise exception 'Bu kullanıcı adı zaten seçilmiş.' using errcode = '23505';
    end if;
  end if;

  insert into public.education_records (collection_name, id, data)
  values ('users', new.id::text, jsonb_build_object(
    'uid', new.id::text,
    'name', v_name,
    'email', coalesce(new.email, ''),
    'username', nullif(v_username,''),
    'usernameLower', nullif(v_username,''),
    'role', 'student', 'points', 0, 'completedLessons', '[]'::jsonb,
    'completedTests', '[]'::jsonb, 'avatarId', 'owl-blue',
    'provider', 'supabase',
    'createdAt', jsonb_build_object('seconds', floor(extract(epoch from now()))::bigint, 'nanoseconds', 0)
  )) on conflict (collection_name, id) do nothing;

  if v_username <> '' then
    insert into public.education_records (collection_name, id, data)
    values ('usernameClaims', v_username, jsonb_build_object(
      'claimed', true,
      'ownerUidHash', encode(digest(new.id::text, 'sha256'),'hex'),
      'createdAt', jsonb_build_object('seconds', floor(extract(epoch from now()))::bigint, 'nanoseconds', 0)
    )) on conflict (collection_name, id) do nothing;
    get diagnostics v_claim_rows = row_count;
    if v_claim_rows = 0 and not exists (
      select 1 from public.education_records where collection_name = 'usernameClaims' and id = v_username
        and data ->> 'ownerUidHash' = encode(digest(new.id::text, 'sha256'),'hex')
    ) then
      raise exception 'Bu kullanıcı adı zaten seçilmiş.' using errcode = '23505';
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists education_auth_user_created on auth.users;
create trigger education_auth_user_created after insert on auth.users
for each row execute function public.education_create_profile_for_auth_user();

notify pgrst, 'reload schema';

-- This function is callable only by the trusted Edge Function (service_role). It grades once,
-- writes the result and updates points in one Postgres transaction to avoid duplicate rewards.
create or replace function public.education_grade_test(
  p_user_id uuid,
  p_test_id text,
  p_test_title text,
  p_answers jsonb,
  p_answer_key jsonb,
  p_wrong_focus jsonb default '[]'::jsonb,
  p_points_per_correct integer default 5,
  p_is_ready boolean default false
)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_profile jsonb;
  v_test_title text;
  v_existing jsonb;
  v_total integer;
  v_correct integer := 0;
  v_wrong integer;
  v_score integer;
  v_points integer := 0;
  v_completed jsonb;
  v_result_id text;
  v_result jsonb;
  i integer;
begin
  if p_user_id is null or p_test_id is null or length(btrim(p_test_id)) = 0 then
    raise exception 'Test bilgisi geçersiz.' using errcode = '22023';
  end if;
  if jsonb_typeof(p_answers) <> 'array' or jsonb_typeof(p_answer_key) <> 'array' then
    raise exception 'Cevap listesi geçersiz.' using errcode = '22023';
  end if;
  v_total := jsonb_array_length(p_answer_key);
  if v_total < 1 or jsonb_array_length(p_answers) <> v_total then
    raise exception 'Tüm sorular cevaplanmalı.' using errcode = '22023';
  end if;

  select data into v_profile
  from public.education_records
  where collection_name = 'users' and id = p_user_id::text
  for update;
  if v_profile is null then raise exception 'Kullanıcı profili bulunamadı.' using errcode = 'P0002'; end if;
  if coalesce(v_profile ->> 'role','student') <> 'student' then
    raise exception 'Bu işlem yalnızca öğrenci hesabında kullanılabilir.' using errcode = '42501';
  end if;

  v_result_id := p_user_id::text || '_' || p_test_id;
  select data into v_existing from public.education_records
  where collection_name = 'results' and id = v_result_id;
  if v_existing is not null then
    return jsonb_build_object(
      'score', coalesce((v_existing ->> 'score')::integer, 0),
      'correct', coalesce((v_existing ->> 'correct')::integer, 0),
      'wrong', coalesce((v_existing ->> 'wrong')::integer, 0),
      'pointsAwarded', coalesce((v_existing ->> 'pointsAwarded')::integer, 0),
      'alreadySubmitted', true,
      'wrongFocus', coalesce(v_existing -> 'wrongFocus', '[]'::jsonb)
    );
  end if;

  for i in 0..v_total-1 loop
    if (p_answers ->> i) !~ '^[0-9]+$' or (p_answer_key ->> i) !~ '^[0-9]+$' then
      raise exception 'Cevaplardan biri geçersiz.' using errcode = '22023';
    end if;
    if (p_answers ->> i)::integer < 0 or (p_answers ->> i)::integer > 5 then
      raise exception 'Cevaplardan biri geçersiz.' using errcode = '22023';
    end if;
    if (p_answers ->> i)::integer = (p_answer_key ->> i)::integer then v_correct := v_correct + 1; end if;
  end loop;

  v_wrong := v_total - v_correct;
  v_score := round((v_correct::numeric / v_total::numeric) * 100)::integer;
  v_points := case when p_is_ready then 0 else greatest(0, p_points_per_correct) * v_correct end;
  v_completed := case when jsonb_typeof(v_profile -> 'completedTests') = 'array' then v_profile -> 'completedTests' else '[]'::jsonb end;
  v_test_title := coalesce(nullif(p_test_title,''), p_test_id);

  v_result := jsonb_build_object(
    'studentId', p_user_id::text,
    'studentName', coalesce(v_profile ->> 'name','Öğrenci'),
    'testId', p_test_id,
    'testTitle', v_test_title,
    'correct', v_correct,
    'wrong', v_wrong,
    'score', v_score,
    'pointsAwarded', v_points,
    'wrongFocus', coalesce(p_wrong_focus, '[]'::jsonb),
    'createdAt', jsonb_build_object('seconds', floor(extract(epoch from clock_timestamp()))::bigint, 'nanoseconds', 0),
    'isReadyCurriculumTest', coalesce(p_is_ready, false)
  );

  insert into public.education_records (collection_name,id,data)
  values ('results',v_result_id,v_result);

  if not (v_completed ? p_test_id) then v_completed := v_completed || jsonb_build_array(p_test_id); end if;
  update public.education_records
  set data = v_profile || jsonb_build_object(
    'completedTests', v_completed,
    'points', coalesce((v_profile ->> 'points')::integer,0) + v_points
  )
  where collection_name = 'users' and id = p_user_id::text;

  return jsonb_build_object('score',v_score,'correct',v_correct,'wrong',v_wrong,'pointsAwarded',v_points,'alreadySubmitted',false,'wrongFocus',coalesce(p_wrong_focus,'[]'::jsonb));
end;
$$;
revoke all on function public.education_grade_test(uuid,text,text,jsonb,jsonb,jsonb,integer,boolean) from public, anon, authenticated;
grant execute on function public.education_grade_test(uuid,text,text,jsonb,jsonb,jsonb,integer,boolean) to service_role;

notify pgrst, 'reload schema';

-- Atomically transfer points between students who are friends in the Education social system.
create or replace function public.education_share_points(
  p_sender_id uuid,
  p_target_id uuid,
  p_amount integer
)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_sender jsonb;
  v_target jsonb;
  v_transfer_id text;
  v_now jsonb;
begin
  if p_sender_id is null or p_target_id is null or p_sender_id = p_target_id then
    raise exception 'Alıcı geçersiz.' using errcode = '22023';
  end if;
  if p_amount is null or p_amount < 20 or p_amount > 100 then
    raise exception '20–100 arasında puan seçmelisin.' using errcode = '22023';
  end if;

  -- Lock both profiles in a stable order so simultaneous transfers do not overspend points.
  perform 1 from public.education_records
  where collection_name = 'users' and id in (p_sender_id::text, p_target_id::text)
  order by id for update;

  select data into v_sender from public.education_records
  where collection_name = 'users' and id = p_sender_id::text;
  select data into v_target from public.education_records
  where collection_name = 'users' and id = p_target_id::text;
  if v_sender is null or v_target is null then
    raise exception 'Kullanıcı bulunamadı.' using errcode = 'P0002';
  end if;
  if coalesce(v_sender ->> 'role','student') <> 'student'
     or coalesce(v_target ->> 'role','student') <> 'student' then
    raise exception 'Puan yalnızca öğrenci hesapları arasında paylaşılabilir.' using errcode = '42501';
  end if;
  if coalesce((v_sender ->> 'points')::integer,0) < p_amount then
    raise exception 'Yeterli puanın yok.' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.education_records f
    where f.collection_name = 'friendships'
      and f.data -> 'members' @> jsonb_build_array(p_sender_id::text)
      and f.data -> 'members' @> jsonb_build_array(p_target_id::text)
  ) then
    raise exception 'Puan göndermek için önce öğrenciyle arkadaş olmalısın.' using errcode = '42501';
  end if;

  update public.education_records
  set data = v_sender || jsonb_build_object('points', coalesce((v_sender ->> 'points')::integer,0) - p_amount)
  where collection_name = 'users' and id = p_sender_id::text;
  update public.education_records
  set data = v_target || jsonb_build_object('points', coalesce((v_target ->> 'points')::integer,0) + p_amount)
  where collection_name = 'users' and id = p_target_id::text;

  v_transfer_id := gen_random_uuid()::text;
  v_now := jsonb_build_object('seconds', floor(extract(epoch from clock_timestamp()))::bigint, 'nanoseconds', 0);
  insert into public.education_records(collection_name, id, data)
  values ('pointTransfers', v_transfer_id, jsonb_build_object(
    'fromUid', p_sender_id::text,
    'toUid', p_target_id::text,
    'fromName', coalesce(v_sender ->> 'name', 'Öğrenci'),
    'toName', coalesce(v_target ->> 'name', 'Öğrenci'),
    'amount', p_amount,
    'createdAt', v_now
  ));
  insert into public.education_records(collection_name, id, data)
  values ('notifications', gen_random_uuid()::text, jsonb_build_object(
    'userId', p_target_id::text,
    'title', 'Puan aldın!',
    'body', coalesce(v_sender ->> 'name','Bir öğrenci') || ' sana ' || p_amount::text || ' puan gönderdi.',
    'type', 'points-received',
    'read', false,
    'createdAt', v_now,
    'actorUid', p_sender_id::text,
    'relatedId', v_transfer_id
  ));

  return jsonb_build_object(
    'senderPoints', coalesce((v_sender ->> 'points')::integer,0) - p_amount,
    'receiverPoints', coalesce((v_target ->> 'points')::integer,0) + p_amount
  );
end;
$$;
revoke all on function public.education_share_points(uuid,uuid,integer) from public, anon, authenticated;
grant execute on function public.education_share_points(uuid,uuid,integer) to service_role;

notify pgrst, 'reload schema';
