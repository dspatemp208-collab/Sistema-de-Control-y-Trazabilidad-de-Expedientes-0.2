-- Ejecutar DESPUÉS de 001. Transiciones atómicas y bitácora del nuevo sistema.
begin;

create function anfora_private.es_activo()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.anfora_perfiles p
    where p.id = (select auth.uid()) and p.activo
  );
$$;

create function anfora_private.tiene_rol(roles text[])
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.anfora_perfiles p
    where p.id = (select auth.uid()) and p.activo and p.rol = any(roles)
  );
$$;

create function anfora_private.es_integrante_de_mi_equipo(persona uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select anfora_private.tiene_rol(array['coordinador']) and exists (
    select 1 from public.anfora_equipos e
    where e.coordinador_id = (select auth.uid()) and e.integrante_id = persona
  );
$$;

create function anfora_private.puede_ver_solicitud(solicitud uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select anfora_private.es_activo() and exists (
    select 1 from public.anfora_solicitudes s
    where s.id = solicitud and (
      s.solicitante_id = (select auth.uid())
      or anfora_private.tiene_rol(array['administrador','archivo'])
      or anfora_private.es_integrante_de_mi_equipo(s.solicitante_id)
    )
  );
$$;

create function anfora_private.puede_editar_solicitud(solicitud uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select anfora_private.es_activo() and exists (
    select 1 from public.anfora_solicitudes s
    where s.id = solicitud and s.estado = 'registrada'
      and (s.solicitante_id = (select auth.uid())
        or anfora_private.tiene_rol(array['administrador','archivo']))
  );
$$;

create function anfora_private.puede_ver_prestamo(prestamo uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select anfora_private.es_activo() and exists (
    select 1 from public.anfora_prestamos p
    where p.id = prestamo and (
      p.receptor_id = (select auth.uid())
      or anfora_private.tiene_rol(array['administrador','archivo'])
      or anfora_private.es_integrante_de_mi_equipo(p.receptor_id)
    )
  );
$$;

create function anfora_private.puede_ver_historial(expediente uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select anfora_private.es_activo() and (
    anfora_private.tiene_rol(array['administrador','archivo'])
    or exists (
      select 1 from public.anfora_solicitud_items i
      join public.anfora_solicitudes s on s.id = i.solicitud_id
      where i.expediente_id = expediente
        and (s.solicitante_id = (select auth.uid())
          or anfora_private.es_integrante_de_mi_equipo(s.solicitante_id))
    )
    or exists (
      select 1 from public.anfora_prestamos p
      where p.expediente_id = expediente
        and (p.receptor_id = (select auth.uid())
          or anfora_private.es_integrante_de_mi_equipo(p.receptor_id))
    )
  );
$$;

create function anfora_private.validar_equipo()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.anfora_perfiles p
    where p.id = new.coordinador_id and p.rol = 'coordinador' and p.activo
  ) then
    raise exception 'El responsable debe ser un coordinador activo';
  end if;
  if not exists (
    select 1 from public.anfora_perfiles p
    where p.id = new.integrante_id and p.activo
  ) then
    raise exception 'El integrante debe tener un perfil activo';
  end if;
  return new;
end;
$$;
create trigger anfora_equipo_validar
before insert on public.anfora_equipos
for each row execute function anfora_private.validar_equipo();

create function anfora_private.proteger_administrador()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if old.rol = 'administrador' and old.activo
     and (new.rol <> 'administrador' or not new.activo)
     and not exists (
       select 1 from public.anfora_perfiles p
       where p.id <> old.id and p.rol = 'administrador' and p.activo
     ) then
    raise exception 'No se puede desactivar al último administrador';
  end if;
  new.actualizado_en := now();
  return new;
end;
$$;
create trigger anfora_perfil_proteger_admin
before update on public.anfora_perfiles
for each row execute function anfora_private.proteger_administrador();

-- Cada expediente empieza en custodia. Los clientes no pueden fijar su estado.
create function anfora_private.preparar_expediente()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.creado_por := auth.uid();
    new.estado := 'en_custodia';
    new.actualizado_en := now();
  else
    new.actualizado_en := now();
  end if;
  return new;
end;
$$;
create trigger anfora_expediente_preparar
before insert or update on public.anfora_expedientes
for each row execute function anfora_private.preparar_expediente();

create function anfora_private.registrar_expediente()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.anfora_movimientos(expediente_id, accion, detalle, actor_id)
  values (new.id, 'expediente_creado',
    pg_catalog.jsonb_build_object('numero', new.numero, 'anio', new.anio), auth.uid());
  return new;
end;
$$;
create trigger anfora_expediente_auditar
after insert on public.anfora_expedientes
for each row execute function anfora_private.registrar_expediente();

create function anfora_private.registrar_solicitud()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if old.estado in ('cerrada','rechazada') and new.estado <> old.estado then
      raise exception 'Una solicitud cerrada o rechazada no se puede reabrir';
    end if;
    if new.estado = 'cerrada' and old.estado <> 'cerrada' and exists (
      select 1 from public.anfora_solicitud_items i
      where i.solicitud_id = old.id and i.estado = 'pendiente'
    ) then
      raise exception 'La solicitud conserva expedientes pendientes';
    end if;
    new.actualizada_en := now();
    if new.estado = 'cerrada' and old.estado <> 'cerrada' then
      new.cerrada_en := now();
    end if;
    new.atendida_por := auth.uid();
  end if;
  return new;
end;
$$;
create trigger anfora_solicitud_preparar
before update on public.anfora_solicitudes
for each row execute function anfora_private.registrar_solicitud();

create function anfora_private.auditar_solicitud_estado()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if old.estado <> new.estado then
    insert into public.anfora_movimientos
      (expediente_id, solicitud_id, accion, detalle, actor_id)
    select i.expediente_id, new.id, 'solicitud_estado',
      pg_catalog.jsonb_build_object('anterior', old.estado, 'nuevo', new.estado),
      auth.uid()
    from public.anfora_solicitud_items i where i.solicitud_id = new.id;
  end if;
  return new;
end;
$$;
create trigger anfora_solicitud_estado_auditar
after update of estado on public.anfora_solicitudes
for each row execute function anfora_private.auditar_solicitud_estado();

create function anfora_private.auditar_solicitud_item()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.anfora_movimientos
    (expediente_id, solicitud_id, accion, detalle, actor_id)
  values
    (new.expediente_id, new.solicitud_id,
     case when tg_op = 'INSERT' then 'solicitud_registrada' else 'solicitud_item_actualizado' end,
     pg_catalog.jsonb_build_object('estado', new.estado), auth.uid());
  return new;
end;
$$;
create trigger anfora_solicitud_item_auditar
after insert or update of estado on public.anfora_solicitud_items
for each row execute function anfora_private.auditar_solicitud_item();

-- El préstamo bloquea el expediente en la misma transacción que crea el cargo.
create function anfora_private.preparar_prestamo()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  new.entregado_por := auth.uid();
  new.entregado_en := now();
  new.estado := 'entregado';
  if new.vence_en < new.entregado_en then
    raise exception 'La fecha límite no puede ser anterior a la entrega';
  end if;
  if new.solicitud_item_id is not null and not exists (
    select 1 from public.anfora_solicitud_items i
    where i.id = new.solicitud_item_id and i.expediente_id = new.expediente_id
  ) then
    raise exception 'El ítem de solicitud no corresponde al expediente';
  end if;
  return new;
end;
$$;
create trigger anfora_prestamo_preparar
before insert on public.anfora_prestamos
for each row execute function anfora_private.preparar_prestamo();

create function anfora_private.entregar_prestamo()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  update public.anfora_expedientes
  set estado = 'en_prestamo',
      area_ubicacion_id = new.area_destino_id,
      ubicacion_detalle = 'En préstamo'
  where id = new.expediente_id and estado = 'en_custodia';
  if not found then
    raise exception 'El expediente no está disponible en custodia';
  end if;
  insert into public.anfora_cargos(prestamo_id) values (new.id);
  insert into public.anfora_movimientos
    (expediente_id, prestamo_id, accion, detalle, actor_id)
  values (new.expediente_id, new.id, 'prestamo_entregado',
    pg_catalog.jsonb_build_object('receptor_id', new.receptor_id,
                                  'vence_en', new.vence_en), auth.uid());
  return new;
end;
$$;
create trigger anfora_prestamo_entregar
after insert on public.anfora_prestamos
for each row execute function anfora_private.entregar_prestamo();

create function anfora_private.validar_devolucion()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if new.estado = old.estado then return new; end if;
  if old.estado = 'entregado' and new.estado = 'devolucion_solicitada' then
    if not (old.receptor_id = auth.uid()
      or anfora_private.tiene_rol(array['administrador','archivo'])) then
      raise exception 'No autorizado para solicitar la devolución';
    end if;
    new.devolucion_solicitada_en := now();
  elsif old.estado in ('entregado','devolucion_solicitada')
    and new.estado = 'devuelto' then
    if not anfora_private.tiene_rol(array['administrador','archivo']) then
      raise exception 'Solo Archivo o Administración confirma la recepción';
    end if;
    new.devuelto_en := now();
    new.recibido_por := auth.uid();
  else
    raise exception 'Transición de préstamo no permitida: % -> %', old.estado, new.estado;
  end if;
  return new;
end;
$$;
create trigger anfora_prestamo_validar_devolucion
before update of estado on public.anfora_prestamos
for each row execute function anfora_private.validar_devolucion();

create function anfora_private.cerrar_prestamo()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if new.estado <> old.estado then
    if new.estado = 'devuelto' then
      update public.anfora_expedientes
      set estado = 'en_custodia', area_ubicacion_id = null,
          ubicacion_detalle = 'Archivo Central'
      where id = new.expediente_id and estado = 'en_prestamo';
      if not found then raise exception 'Estado inconsistente del expediente'; end if;
    end if;
    insert into public.anfora_movimientos
      (expediente_id, prestamo_id, accion, detalle, actor_id)
    values (new.expediente_id, new.id,
      case when new.estado = 'devuelto' then 'devolucion_confirmada'
           else 'devolucion_solicitada' end,
      pg_catalog.jsonb_build_object('estado', new.estado), auth.uid());
  end if;
  return new;
end;
$$;
create trigger anfora_prestamo_cerrar
after update of estado on public.anfora_prestamos
for each row execute function anfora_private.cerrar_prestamo();

create function anfora_private.preparar_derivacion()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  new.enviado_por := auth.uid();
  new.enviado_en := now();
  new.estado := 'derivado';
  return new;
end;
$$;
create trigger anfora_derivacion_preparar
before insert on public.anfora_derivaciones
for each row execute function anfora_private.preparar_derivacion();

create function anfora_private.enviar_derivacion()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  update public.anfora_expedientes
  set estado = 'derivado', area_ubicacion_id = new.destino_area_id,
      ubicacion_detalle = 'Derivado'
  where id = new.expediente_id and estado = 'en_custodia';
  if not found then raise exception 'El expediente no está disponible en custodia'; end if;
  insert into public.anfora_movimientos
    (expediente_id, derivacion_id, accion, detalle, actor_id)
  values (new.expediente_id, new.id, 'expediente_derivado',
    pg_catalog.jsonb_build_object('destino_area_id', new.destino_area_id), auth.uid());
  return new;
end;
$$;
create trigger anfora_derivacion_enviar
after insert on public.anfora_derivaciones
for each row execute function anfora_private.enviar_derivacion();

create function anfora_private.validar_retorno()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if new.estado = old.estado then return new; end if;
  if old.estado <> 'derivado' or new.estado <> 'retornado'
    or not anfora_private.tiene_rol(array['administrador','archivo']) then
    raise exception 'Solo Archivo o Administración registra el retorno';
  end if;
  new.retornado_en := now();
  new.recibido_por := auth.uid();
  return new;
end;
$$;
create trigger anfora_derivacion_validar_retorno
before update of estado on public.anfora_derivaciones
for each row execute function anfora_private.validar_retorno();

create function anfora_private.cerrar_derivacion()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if old.estado <> new.estado and new.estado = 'retornado' then
    update public.anfora_expedientes
    set estado = 'en_custodia', area_ubicacion_id = null,
        ubicacion_detalle = 'Archivo Central'
    where id = new.expediente_id and estado = 'derivado';
    if not found then raise exception 'Estado inconsistente del expediente'; end if;
    insert into public.anfora_movimientos
      (expediente_id, derivacion_id, accion, detalle, actor_id)
    values (new.expediente_id, new.id, 'derivacion_retornada',
      pg_catalog.jsonb_build_object('destino_area_id', new.destino_area_id),
      auth.uid());
  end if;
  return new;
end;
$$;
create trigger anfora_derivacion_cerrar
after update of estado on public.anfora_derivaciones
for each row execute function anfora_private.cerrar_derivacion();

-- Cada cuenta nace inactiva y como usuario común. Un administrador la habilita.
create function anfora_private.crear_perfil()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.anfora_perfiles(id, nombre, rol, activo)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', ''),
          'usuario', false)
  on conflict (id) do nothing;
  return new;
end;
$$;
create trigger anfora_usuario_crear_perfil
after insert on auth.users
for each row execute function anfora_private.crear_perfil();

insert into public.anfora_perfiles(id, nombre, rol, activo)
select u.id, coalesce(u.raw_user_meta_data ->> 'full_name', ''),
       'usuario', false
from auth.users u
on conflict (id) do nothing;

revoke execute on all functions in schema anfora_private from public, anon;
grant execute on function
  anfora_private.es_activo(),
  anfora_private.tiene_rol(text[]),
  anfora_private.es_integrante_de_mi_equipo(uuid),
  anfora_private.puede_ver_solicitud(uuid),
  anfora_private.puede_editar_solicitud(uuid),
  anfora_private.puede_ver_prestamo(uuid),
  anfora_private.puede_ver_historial(uuid)
to authenticated;

commit;
