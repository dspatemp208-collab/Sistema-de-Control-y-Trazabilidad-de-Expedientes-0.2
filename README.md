# Ánfora

Proyecto nuevo de control y trazabilidad de expedientes, inspirado en la
organización funcional del sistema anterior, pero desarrollado de forma
independiente.

## Abrir la aplicación

Abrir `dist/index.html` directamente en el navegador. No requiere instalar
dependencias para usar la versión local.

La aplicación actual guarda datos solo en el navegador mediante localStorage.
El selector de perfil es una vista de demostración, no autenticación real.

## Base de datos

Los scripts de `sql/` preparan una base Supabase/PostgreSQL nueva. Consultar
`sql/README.md` antes de ejecutarlos. Todavía no están conectados al HTML ni
han sido aplicados a una base de datos.

## Verificación

`verify.cjs` comprueba con Playwright el registro de un expediente, una
solicitud, el buscador y los filtros. Usa Chrome instalado localmente.
