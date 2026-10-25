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
do $$
declare
  v_email    text := 'BURAYA_ADMIN_EPOSTASINI_YAZ@ornek.com';   -- <== DEĞİŞTİR
  v_username text := 'A_UR_A_XX';
  v_uid      uuid;
  v_now_ms   bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
begin
  select id into v_uid from auth.users where lower(email) = lower(btrim(v_email)) limit 1;
  if v_uid is null then
    raise exception 'Bu e-posta Authentication > Users listesinde yok. Önce kullanıcıyı ekleyin (Auto Confirm işaretli).';
  end if;

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

  -- Beray Eğitim yönetici profili
  if to_regclass('public.education_records') is not null then
    insert into public.education_records (collection_name, id, data)
    values ('users', v_uid::text, jsonb_build_object(
      'uid', v_uid::text, 'name', 'A_UR_A_XX', 'email', lower(btrim(v_email)),
      'username', v_username, 'usernameLower', lower(v_username), 'auraxUsername', v_username,
      'provider', 'aurax', 'role', 'admin', 'points', 0,
      'completedLessons', '[]'::jsonb, 'completedTests', '[]'::jsonb, 'avatarId', 'owl-blue',
      'createdAt', jsonb_build_object('seconds', floor(extract(epoch from now()))::bigint, 'nanoseconds', 0)))
    on conflict (collection_name, id) do update
      set data = public.education_records.data || jsonb_build_object(
        'role', 'admin', 'username', v_username, 'usernameLower', lower(v_username),
        'auraxUsername', v_username, 'provider', 'aurax');
  end if;

  raise notice 'Tamam: % (%) yönetici olarak bağlandı. Aura X ve Eğitim''de kullanıcı adı A_UR_A_XX + yukarıda belirlediğiniz şifreyle girin.', v_username, v_uid;
end $$;


-- ======================================================================
-- ÖĞRETMEN / ÖĞRENCİ ROLÜ DEĞİŞTİRME  (Eğitim)
-- Normalde Eğitim > Öğretmen paneli > kullanıcı listesinden "Öğretmen Yap" ile yapılır
-- (yönetici girişi ve education-actions fonksiyonu gerekir). Panel kullanılamıyorsa
-- aşağıdakini KULLANICI ADINI değiştirip çalıştırın. Rol: 'teacher' veya 'student'.
-- Not: Tablo Editörü'nde "data" JSON alanını elle düzenlemeye çalışmayın; bu sorgu daha güvenlidir.
-- ======================================================================
-- update public.education_records er
-- set data = jsonb_set(er.data, '{role}', to_jsonb('teacher'::text), true)   -- 'teacher' | 'student'
-- where er.collection_name = 'users'
--   and lower(er.data ->> 'usernameLower') = lower('KULLANICI_ADI')
--   and coalesce(er.data ->> 'role','') <> 'admin';
