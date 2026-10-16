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
