-- Ejecutar DESPUÉS de 001 y 002.
-- anon no recibe acceso. Los clientes autenticados solo reciben operaciones
-- compatibles con su rol; los disparadores de 002 controlan las transiciones.
begin;

alter table public.anfora_areas enable row level security;
alter table public.anfora_asuntos enable row level security;
alter table public.anfora_perfiles enable row level security;
alter table public.anfora_equipos enable row level security;
alter table public.anfora_expedientes enable row level security;
alter table public.anfora_solicitudes enable row level security;
alter table public.anfora_solicitud_items enable row level security;
alter table public.anfora_prestamos enable row level security;
alter table public.anfora_cargos enable row level security;
alter table public.anfora_derivaciones enable row level security;
alter table public.anfora_movimientos enable row level security;

revoke all on table
  public.anfora_areas, public.anfora_asuntos, public.anfora_perfiles,
  public.anfora_equipos, public.anfora_expedientes,
  public.anfora_solicitudes, public.anfora_solicitud_items,
  public.anfora_prestamos, public.anfora_cargos,
  public.anfora_derivaciones, public.anfora_movimientos
from anon, authenticated;

grant select on table
  public.anfora_areas, public.anfora_asuntos, public.anfora_perfiles,
  public.anfora_equipos, public.anfora_expedientes,
  public.anfora_solicitudes, public.anfora_solicitud_items,
  public.anfora_prestamos, public.anfora_cargos,
  public.anfora_derivaciones, public.anfora_movimientos
to authenticated;

grant insert(nombre, activa), update(nombre, activa)
  on public.anfora_areas to authenticated;
grant insert(nombre, activo), update(nombre, activo)
  on public.anfora_asuntos to authenticated;
grant update(nombre, rol, area_id, activo)
  on public.anfora_perfiles to authenticated;
grant insert(coordinador_id, integrante_id), delete
  on public.anfora_equipos to authenticated;
grant insert(numero, anio, extension, asunto_id, area_origen_id,
  area_ubicacion_id, ubicacion_detalle, folios, observaciones),
  update(asunto_id, area_origen_id, area_ubicacion_id,
    ubicacion_detalle, folios, observaciones)
  on public.anfora_expedientes to authenticated;
grant insert(area_solicitante_id, motivo),
  update(estado, observaciones_atencion)
  on public.anfora_solicitudes to authenticated;
grant insert(solicitud_id, expediente_id, nota), update(estado, nota),
  delete on public.anfora_solicitud_items to authenticated;
grant insert(expediente_id, solicitud_item_id, receptor_id,
  area_destino_id, motivo, vence_en), update(estado)
  on public.anfora_prestamos to authenticated;
grant insert(expediente_id, destino_area_id, responsable_id, motivo),
  update(estado) on public.anfora_derivaciones to authenticated;
-- anfora_cargos y anfora_movimientos: lectura solamente para clientes.

create policy anfora_areas_leer on public.anfora_areas
for select to authenticated
using ((select anfora_private.es_activo()));
create policy anfora_areas_insertar on public.anfora_areas
for insert to authenticated
with check ((select anfora_private.tiene_rol(array['administrador','archivo'])));
create policy anfora_areas_actualizar on public.anfora_areas
for update to authenticated
using ((select anfora_private.tiene_rol(array['administrador','archivo'])))
with check ((select anfora_private.tiene_rol(array['administrador','archivo'])));

create policy anfora_asuntos_leer on public.anfora_asuntos
for select to authenticated
using ((select anfora_private.es_activo()));
create policy anfora_asuntos_insertar on public.anfora_asuntos
for insert to authenticated
with check ((select anfora_private.tiene_rol(array['administrador','archivo'])));
create policy anfora_asuntos_actualizar on public.anfora_asuntos
for update to authenticated
using ((select anfora_private.tiene_rol(array['administrador','archivo'])))
with check ((select anfora_private.tiene_rol(array['administrador','archivo'])));

create policy anfora_perfiles_leer on public.anfora_perfiles
for select to authenticated
using (
  id = (select auth.uid())
  or (select anfora_private.tiene_rol(array['administrador','archivo']))
  or anfora_private.es_integrante_de_mi_equipo(id)
);
create policy anfora_perfiles_actualizar on public.anfora_perfiles
for update to authenticated
using ((select anfora_private.tiene_rol(array['administrador'])))
with check ((select anfora_private.tiene_rol(array['administrador'])));

