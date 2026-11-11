-- =====================================================================
-- AVATARES DE LOS CLIENTES (2026.11.11-a)
-- Cada cliente se monta su muñeco con opciones cerradas (piel, pelo, barba,
-- gafas, gorra/sombrero, ropa, expresión y colores de una paleta fija).
-- Sale en Barman Exprés como cliente de la barra y en «La cola de La Burbuja».
-- Se guarda por email: no se pierde al renovar el cupón.
-- Se puede ejecutar varias veces; no borra datos.
-- =====================================================================

create table if not exists public.avatars (
  email      text primary key,
  spec       jsonb not null,
  updated_at timestamptz not null default now()
);
alter table public.avatars enable row level security;
drop policy if exists avatars_select on public.avatars;
create policy avatars_select on public.avatars for select to authenticated using (public.is_owner());  -- copia de seguridad
grant select on public.avatars to authenticated;

-- Valores permitidos: un número dentro de su lista o un color de la paleta. Cualquier otra cosa se descarta.
create or replace function public.avatar_int(p jsonb, k text, mx int)
returns int language sql immutable as $$
  select case when coalesce(p->>k, '') ~ '^[0-9]{1,2}$' and (p->>k)::int <= mx then (p->>k)::int else 0 end
$$;
create or replace function public.avatar_col(p jsonb, k text, opts text[], def text)
returns text language sql immutable as $$
  select case when lower(coalesce(p->>k, '')) = any(opts) then lower(p->>k) else def end
$$;
create or replace function public.avatar_clean(p jsonb)
returns jsonb language plpgsql immutable set search_path = public as $$
declare
  skins  text[] := array['#f6d3b3','#eac2a0','#e0ac69','#c68642','#a86b3c','#8d5524','#5e3a1e','#3d2614'];
  hairs  text[] := array['#0f0b0a','#2b1d14','#4a2f1d','#7a4b2a','#b07a3c','#d9b26a','#efe0b4','#a33a1f','#8f8f8f','#e6e6e6','#d94f9c','#3d7bd9'];
  shirts text[] := array['#c7a84d','#c0392b','#2f6fd6','#2e9d5b','#8e44ad','#e67e22','#16a2b8','#d35480','#7f8c8d','#1d1d1d','#f4f1e6','#6b4423'];
begin
  if p is null or jsonb_typeof(p) <> 'object' or length(p::text) > 1000 then raise exception 'bad_avatar'; end if;
  return jsonb_build_object(
    'skin',    avatar_col(p, 'skin',  skins,  '#e0ac69'),
    'hair',    avatar_int(p, 'hair', 7),
    'hairC',   avatar_col(p, 'hairC', hairs,  '#2b1d14'),
    'beard',   avatar_int(p, 'beard', 4),
    'glasses', avatar_int(p, 'glasses', 3),
    'hat',     avatar_int(p, 'hat', 3),
    'hatC',    avatar_col(p, 'hatC',  shirts, '#c0392b'),
    'shirt',   avatar_col(p, 'shirt', shirts, '#2f6fd6'),
    'top',     avatar_int(p, 'top', 4),
    'expr',    avatar_int(p, 'expr', 2));
end $$;

-- CLIENTE: su avatar (null si todavía no lo ha hecho)
create or replace function public.my_avatar()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform require_customer();
  return (select spec from avatars where email = lower(auth.jwt() ->> 'email'));
end $$;

-- CLIENTE: guarda su avatar
create or replace function public.set_my_avatar(p_spec jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_email text; v jsonb := avatar_clean(p_spec);
begin
  perform require_customer();
  v_email := lower(auth.jwt() ->> 'email');
  insert into avatars (email, spec, updated_at) values (v_email, v, now())
    on conflict (email) do update set spec = excluded.spec, updated_at = now();
  return v;
end $$;

-- JUEGOS: el avatar de quien juega y hasta 24 de otros clientes, al azar
create or replace function public.game_avatars()
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  return jsonb_build_object(
    'me', (select spec from avatars where email = v_me and v_me <> ''),
    'others', coalesce((select jsonb_agg(x.spec) from (select spec from avatars where email <> v_me order by random() limit 24) x), '[]'::jsonb));
end $$;

-- LA COLA DE LA BURBUJA: igual que antes, y ahora con el avatar de cada uno ('av')
create or replace function public.fans_queue()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_me text := lower(coalesce(auth.jwt() ->> 'email', '')); r jsonb;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  with gp as (
    select c.email, sum(l.delta) as pts from points_log l join coupons c on c.id = l.coupon_id
     where l.reason = 'game' and l.delta > 0 group by c.email),
  st as (
    select c.email, count(*) as n from stamps s join coupons c on c.id = s.coupon_id
     where coalesce(s.source, '') <> 'points' and (s.deleted_at is null or s.renewed_at is not null) group by c.email),
  people as (
    select a.email, a.name, a.number, coalesce(gp.pts, 0) + 300 * coalesce(st.n, 0) as score
      from coupons a left join gp on gp.email = a.email left join st on st.email = a.email
     where a.status = 'active'),
  rk as (select *, row_number() over (order by score desc, number asc) as pos from people where score > 0)
  select jsonb_build_object(
    'top', coalesce((select jsonb_agg(jsonb_build_object('pos', pos, 'name', board_name(name, number), 'score', score,
                                                         'me', email = v_me, 'seed', left(md5(email), 10),
                                                         'av', (select v.spec from avatars v where v.email = lower(rk.email))) order by pos)
                       from rk where pos <= 10), '[]'::jsonb),
    'me', (select jsonb_build_object('pos', pos, 'score', score, 'name', board_name(name, number), 'seed', left(md5(email), 10)) from rk where email = v_me),
    'tenth', (select score from rk where pos = 10),
    'total', (select count(*) from rk)) into r;
  return r;
end $$;

-- PROPIETARIO: restaurar avatares desde una copia de seguridad (solo durante una restauración)
create or replace function public.restore_avatars(p_rows jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not is_owner() then raise exception 'forbidden'; end if;
  if coalesce((select value from app_config where key = 'restore_open'), '') <> '1' then raise exception 'forbidden'; end if;
  insert into avatars (email, spec, updated_at)
  select lower(r->>'email'), avatar_clean(r->'spec'), coalesce(nullif(r->>'updated_at', '')::timestamptz, now())
    from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) r
   where coalesce(r->>'email', '') <> '' and jsonb_typeof(r->'spec') = 'object'
  on conflict (email) do update set spec = excluded.spec, updated_at = excluded.updated_at;
  get diagnostics n = row_count;
  return n;
end $$;

revoke execute on function public.avatar_int(jsonb, text, int), public.avatar_col(jsonb, text, text[], text),
                           public.avatar_clean(jsonb), public.my_avatar(), public.set_my_avatar(jsonb),
                           public.game_avatars(), public.fans_queue(), public.restore_avatars(jsonb) from public, anon;
grant execute on function public.avatar_int(jsonb, text, int), public.avatar_col(jsonb, text, text[], text),
                          public.avatar_clean(jsonb), public.my_avatar(), public.set_my_avatar(jsonb),
                          public.game_avatars(), public.fans_queue(), public.restore_avatars(jsonb) to authenticated;
