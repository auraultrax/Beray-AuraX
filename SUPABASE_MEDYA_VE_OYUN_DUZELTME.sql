-- Aura X: medya yükleme düzeltmesi + oda içi "Şişe Çevirme" oyunu izinleri
-- Supabase Dashboard -> SQL Editor'de BİR KEZ çalıştırın. Tamamen ekleme yapar; mevcut veri/politika silinmez
-- (yalnızca aynı adlı yeni politikalar yeniden oluşturulur). Tekrar çalıştırmak güvenlidir.

-- 1) "media" deposu: yoksa oluştur, herkese açık okuma, 100 MB dosya sınırı, tür kısıtı yok.
--    (Supabase ücretsiz planda genel üst sınır 50 MB'tır; uygulama zaten 50 MB ile sınırlar.)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('media', 'media', true, 104857600, null)
on conflict (id) do update
  set public = true,
      file_size_limit = greatest(coalesce(storage.buckets.file_size_limit, 0), 104857600),
      allowed_mime_types = null;

-- 2) Giriş yapmış kullanıcı media deposundaki dosyaları görebilsin (upsert/INSERT..RETURNING için gerekli).
drop policy if exists aurax_media_select on storage.objects;
create policy aurax_media_select on storage.objects
for select to authenticated, anon
using (bucket_id = 'media');

-- 3) Kullanıcı yalnızca kendi yollarındaki dosyaları güncelleyebilsin (aynı yol yeniden yüklenirse).
drop policy if exists aurax_media_update on storage.objects;
create policy aurax_media_update on storage.objects
for update to authenticated
using (
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
)
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

-- 4) Kullanıcı kendi yüklediği dosyayı silebilsin (gönderi/duyuru silinirken kullanılır).
drop policy if exists aurax_media_delete on storage.objects;
create policy aurax_media_delete on storage.objects
for delete to authenticated
using (
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

-- 5) Yükleme yolu: duyuru videoları da kullanıcı adıyla başlayan bir klasöre gidiyorsa izinli olsun.
--    (Mevcut INSERT politikası korunur; burada yalnızca ek, ayrı bir politika eklenir. Politikalar OR ile birleşir.)
drop policy if exists aurax_media_insert_extra on storage.objects;
create policy aurax_media_insert_extra on storage.objects
for insert to authenticated
with check (
  bucket_id = 'media'
  and (
    name like ('announcements/' || public.aurax_base_current_username(auth.uid()) || '_%')
    or name like ('announcementVideos/' || public.aurax_base_current_username(auth.uid()) || '_%')
    or name like ('announcementImages/' || public.aurax_base_current_username(auth.uid()) || '_%')
  )
);

-- 6) Oda üyeleri, üyesi oldukları odanın belgesini (mesaj, oyun durumu vb.) güncelleyebilsin.
--    Oda mesajları ve oyun durumu oda belgesinde tutulduğu için gereklidir. Odaya üye olmayan yazamaz.
drop policy if exists aurax_rooms_update_member on public.rooms;
create policy aurax_rooms_update_member on public.rooms
for update to authenticated
using (
  coalesce(data -> 'members', '[]'::jsonb) ? coalesce(public.aurax_base_current_username(auth.uid()), '')
)
-- WITH CHECK serbest: üye odadan çıkarken kendi adını members listesinden de silebilsin.
with check (true);
