-- Consultas de ejemplo. Son de solo lectura y respetan RLS cuando se ejecutan
-- con un usuario autenticado. No crean objetos ni modifican información.

-- Resumen del panel.
select
  (select count(*) from public.anfora_expedientes) as expedientes,
  (select count(*) from public.anfora_expedientes
     where estado = 'en_custodia') as en_custodia,
  (select count(*) from public.anfora_prestamos
     where estado in ('entregado','devolucion_solicitada')) as prestamos_activos,
  (select count(*) from public.anfora_solicitudes
     where estado in ('registrada','en_atencion')) as solicitudes_pendientes;

-- Préstamos vencidos (excluye los ya devueltos).
select p.id, e.numero, e.anio, p.receptor_id, p.vence_en, p.estado
from public.anfora_prestamos p
join public.anfora_expedientes e on e.id = p.expediente_id
where p.estado in ('entregado','devolucion_solicitada')
  and p.vence_en < now()
order by p.vence_en;

-- Devoluciones solicitadas a la espera de recepción física.
select p.id, e.numero, e.anio, p.receptor_id,
       p.devolucion_solicitada_en
from public.anfora_prestamos p
join public.anfora_expedientes e on e.id = p.expediente_id
where p.estado = 'devolucion_solicitada'
order by p.devolucion_solicitada_en;

-- Trazabilidad: sustituir el UUID mediante un parámetro enlazado.
select m.ocurrido_en, m.accion, m.detalle, m.actor_id
from public.anfora_movimientos m
where m.expediente_id = $1
order by m.ocurrido_en, m.id;
