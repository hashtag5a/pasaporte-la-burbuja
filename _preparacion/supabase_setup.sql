-- =====================================================================
--  PASAPORTE LA BURBUJA · Configuración de la base de datos (Supabase)
--  Pégalo ENTERO en: SQL Editor -> New query -> Run
--  Se puede ejecutar más de una vez sin problema.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. TABLAS
-- ---------------------------------------------------------------------

-- Ajustes internos (el email que podrá reclamar el rol de propietario)
create table if not exists public.app_config (
  key   text primary key,
  value text not null
);
insert into public.app_config (key, value)
values ('owner_bootstrap_email', 'PON_AQUI_TU_EMAIL')
on conflict (key) do nothing;

-- Propietario (se identifica por usuario, no por email, para poder cambiar el email)
create table if not exists public.owners (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

-- Invitaciones para nuevos propietarios (entran con ese email y quedan como propietarios)
create table if not exists public.owner_invites (
  email      text primary key,
  invited_by uuid,
  created_at timestamptz not null default now()
);

-- Registro de aceptación de la política de protección de datos (prueba del consentimiento).
-- Sin vínculo con la cuenta a propósito: el registro se conserva aunque se borre el cupón o la cuenta.
create table if not exists public.consents (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid,
  email       text not null,
  version     text not null,
  accepted_at timestamptz not null default now(),
  unique (email, version)
);

-- Diseños (solo se conserva el actual y los que aún usen cupones)
create table if not exists public.designs (
  id          uuid primary key default gen_random_uuid(),
  cover_path  text,          -- null = portada por defecto (la incluida en la página)
  inside_path text,          -- null = contraportada por defecto
  layout      jsonb,         -- null = distribución por defecto de las casillas
  ar          numeric,       -- proporción ancho/alto de la contraportada
  created_at  timestamptz not null default now()
);

-- Una sola fila: diseño actual y sello activo
create table if not exists public.settings (
  id                int primary key default 1 check (id = 1),
  current_design_id uuid references public.designs(id),
  seal_path         text      -- null = sello por defecto
);

do $$
declare d uuid;
begin
  if not exists (select 1 from public.settings) then
    insert into public.designs default values returning id into d;
    insert into public.settings (id, current_design_id) values (1, d);
  end if;
end $$;

-- Cupones
create sequence if not exists public.coupon_number_seq minvalue 0 start 0;
alter sequence public.coupon_number_seq minvalue 0;   -- el primer cupón es el 00000

create table if not exists public.coupons (
  id          uuid primary key default gen_random_uuid(),
  number      bigint not null unique default nextval('public.coupon_number_seq'),
  customer_id uuid not null references auth.users(id) on delete cascade,
  email       text not null,
  name        text,
  qr_token    text not null unique default replace(gen_random_uuid()::text, '-', ''),
  status      text not null default 'active' check (status in ('active', 'deleted')),
  design_id   uuid references public.designs(id) on delete set null,
  created_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  completed   int not null default 0   -- veces que se ha completado y renovado
);
alter table public.coupons add column if not exists completed int not null default 0;
-- Un cupón restaurado desde una copia de seguridad no tiene cuenta hasta que su cliente entra con su email
alter table public.coupons alter column customer_id drop not null;
-- Si la tabla ya existía de una ejecución anterior, la regla anterior no llevaba "on delete set null"
alter table public.coupons drop constraint if exists coupons_design_id_fkey;
alter table public.coupons add constraint coupons_design_id_fkey
  foreign key (design_id) references public.designs(id) on delete set null;
-- Un cliente solo puede tener un cupón activo a la vez
create unique index if not exists one_active_coupon_per_customer
  on public.coupons (customer_id) where status = 'active';
create index if not exists coupons_email_idx on public.coupons (lower(email));

-- Sellos (el borrado deja constancia: no se elimina la fila)
create table if not exists public.stamps (
  id         uuid primary key default gen_random_uuid(),
  coupon_id  uuid not null references public.coupons(id) on delete cascade,
  box        int  not null check (box between 1 and 10),
  stamped_at timestamptz not null default now(),
  stamped_by uuid,
  image_path text,            -- imagen del sello en el momento de ponerlo
  deleted_at timestamptz,
  deleted_by uuid,
  redeemed_at timestamptz,    -- premio canjeado (solo casillas 3, 5, 7 y 10)
  redeemed_by uuid
);
alter table public.stamps add column if not exists redeemed_at timestamptz;
alter table public.stamps add column if not exists redeemed_by uuid;
create unique index if not exists one_active_stamp_per_box
  on public.stamps (coupon_id, box) where deleted_at is null;

-- Dispositivos autorizados (y altas pendientes con código de 10 minutos)
create table if not exists public.devices (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  user_id     uuid unique references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now(),
  last_access timestamptz,
  code_hash   text,
  code_expires timestamptz
);

-- Registro de acciones y de intentos fallidos de código
create table if not exists public.audit_log (
  id     bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  actor  uuid,
  action text not null,
  detail jsonb
);
create table if not exists public.redeem_failures (
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- JUEGOS: Búsqueda del Tesoro ('treasure'), Búsqueda del Tesoro Interactivo ('quiz') y Sello Sorpresa ('scratch')
-- ---------------------------------------------------------------------
create table if not exists public.games (
  id           uuid primary key default gen_random_uuid(),
  kind         text not null check (kind in ('treasure', 'quiz', 'scratch')),
  name         text not null,
  starts_at    timestamptz not null,
  ends_at      timestamptz not null,
  stopped_at   timestamptz,                 -- parada manual del propietario
  prize_mode   text not null check (prize_mode in ('single', 'random')),
  single_prize text,                        -- regalo único (modo 'single')
  consolation  text,                        -- regalo de consolación (opcional, sin límite)
  no_prize_msg text,                        -- mensaje cuando no hay premio
  cells        int,                         -- tesoro / interactivo: número de casillas (= número de QRs)
  img_a        text,                        -- imagen opcional: portada de la tarjeta / capa para rascar
  img_b        text,                        -- imagen opcional: reverso de la tarjeta / fondo del premio
  created_at   timestamptz not null default now(),
  created_by   uuid,
  check (ends_at > starts_at)
);
-- Regalos con unidades limitadas (modo 'random')
create table if not exists public.game_prizes (
  id        uuid primary key default gen_random_uuid(),
  game_id   uuid not null references public.games(id) on delete cascade,
  pos       int not null default 0,
  name      text not null,
  units     int not null check (units >= 0),
  remaining int not null check (remaining >= 0)
);
-- QRs del local (tesoro) o preguntas (interactivo)
create table if not exists public.game_spots (
  id       uuid primary key default gen_random_uuid(),
  game_id  uuid not null references public.games(id) on delete cascade,
  idx      int not null,
  label    text,                            -- dónde está el QR (solo lo ve el propietario)
  token    text not null unique default replace(gen_random_uuid()::text, '-', ''),
  question text,                            -- interactivo
  answer   text,                            -- interactivo (nunca se envía al cliente)
  unique (game_id, idx)
);
-- Tarjeta de cada cupón en cada juego (una por cupón y por juego)
create table if not exists public.game_cards (
  id           uuid primary key default gen_random_uuid(),
  game_id      uuid not null references public.games(id) on delete cascade,
  coupon_id    uuid not null references public.coupons(id) on delete cascade,
  created_at   timestamptz not null default now(),
  completed_at timestamptz,                 -- tarjeta llena / rasca generado: momento en que se obtuvo el premio
  prize_kind   text check (prize_kind in ('prize', 'consolation', 'none')),
  prize        text,
  prize_id     uuid,
  revealed_at  timestamptz,                 -- el cliente ha rascado / visto el reverso
  delivered_at timestamptz,
  delivered_by uuid,
  unique (game_id, coupon_id)
);
-- QRs encontrados / preguntas acertadas
create table if not exists public.game_finds (
  card_id  uuid not null references public.game_cards(id) on delete cascade,
  spot_id  uuid not null references public.game_spots(id) on delete cascade,
  found_at timestamptz not null default now(),
  primary key (card_id, spot_id)
);

-- ---------------------------------------------------------------------
-- JUEGOS FUERA DE CONCIERTO ('puzzle', 'memory', 'beat', 'barman') y PUNTOS
-- ---------------------------------------------------------------------
alter table public.games drop constraint if exists games_kind_check;
alter table public.games add constraint games_kind_check
  check (kind in ('treasure', 'quiz', 'scratch', 'puzzle', 'memory', 'beat', 'barman'));
alter table public.games add column if not exists reward_mode text not null default 'prize';  -- 'prize' | 'points'
alter table public.games add column if not exists points int;                                -- puntos que da (modo 'points')
alter table public.games add column if not exists config jsonb;                              -- ajustes propios de cada juego
alter table public.game_cards drop constraint if exists game_cards_prize_kind_check;
alter table public.game_cards add constraint game_cards_prize_kind_check
  check (prize_kind in ('prize', 'consolation', 'none', 'points'));
alter table public.game_cards add column if not exists declined_at timestamptz;      -- dijo NO al aviso de la portada
alter table public.game_cards add column if not exists play_started_at timestamptz;  -- inicio de la partida en curso
alter table public.game_cards add column if not exists points int;                   -- puntos ganados

-- Puntos: saldo en el cupón, equivalencia en ajustes y registro de movimientos
alter table public.coupons add column if not exists points int not null default 0;
alter table public.stamps add column if not exists source text;                      -- 'points' si el sello vino de puntos
alter table public.settings add column if not exists points_per_stamp int not null default 100;
create table if not exists public.points_log (
  id         bigint generated always as identity primary key,
  coupon_id  uuid references public.coupons(id) on delete cascade,
  delta      int not null,
  reason     text,
  game_id    uuid,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- JUEGOS CON CLASIFICACIÓN ('beat', 'barman')
-- ---------------------------------------------------------------------
alter table public.game_cards add column if not exists best_score int;           -- mejor puntuación del cliente en ese juego
alter table public.game_cards add column if not exists best_at timestamptz;      -- cuándo la consiguió (desempata: gana quien llegó antes)
alter table public.game_cards add column if not exists score_removed boolean not null default false;  -- quitada de la clasificación por el propietario
alter table public.games add column if not exists finalized_at timestamptz;      -- premios por puesto ya repartidos
-- Premios por puesto en la clasificación (se reparten al terminar el juego; caducan a los 30 días)
create table if not exists public.game_awards (
  id           uuid primary key default gen_random_uuid(),
  game_id      uuid not null references public.games(id) on delete cascade,
  coupon_id    uuid not null references public.coupons(id) on delete cascade,
  pos          int not null,
  prize        text not null,
  score        int,
  awarded_at   timestamptz not null default now(),
  delivered_at timestamptz,
  delivered_by uuid,
  unique (game_id, pos)
);

-- ---------------------------------------------------------------------
-- PERSONAJES de Barman Exprés (caricaturas de habituales, personal y músicos) y FONDO DE LA BARRA
-- ---------------------------------------------------------------------
create table if not exists public.characters (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  grp        text not null default 'regular' check (grp in ('regular', 'staff', 'musician')),
  spec       jsonb not null default '{}'::jsonb,   -- cómo se dibuja: piel, pelo, barba, gafas, gorra, ropa, expresión
  active     boolean not null default true,        -- sale en Barman Exprés
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.settings add column if not exists bar_bg_path text;
alter table public.settings add column if not exists door_bg_path text;
-- MODO EVENTO: mientras tiene un juego, los clientes solo ven la portada y al tocarla entran en ese juego (sin necesidad de sello)
alter table public.settings add column if not exists event_game_id uuid references public.games(id) on delete set null;  -- fachada de «La cola de La Burbuja» (portada)
-- Sellos archivados al renovar un cupón (siguen contando como conciertos en la cola de La Burbuja)
alter table public.stamps add column if not exists renewed_at timestamptz;  -- foto de la barra convertida en dibujo (fondo de Barman Exprés)

-- ---------------------------------------------------------------------
-- PRÓXIMOS CONCIERTOS (carteles en las casillas libres del cupón) y COMPRA DE ENTRADAS
-- ---------------------------------------------------------------------
create table if not exists public.concerts (
  id             uuid primary key default gen_random_uuid(),
  title          text not null,
  starts_at      timestamptz not null,
  poster_path    text not null,                    -- cartel (en el almacén 'assets', carpeta concerts/)
  price_cents    int check (price_cents is null or price_cents >= 0),   -- precio de la entrada en céntimos (opcional)
  discount_kind  text check (discount_kind in ('eur', 'pct')),          -- descuento comprando desde el pasaporte
  discount_value numeric(10,2) check (discount_value is null or discount_value > 0),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index if not exists concerts_starts_idx on public.concerts (starts_at);
-- Compras de entradas (preparado para la pasarela de pago: Redsys, Stripe…). El importe lo calcula siempre el servidor.
create table if not exists public.ticket_orders (
  id             uuid primary key default gen_random_uuid(),
  concert_id     uuid references public.concerts(id) on delete set null,
  coupon_id      uuid references public.coupons(id) on delete set null,
  customer_id    uuid,
  email          text,
  concert_title  text,
  concert_at     timestamptz,
  price_cents    int not null,
  discount_cents int not null default 0,
  total_cents    int not null,
  status         text not null default 'pending' check (status in ('pending', 'paid', 'failed', 'cancelled', 'refunded')),
  provider       text,                             -- 'redsys', 'stripe'… (cuando se contrate)
  provider_ref   text,                             -- referencia del pago en la pasarela
  created_at     timestamptz not null default now(),
  paid_at        timestamptz,
  refunded_at    timestamptz
);
create index if not exists ticket_orders_concert_idx on public.ticket_orders (concert_id);
alter table public.settings add column if not exists tickets_enabled boolean not null default false;  -- venta de entradas activada (cuando haya pasarela)

-- ---------------------------------------------------------------------
-- 2. FUNCIONES AUXILIARES DE PERMISOS
-- ---------------------------------------------------------------------

create or replace function public.is_owner()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.owners where user_id = auth.uid());
$$;

create or replace function public.is_staff()
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_owner()
      or exists (select 1 from public.devices where user_id = auth.uid());
$$;

-- ---------------------------------------------------------------------
-- 3. FUNCIONES (lo único que la página puede ejecutar para modificar datos)
-- ---------------------------------------------------------------------

-- El primer usuario que entre con el email configurado pasa a ser propietario
create or replace function public.claim_owner()
returns boolean language plpgsql security definer set search_path = public as $$
declare v_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if auth.uid() is null or v_email = '' or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then return false; end if;
  if exists (select 1 from owners where user_id = auth.uid()) then return true; end if;
  -- invitado por un propietario
  if exists (select 1 from owner_invites where email = v_email) then
    insert into owners (user_id) values (auth.uid()) on conflict do nothing;
    delete from owner_invites where email = v_email;
    insert into audit_log (actor, action, detail) values (auth.uid(), 'owner_joined', jsonb_build_object('email', v_email));
    return true;
  end if;
  -- primer propietario: el email configurado en app_config
  if not exists (select 1 from owners)
     and v_email = lower((select value from app_config where key = 'owner_bootstrap_email')) then
    insert into owners (user_id) values (auth.uid());
    insert into audit_log (actor, action) values (auth.uid(), 'owner_claimed');
    return true;
  end if;
  return false;
end $$;

-- PROPIETARIO: lista de propietarios (con email) e invitaciones pendientes
create or replace function public.list_owners()
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not is_owner() then raise exception 'forbidden'; end if;
  return coalesce((
    select jsonb_agg(x order by x->>'pending', x->>'created_at') from (
      select jsonb_build_object('id', o.user_id, 'email', u.email, 'me', o.user_id = auth.uid(), 'pending', false, 'created_at', o.created_at) as x
        from owners o left join auth.users u on u.id = o.user_id
      union all
      select jsonb_build_object('id', null, 'email', i.email, 'me', false, 'pending', true, 'created_at', i.created_at)
        from owner_invites i
    ) q), '[]'::jsonb);
end $$;

-- PROPIETARIO: invitar a otro propietario por email
create or replace function public.add_owner(p_email text)
returns text language plpgsql security definer set search_path = public as $$
declare v_email text := lower(trim(coalesce(p_email, '')));
begin
  if not is_owner() then raise exception 'forbidden'; end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'bad_email'; end if;
  if exists (select 1 from owners o join auth.users u on u.id = o.user_id where lower(u.email) = v_email) then
    raise exception 'already_owner';
  end if;
  insert into owner_invites (email, invited_by) values (v_email, auth.uid())
    on conflict (email) do update set created_at = now(), invited_by = auth.uid();
  insert into audit_log (actor, action, detail) values (auth.uid(), 'owner_invite', jsonb_build_object('email', v_email));
  return 'ok';
end $$;

-- PROPIETARIO: cancelar una invitación pendiente
create or replace function public.cancel_owner_invite(p_email text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_owner() then raise exception 'forbidden'; end if;
  delete from owner_invites where email = lower(trim(coalesce(p_email, '')));
end $$;

-- PROPIETARIO: quitar a otro propietario (nunca a uno mismo, siempre queda al menos uno)
create or replace function public.remove_owner(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_owner() then raise exception 'forbidden'; end if;
  if p_id = auth.uid() then raise exception 'cannot_remove_self'; end if;
  delete from owners where user_id = p_id;
  insert into audit_log (actor, action, detail) values (auth.uid(), 'owner_remove', jsonb_build_object('owner', p_id));
end $$;

-- Rol del usuario actual: owner | device | customer | none
create or replace function public.my_role()
returns text language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return 'none'; end if;
  if exists (select 1 from owners where user_id = auth.uid()) then return 'owner'; end if;
  if exists (select 1 from devices where user_id = auth.uid()) then
    update devices set last_access = now() where user_id = auth.uid();
    return 'device';
  end if;
  if coalesce(auth.jwt() ->> 'email', '') <> ''
     and not coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    return 'customer';
  end if;
  return 'none';
end $$;

-- Datos de un cupón (solo su cliente o el personal)
create or replace function public.coupon_json(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c coupons; r jsonb;
begin
  select * into c from coupons where id = p_id;
  if not found then return null; end if;
  if not (is_staff() or c.customer_id = auth.uid()) then raise exception 'forbidden'; end if;
  select jsonb_build_object(
    'id', c.id,
    'number', c.number,
    'name', c.name,
    'email', c.email,
    'status', c.status,
    'completed', c.completed,
    'points', c.points,
    'points_per_stamp', (select points_per_stamp from settings where id = 1),
    'design_id', c.design_id,
    -- último día que vino a un concierto (último sello real, también de cupones anteriores; los sellos por puntos no cuentan)
    'last_visit', (select max(s2.stamped_at) from stamps s2 join coupons c2 on c2.id = s2.coupon_id
                    where c2.email = c.email and s2.deleted_at is null and coalesce(s2.source, '') <> 'points'),
    'qr_token', case when c.customer_id = auth.uid() then c.qr_token end,
    'stamps', coalesce((
      select jsonb_agg(jsonb_build_object('box', s.box, 'stamped_at', s.stamped_at, 'image_path', s.image_path, 'redeemed', s.redeemed_at is not null) order by s.box)
      from stamps s where s.coupon_id = c.id and s.deleted_at is null
    ), '[]'::jsonb)
  ) into r;
  return r;
end $$;

-- CLIENTE: devuelve su cupón activo; si no tiene, lo crea
create or replace function public.my_coupon()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid   uuid := auth.uid();
  v_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_id    uuid;
begin
  if v_uid is null or v_email = '' or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    raise exception 'not_customer';
  end if;
  select id into v_id from coupons where customer_id = v_uid and status = 'active';
  if v_id is null then
    -- cupón activo restaurado desde una copia de seguridad: lo reclama quien entra con ese email
    begin
      update coupons set customer_id = v_uid
       where id = (select x.id from coupons x
                    where x.customer_id is null and x.status = 'active' and lower(x.email) = v_email
                    order by x.number limit 1)
      returning id into v_id;
    exception when unique_violation then
      select id into v_id from coupons where customer_id = v_uid and status = 'active';
    end;
  end if;
  if v_id is null then
    begin
      insert into coupons (customer_id, email, design_id)
      values (v_uid, v_email, (select current_design_id from settings where id = 1))
      returning id into v_id;
      insert into audit_log (actor, action, detail) values (v_uid, 'coupon_created', jsonb_build_object('coupon', v_id));
    exception when unique_violation then
      select id into v_id from coupons where customer_id = v_uid and status = 'active';
    end;
  end if;
  return coupon_json(v_id);
end $$;

-- CLIENTE: deja constancia de que aceptó la política de protección de datos (fecha y hora del servidor, email verificado)
create or replace function public.record_consent(p_version text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_ver   text := left(trim(coalesce(p_version, '')), 40);
begin
  if auth.uid() is null or v_email = '' or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    raise exception 'not_customer';
  end if;
  if v_ver = '' then raise exception 'bad_version'; end if;
  insert into consents (user_id, email, version) values (auth.uid(), v_email, v_ver)
    on conflict (email, version) do nothing;
end $$;

-- CLIENTE: guarda su nombre en su cupón activo
create or replace function public.set_my_name(p_name text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  select id into v_id from coupons where customer_id = auth.uid() and status = 'active';
  if v_id is null then raise exception 'no_coupon'; end if;
  update coupons set name = nullif(left(trim(coalesce(p_name, '')), 60), '') where id = v_id;
  return coupon_json(v_id);
end $$;

-- PERSONAL: escanear un QR. Cupón eliminado o desconocido -> solo el estado
create or replace function public.scan_coupon(p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c coupons;
begin
  if not is_staff() then raise exception 'forbidden'; end if;
  select * into c from coupons where qr_token = p_token;
  if not found then return jsonb_build_object('status', 'invalid'); end if;
  if c.status <> 'active' then return jsonb_build_object('status', 'deleted'); end if;
  return jsonb_build_object('status', 'active', 'coupon', coupon_json(c.id));
end $$;

-- PERSONAL: abrir un cupón desde la lista
create or replace function public.coupon_detail(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not is_staff() then raise exception 'forbidden'; end if;
  return coupon_json(p_id);
end $$;

-- PERSONAL: lista de cupones, con búsqueda por email
create or replace function public.search_coupons(p_q text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not is_staff() then raise exception 'forbidden'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', t.id, 'number', t.number, 'email', t.email, 'status', t.status, 'completed', t.completed, 'stamps', t.n) order by t.number desc)
    from (
      select c.id, c.number, c.email, c.status, c.completed,
             (select count(*)::int from stamps s where s.coupon_id = c.id and s.deleted_at is null) as n
      from coupons c
      where coalesce(p_q, '') = '' or c.email ilike '%' || p_q || '%'
      order by c.number desc
      limit 200
    ) t
  ), '[]'::jsonb);
end $$;

-- PERSONAL: poner un sello en la siguiente casilla libre
create or replace function public.add_stamp(p_coupon uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c coupons; v_box int; v_seal text;
begin
  if not is_staff() then raise exception 'forbidden'; end if;
  select * into c from coupons where id = p_coupon for update;
  if not found or c.status <> 'active' then raise exception 'coupon_not_active'; end if;
  select min(g) into v_box from generate_series(1, 10) as g
   where not exists (select 1 from stamps s where s.coupon_id = c.id and s.box = g and s.deleted_at is null);
  if v_box is null then raise exception 'coupon_full'; end if;
  select seal_path into v_seal from settings where id = 1;
  insert into stamps (coupon_id, box, stamped_by, image_path) values (c.id, v_box, auth.uid(), v_seal);
  perform game_on_stamp(c.id);
  insert into audit_log (actor, action, detail)
    values (auth.uid(), 'stamp_add', jsonb_build_object('coupon', c.id, 'box', v_box));
  return coupon_json(c.id);
end $$;

-- PERSONAL: borrar SOLO el último sello (queda constancia)
create or replace function public.remove_last_stamp(p_coupon uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c coupons; v_stamp uuid; v_box int; v_red timestamptz;
begin
  if not is_staff() then raise exception 'forbidden'; end if;
  select * into c from coupons where id = p_coupon for update;
  if not found or c.status <> 'active' then raise exception 'coupon_not_active'; end if;
  select s.id, s.box, s.redeemed_at into v_stamp, v_box, v_red from stamps s
   where s.coupon_id = c.id and s.deleted_at is null order by s.box desc limit 1;
  if v_stamp is null then raise exception 'no_stamps'; end if;
  if v_red is not null and not is_owner() then raise exception 'redeemed_owner_only'; end if;
  update stamps set deleted_at = now(), deleted_by = auth.uid() where id = v_stamp;
  insert into audit_log (actor, action, detail)
    values (auth.uid(), 'stamp_remove', jsonb_build_object('coupon', c.id, 'box', v_box));
  return coupon_json(c.id);
end $$;

-- PROPIETARIO: canjear el premio de una casilla (3, 5, 7 o 10) que ya tiene sello.
-- Si luego se borra ese sello, la casilla vuelve a su estado inicial (el sello nuevo no estará canjeado).
create or replace function public.redeem_stamp(p_coupon uuid, p_box int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c coupons; v_id uuid; v_red timestamptz;
begin
  if not is_owner() then raise exception 'forbidden'; end if;
  if p_box not in (3, 5, 7, 10) then raise exception 'not_reward_box'; end if;
  select * into c from coupons where id = p_coupon for update;
  if not found or c.status <> 'active' then raise exception 'coupon_not_active'; end if;
  select s.id, s.redeemed_at into v_id, v_red from stamps s
   where s.coupon_id = c.id and s.box = p_box and s.deleted_at is null;
  if v_id is null then raise exception 'no_stamp'; end if;
  if v_red is not null then raise exception 'already_redeemed'; end if;
  update stamps set redeemed_at = now(), redeemed_by = auth.uid() where id = v_id;
  insert into audit_log (actor, action, detail)
    values (auth.uid(), 'reward_redeem', jsonb_build_object('coupon', c.id, 'box', p_box));
  return coupon_json(c.id);
end $$;

-- PROPIETARIO: eliminar un cupón (no hay vuelta atrás)
create or replace function public.delete_coupon(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_owner() then raise exception 'forbidden'; end if;
  update coupons set status = 'deleted', deleted_at = now() where id = p_id and status = 'active';
  insert into audit_log (actor, action, detail) values (auth.uid(), 'coupon_delete', jsonb_build_object('coupon', p_id));
end $$;

-- PROPIETARIO: renovar un cupón completo (mismo número y mismo cliente; suma 1 a "completed").
-- Los 10 sellos no se borran: quedan marcados como retirados, como constancia.
create or replace function public.renew_coupon(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c coupons; v_n int;
begin
  if not is_owner() then raise exception 'forbidden'; end if;
  select * into c from coupons where id = p_id for update;
  if not found or c.status <> 'active' then raise exception 'coupon_not_active'; end if;
  select count(*)::int into v_n from stamps s where s.coupon_id = c.id and s.deleted_at is null;
  if v_n < 10 then raise exception 'coupon_not_full'; end if;
  update stamps set deleted_at = now(), deleted_by = auth.uid(), renewed_at = now() where coupon_id = c.id and deleted_at is null;
  update coupons set completed = completed + 1 where id = c.id;
  insert into audit_log (actor, action, detail)
    values (auth.uid(), 'coupon_renew', jsonb_build_object('coupon', c.id, 'completed', c.completed + 1));
  perform convert_points(c.id);
  return coupon_json(c.id);
end $$;

-- =====================================================================
-- JUEGOS: funciones
-- =====================================================================

-- ¿Está el juego en marcha ahora mismo?
create or replace function public.game_live(g public.games)
returns boolean language sql stable as $$
  select g.stopped_at is null and now() >= g.starts_at and now() < g.ends_at;
$$;

-- Respuestas: se ignoran mayúsculas, acentos (la ñ cuenta como n), espacios y signos
create or replace function public.norm_answer(t text)
returns text language sql immutable as $$
  select regexp_replace(
           lower(translate(coalesce(t, ''),
             'ÁÀÂÄÉÈÊËÍÌÎÏÓÒÔÖÚÙÛÜáàâäéèêëíìîïóòôöúùûüÑñÇç',
             'AAAAEEEEIIIIOOOOUUUUaaaaeeeeiiiioooouuuuNnCc')),
           '[^a-z0-9]', '', 'g');
$$;

-- Huecos que ve el cliente: "_" por cada letra o número, los espacios y signos se muestran tal cual
create or replace function public.answer_mask(t text)
returns text language sql immutable as $$
  select regexp_replace(trim(coalesce(t, '')),
           '[A-Za-z0-9ÁÀÂÄÉÈÊËÍÌÎÏÓÒÔÖÚÙÛÜáàâäéèêëíìîïóòôöúùûüÑñÇç]', '_', 'g');
$$;

-- Sorteo del regalo (el servidor decide; cada unidad que queda tiene la misma probabilidad)
create or replace function public.draw_prize(p_game uuid, out o_kind text, out o_name text, out o_prize uuid)
language plpgsql security definer set search_path = public as $$
declare g games; v_total int; v_r int;
begin
  select * into g from games where id = p_game for update;
  if g.prize_mode = 'single' and coalesce(trim(g.single_prize), '') <> '' then
    o_kind := 'prize'; o_name := g.single_prize; return;
  end if;
  select coalesce(sum(remaining), 0) into v_total from game_prizes where game_id = p_game and remaining > 0;
  if v_total > 0 then
    v_r := floor(random() * v_total)::int;
    select t.id, t.name into o_prize, o_name from (
      select p.id, p.name, sum(p.remaining) over (order by p.pos, p.id) as cum
        from game_prizes p where p.game_id = p_game and p.remaining > 0
    ) t where t.cum > v_r order by t.cum limit 1;
    update game_prizes set remaining = remaining - 1 where id = o_prize;
    o_kind := 'prize'; return;
  end if;
  if coalesce(trim(g.consolation), '') <> '' then
    o_kind := 'consolation'; o_name := g.consolation; return;
  end if;
  o_kind := 'none'; o_name := null;
end $$;

-- Completa una tarjeta: sortea su regalo
create or replace function public.complete_card(p_card uuid)
returns void language plpgsql security definer set search_path = public as $$
declare k game_cards; d record;
begin
  select * into k from game_cards where id = p_card for update;
  if k.completed_at is not null then return; end if;
  select * into d from draw_prize(k.game_id);
  update game_cards set completed_at = now(), prize_kind = d.o_kind, prize = d.o_name, prize_id = d.o_prize where id = p_card;
end $$;

-- Al poner un sello: crea la tarjeta de cada juego en marcha (solo la primera vez por cupón y juego).
-- En el Sello Sorpresa el regalo se sortea en ese momento.
create or replace function public.game_on_stamp(p_coupon uuid)
returns void language plpgsql security definer set search_path = public as $$
declare g games; v_card uuid;
begin
  for g in select * from games x where game_live(x) and x.kind in ('treasure', 'quiz', 'scratch') order by x.starts_at loop
    v_card := null;
    insert into game_cards (game_id, coupon_id) values (g.id, p_coupon)
      on conflict (game_id, coupon_id) do nothing
      returning id into v_card;
    if v_card is not null and g.kind = 'scratch' then
      perform complete_card(v_card);
    end if;
  end loop;
end $$;

-- Vista de una tarjeta para el cliente
create or replace function public.card_json(p_card uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare k game_cards; g games; v_done boolean;
begin
  select * into k from game_cards where id = p_card;
  if not found then return null; end if;
  select * into g from games where id = k.game_id;
  v_done := k.completed_at is not null;
  return jsonb_build_object(
    'id', k.id, 'game_id', g.id, 'kind', g.kind, 'game', g.name, 'ends_at', g.ends_at, 'live', game_live(g),
    'cells', coalesce(g.cells, 0),
    'found', coalesce((select jsonb_agg(sp.idx order by sp.idx) from game_finds f join game_spots sp on sp.id = f.spot_id where f.card_id = k.id), '[]'::jsonb),
    'completed', v_done,
    'prize_kind', case when v_done then k.prize_kind end,
    'prize', case when v_done then coalesce(k.prize, nullif(trim(g.no_prize_msg), ''), 'Esta vez no ha habido premio. ¡Gracias por jugar!') end,
    'revealed', k.revealed_at is not null,
    'delivered', k.delivered_at is not null, 'points', k.points,
    'img_a', g.img_a, 'img_b', g.img_b,
    'fx', case when g.kind in ('treasure', 'quiz') then g.config end);
end $$;

-- Comprueba que quien llama es un cliente con email verificado
create or replace function public.require_customer()
returns uuid language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null or coalesce(auth.jwt() ->> 'email', '') = ''
     or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    raise exception 'not_customer';
  end if;
  return auth.uid();
end $$;

-- CLIENTE: tarjetas en juego y lista "Mis premios"
create or replace function public.my_games()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid := require_customer();
begin
  perform finalize_ended_games();
  return jsonb_build_object(
    'cards', coalesce((
      select jsonb_agg(card_json(k.id) order by k.created_at)
        from game_cards k join games g on g.id = k.game_id join coupons c on c.id = k.coupon_id
       where c.customer_id = v_uid and c.status = 'active' and k.delivered_at is null and game_live(g)
         and g.kind in ('treasure', 'quiz', 'scratch')
         and not (k.completed_at is not null and k.prize_kind = 'none' and k.revealed_at is not null)
    ), '[]'::jsonb),
    'offers', coalesce((
      select jsonb_agg(jsonb_build_object(
               'game_id', g.id, 'kind', g.kind, 'name', g.name, 'ends_at', g.ends_at,
               'reward', g.reward_mode, 'points', g.points, 'config', coalesce(g.config, '{}'::jsonb), 'img_a', g.img_a, 'img_b', g.img_b,
               'state', case when k.id is null then 'new' when k.completed_at is not null then 'won'
                             when k.play_started_at is not null then 'started' when k.declined_at is not null then 'declined' else 'new' end,
               'card', case when k.completed_at is not null then card_json(k.id) end,
               'best', case when k.score_removed then null else k.best_score end)
             order by g.starts_at)
        from games g
        left join game_cards k on k.game_id = g.id and k.coupon_id = (select c.id from coupons c where c.customer_id = v_uid and c.status = 'active')
       where game_live(g) and g.kind in ('puzzle', 'memory', 'beat', 'barman')
         and exists (select 1 from coupons c where c.customer_id = v_uid and c.status = 'active')
    ), '[]'::jsonb),
    'prizes', coalesce((
      select jsonb_agg(x order by x->>'at' desc) from (
        select jsonb_build_object(
               'at', k.completed_at, 'prize', k.prize, 'consolation', k.prize_kind = 'consolation',
               'game', g.name, 'kind', g.kind,
               'status', case when k.prize_kind = 'points' then 'points' when k.delivered_at is not null then 'delivered' when not game_live(g) then 'expired' else 'pending' end,
               'delivered_at', k.delivered_at) as x
          from game_cards k join games g on g.id = k.game_id join coupons c on c.id = k.coupon_id
         where c.customer_id = v_uid and k.completed_at is not null and k.prize_kind in ('prize', 'consolation', 'points')
           and (g.kind <> 'scratch' or k.revealed_at is not null or not game_live(g))
        union all
        select jsonb_build_object(
               'at', a.awarded_at, 'prize', a.pos || 'º puesto · ' || a.prize, 'award', true, 'game', g.name, 'kind', g.kind,
               'status', case when a.delivered_at is not null then 'delivered' when now() > a.awarded_at + interval '30 days' then 'expired' else 'pending' end,
               'delivered_at', a.delivered_at, 'expires_at', a.awarded_at + interval '30 days')
          from game_awards a join games g on g.id = a.game_id join coupons c on c.id = a.coupon_id
         where c.customer_id = v_uid
      ) t
    ), '[]'::jsonb));
end $$;

-- CLIENTE: ha rascado / ha visto el reverso
create or replace function public.reveal_card(p_card uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid := require_customer();
begin
  update game_cards k set revealed_at = coalesce(k.revealed_at, now())
   where k.id = p_card and k.completed_at is not null
     and exists (select 1 from coupons c where c.id = k.coupon_id and c.customer_id = v_uid);
  return card_json(p_card);
end $$;

-- Busca el QR del local y la tarjeta del cliente en ese juego
create or replace function public.game_spot_ctx(p_token text, out o_spot game_spots, out o_game games, out o_card uuid, out o_status text)
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := require_customer();
begin
  select * into o_spot from game_spots where token = p_token;
  if not found then o_status := 'invalid'; return; end if;
  select * into o_game from games where id = o_spot.game_id;
  if not game_live(o_game) then o_status := 'not_active'; return; end if;
  select k.id into o_card from game_cards k join coupons c on c.id = k.coupon_id
   where k.game_id = o_game.id and c.customer_id = v_uid and c.status = 'active';
  if o_card is null then o_status := 'no_card'; return; end if;
  o_status := 'ok';
end $$;

-- Marca un hallazgo y completa la tarjeta si ya están todos
create or replace function public.add_find(p_card uuid, p_spot uuid)
returns text language plpgsql security definer set search_path = public as $$
declare n int; v_game uuid; v_total int; v_done timestamptz;
begin
  select game_id, completed_at into v_game, v_done from game_cards where id = p_card for update;
  if v_done is not null then return 'done'; end if;
  insert into game_finds (card_id, spot_id) values (p_card, p_spot) on conflict do nothing;
  get diagnostics n = row_count;
  if n = 0 then return 'already'; end if;
  select count(*) into v_total from game_spots where game_id = v_game;
  if (select count(*) from game_finds where card_id = p_card) >= v_total then
    perform complete_card(p_card);
    return 'complete';
  end if;
  return 'found';
end $$;

-- CLIENTE: ha escaneado un QR del juego
create or replace function public.game_scan(p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare x record; v_res text; v_done boolean;
begin
  select * into x from game_spot_ctx(p_token);
  if x.o_status = 'invalid' then return jsonb_build_object('status', 'invalid'); end if;
  if x.o_status <> 'ok' then return jsonb_build_object('status', x.o_status, 'game', (x.o_game).name, 'kind', (x.o_game).kind); end if;
  select completed_at is not null into v_done from game_cards where id = x.o_card;
  if v_done then return jsonb_build_object('status', 'done', 'card', card_json(x.o_card)); end if;
  if (x.o_game).kind = 'quiz' then
    return jsonb_build_object('status', 'question', 'kind', 'quiz', 'game', (x.o_game).name,
      'idx', (x.o_spot).idx, 'question', (x.o_spot).question, 'mask', answer_mask((x.o_spot).answer),
      'answered', exists (select 1 from game_finds f where f.card_id = x.o_card and f.spot_id = (x.o_spot).id),
      'card', card_json(x.o_card));
  end if;
  if (x.o_game).kind <> 'treasure' then return jsonb_build_object('status', 'invalid'); end if;
  v_res := add_find(x.o_card, (x.o_spot).id);
  return jsonb_build_object('status', v_res, 'idx', (x.o_spot).idx, 'card', card_json(x.o_card));
end $$;

-- CLIENTE: responde una pregunta del juego interactivo (sin límite de intentos)
create or replace function public.game_answer(p_token text, p_answer text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare x record; v_res text;
begin
  select * into x from game_spot_ctx(p_token);
  if x.o_status = 'invalid' or (x.o_status = 'ok' and (x.o_game).kind <> 'quiz') then return jsonb_build_object('status', 'invalid'); end if;
  if x.o_status <> 'ok' then return jsonb_build_object('status', x.o_status, 'game', (x.o_game).name); end if;
  if norm_answer(p_answer) = '' or norm_answer(p_answer) <> norm_answer((x.o_spot).answer) then
    return jsonb_build_object('status', 'wrong');
  end if;
  v_res := add_find(x.o_card, (x.o_spot).id);
  return jsonb_build_object('status', case when v_res = 'found' then 'correct' else v_res end, 'card', card_json(x.o_card));
end $$;

-- PROPIETARIO: crear un juego
create or replace function public.game_create(p jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_kind text := p->>'kind'; v_cells int; v_mode text := coalesce(p->>'prize_mode', 'single');
        v_reward text := coalesce(p->>'reward_mode', 'prize'); v_points int; v_cfg jsonb; v_n int; s jsonb; i int := 0;
begin
  if not is_owner() then raise exception 'forbidden'; end if;
  if v_kind not in ('treasure', 'quiz', 'scratch', 'puzzle', 'memory', 'beat', 'barman') then raise exception 'bad_game'; end if;
  if coalesce(trim(p->>'name'), '') = '' then raise exception 'game_name_required'; end if;
  if (p->>'starts_at') is null or (p->>'ends_at') is null or (p->>'ends_at')::timestamptz <= (p->>'starts_at')::timestamptz then
    raise exception 'game_bad_dates';
  end if;
  if (p->>'ends_at')::timestamptz <= now() then raise exception 'game_bad_dates'; end if;
  -- recompensa: premio (todos los juegos) o puntos (solo los de fuera de concierto)
  if v_reward not in ('prize', 'points') or (v_reward = 'points' and v_kind not in ('puzzle', 'memory', 'beat', 'barman')) then raise exception 'bad_game'; end if;
  if v_reward = 'points' then
    v_points := (p->>'points')::int;
    if v_points is null or v_points < 1 or v_points > 100000 then raise exception 'game_points_required'; end if;
    v_mode := 'single';
  else
    if v_mode not in ('single', 'random') then raise exception 'bad_game'; end if;
    if v_mode = 'single' and coalesce(trim(p->>'single_prize'), '') = '' then raise exception 'game_prize_required'; end if;
    if v_mode = 'random' then
      if jsonb_typeof(p->'prizes') <> 'array' or jsonb_array_length(p->'prizes') = 0 then raise exception 'game_prize_required'; end if;
      if exists (select 1 from jsonb_array_elements(p->'prizes') r
                  where coalesce(trim(r->>'name'), '') = '' or coalesce((r->>'units')::int, 0) < 1) then
        raise exception 'game_prize_required';
      end if;
    end if;
  end if;
  if v_kind in ('treasure', 'quiz') then
    v_cells := (p->>'cells')::int;
    if v_cells is null or v_cells < 3 or v_cells > 10 or jsonb_typeof(p->'spots') <> 'array'
       or jsonb_array_length(p->'spots') <> v_cells then
      raise exception 'game_bad_cells';
    end if;
    if v_kind = 'quiz' and exists (select 1 from jsonb_array_elements(p->'spots') r
         where coalesce(trim(r->>'question'), '') = '' or norm_answer(r->>'answer') = '') then
      raise exception 'game_quiz_incomplete';
    end if;
    -- tema opcional: al encontrar cada QR aparece un objeto 3D (Halloween: calabaza, fantasma, murciélago, calavera, caldero, gato)
    if p->'config'->>'theme' = 'halloween' then
      v_cfg := jsonb_build_object('theme', 'halloween', 'objects', coalesce((
        select jsonb_agg(case when x in ('pumpkin', 'ghost', 'bat', 'skull', 'cauldron', 'cat') then x else 'auto' end order by n)
          from jsonb_array_elements_text(case when jsonb_typeof(p->'config'->'objects') = 'array' then p->'config'->'objects' else '[]'::jsonb end) with ordinality as t(x, n)
         where n <= 10), '[]'::jsonb));
      -- interactivo: minijuego «escape room» antes de cada pregunta (calabazas, candado, poción, arañas, fantasma, laberinto)
      if v_kind = 'quiz' and coalesce((p->'config'->>'escape')::boolean, false) then
        v_cfg := v_cfg || jsonb_build_object('escape', true, 'minis', coalesce((
          select jsonb_agg(case when x in ('pumpkins', 'lock', 'potion', 'spiders', 'ghost', 'maze') then x else 'auto' end order by n)
            from jsonb_array_elements_text(case when jsonb_typeof(p->'config'->'minis') = 'array' then p->'config'->'minis' else '[]'::jsonb end) with ordinality as t(x, n)
           where n <= 10), '[]'::jsonb));
      end if;
    end if;
  elsif v_kind = 'puzzle' then
    if coalesce(p->>'img_a', '') not like 'games/%' then raise exception 'game_image_required'; end if;
    if coalesce((p->'config'->>'grid')::int, 0) not in (3, 4, 5) then raise exception 'bad_game'; end if;
    v_cfg := jsonb_build_object('grid', (p->'config'->>'grid')::int);
  elsif v_kind = 'memory' then
    if jsonb_typeof(p->'config'->'images') <> 'array' then raise exception 'game_images_required'; end if;
    v_n := jsonb_array_length(p->'config'->'images');
    if v_n < 4 or v_n > 10 or exists (select 1 from jsonb_array_elements_text(p->'config'->'images') x where x not like 'games/%') then
      raise exception 'game_images_required';
    end if;
    if coalesce((p->'config'->>'max_moves')::int, 0) < v_n or (p->'config'->>'max_moves')::int > 999 then raise exception 'game_bad_moves'; end if;
    v_cfg := jsonb_build_object('images', p->'config'->'images', 'max_moves', (p->'config'->>'max_moves')::int);
  elsif v_kind in ('beat', 'barman') then
    if coalesce(p->'config'->>'difficulty', '') not in ('easy', 'medium', 'hard') then raise exception 'bad_game'; end if;
    if coalesce((p->'config'->>'min_score')::int, 0) < 1 or (v_kind = 'beat' and (p->'config'->>'min_score')::int > 100)
       or (p->'config'->>'min_score')::int > 100000 then
      raise exception 'game_bad_min';
    end if;
    if jsonb_typeof(coalesce(p->'config'->'rank_prizes', '[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(p->'config'->'rank_prizes', '[]'::jsonb)) > 10 then
      raise exception 'bad_game';
    end if;
    v_cfg := jsonb_build_object('difficulty', p->'config'->>'difficulty', 'min_score', (p->'config'->>'min_score')::int,
               'rank_prizes', coalesce((select jsonb_agg(left(trim(x), 80) order by n) from jsonb_array_elements_text(coalesce(p->'config'->'rank_prizes', '[]'::jsonb)) with ordinality as t(x, n)), '[]'::jsonb));
    if v_kind = 'beat' then
      if coalesce((p->'config'->>'bpm')::int, 0) not between 60 and 200 then raise exception 'game_bad_bpm'; end if;
      v_cfg := v_cfg || jsonb_build_object('bpm', (p->'config'->>'bpm')::int,
                 'audio', case when (p->'config'->>'audio') like 'games/%' then p->'config'->>'audio' end,
                 'offset', least(2, greatest(-2, coalesce((p->'config'->>'offset')::numeric, 0))),
                 -- mapa de notas sacado de la canción al subirla: [segundo, banda 0-2, fuerza 0-9] (máx. 400)
                 'notes', coalesce((select jsonb_agg(jsonb_build_array(round(least(40, greatest(0, (e->>0)::numeric)), 3),
                                                                      least(2, greatest(0, coalesce((e->>1)::int, 0))),
                                                                      least(9, greatest(0, coalesce((e->>2)::int, 5)))) order by n)
                                      from jsonb_array_elements(case when jsonb_typeof(p->'config'->'notes') = 'array' then p->'config'->'notes' else '[]'::jsonb end)
                                           with ordinality as t(e, n)
                                     where n <= 400 and jsonb_typeof(e) = 'array' and jsonb_typeof(e->0) = 'number'), '[]'::jsonb));
    else
      if jsonb_typeof(p->'config'->'drinks') <> 'array' or jsonb_array_length(p->'config'->'drinks') not between 3 and 6
         or exists (select 1 from jsonb_array_elements(p->'config'->'drinks') d where coalesce(trim(d->>'name'), '') = '') then
        raise exception 'game_bad_drinks';
      end if;
      if jsonb_typeof(coalesce(p->'config'->'offers', '[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(p->'config'->'offers', '[]'::jsonb)) > 3 then raise exception 'bad_game'; end if;
      v_cfg := v_cfg || jsonb_build_object(
                 'drinks', (select jsonb_agg(jsonb_build_object('name', left(trim(d->>'name'), 30), 'icon', left(coalesce(d->>'icon', 'beer'), 20),
                                                                'img', case when (d->>'img') like 'games/%' then d->>'img' end) order by n)
                              from jsonb_array_elements(p->'config'->'drinks') with ordinality as t(d, n)),
                 'offers', coalesce((select jsonb_agg(left(trim(x), 80) order by n) from jsonb_array_elements_text(coalesce(p->'config'->'offers', '[]'::jsonb)) with ordinality as t(x, n) where trim(x) <> ''), '[]'::jsonb),
                 -- duración de cada partida en segundos (0 = sin límite: hasta perder las 3 vidas)
                 'duration', case when (p->'config'->>'duration') in ('60', '120', '180') then (p->'config'->>'duration')::int else 0 end);
    end if;
  end if;
  insert into games (kind, name, starts_at, ends_at, prize_mode, single_prize, consolation, no_prize_msg, cells, img_a, img_b, created_by, reward_mode, points, config)
  values (v_kind, left(trim(p->>'name'), 60), (p->>'starts_at')::timestamptz, (p->>'ends_at')::timestamptz, v_mode,
          case when v_reward = 'prize' and v_mode = 'single' then left(trim(p->>'single_prize'), 80) end,
          case when v_reward = 'prize' then nullif(left(trim(coalesce(p->>'consolation', '')), 80), '') end,
          nullif(left(trim(coalesce(p->>'no_prize_msg', '')), 160), ''),
          v_cells,
          case when (p->>'img_a') like 'games/%' then p->>'img_a' end,
          case when (p->>'img_b') like 'games/%' then p->>'img_b' end,
          auth.uid(), v_reward, v_points, v_cfg)
  returning id into v_id;
  if v_reward = 'prize' and v_mode = 'random' then
    insert into game_prizes (game_id, pos, name, units, remaining)
    select v_id, t.n, left(trim(t.r->>'name'), 80), (t.r->>'units')::int, (t.r->>'units')::int
      from jsonb_array_elements(p->'prizes') with ordinality as t(r, n);
  end if;
  if v_kind in ('treasure', 'quiz') then
    for s in select * from jsonb_array_elements(p->'spots') loop
      i := i + 1;
      insert into game_spots (game_id, idx, label, question, answer)
      values (v_id, i, nullif(left(trim(coalesce(s->>'label', '')), 60), ''),
              case when v_kind = 'quiz' then left(trim(s->>'question'), 200) end,
              case when v_kind = 'quiz' then left(trim(s->>'answer'), 60) end);
    end loop;
  end if;
  insert into audit_log (actor, action, detail) values (auth.uid(), 'game_create', jsonb_build_object('game', v_id, 'kind', v_kind));
  return v_id;
end $$;

-- PROPIETARIO: lista de juegos con todo su detalle
create or replace function public.games_admin()
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not is_owner() then raise exception 'forbidden'; end if;
  perform finalize_ended_games();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', g.id, 'kind', g.kind, 'name', g.name, 'starts_at', g.starts_at, 'ends_at', g.ends_at, 'stopped_at', g.stopped_at,
      'status', case when game_live(g) then 'live' when g.stopped_at is null and now() < g.starts_at then 'scheduled' else 'ended' end,
      'prize_mode', g.prize_mode, 'single_prize', g.single_prize, 'consolation', g.consolation, 'no_prize_msg', g.no_prize_msg,
      'cells', g.cells, 'img_a', g.img_a, 'img_b', g.img_b, 'reward_mode', g.reward_mode, 'points', g.points, 'config', g.config,
      'finalized_at', g.finalized_at,
      'players', (select count(*) from game_cards k where k.game_id = g.id and k.best_score is not null),
      'awards', coalesce((select jsonb_agg(jsonb_build_object('pos', a.pos, 'prize', a.prize, 'score', a.score, 'name', board_name(c.name, c.number), 'email', c.email,
                   'delivered', a.delivered_at is not null, 'expired', a.delivered_at is null and now() > a.awarded_at + interval '30 days') order by a.pos)
                 from game_awards a join coupons c on c.id = a.coupon_id where a.game_id = g.id), '[]'::jsonb),
      'declined', (select count(*) from game_cards k where k.game_id = g.id and k.declined_at is not null and k.play_started_at is null and k.completed_at is null),
      'prizes', coalesce((select jsonb_agg(jsonb_build_object('name', p.name, 'units', p.units, 'remaining', p.remaining) order by p.pos) from game_prizes p where p.game_id = g.id), '[]'::jsonb),
      'spots', coalesce((select jsonb_agg(jsonb_build_object('idx', s.idx, 'label', s.label, 'token', s.token, 'question', s.question, 'answer', s.answer) order by s.idx) from game_spots s where s.game_id = g.id), '[]'::jsonb),
      'cards', (select count(*) from game_cards k where k.game_id = g.id),
      'completed', (select count(*) from game_cards k where k.game_id = g.id and k.completed_at is not null),
      'won', (select count(*) from game_cards k where k.game_id = g.id and k.prize_kind in ('prize', 'consolation', 'points')),
      'delivered', (select count(*) from game_cards k where k.game_id = g.id and k.delivered_at is not null))
      order by g.starts_at desc)
    from games g), '[]'::jsonb);
end $$;

-- PROPIETARIO: detener un juego (los premios no entregados caducan y las tarjetas a medias se anulan)
create or replace function public.game_stop(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_owner() then raise exception 'forbidden'; end if;
  update games set stopped_at = now() where id = p_id and stopped_at is null and now() < ends_at;
  insert into audit_log (actor, action, detail) values (auth.uid(), 'game_stop', jsonb_build_object('game', p_id));
end $$;

-- PROPIETARIO: eliminar un juego que todavía no tiene tarjetas
create or replace function public.game_delete(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_owner() then raise exception 'forbidden'; end if;
  if exists (select 1 from game_cards where game_id = p_id) then raise exception 'game_has_cards'; end if;
  delete from games where id = p_id;
  insert into audit_log (actor, action, detail) values (auth.uid(), 'game_delete', jsonb_build_object('game', p_id));
end $$;

-- PROPIETARIO: tarjetas de un cupón en los juegos en marcha (para entregar premios)
create or replace function public.coupon_games(p_coupon uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not is_owner() then raise exception 'forbidden'; end if;
  perform finalize_ended_games();
  return coalesce((
    select jsonb_agg(card_json(k.id) order by k.created_at)
      from game_cards k join games g on g.id = k.game_id
     where k.coupon_id = p_coupon and k.delivered_at is null and game_live(g)
       and (g.kind in ('treasure', 'quiz', 'scratch') or k.prize_kind in ('prize', 'consolation'))
  ), '[]'::jsonb) || coalesce((
    select jsonb_agg(jsonb_build_object('id', a.id, 'award', true, 'kind', g.kind, 'game', g.name, 'pos', a.pos, 'prize', a.prize,
                                        'completed', true, 'prize_kind', 'prize', 'revealed', true, 'expires_at', a.awarded_at + interval '30 days')
                     order by a.awarded_at)
      from game_awards a join games g on g.id = a.game_id
     where a.coupon_id = p_coupon and a.delivered_at is null and now() <= a.awarded_at + interval '30 days'
  ), '[]'::jsonb);
end $$;

-- PROPIETARIO: entregar el premio de una tarjeta (una sola vez)
create or replace function public.deliver_card(p_card uuid)
returns void language plpgsql security definer set search_path = public as $$
declare k game_cards; g games;
begin
  if not is_owner() then raise exception 'forbidden'; end if;
  select * into k from game_cards where id = p_card for update;
  if not found then raise exception 'no_card'; end if;
  select * into g from games where id = k.game_id;
  if k.delivered_at is not null then raise exception 'already_delivered'; end if;
  if k.completed_at is null or k.prize_kind not in ('prize', 'consolation') then raise exception 'no_prize'; end if;
  if not game_live(g) then raise exception 'game_ended'; end if;
  update game_cards set delivered_at = now(), delivered_by = auth.uid() where id = p_card;
  insert into audit_log (actor, action, detail) values (auth.uid(), 'game_deliver', jsonb_build_object('card', p_card, 'prize', k.prize));
end $$;

-- =====================================================================
-- PUNTOS y JUEGOS FUERA DE CONCIERTO
-- =====================================================================

-- Convierte los puntos del cupón en sellos (automático). Devuelve cuántos sellos se han puesto.
create or replace function public.convert_points(p_coupon uuid)
returns int language plpgsql security definer set search_path = public as $$
declare v_rate int; v_pts int; v_box int; v_seal text; n int := 0; v_status text;
begin
  select points_per_stamp, seal_path into v_rate, v_seal from settings where id = 1;
  if coalesce(v_rate, 0) <= 0 then return 0; end if;
  loop
    select points, status into v_pts, v_status from coupons where id = p_coupon for update;
    exit when v_status is distinct from 'active' or v_pts < v_rate;
    select min(g) into v_box from generate_series(1, 10) as g
     where not exists (select 1 from stamps s where s.coupon_id = p_coupon and s.box = g and s.deleted_at is null);
    exit when v_box is null;   -- cupón lleno: los puntos se guardan
    insert into stamps (coupon_id, box, stamped_by, image_path, source) values (p_coupon, v_box, null, v_seal, 'points');
    update coupons set points = points - v_rate where id = p_coupon;
    insert into points_log (coupon_id, delta, reason) values (p_coupon, -v_rate, 'stamp');
    insert into audit_log (actor, action, detail) values (auth.uid(), 'stamp_points', jsonb_build_object('coupon', p_coupon, 'box', v_box));
    n := n + 1;
  end loop;
  return n;
end $$;

-- PROPIETARIO: puntos necesarios para un sello
create or replace function public.set_points_rate(p_rate int)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_owner() then raise exception 'forbidden'; end if;
  if p_rate is null or p_rate < 1 or p_rate > 100000 then raise exception 'bad_rate'; end if;
  update settings set points_per_stamp = p_rate where id = 1;
  insert into audit_log (actor, action, detail) values (auth.uid(), 'points_rate', jsonb_build_object('rate', p_rate));
end $$;

-- Cupón activo del cliente que llama
create or replace function public.my_active_coupon()
returns uuid language plpgsql stable security definer set search_path = public as $$
declare v uuid;
begin
  select id into v from coupons where customer_id = require_customer() and status = 'active';
  if v is null then raise exception 'no_coupon'; end if;
  return v;
end $$;

-- CLIENTE: empieza una partida (crea su tarjeta si no la tenía)
create or replace function public.game_start(p_game uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare g games; v_coupon uuid := my_active_coupon(); k game_cards;
begin
  select * into g from games where id = p_game;
  if not found or g.kind not in ('puzzle', 'memory', 'beat', 'barman') then raise exception 'bad_game'; end if;
  if not game_live(g) then raise exception 'game_not_active'; end if;
  insert into game_cards (game_id, coupon_id) values (g.id, v_coupon) on conflict (game_id, coupon_id) do nothing;
  select * into k from game_cards where game_id = g.id and coupon_id = v_coupon for update;
  if k.completed_at is not null and g.kind in ('puzzle', 'memory') then raise exception 'already_won'; end if;
  update game_cards set play_started_at = now(), declined_at = null where id = k.id;
  return jsonb_build_object('card', k.id, 'started_at', now());
end $$;

-- CLIENTE: "NO" en el aviso de la portada (queda en un botón para jugar más tarde)
create or replace function public.game_decline(p_game uuid)
returns void language plpgsql security definer set search_path = public as $$
declare g games; v_coupon uuid := my_active_coupon();
begin
  select * into g from games where id = p_game;
  if not found or g.kind not in ('puzzle', 'memory', 'beat', 'barman') then raise exception 'bad_game'; end if;
  insert into game_cards (game_id, coupon_id, declined_at) values (g.id, v_coupon, now())
    on conflict (game_id, coupon_id) do update set declined_at = coalesce(game_cards.declined_at, now())
    where game_cards.completed_at is null and game_cards.play_started_at is null;
end $$;

-- CLIENTE: partida terminada. El servidor comprueba lo que puede y da la recompensa (una sola vez)
create or replace function public.game_finish(p_game uuid, p_result jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare g games; v_coupon uuid := my_active_coupon(); k game_cards; v_min numeric; v_el numeric; v_moves int; v_pairs int; n int := 0;
begin
  select * into g from games where id = p_game;
  if not found or g.kind not in ('puzzle', 'memory') then raise exception 'bad_game'; end if;
  if not game_live(g) then raise exception 'game_not_active'; end if;
  select * into k from game_cards where game_id = g.id and coupon_id = v_coupon for update;
  if not found or k.play_started_at is null then raise exception 'not_started'; end if;
  if k.completed_at is not null then return jsonb_build_object('status', 'already', 'card', card_json(k.id)); end if;
  v_el := extract(epoch from now() - k.play_started_at);
  if g.kind = 'puzzle' then
    v_min := case coalesce((g.config->>'grid')::int, 3) when 3 then 15 when 4 then 25 else 40 end;
  else
    v_pairs := jsonb_array_length(coalesce(g.config->'images', '[]'::jsonb));
    v_moves := (p_result->>'moves')::int;
    if v_moves is null or v_moves < v_pairs or v_moves > coalesce((g.config->>'max_moves')::int, 0) then
      return jsonb_build_object('status', 'invalid');
    end if;
    v_min := v_pairs * 2;
  end if;
  if v_el < v_min then return jsonb_build_object('status', 'wait', 'seconds', ceil(v_min - v_el)); end if;
  if g.reward_mode = 'points' then
    update game_cards set completed_at = now(), prize_kind = 'points', points = g.points, prize = g.points || ' puntos', revealed_at = now()
     where id = k.id;
    update coupons set points = points + g.points where id = v_coupon;
    insert into points_log (coupon_id, delta, reason, game_id) values (v_coupon, g.points, 'game', g.id);
    n := convert_points(v_coupon);
  else
    perform complete_card(k.id);
    update game_cards set revealed_at = now() where id = k.id;
  end if;
  insert into audit_log (actor, action, detail) values (auth.uid(), 'game_won', jsonb_build_object('game', g.id, 'card', k.id));
  return jsonb_build_object('status', 'won', 'card', card_json(k.id), 'stamps_added', n, 'coupon', coupon_json(v_coupon));
end $$;

-- =====================================================================
-- JUEGOS CON CLASIFICACIÓN: Tap the Beat ('beat') y Barman Exprés ('barman')
-- =====================================================================

-- Nombre en la clasificación: "Ana G." (nombre + inicial del apellido) o "Pasaporte nº 12". Nunca el email.
create or replace function public.board_name(p_name text, p_number bigint)
returns text language sql immutable as $$
  select case when coalesce(trim(p_name), '') = '' then 'Pasaporte nº ' || p_number
              when position(' ' in trim(p_name)) = 0 then trim(p_name)
              else split_part(trim(p_name), ' ', 1) || ' ' || upper(left(regexp_replace(trim(p_name), '^\S+\s+', ''), 1)) || '.' end;
$$;

-- Reparte los premios por puesto de los juegos con clasificación que ya han terminado (una sola vez por juego)
create or replace function public.finalize_ended_games()
returns void language plpgsql security definer set search_path = public as $$
declare g games; r record;
begin
  for g in select * from games x
            where x.kind in ('beat', 'barman') and x.finalized_at is null
              and (x.stopped_at is not null or now() >= x.ends_at)
            for update skip locked loop
    for r in
      with prizes as (
        select t.n::int as pos, trim(t.p) as prize
          from jsonb_array_elements_text(coalesce(g.config->'rank_prizes', '[]'::jsonb)) with ordinality as t(p, n)
         where trim(t.p) <> ''),
      ranking as (
        select k.coupon_id, k.best_score, row_number() over (order by k.best_score desc, k.best_at asc) as pos
          from game_cards k
         where k.game_id = g.id and k.best_score is not null and not k.score_removed)
      select p.pos, p.prize, rk.coupon_id, rk.best_score from prizes p join ranking rk on rk.pos = p.pos
    loop
      insert into game_awards (game_id, coupon_id, pos, prize, score) values (g.id, r.coupon_id, r.pos, r.prize, r.best_score)
        on conflict (game_id, pos) do nothing;
    end loop;
    update games set finalized_at = now() where id = g.id;
  end loop;
end $$;

-- Clasificación (cliente): top 10 + su posición
create or replace function public.game_board(p_game uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_coupon uuid; v_me jsonb;
begin
  if not is_owner() then v_coupon := my_active_coupon(); end if;
  if not exists (select 1 from games where id = p_game and kind in ('beat', 'barman')) then raise exception 'bad_game'; end if;
  with rk as (
    select k.coupon_id, k.best_score as score, row_number() over (order by k.best_score desc, k.best_at asc) as pos,
           board_name(c.name, c.number) as name
      from game_cards k join coupons c on c.id = k.coupon_id
     where k.game_id = p_game and k.best_score is not null and not k.score_removed)
  select jsonb_build_object('pos', pos, 'score', score) into v_me from rk where coupon_id = v_coupon;
  return jsonb_build_object(
    'top', coalesce((
      select jsonb_agg(jsonb_build_object('pos', rk.pos, 'name', rk.name, 'score', rk.score, 'me', rk.coupon_id = v_coupon) order by rk.pos)
        from (select k.coupon_id, k.best_score as score, row_number() over (order by k.best_score desc, k.best_at asc) as pos,
                     board_name(c.name, c.number) as name
                from game_cards k join coupons c on c.id = k.coupon_id
               where k.game_id = p_game and k.best_score is not null and not k.score_removed) rk
       where rk.pos <= 10), '[]'::jsonb),
    'me', v_me,
    'total', (select count(*) from game_cards k where k.game_id = p_game and k.best_score is not null and not k.score_removed));
end $$;

-- CLIENTE: guarda el resultado de una partida (Tap the Beat: % de acierto; Barman: puntos)
create or replace function public.game_score(p_game uuid, p_score int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare g games; v_coupon uuid := my_active_coupon(); k game_cards; v_el numeric; v_min int; v_better boolean; v_won boolean := false; n int := 0; v_pos int;
begin
  select * into g from games where id = p_game;
  if not found or g.kind not in ('beat', 'barman') then raise exception 'bad_game'; end if;
  if not game_live(g) then raise exception 'game_not_active'; end if;
  select * into k from game_cards where game_id = g.id and coupon_id = v_coupon for update;
  if not found or k.play_started_at is null then raise exception 'not_started'; end if;
  v_el := extract(epoch from now() - k.play_started_at);
  -- partidas imposibles: demasiado cortas o con una puntuación que no se puede conseguir en ese tiempo
  if p_score is null or p_score < 0
     or (g.kind = 'beat' and (v_el < 28 or p_score > 100))
     or (g.kind = 'barman' and (v_el < 8 or p_score > v_el * 25 + 50)) then
    update game_cards set play_started_at = null where id = k.id;
    return jsonb_build_object('status', 'invalid');
  end if;
  v_better := k.best_score is null or p_score > k.best_score;
  update game_cards set play_started_at = null,
         best_score = case when v_better then p_score else best_score end,
         best_at = case when v_better then now() else best_at end
   where id = k.id;
  v_min := coalesce((g.config->>'min_score')::int, 0);
  if k.completed_at is null and p_score >= v_min then
    v_won := true;
    if g.reward_mode = 'points' then
      update game_cards set completed_at = now(), prize_kind = 'points', points = g.points, prize = g.points || ' puntos', revealed_at = now() where id = k.id;
      update coupons set points = points + g.points where id = v_coupon;
      insert into points_log (coupon_id, delta, reason, game_id) values (v_coupon, g.points, 'game', g.id);
      n := convert_points(v_coupon);
    else
      perform complete_card(k.id);
      update game_cards set revealed_at = now() where id = k.id;
    end if;
    insert into audit_log (actor, action, detail) values (auth.uid(), 'game_won', jsonb_build_object('game', g.id, 'card', k.id, 'score', p_score));
  end if;
  select x.pos into v_pos from (
    select k2.id, row_number() over (order by k2.best_score desc, k2.best_at asc) as pos
      from game_cards k2 where k2.game_id = g.id and k2.best_score is not null and not k2.score_removed) x
   where x.id = k.id;
  return jsonb_build_object('status', 'ok', 'score', p_score, 'best', greatest(p_score, coalesce(k.best_score, 0)), 'improved', v_better,
                            'won', v_won, 'pos', v_pos, 'card', card_json(k.id), 'stamps_added', n, 'coupon', coupon_json(v_coupon));
end $$;

-- PROPIETARIO: clasificación completa (con email) para revisar puntuaciones sospechosas
create or replace function public.game_board_admin(p_game uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not is_owner() then raise exception 'forbidden'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('card', t.id, 'pos', t.pos, 'name', t.name, 'email', t.email, 'score', t.best_score, 'at', t.best_at, 'removed', t.score_removed)
                     order by t.score_removed, t.pos)
      from (select k.id, k.best_score, k.best_at, k.score_removed, c.email, board_name(c.name, c.number) as name,
                   case when k.score_removed then null else row_number() over (partition by k.score_removed order by k.best_score desc, k.best_at asc) end as pos
              from game_cards k join coupons c on c.id = k.coupon_id
             where k.game_id = p_game and k.best_score is not null) t
     where t.score_removed or t.pos <= 100), '[]'::jsonb);
end $$;

-- PROPIETARIO: quitar (o devolver) una puntuación de la clasificación antes del final
create or replace function public.game_score_remove(p_card uuid, p_removed boolean)
returns void language plpgsql security definer set search_path = public as $$
declare g games;
begin
  if not is_owner() then raise exception 'forbidden'; end if;
  select x.* into g from games x join game_cards k on k.game_id = x.id where k.id = p_card;
  if g.finalized_at is not null then raise exception 'game_finalized'; end if;
  update game_cards set score_removed = coalesce(p_removed, true) where id = p_card;
  insert into audit_log (actor, action, detail) values (auth.uid(), 'score_remove', jsonb_build_object('card', p_card, 'removed', p_removed));
end $$;

-- PROPIETARIO: entregar un premio por puesto (caduca a los 30 días)
create or replace function public.deliver_award(p_award uuid)
returns void language plpgsql security definer set search_path = public as $$
declare a game_awards;
begin
  if not is_owner() then raise exception 'forbidden'; end if;
  select * into a from game_awards where id = p_award for update;
  if not found then raise exception 'no_card'; end if;
  if a.delivered_at is not null then raise exception 'already_delivered'; end if;
  if now() > a.awarded_at + interval '30 days' then raise exception 'award_expired'; end if;
  update game_awards set delivered_at = now(), delivered_by = auth.uid() where id = p_award;
  insert into audit_log (actor, action, detail) values (auth.uid(), 'award_deliver', jsonb_build_object('award', p_award, 'prize', a.prize));
end $$;

-- =====================================================================
-- MODO EVENTO (Búsqueda del Tesoro sin sello: portada → juego)
-- =====================================================================
create or replace function public.set_event_game(p_game uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_owner() then raise exception 'forbidden'; end if;
  if p_game is not null and not exists (select 1 from games where id = p_game and kind in ('treasure', 'quiz')) then raise exception 'bad_game'; end if;
  update settings set event_game_id = p_game where id = 1;
  insert into audit_log (actor, action, detail) values (auth.uid(), 'event_game', jsonb_build_object('game', p_game));
end $$;

-- CLIENTE: entrar en el juego del modo evento (crea su tarjeta sin sello). Devuelve la tarjeta.
create or replace function public.game_join(p_game uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare g games; v_coupon uuid := my_active_coupon(); v_card uuid;
begin
  select * into g from games where id = p_game;
  if not found or p_game is distinct from (select event_game_id from settings where id = 1) then raise exception 'bad_game'; end if;
  if not game_live(g) then raise exception 'game_not_active'; end if;
  insert into game_cards (game_id, coupon_id) values (g.id, v_coupon) on conflict (game_id, coupon_id) do nothing;
  select id into v_card from game_cards where game_id = g.id and coupon_id = v_coupon;
  return card_json(v_card);
end $$;

-- =====================================================================
-- LA COLA DE LA BURBUJA: clasificación general en la portada
-- puntos = puntos ganados en todos los juegos + 300 por cada sello de concierto (también de cupones ya renovados;
-- no cuentan los sellos borrados ni los conseguidos con puntos, que ya están sumados como puntos)
-- =====================================================================
-- Sellos de cupones renovados antes de existir renewed_at: se reconocen por la renovación registrada en el historial
update public.stamps s set renewed_at = s.deleted_at
 where s.renewed_at is null and s.deleted_at is not null
   and exists (select 1 from public.audit_log a where a.action = 'coupon_renew' and a.detail->>'coupon' = s.coupon_id::text and a.created_at = s.deleted_at);

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
                                                         'me', email = v_me, 'seed', left(md5(email), 10)) order by pos)
                       from rk where pos <= 10), '[]'::jsonb),
    'me', (select jsonb_build_object('pos', pos, 'score', score, 'name', board_name(name, number), 'seed', left(md5(email), 10)) from rk where email = v_me),
    'tenth', (select score from rk where pos = 10),
    'total', (select count(*) from rk)) into r;
  return r;
end $$;

-- =====================================================================
-- PERSONAJES Y FONDO DE LA BARRA (Barman Exprés)
-- =====================================================================
create or replace function public.character_save(p jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid := nullif(p->>'id', '')::uuid; v_name text := left(trim(coalesce(p->>'name', '')), 40); v_grp text := coalesce(p->>'grp', 'regular');
begin
  if not is_owner() then raise exception 'forbidden'; end if;
  if v_name = '' then raise exception 'char_name_required'; end if;
  if v_grp not in ('regular', 'staff', 'musician') then raise exception 'bad_game'; end if;
  if jsonb_typeof(p->'spec') <> 'object' or length((p->'spec')::text) > 2000 then raise exception 'bad_game'; end if;
  if v_id is null then
    insert into characters (name, grp, spec, active) values (v_name, v_grp, p->'spec', coalesce((p->>'active')::boolean, true)) returning id into v_id;
  else
    update characters set name = v_name, grp = v_grp, spec = p->'spec', updated_at = now() where id = v_id;
    if not found then raise exception 'no_card'; end if;
  end if;
  insert into audit_log (actor, action, detail) values (auth.uid(), 'character_save', jsonb_build_object('character', v_id, 'name', v_name));
  return v_id;
end $$;

create or replace function public.character_active(p_id uuid, p_on boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_owner() then raise exception 'forbidden'; end if;
  update characters set active = coalesce(p_on, false), updated_at = now() where id = p_id;
end $$;

create or replace function public.character_delete(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_owner() then raise exception 'forbidden'; end if;
  delete from characters where id = p_id;
  insert into audit_log (actor, action, detail) values (auth.uid(), 'character_delete', jsonb_build_object('character', p_id));
end $$;

-- PROPIETARIO: fachada de la cola de la portada (null = la fachada dibujada por la app). Devuelve la anterior para borrarla.
create or replace function public.set_door_bg(p_path text)
returns text language plpgsql security definer set search_path = public as $$
declare v_old text;
begin
  if not is_owner() then raise exception 'forbidden'; end if;
  if p_path is not null and p_path !~ '^games/[A-Za-z0-9._-]+$' then raise exception 'bad_game'; end if;
  select door_bg_path into v_old from settings where id = 1;
  update settings set door_bg_path = p_path where id = 1;
  return case when v_old is distinct from p_path then v_old end;
end $$;

-- PROPIETARIO: fondo de la barra (null = la barra dibujada por la app). Devuelve el fondo anterior para borrarlo del almacén.
create or replace function public.set_bar_bg(p_path text)
returns text language plpgsql security definer set search_path = public as $$
declare v_old text;
begin
  if not is_owner() then raise exception 'forbidden'; end if;
  if p_path is not null and p_path !~ '^games/[A-Za-z0-9._-]+$' then raise exception 'bad_game'; end if;
  select bar_bg_path into v_old from settings where id = 1;
  update settings set bar_bg_path = p_path where id = 1;
  return case when v_old is distinct from p_path then v_old end;
end $$;

-- =====================================================================
-- CONCIERTOS Y ENTRADAS
-- =====================================================================

-- Descuento en céntimos de un concierto para un precio dado
create or replace function public.concert_discount_cents(p_price int, p_kind text, p_value numeric)
returns int language sql immutable as $$
  select case when p_price is null or p_kind is null or p_value is null then 0
              when p_kind = 'eur' then least(p_price, round(p_value * 100)::int)
              else least(p_price, round(p_price * p_value / 100.0)::int) end;
$$;

-- PROPIETARIO: crear o modificar un concierto
create or replace function public.concert_save(p jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid := nullif(p->>'id', '')::uuid; v_title text := left(trim(coalesce(p->>'title', '')), 80);
        v_at timestamptz; v_poster text := p->>'poster_path'; v_price int; v_kind text := nullif(p->>'discount_kind', ''); v_val numeric;
begin
  if not is_owner() then raise exception 'forbidden'; end if;
  if v_title = '' then raise exception 'concert_title_required'; end if;
  begin v_at := (p->>'starts_at')::timestamptz; exception when others then v_at := null; end;
  if v_at is null then raise exception 'concert_date_required'; end if;
  if coalesce(v_poster, '') !~ '^concerts/[A-Za-z0-9._-]+$' then raise exception 'concert_poster_required'; end if;
  v_price := case when nullif(p->>'price', '') is null then null else round((p->>'price')::numeric * 100)::int end;
  if v_price is not null and (v_price < 0 or v_price > 10000000) then raise exception 'concert_bad_price'; end if;
  v_val := nullif(p->>'discount_value', '')::numeric;
  if v_kind is null or v_val is null then v_kind := null; v_val := null;
  elsif v_kind not in ('eur', 'pct') or v_val <= 0 or (v_kind = 'pct' and v_val > 100)
        or (v_kind = 'eur' and v_price is not null and v_val * 100 > v_price) then raise exception 'concert_bad_discount';
  end if;
  if v_id is null then
    insert into concerts (title, starts_at, poster_path, price_cents, discount_kind, discount_value)
    values (v_title, v_at, v_poster, v_price, v_kind, v_val) returning id into v_id;
    insert into audit_log (actor, action, detail) values (auth.uid(), 'concert_create', jsonb_build_object('concert', v_id, 'title', v_title));
  else
    update concerts set title = v_title, starts_at = v_at, poster_path = v_poster, price_cents = v_price,
                        discount_kind = v_kind, discount_value = v_val, updated_at = now() where id = v_id;
    if not found then raise exception 'concert_not_found'; end if;
    insert into audit_log (actor, action, detail) values (auth.uid(), 'concert_update', jsonb_build_object('concert', v_id, 'title', v_title));
  end if;
  return v_id;
end $$;

-- PROPIETARIO: borrar un concierto (no si ya tiene entradas pagadas). Devuelve el cartel para borrarlo del almacén.
create or replace function public.concert_delete(p_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare c concerts;
begin
  if not is_owner() then raise exception 'forbidden'; end if;
  select * into c from concerts where id = p_id;
  if not found then raise exception 'concert_not_found'; end if;
  if exists (select 1 from ticket_orders where concert_id = p_id and status = 'paid') then raise exception 'concert_has_tickets'; end if;
  delete from concerts where id = p_id;
  insert into audit_log (actor, action, detail) values (auth.uid(), 'concert_delete', jsonb_build_object('concert', p_id, 'title', c.title));
  return case when exists (select 1 from concerts where poster_path = c.poster_path) then null else c.poster_path end;
end $$;

-- PROPIETARIO: activar la venta de entradas (cuando se haya contratado la pasarela de pago)
create or replace function public.set_tickets_enabled(p_on boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_owner() then raise exception 'forbidden'; end if;
  update settings set tickets_enabled = coalesce(p_on, false) where id = 1;
  insert into audit_log (actor, action, detail) values (auth.uid(), 'tickets_enabled', jsonb_build_object('on', p_on));
end $$;

-- CLIENTE: empezar la compra de una entrada. Crea el pedido pendiente con el importe calculado aquí;
-- la pasarela de pago (cuando se contrate) cobrará ese pedido y lo marcará como pagado.
create or replace function public.ticket_start(p_concert uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c concerts; v_coupon uuid := my_active_coupon(); v_disc int; o ticket_orders;
begin
  if not coalesce((select tickets_enabled from settings where id = 1), false) then raise exception 'tickets_soon'; end if;
  select * into c from concerts where id = p_concert;
  if not found or c.starts_at < now() then raise exception 'concert_not_found'; end if;
  if c.price_cents is null then raise exception 'tickets_soon'; end if;
  v_disc := concert_discount_cents(c.price_cents, c.discount_kind, c.discount_value);
  insert into ticket_orders (concert_id, coupon_id, customer_id, email, concert_title, concert_at, price_cents, discount_cents, total_cents)
  values (c.id, v_coupon, auth.uid(), (select email from coupons where id = v_coupon), c.title, c.starts_at, c.price_cents, v_disc, c.price_cents - v_disc)
  returning * into o;
  return jsonb_build_object('order', o.id, 'title', c.title, 'price_cents', o.price_cents, 'discount_cents', o.discount_cents, 'total_cents', o.total_cents);
end $$;

-- PROPIETARIO: restaurar una copia de seguridad (solo si todavía no hay cupones)
create or replace function public.restore_begin()
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_owner() then raise exception 'forbidden'; end if;
  if coalesce((select value from app_config where key = 'restore_open'), '') = '1' then
    -- una restauración anterior se interrumpió: se descarta lo que quedó a medias y se empieza de nuevo
    delete from stamps;
    delete from coupons;
  elsif exists (select 1 from coupons) or exists (select 1 from stamps) then
    raise exception 'not_empty';
  end if;
  delete from games;
  delete from ticket_orders;
  delete from concerts;
  delete from characters;
  update settings set current_design_id = null, seal_path = null where id = 1;
  delete from designs;
  insert into app_config (key, value) values ('restore_open', '1')
    on conflict (key) do update set value = '1';
  insert into audit_log (actor, action) values (auth.uid(), 'restore_begin');
end $$;

create or replace function public.restore_chunk(p_kind text, p_rows jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare n int := 0;
begin
  if not is_owner() then raise exception 'forbidden'; end if;
  if coalesce((select value from app_config where key = 'restore_open'), '') <> '1' then raise exception 'restore_closed'; end if;
  if p_kind = 'designs' then
    insert into designs (id, cover_path, inside_path, layout, ar, created_at)
    select (r->>'id')::uuid, r->>'cover_path', r->>'inside_path', nullif(r->'layout', 'null'::jsonb),
           nullif(r->>'ar', '')::numeric, coalesce(nullif(r->>'created_at', '')::timestamptz, now())
      from jsonb_array_elements(p_rows) r;
    get diagnostics n = row_count;
  elsif p_kind = 'settings' then
    update settings
       set current_design_id = (select d.id from designs d where d.id = nullif(p_rows->0->>'current_design_id', '')::uuid),
           seal_path = nullif(p_rows->0->>'seal_path', ''),
           points_per_stamp = coalesce(nullif(p_rows->0->>'points_per_stamp', '')::int, points_per_stamp),
           tickets_enabled = coalesce(nullif(p_rows->0->>'tickets_enabled', '')::boolean, tickets_enabled),
           bar_bg_path = nullif(p_rows->0->>'bar_bg_path', ''),
           door_bg_path = nullif(p_rows->0->>'door_bg_path', '')
     where id = 1;
    n := 1;
  elsif p_kind = 'coupons' then
    insert into coupons (id, number, customer_id, email, name, qr_token, status, design_id, created_at, deleted_at, completed, points)
    select (r->>'id')::uuid, (r->>'number')::bigint, null, lower(r->>'email'), nullif(r->>'name', ''), r->>'qr_token',
           case when r->>'status' = 'deleted' then 'deleted' else 'active' end,
           (select d.id from designs d where d.id = nullif(r->>'design_id', '')::uuid),
           coalesce(nullif(r->>'created_at', '')::timestamptz, now()), nullif(r->>'deleted_at', '')::timestamptz,
           coalesce(nullif(r->>'completed', '')::int, 0), coalesce(nullif(r->>'points', '')::int, 0)
      from jsonb_array_elements(p_rows) r;
    get diagnostics n = row_count;
  elsif p_kind = 'stamps' then
    insert into stamps (id, coupon_id, box, stamped_at, image_path, deleted_at, redeemed_at, source, renewed_at)
    select (r->>'id')::uuid, (r->>'coupon_id')::uuid, (r->>'box')::int,
           coalesce(nullif(r->>'stamped_at', '')::timestamptz, now()), nullif(r->>'image_path', ''),
           nullif(r->>'deleted_at', '')::timestamptz, nullif(r->>'redeemed_at', '')::timestamptz, nullif(r->>'source', ''),
           nullif(r->>'renewed_at', '')::timestamptz
      from jsonb_array_elements(p_rows) r
     where exists (select 1 from coupons c where c.id = (r->>'coupon_id')::uuid);
    get diagnostics n = row_count;
  elsif p_kind = 'consents' then
    insert into consents (id, user_id, email, version, accepted_at)
    select coalesce(nullif(r->>'id', '')::uuid, gen_random_uuid()), nullif(r->>'user_id', '')::uuid, lower(r->>'email'), r->>'version',
           coalesce(nullif(r->>'accepted_at', '')::timestamptz, now())
      from jsonb_array_elements(p_rows) r
    on conflict (email, version) do nothing;
    get diagnostics n = row_count;
  elsif p_kind = 'games' then
    insert into games (id, kind, name, starts_at, ends_at, stopped_at, prize_mode, single_prize, consolation, no_prize_msg, cells, img_a, img_b, created_at, reward_mode, points, config, finalized_at)
    select (r->>'id')::uuid, r->>'kind', r->>'name', (r->>'starts_at')::timestamptz, (r->>'ends_at')::timestamptz, nullif(r->>'stopped_at', '')::timestamptz,
           r->>'prize_mode', r->>'single_prize', r->>'consolation', r->>'no_prize_msg', nullif(r->>'cells', '')::int, r->>'img_a', r->>'img_b',
           coalesce(nullif(r->>'created_at', '')::timestamptz, now()), coalesce(r->>'reward_mode', 'prize'), nullif(r->>'points', '')::int, nullif(r->'config', 'null'::jsonb), nullif(r->>'finalized_at', '')::timestamptz
      from jsonb_array_elements(p_rows) r
    on conflict (id) do nothing;
    get diagnostics n = row_count;
  elsif p_kind = 'game_prizes' then
    insert into game_prizes (id, game_id, pos, name, units, remaining)
    select (r->>'id')::uuid, (r->>'game_id')::uuid, coalesce((r->>'pos')::int, 0), r->>'name', (r->>'units')::int, (r->>'remaining')::int
      from jsonb_array_elements(p_rows) r where exists (select 1 from games g where g.id = (r->>'game_id')::uuid)
    on conflict (id) do nothing;
    get diagnostics n = row_count;
  elsif p_kind = 'game_spots' then
    insert into game_spots (id, game_id, idx, label, token, question, answer)
    select (r->>'id')::uuid, (r->>'game_id')::uuid, (r->>'idx')::int, r->>'label', r->>'token', r->>'question', r->>'answer'
      from jsonb_array_elements(p_rows) r where exists (select 1 from games g where g.id = (r->>'game_id')::uuid)
    on conflict (id) do nothing;
    get diagnostics n = row_count;
  elsif p_kind = 'game_cards' then
    insert into game_cards (id, game_id, coupon_id, created_at, completed_at, prize_kind, prize, prize_id, revealed_at, delivered_at, declined_at, play_started_at, points, best_score, best_at, score_removed)
    select (r->>'id')::uuid, (r->>'game_id')::uuid, (r->>'coupon_id')::uuid, coalesce(nullif(r->>'created_at', '')::timestamptz, now()),
           nullif(r->>'completed_at', '')::timestamptz, r->>'prize_kind', r->>'prize', nullif(r->>'prize_id', '')::uuid,
           nullif(r->>'revealed_at', '')::timestamptz, nullif(r->>'delivered_at', '')::timestamptz,
           nullif(r->>'declined_at', '')::timestamptz, nullif(r->>'play_started_at', '')::timestamptz, nullif(r->>'points', '')::int,
           nullif(r->>'best_score', '')::int, nullif(r->>'best_at', '')::timestamptz, coalesce((r->>'score_removed')::boolean, false)
      from jsonb_array_elements(p_rows) r
     where exists (select 1 from games g where g.id = (r->>'game_id')::uuid)
       and exists (select 1 from coupons c where c.id = (r->>'coupon_id')::uuid)
    on conflict (id) do nothing;
    get diagnostics n = row_count;
  elsif p_kind = 'game_finds' then
    insert into game_finds (card_id, spot_id, found_at)
    select (r->>'card_id')::uuid, (r->>'spot_id')::uuid, coalesce(nullif(r->>'found_at', '')::timestamptz, now())
      from jsonb_array_elements(p_rows) r
     where exists (select 1 from game_cards k where k.id = (r->>'card_id')::uuid)
       and exists (select 1 from game_spots sp where sp.id = (r->>'spot_id')::uuid)
    on conflict do nothing;
    get diagnostics n = row_count;
  elsif p_kind = 'game_awards' then
    insert into game_awards (id, game_id, coupon_id, pos, prize, score, awarded_at, delivered_at)
    select (r->>'id')::uuid, (r->>'game_id')::uuid, (r->>'coupon_id')::uuid, (r->>'pos')::int, r->>'prize', nullif(r->>'score', '')::int,
           coalesce(nullif(r->>'awarded_at', '')::timestamptz, now()), nullif(r->>'delivered_at', '')::timestamptz
      from jsonb_array_elements(p_rows) r
     where exists (select 1 from games g where g.id = (r->>'game_id')::uuid) and exists (select 1 from coupons c where c.id = (r->>'coupon_id')::uuid)
    on conflict do nothing;
    get diagnostics n = row_count;
  elsif p_kind = 'characters' then
    insert into characters (id, name, grp, spec, active, created_at, updated_at)
    select (r->>'id')::uuid, r->>'name', coalesce(r->>'grp', 'regular'), coalesce(r->'spec', '{}'::jsonb), coalesce((r->>'active')::boolean, true),
           coalesce(nullif(r->>'created_at', '')::timestamptz, now()), coalesce(nullif(r->>'updated_at', '')::timestamptz, now())
      from jsonb_array_elements(p_rows) r
    on conflict do nothing;
    get diagnostics n = row_count;
  elsif p_kind = 'concerts' then
    insert into concerts (id, title, starts_at, poster_path, price_cents, discount_kind, discount_value, created_at, updated_at)
    select (r->>'id')::uuid, r->>'title', (r->>'starts_at')::timestamptz, r->>'poster_path', nullif(r->>'price_cents', '')::int,
           nullif(r->>'discount_kind', ''), nullif(r->>'discount_value', '')::numeric,
           coalesce(nullif(r->>'created_at', '')::timestamptz, now()), coalesce(nullif(r->>'updated_at', '')::timestamptz, now())
      from jsonb_array_elements(p_rows) r
    on conflict do nothing;
    get diagnostics n = row_count;
  elsif p_kind = 'ticket_orders' then
    insert into ticket_orders (id, concert_id, coupon_id, customer_id, email, concert_title, concert_at, price_cents, discount_cents, total_cents,
                               status, provider, provider_ref, created_at, paid_at, refunded_at)
    select (r->>'id')::uuid,
           (select x.id from concerts x where x.id = nullif(r->>'concert_id', '')::uuid),
           (select x.id from coupons x where x.id = nullif(r->>'coupon_id', '')::uuid),
           null, r->>'email', r->>'concert_title', nullif(r->>'concert_at', '')::timestamptz,
           (r->>'price_cents')::int, coalesce(nullif(r->>'discount_cents', '')::int, 0), (r->>'total_cents')::int,
           coalesce(r->>'status', 'pending'), r->>'provider', r->>'provider_ref',
           coalesce(nullif(r->>'created_at', '')::timestamptz, now()), nullif(r->>'paid_at', '')::timestamptz, nullif(r->>'refunded_at', '')::timestamptz
      from jsonb_array_elements(p_rows) r
    on conflict do nothing;
    get diagnostics n = row_count;
  elsif p_kind = 'points_log' then
    insert into points_log (coupon_id, delta, reason, game_id, created_at)
    select (r->>'coupon_id')::uuid, (r->>'delta')::int, r->>'reason', nullif(r->>'game_id', '')::uuid, coalesce(nullif(r->>'created_at', '')::timestamptz, now())
      from jsonb_array_elements(p_rows) r where exists (select 1 from coupons c where c.id = (r->>'coupon_id')::uuid);
    get diagnostics n = row_count;
  elsif p_kind = 'audit' then
    insert into audit_log (created_at, actor, action, detail)
    select coalesce(nullif(r->>'created_at', '')::timestamptz, now()), null, coalesce(r->>'action', 'restored'), nullif(r->'detail', 'null'::jsonb)
      from jsonb_array_elements(p_rows) r;
    get diagnostics n = row_count;
  else
    raise exception 'bad_kind';
  end if;
  return n;
end $$;

create or replace function public.restore_end()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_max bigint; v_d uuid;
begin
  if not is_owner() then raise exception 'forbidden'; end if;
  select max(number) into v_max from coupons;
  if v_max is null then
    perform setval('public.coupon_number_seq', 0, false);      -- sin cupones: el siguiente será el 00000
  else
    perform setval('public.coupon_number_seq', v_max, true);   -- el siguiente será max + 1
  end if;
  if (select current_design_id from settings where id = 1) is null then
    select id into v_d from designs order by created_at desc limit 1;
    if v_d is null then insert into designs default values returning id into v_d; end if;
    update settings set current_design_id = v_d where id = 1;
  end if;
  delete from app_config where key = 'restore_open';
  insert into audit_log (actor, action) values (auth.uid(), 'restore_end');
  return jsonb_build_object('coupons', (select count(*) from coupons), 'stamps', (select count(*) from stamps));
end $$;

-- PROPIETARIO: crear el código de alta de un dispositivo (válido 10 minutos)
create or replace function public.create_device_invite(p_name text)
returns text language plpgsql security definer set search_path = public as $$
declare v_id uuid := gen_random_uuid(); v_code text;
begin
  if not is_owner() then raise exception 'forbidden'; end if;
  if trim(coalesce(p_name, '')) = '' then raise exception 'name_required'; end if;
  delete from devices where user_id is null and code_expires < now();
  v_code := lpad((('x' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))::bit(32)::bigint % 1000000)::text, 6, '0');
  insert into devices (id, name, code_hash, code_expires)
  values (v_id, left(trim(p_name), 40),
          encode(sha256(convert_to(v_code || v_id::text, 'UTF8')), 'hex'),
          now() + interval '10 minutes');
  insert into audit_log (actor, action, detail) values (auth.uid(), 'device_invite', jsonb_build_object('name', left(trim(p_name), 40)));
  return v_code;
end $$;

-- DISPOSITIVO NUEVO: canjear el código. Devuelve ok | invalid | blocked
create or replace function public.redeem_device_code(p_code text)
returns text language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  if exists (select 1 from devices where user_id = auth.uid()) then return 'ok'; end if;
  delete from redeem_failures where created_at < now() - interval '1 day';
  if (select count(*) from redeem_failures where created_at > now() - interval '10 minutes') >= 10 then
    return 'blocked';
  end if;
  select id into v_id from devices
   where user_id is null and code_expires > now()
     and code_hash = encode(sha256(convert_to(trim(coalesce(p_code, '')) || id::text, 'UTF8')), 'hex');
  if v_id is null then
    insert into redeem_failures default values;
    return 'invalid';
  end if;
  update devices set user_id = auth.uid(), code_hash = null, code_expires = null, last_access = now() where id = v_id;
  insert into audit_log (actor, action, detail) values (auth.uid(), 'device_redeemed', jsonb_build_object('device', v_id));
  return 'ok';
end $$;

-- PROPIETARIO: eliminar un dispositivo
create or replace function public.remove_device(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_owner() then raise exception 'forbidden'; end if;
  delete from devices where id = p_id;
  insert into audit_log (actor, action, detail) values (auth.uid(), 'device_remove', jsonb_build_object('device', p_id));
end $$;

-- PROPIETARIO: guardar el sello activo
create or replace function public.set_seal(p_path text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_owner() then raise exception 'forbidden'; end if;
  update settings set seal_path = p_path where id = 1;
  insert into audit_log (actor, action, detail) values (auth.uid(), 'seal_change', jsonb_build_object('path', p_path));
end $$;

-- PROPIETARIO: nuevo diseño. p_scope = 'all' (todos los cupones) o 'new' (solo nuevos)
create or replace function public.apply_design(p_cover text, p_inside text, p_layout jsonb, p_ar numeric, p_scope text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not is_owner() then raise exception 'forbidden'; end if;
  insert into designs (cover_path, inside_path, layout, ar) values (p_cover, p_inside, p_layout, p_ar) returning id into v_id;
  update settings set current_design_id = v_id where id = 1;
  if p_scope = 'all' then
    update coupons set design_id = v_id where status = 'active';
  end if;
  insert into audit_log (actor, action, detail) values (auth.uid(), 'design_change', jsonb_build_object('design', v_id, 'scope', p_scope));
  return v_id;
end $$;

-- PROPIETARIO: renovar el diseño de todos los cupones
create or replace function public.renew_all_designs()
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_owner() then raise exception 'forbidden'; end if;
  update coupons set design_id = (select current_design_id from settings where id = 1) where status = 'active';
  insert into audit_log (actor, action) values (auth.uid(), 'design_renew_all');
end $$;

-- PROPIETARIO: borra los diseños que ya no usa nadie y devuelve los archivos que se pueden eliminar
create or replace function public.purge_designs()
returns text[] language plpgsql security definer set search_path = public as $$
declare v_paths text[];
begin
  if not is_owner() then raise exception 'forbidden'; end if;
  with del as (
    delete from designs d
     where d.id <> (select current_design_id from settings where id = 1)
       and not exists (select 1 from coupons c where c.design_id = d.id and c.status = 'active')
    returning d.cover_path, d.inside_path
  )
  select coalesce(array_agg(distinct x.p), '{}') into v_paths
    from (select cover_path as p from del union all select inside_path from del) x
   where x.p is not null;
  select coalesce(array_agg(t.p), '{}') into v_paths
    from unnest(v_paths) as t(p)
   where t.p not in (select cover_path from designs where cover_path is not null
                     union select inside_path from designs where inside_path is not null);
  return v_paths;
end $$;

-- ---------------------------------------------------------------------
-- 4. SEGURIDAD: quién puede LEER cada tabla (escribir solo con las funciones de arriba)
-- ---------------------------------------------------------------------

alter table public.app_config      enable row level security;
alter table public.owners          enable row level security;
alter table public.owner_invites  enable row level security;
alter table public.consents       enable row level security;
alter table public.games          enable row level security;
alter table public.game_prizes    enable row level security;
alter table public.game_spots     enable row level security;
alter table public.game_cards     enable row level security;
alter table public.game_finds     enable row level security;
alter table public.points_log     enable row level security;
alter table public.game_awards    enable row level security;
alter table public.concerts       enable row level security;
alter table public.ticket_orders  enable row level security;
alter table public.characters     enable row level security;
alter table public.designs         enable row level security;
alter table public.settings        enable row level security;
alter table public.coupons         enable row level security;
alter table public.stamps          enable row level security;
alter table public.devices         enable row level security;
alter table public.audit_log       enable row level security;
alter table public.redeem_failures enable row level security;

drop policy if exists owners_select on public.owners;
create policy owners_select on public.owners for select to authenticated using (user_id = auth.uid());

drop policy if exists designs_select on public.designs;
create policy designs_select on public.designs for select to authenticated using (true);

drop policy if exists settings_select on public.settings;
create policy settings_select on public.settings for select to authenticated using (true);

drop policy if exists coupons_select on public.coupons;
create policy coupons_select on public.coupons for select to authenticated
  using (public.is_staff() or customer_id = auth.uid());

drop policy if exists stamps_select on public.stamps;
create policy stamps_select on public.stamps for select to authenticated
  using (public.is_staff() or exists (select 1 from public.coupons c where c.id = coupon_id and c.customer_id = auth.uid()));

drop policy if exists devices_select on public.devices;
create policy devices_select on public.devices for select to authenticated using (public.is_owner());

drop policy if exists game_awards_select on public.game_awards;
create policy game_awards_select on public.game_awards for select to authenticated using (public.is_owner());
-- Conciertos: los ve cualquiera con sesión (son los carteles del cupón); las compras, solo el propietario
drop policy if exists concerts_select on public.concerts;
create policy concerts_select on public.concerts for select to authenticated using (true);
-- Personajes: los lee cualquiera con sesión (el juego los dibuja); solo el propietario los cambia (con las funciones)
drop policy if exists characters_select on public.characters;
create policy characters_select on public.characters for select to authenticated using (true);
drop policy if exists ticket_orders_select on public.ticket_orders;
create policy ticket_orders_select on public.ticket_orders for select to authenticated using (public.is_owner());
drop policy if exists points_log_select on public.points_log;
create policy points_log_select on public.points_log for select to authenticated using (public.is_owner());

-- Juegos: solo el propietario lee las tablas (los clientes usan las funciones; nunca ven las respuestas)
drop policy if exists games_select on public.games;
create policy games_select on public.games for select to authenticated using (public.is_owner());
drop policy if exists game_prizes_select on public.game_prizes;
create policy game_prizes_select on public.game_prizes for select to authenticated using (public.is_owner());
drop policy if exists game_spots_select on public.game_spots;
create policy game_spots_select on public.game_spots for select to authenticated using (public.is_owner());
drop policy if exists game_cards_select on public.game_cards;
create policy game_cards_select on public.game_cards for select to authenticated using (public.is_owner());
drop policy if exists game_finds_select on public.game_finds;
create policy game_finds_select on public.game_finds for select to authenticated using (public.is_owner());

drop policy if exists consents_select on public.consents;
create policy consents_select on public.consents for select to authenticated using (public.is_owner());

drop policy if exists audit_select on public.audit_log;
create policy audit_select on public.audit_log for select to authenticated using (public.is_owner());

-- Permiso de LECTURA a nivel de tabla para quien tiene sesión (las políticas de arriba deciden qué filas ve cada uno).
-- Los proyectos nuevos de Supabase ya no lo conceden solos: sin esto sale «permission denied for table ...».
grant usage on schema public to authenticated;
grant select on all tables in schema public to authenticated;

-- Sin sesión (anon) no se puede tocar nada; con sesión solo lo que dicen las políticas
revoke all on all tables    in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke execute on all functions in schema public from public, anon;
grant  execute on all functions in schema public to authenticated;

-- ---------------------------------------------------------------------
-- 5. ALMACÉN DE IMÁGENES (diseños y sellos): lectura pública, escritura solo propietario
-- ---------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('assets', 'assets', true, 5242880, array['image/png', 'image/jpeg', 'image/webp', 'audio/mpeg', 'audio/mp3', 'audio/mp4', 'audio/x-m4a', 'audio/aac', 'audio/wav', 'audio/x-wav', 'audio/ogg'])
on conflict (id) do update
  set public = true, file_size_limit = 5242880, allowed_mime_types = array['image/png', 'image/jpeg', 'image/webp', 'audio/mpeg', 'audio/mp3', 'audio/mp4', 'audio/x-m4a', 'audio/aac', 'audio/wav', 'audio/x-wav', 'audio/ogg'];

drop policy if exists assets_owner_insert on storage.objects;
create policy assets_owner_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'assets' and public.is_owner());

-- Necesaria para poder borrar archivos desde la página (el borrado consulta antes el archivo)
drop policy if exists assets_owner_select on storage.objects;
create policy assets_owner_select on storage.objects for select to authenticated
  using (bucket_id = 'assets' and public.is_owner());

drop policy if exists assets_owner_update on storage.objects;
create policy assets_owner_update on storage.objects for update to authenticated
  using (bucket_id = 'assets' and public.is_owner())
  with check (bucket_id = 'assets' and public.is_owner());

drop policy if exists assets_owner_delete on storage.objects;
create policy assets_owner_delete on storage.objects for delete to authenticated
  using (bucket_id = 'assets' and public.is_owner());

-- FIN

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
