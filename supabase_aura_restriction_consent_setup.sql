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
