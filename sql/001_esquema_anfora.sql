-- ÁNFORA · Esquema nuevo para un proyecto Supabase/PostgreSQL independiente.
-- Ejecutar únicamente en una base NUEVA. No modifica tablas del V407.
begin;

create schema if not exists anfora_private;
revoke all on schema anfora_private from public, anon, authenticated;
grant usage on schema anfora_private to authenticated;

create table public.anfora_areas (
  id uuid primary key default gen_random_uuid(),
  nombre text not null check (length(btrim(nombre)) between 2 and 120),
  activa boolean not null default true,
  creada_en timestamptz not null default now()
);
create unique index anfora_areas_nombre_uq on public.anfora_areas (lower(btrim(nombre)));

create table public.anfora_asuntos (
  id uuid primary key default gen_random_uuid(),
  nombre text not null check (length(btrim(nombre)) between 2 and 180),
  activo boolean not null default true,
  creado_en timestamptz not null default now()
);
create unique index anfora_asuntos_nombre_uq on public.anfora_asuntos (lower(btrim(nombre)));

create table public.anfora_perfiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nombre text not null default '' check (length(nombre) <= 180),
  rol text not null default 'usuario'
    check (rol in ('administrador','archivo','coordinador','usuario')),
  area_id uuid references public.anfora_areas(id) on delete set null,
  activo boolean not null default false,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);
create index anfora_perfiles_area_idx on public.anfora_perfiles(area_id);

create table public.anfora_equipos (
  coordinador_id uuid not null references public.anfora_perfiles(id) on delete cascade,
  integrante_id uuid not null references public.anfora_perfiles(id) on delete cascade,
  creado_en timestamptz not null default now(),
  primary key (coordinador_id, integrante_id),
  constraint anfora_equipo_sin_autoreferencia check (coordinador_id <> integrante_id)
);
create index anfora_equipos_integrante_idx on public.anfora_equipos(integrante_id);

create table public.anfora_expedientes (
  id uuid primary key default gen_random_uuid(),
  numero text not null check (length(btrim(numero)) between 1 and 80),
  anio integer not null check (anio between 1900 and 2200),
  extension text not null default '' check (length(extension) <= 80),
  asunto_id uuid not null references public.anfora_asuntos(id),
  area_origen_id uuid not null references public.anfora_areas(id),
  area_ubicacion_id uuid references public.anfora_areas(id),
  ubicacion_detalle text not null default '' check (length(ubicacion_detalle) <= 240),
  folios integer check (folios is null or folios >= 0),
  observaciones text not null default '',
  estado text not null default 'en_custodia'
    check (estado in ('en_custodia','en_prestamo','derivado')),
  creado_por uuid references public.anfora_perfiles(id) on delete set null,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  unique (numero, anio, extension)
);
create index anfora_expedientes_estado_idx on public.anfora_expedientes(estado);
create index anfora_expedientes_area_idx on public.anfora_expedientes(area_ubicacion_id);
create index anfora_expedientes_numero_idx on public.anfora_expedientes(numero, anio);

create table public.anfora_solicitudes (
  id uuid primary key default gen_random_uuid(),
  solicitante_id uuid not null default auth.uid() references public.anfora_perfiles(id),
  area_solicitante_id uuid references public.anfora_areas(id),
  motivo text not null check (length(btrim(motivo)) between 3 and 2000),
  estado text not null default 'registrada'
    check (estado in ('registrada','en_atencion','entrega_parcial','entrega_total','rechazada','cerrada')),
  observaciones_atencion text not null default '',
  atendida_por uuid references public.anfora_perfiles(id),
  creada_en timestamptz not null default now(),
  actualizada_en timestamptz not null default now(),
  cerrada_en timestamptz
);
create index anfora_solicitudes_solicitante_idx on public.anfora_solicitudes(solicitante_id, creada_en desc);
create index anfora_solicitudes_estado_idx on public.anfora_solicitudes(estado, creada_en desc);

