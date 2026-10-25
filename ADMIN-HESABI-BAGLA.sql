-- ======================================================================
-- A_UR_A_XX YÖNETİCİ HESABINI BAĞLA  (mevcut hiçbir tabloyu/fonksiyonu değiştirmez)
--
-- NEDEN GEREKLİ?
-- Aura X girişi artık "kullanıcı adı -> Supabase Auth e-postası" eşlemesiyle çalışır
-- (username-login fonksiyonu). A_UR_A_XX eski sistemden kaldıysa public.users
-- kaydında authUid / authEmail yoktur; bu yüzden şifre doğru olsa bile
-- "Hatalı kullanıcı adı veya şifre" alırsınız. Bu dosya o bağı kurar.
--
-- ÖNCE (bir kerelik):
--   Supabase Dashboard -> Authentication -> Users -> Add user -> Create new user
--   * E-posta: size ait gerçek bir adres
--   * Şifre  : yeni, güçlü bir şifre (eski "Muhammed.2009" artık herkese açık sayılmalı)
--   * "Auto Confirm User" kutusunu İŞARETLEYİN
--
-- SONRA: aşağıdaki v_email değerini o e-posta ile değiştirip SQL Editor'de çalıştırın.
-- Tekrar çalıştırmak güvenlidir.
-- ======================================================================
-- Canlı veritabanında aynı adlı iki aurax_is_admin fonksiyonu olması "is not unique" hatasına yol açar.
-- Parametreli (uuid) kopyayı kaldırır; parametresiz olan (eski kurulumun kullandığı) kalır.
do $$
begin
  begin
    drop function if exists public.aurax_is_admin(uuid);
  exception when dependent_objects_still_exist then
    null;
  end;
  if to_regprocedure('public.aurax_is_admin()') is null and to_regprocedure('public.aurax_base_is_admin(uuid)') is not null then
    execute 'create function public.aurax_is_admin() returns boolean language sql stable security definer set search_path = public as $f$ select public.aurax_base_is_admin(auth.uid()) $f$';
    execute 'grant execute on function public.aurax_is_admin() to authenticated, service_role';
  end if;
end $$;

do $$
declare
  v_email    text := 'BURAYA_ADMIN_EPOSTASINI_YAZ@ornek.com';   -- <== 1) SADECE BU İKİ SATIRI DEĞİŞTİR
  v_password text := 'BURAYA_YENI_SIFRENI_YAZ';                  -- <== 2) en az 8 karakter
  v_username text := 'A_UR_A_XX';
  v_uid      uuid;
  v_now_ms   bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
begin
  select id into v_uid from auth.users where lower(email) = lower(btrim(v_email)) limit 1;
  if v_uid is null then
    raise exception 'Bu e-posta Authentication > Users listesinde yok. Listede görünen e-postayı birebir yazın.';
  end if;
  if length(coalesce(v_password,'')) < 8 or v_password like 'BURAYA_%' then
    raise exception 'v_password satırına en az 8 karakterlik yeni şifrenizi yazın.';
  end if;

  -- Şifreyi bu şifreyle değiştir ve e-postayı onaylı yap (Dashboard'da hiçbir şey yapmanıza gerek kalmaz).
  update auth.users
     set encrypted_password = extensions.crypt(v_password, extensions.gen_salt('bf')),
         email_confirmed_at = coalesce(email_confirmed_at, now()),
         updated_at = now()
   where id = v_uid;

  -- Aura X profili (varsa korunur, yalnızca bağ alanları ve rol güncellenir)
  insert into public.users (id, data)
  values (v_username, jsonb_build_object(
    'username', v_username, 'firstName', 'A_UR_A', 'lastName', 'XX', 'displayName', 'A_UR_A_XX',
    'authUid', v_uid::text, 'authEmail', lower(btrim(v_email)), 'authProvider', 'email',
    'role', 'admin', 'restricted', false, 'banned', false, 'votes', 0,
    'followers', '[]'::jsonb, 'following', '[]'::jsonb, 'verified', true, 'special', true,
    'createdAt', v_now_ms, 'lastSeenAt', v_now_ms))
  on conflict (id) do update
    set data = public.users.data || jsonb_build_object(
      'authUid', v_uid::text, 'authEmail', lower(btrim(v_email)), 'role', 'admin');

  -- Hesap bağlantısı (uid -> kullanıcı adı)
  insert into public.account_links (id, data)
  values (v_uid::text, jsonb_build_object('username', v_username, 'authUid', v_uid::text, 'createdAt', v_now_ms))
  on conflict (id) do update
    set data = public.account_links.data || jsonb_build_object('username', v_username, 'authUid', v_uid::text);

  raise notice 'Tamam: % (%) yönetici olarak bağlandı. Aura X''te kullanıcı adı A_UR_A_XX + yukarıda belirlediğiniz şifreyle girin.', v_username, v_uid;
end $$;
