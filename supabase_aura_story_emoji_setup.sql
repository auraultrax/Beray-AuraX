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
