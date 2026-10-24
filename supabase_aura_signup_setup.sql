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
