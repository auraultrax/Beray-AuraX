-- Aura X: beğeni, oylama ve gizli hesap oda davetleri düzeltmesi
-- Supabase SQL Editor'de BİR KEZ çalıştırın. Tekrar çalıştırmak güvenlidir; veri silmez.

-- 1) Gönderi beğenisi: başkasının gönderisini istemci doğrudan güncelleyemez (RLS), bu yüzden güvenli RPC.
create or replace function public.aurax_toggle_post_like(p_post text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me text := public.aurax_base_current_username(auth.uid());
  v_data jsonb;
  v_likes jsonb;
  v_has boolean;
begin
  if v_me is null or v_me = '' then raise exception 'Aura X oturumu bulunamadı.' using errcode = '28000'; end if;
  select p.data into v_data from public.posts p where p.id::text = p_post for update;
  if not found then raise exception 'Gönderi bulunamadı.' using errcode = 'P0002'; end if;
  v_likes := case when jsonb_typeof(v_data -> 'likedBy') = 'array' then v_data -> 'likedBy' else '[]'::jsonb end;
  v_has := v_likes ? v_me;
  if v_has then
    select coalesce(jsonb_agg(x.value), '[]'::jsonb) into v_likes
    from jsonb_array_elements(v_likes) as x(value) where x.value <> to_jsonb(v_me);
  else
    v_likes := v_likes || to_jsonb(v_me);
  end if;
  update public.posts set data = jsonb_set(v_data, '{likedBy}', v_likes, true), updated_at = now() where id::text = p_post;
  return jsonb_build_object('liked', not v_has, 'likedBy', v_likes);
end;
$$;
revoke all on function public.aurax_toggle_post_like(text) from public, anon;
grant execute on function public.aurax_toggle_post_like(text) to authenticated;

-- 2) Oylama: oy kaydını yazar ve sayaç artırır (kendine/yöneticiye/ikinci kez oy yok).
create or replace function public.aurax_cast_vote(p_target text)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me text := public.aurax_base_current_username(auth.uid());
  v_id text;
  v_rows integer;
  v_votes integer;
begin
  if v_me is null or v_me = '' then raise exception 'Aura X oturumu bulunamadı.' using errcode = '28000'; end if;
  if p_target is null or p_target = v_me then raise exception 'Kendinize oy veremezsiniz.' using errcode = '22023'; end if;
  if not exists (select 1 from public.users u where u.id = p_target) then raise exception 'USER_NOT_FOUND' using errcode = 'P0002'; end if;
  if exists (select 1 from public.users u where u.id = p_target and u.data ->> 'role' = 'admin') then
    raise exception 'Sistem yöneticisi oylamaya tabi değildir.' using errcode = '22023';
  end if;
  v_id := regexp_replace(v_me || '__' || p_target, '[^a-zA-Z0-9_-]', '_', 'g');
  insert into public.votes (id, data)
  values (v_id, jsonb_build_object('voter', v_me, 'target', p_target, 'createdAt', (extract(epoch from clock_timestamp()) * 1000)::bigint))
  on conflict (id) do nothing;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then raise exception 'ALREADY_VOTED' using errcode = '23505'; end if;
  update public.users
     set data = jsonb_set(data, '{votes}', to_jsonb(coalesce(nullif(data ->> 'votes', '')::integer, 0) + 1), true), updated_at = now()
   where id = p_target
   returning coalesce(nullif(data ->> 'votes', '')::integer, 0) into v_votes;
  return v_votes;
end;
$$;
revoke all on function public.aurax_cast_vote(text) from public, anon;
grant execute on function public.aurax_cast_vote(text) to authenticated;

-- 3) Bildirimler: gönderen kendi adına bildirim yazabilsin, alıcı okundu/yanıt güncelleyip silebilsin.
drop policy if exists aurax_notifications_insert_from on public.notifications;
create policy aurax_notifications_insert_from on public.notifications
for insert to authenticated
with check (data ->> 'from' = coalesce(public.aurax_base_current_username(auth.uid()), '') or data ->> 'to' = coalesce(public.aurax_base_current_username(auth.uid()), ''));

drop policy if exists aurax_notifications_update_to on public.notifications;
create policy aurax_notifications_update_to on public.notifications
for update to authenticated
using (data ->> 'to' = coalesce(public.aurax_base_current_username(auth.uid()), ''))
with check (data ->> 'to' = coalesce(public.aurax_base_current_username(auth.uid()), ''));

drop policy if exists aurax_notifications_delete_to on public.notifications;
create policy aurax_notifications_delete_to on public.notifications
for delete to authenticated
using (data ->> 'to' = coalesce(public.aurax_base_current_username(auth.uid()), ''));

-- 4) Gizli hesap oda daveti: kullanıcı "Evet" derse odaya yalnızca bu RPC ile eklenir.
create or replace function public.aurax_accept_room_invite(p_notification text)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me text := public.aurax_base_current_username(auth.uid());
  v_n jsonb;
  v_room text;
  v_from text;
begin
  if v_me is null or v_me = '' then raise exception 'Aura X oturumu bulunamadı.' using errcode = '28000'; end if;
  select n.data into v_n from public.notifications n where n.id::text = p_notification for update;
  if not found or v_n ->> 'to' <> v_me or v_n ->> 'type' <> 'room_join_request' then
    raise exception 'Davet bulunamadı.' using errcode = 'P0002';
  end if;
  if coalesce(v_n ->> 'inviteStatus', 'pending') <> 'pending' then
    raise exception 'Bu davet zaten yanıtlanmış.' using errcode = '22023';
  end if;
  v_room := v_n ->> 'roomId';
  v_from := v_n ->> 'from';
  -- Davet, gerçekten odanın yöneticisi/kurucusu tarafından gönderilmiş olmalı.
  if not exists (
    select 1 from public.rooms r
    where r.id::text = v_room
      and coalesce(r.data ->> 'deleted', 'false') <> 'true'
      and (r.data ->> 'admin' = v_from or coalesce(r.data -> 'admins', '[]'::jsonb) ? v_from)
  ) then
    raise exception 'Davet geçersiz veya oda artık yok.' using errcode = '22023';
  end if;
  update public.rooms r
     set data = jsonb_set(r.data, '{members}',
           case when jsonb_typeof(r.data -> 'members') = 'array' then r.data -> 'members' else '[]'::jsonb end || to_jsonb(v_me), true),
         updated_at = now()
   where r.id::text = v_room
     and not (coalesce(r.data -> 'members', '[]'::jsonb) ? v_me)
     and not (coalesce(r.data -> 'restrictedMembers', '[]'::jsonb) ? v_me);
  update public.notifications n
     set data = n.data || jsonb_build_object('inviteStatus', 'accepted', 'read', true), updated_at = now()
   where n.id::text = p_notification;
  return v_room;
end;
$$;
revoke all on function public.aurax_accept_room_invite(text) from public, anon;
grant execute on function public.aurax_accept_room_invite(text) to authenticated;
