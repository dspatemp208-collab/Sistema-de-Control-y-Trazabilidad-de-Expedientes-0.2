-- Opcional. Ejecutar DESPUÉS de 001–003 en la base nueva.
begin;
insert into public.anfora_areas(nombre) values
  ('Archivo Central'), ('CONAS'), ('DVC'), ('Instrucción')
on conflict do nothing;

insert into public.anfora_asuntos(nombre) values
  ('Procedimiento sancionador'),
  ('Informe técnico'),
  ('Recurso administrativo')
on conflict do nothing;
commit;