create table public.anfora_solicitud_items (
  id uuid primary key default gen_random_uuid(),
  solicitud_id uuid not null references public.anfora_solicitudes(id) on delete cascade,
  expediente_id uuid not null references public.anfora_expedientes(id),
  estado text not null default 'pendiente'
    check (estado in ('pendiente','atendido','no_disponible','cerrado')),
  nota text not null default '',
  creado_en timestamptz not null default now(),
  unique (solicitud_id, expediente_id)
);
create index anfora_solicitud_items_expediente_idx on public.anfora_solicitud_items(expediente_id);

create table public.anfora_prestamos (
  id uuid primary key default gen_random_uuid(),
  expediente_id uuid not null references public.anfora_expedientes(id),
  solicitud_item_id uuid references public.anfora_solicitud_items(id),
  receptor_id uuid not null references public.anfora_perfiles(id),
  area_destino_id uuid not null references public.anfora_areas(id),
  estado text not null default 'entregado'
    check (estado in ('entregado','devolucion_solicitada','devuelto')),
  motivo text not null default '',
  entregado_por uuid not null references public.anfora_perfiles(id),
  entregado_en timestamptz not null default now(),
  vence_en timestamptz not null,
  devolucion_solicitada_en timestamptz,
  devuelto_en timestamptz,
  recibido_por uuid references public.anfora_perfiles(id),
  constraint anfora_prestamo_plazo_valido check (vence_en >= entregado_en),
  constraint anfora_prestamo_devolucion_coherente check (
    estado <> 'devuelto' or (devuelto_en is not null and recibido_por is not null)
  )
);
create unique index anfora_prestamo_activo_por_expediente
  on public.anfora_prestamos(expediente_id)
  where estado in ('entregado','devolucion_solicitada');
create index anfora_prestamos_receptor_idx on public.anfora_prestamos(receptor_id, entregado_en desc);
create index anfora_prestamos_vencimiento_idx on public.anfora_prestamos(vence_en)
  where estado in ('entregado','devolucion_solicitada');

create table public.anfora_cargos (
  id uuid primary key default gen_random_uuid(),
  prestamo_id uuid not null unique references public.anfora_prestamos(id),
  numero bigint generated always as identity unique,
  generado_en timestamptz not null default now()
);

create table public.anfora_derivaciones (
  id uuid primary key default gen_random_uuid(),
  expediente_id uuid not null references public.anfora_expedientes(id),
  destino_area_id uuid not null references public.anfora_areas(id),
  responsable_id uuid references public.anfora_perfiles(id),
  motivo text not null check (length(btrim(motivo)) between 3 and 2000),
  estado text not null default 'derivado'
    check (estado in ('derivado','retornado')),
  enviado_por uuid not null references public.anfora_perfiles(id),
  enviado_en timestamptz not null default now(),
  retornado_en timestamptz,
  recibido_por uuid references public.anfora_perfiles(id),
  constraint anfora_derivacion_retorno_coherente check (
    estado <> 'retornado' or (retornado_en is not null and recibido_por is not null)
  )
);
create unique index anfora_derivacion_activa_por_expediente
  on public.anfora_derivaciones(expediente_id) where estado = 'derivado';
create index anfora_derivaciones_destino_idx
  on public.anfora_derivaciones(destino_area_id, enviado_en desc);

create table public.anfora_movimientos (
  id bigint generated always as identity primary key,
  expediente_id uuid not null references public.anfora_expedientes(id),
  solicitud_id uuid references public.anfora_solicitudes(id),
  prestamo_id uuid references public.anfora_prestamos(id),
  derivacion_id uuid references public.anfora_derivaciones(id),
  accion text not null check (length(btrim(accion)) between 3 and 100),
  detalle jsonb not null default '{}'::jsonb,
  actor_id uuid references public.anfora_perfiles(id),
  ocurrido_en timestamptz not null default now()
);
create index anfora_movimientos_expediente_idx
  on public.anfora_movimientos(expediente_id, ocurrido_en desc);

comment on table public.anfora_expedientes is
  'Registro maestro único. Los préstamos, solicitudes y derivaciones no duplican el expediente.';
comment on table public.anfora_movimientos is
  'Bitácora de solo lectura para clientes; los disparadores registran transiciones.';

commit;
