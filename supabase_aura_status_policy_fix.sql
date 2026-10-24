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