create policy anfora_equipos_leer on public.anfora_equipos
for select to authenticated
using (
  (select anfora_private.tiene_rol(array['administrador','archivo']))
  or (coordinador_id = (select auth.uid())
      and (select anfora_private.tiene_rol(array['coordinador'])))
  or integrante_id = (select auth.uid())
);
create policy anfora_equipos_insertar on public.anfora_equipos
for insert to authenticated
with check ((select anfora_private.tiene_rol(array['administrador'])));
create policy anfora_equipos_eliminar on public.anfora_equipos
for delete to authenticated
using ((select anfora_private.tiene_rol(array['administrador'])));

create policy anfora_expedientes_leer on public.anfora_expedientes
for select to authenticated
using ((select anfora_private.es_activo()));
create policy anfora_expedientes_insertar on public.anfora_expedientes
for insert to authenticated
with check (
  (select anfora_private.tiene_rol(array['administrador','archivo']))
  and estado = 'en_custodia' and creado_por = (select auth.uid())
);
create policy anfora_expedientes_actualizar on public.anfora_expedientes
for update to authenticated
using ((select anfora_private.tiene_rol(array['administrador','archivo'])))
with check ((select anfora_private.tiene_rol(array['administrador','archivo'])));

create policy anfora_solicitudes_leer on public.anfora_solicitudes
for select to authenticated
using (
  (select anfora_private.es_activo()) and (
    solicitante_id = (select auth.uid())
    or (select anfora_private.tiene_rol(array['administrador','archivo']))
    or anfora_private.es_integrante_de_mi_equipo(solicitante_id)
  )
);
create policy anfora_solicitudes_insertar on public.anfora_solicitudes
for insert to authenticated
with check (
  (select anfora_private.es_activo())
  and solicitante_id = (select auth.uid()) and estado = 'registrada'
);
create policy anfora_solicitudes_actualizar on public.anfora_solicitudes
for update to authenticated
using ((select anfora_private.tiene_rol(array['administrador','archivo'])))
with check ((select anfora_private.tiene_rol(array['administrador','archivo'])));

create policy anfora_items_leer on public.anfora_solicitud_items
for select to authenticated
using (anfora_private.puede_ver_solicitud(solicitud_id));
create policy anfora_items_insertar on public.anfora_solicitud_items
for insert to authenticated
with check (
  anfora_private.puede_editar_solicitud(solicitud_id)
  and estado = 'pendiente'
);
create policy anfora_items_actualizar on public.anfora_solicitud_items
for update to authenticated
using ((select anfora_private.tiene_rol(array['administrador','archivo'])))
with check ((select anfora_private.tiene_rol(array['administrador','archivo'])));
create policy anfora_items_eliminar on public.anfora_solicitud_items
for delete to authenticated
using (anfora_private.puede_editar_solicitud(solicitud_id));

create policy anfora_prestamos_leer on public.anfora_prestamos
for select to authenticated
using (
  (select anfora_private.es_activo()) and (
    receptor_id = (select auth.uid())
    or (select anfora_private.tiene_rol(array['administrador','archivo']))
    or anfora_private.es_integrante_de_mi_equipo(receptor_id)
  )
);
create policy anfora_prestamos_insertar on public.anfora_prestamos
for insert to authenticated
with check (
  (select anfora_private.tiene_rol(array['administrador','archivo']))
  and entregado_por = (select auth.uid()) and estado = 'entregado'
);
create policy anfora_prestamos_actualizar on public.anfora_prestamos
for update to authenticated
using (
  (select anfora_private.tiene_rol(array['administrador','archivo']))
  or (receptor_id = (select auth.uid())
      and (select anfora_private.es_activo()))
)
with check (
  (select anfora_private.tiene_rol(array['administrador','archivo']))
  or (receptor_id = (select auth.uid())
      and (select anfora_private.es_activo()))
);

create policy anfora_cargos_leer on public.anfora_cargos
for select to authenticated
using (anfora_private.puede_ver_prestamo(prestamo_id));

create policy anfora_derivaciones_leer on public.anfora_derivaciones
for select to authenticated
using (
  (select anfora_private.es_activo()) and (
    (select anfora_private.tiene_rol(array['administrador','archivo']))
    or responsable_id = (select auth.uid())
    or anfora_private.es_integrante_de_mi_equipo(responsable_id)
  )
);
create policy anfora_derivaciones_insertar on public.anfora_derivaciones
for insert to authenticated
with check (
  (select anfora_private.tiene_rol(array['administrador','archivo']))
  and enviado_por = (select auth.uid()) and estado = 'derivado'
);
create policy anfora_derivaciones_actualizar on public.anfora_derivaciones
for update to authenticated
using ((select anfora_private.tiene_rol(array['administrador','archivo'])))
with check ((select anfora_private.tiene_rol(array['administrador','archivo'])));

create policy anfora_movimientos_leer on public.anfora_movimientos
for select to authenticated
using (anfora_private.puede_ver_historial(expediente_id));

commit;
