# SQL de Ánfora

Estos scripts crean una base nueva e independiente para Ánfora en
Supabase/PostgreSQL. No son migraciones para la base del V407 y no deben
ejecutarse allí.

## Orden

1. Crear un proyecto Supabase nuevo.
2. Ejecutar 001_esquema_anfora.sql.
3. Ejecutar 002_flujos_y_auditoria.sql.
4. Ejecutar 003_permisos_rls.sql.
5. Ejecutar opcionalmente 004_catalogos_iniciales.sql.
6. Usar 005_consultas_operativas.sql como referencia. Su última consulta
   contiene un parámetro $1 y debe ejecutarse como consulta parametrizada.

Los tres primeros archivos son migraciones separadas y transaccionales. Una
instalación debe aplicarlos una sola vez, en ese orden. Hacer una copia de
seguridad antes de aplicar cambios a una base con datos.

## Primer administrador

Las cuentas nuevas y preexistentes reciben perfil usuario inactivo.
Después de crear la primera cuenta mediante Supabase Auth, un operador con
acceso al SQL Editor puede activar solo esa cuenta y darle el rol de
administrador, sustituyendo el correo:

    update public.anfora_perfiles p
    set rol = 'administrador', activo = true,
        actualizado_en = now()
    from auth.users u
    where p.id = u.id
      and lower(u.email) = lower('ADMIN@EJEMPLO.COM');

Confirmar que la actualización afectó exactamente una fila. A partir de ahí,
ese administrador puede habilitar perfiles y asignar integrantes a
anfora_equipos.

## Mapa de datos

| Vista del HTML | Tablas principales |
| --- | --- |
| Registro maestro, buscador y estados | anfora_expedientes, anfora_asuntos, anfora_areas |
| Solicitudes | anfora_solicitudes, anfora_solicitud_items |
| Préstamos, devoluciones y cargos | anfora_prestamos, anfora_cargos |
| Derivaciones | anfora_derivaciones |
| Equipo y perfiles | anfora_perfiles, anfora_equipos |
| Historial | anfora_movimientos |

El expediente maestro es único por número, año y extensión. Las solicitudes
pueden incluir varios expedientes. Los préstamos y derivaciones solo se inician
cuando el expediente está en custodia; su registro cambia el estado
atómicamente. Los retornos devuelven el expediente a custodia. Los cargos y
movimientos se generan automáticamente; los clientes no pueden editarlos.

## Seguridad y alcance

- Las políticas RLS exigen una sesión de Supabase Auth; la clave anon por
  sí sola no da acceso a los datos.
- El selector de perfiles del HTML actual no equivale a esos permisos.
  El HTML todavía guarda datos en localStorage; integrar esta base requiere
  sustituir esa capa por llamadas autenticadas a Supabase y adaptar los
  formularios a los identificadores de las tablas.
- Nunca colocar la clave service_role en el HTML ni publicar credenciales
  de administración.
- Los scripts no se han ejecutado contra ninguna base. Revisar las políticas
  con usuarios de prueba de cada rol antes de usar datos reales.
