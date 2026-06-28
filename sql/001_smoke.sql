\set QUIET 1
\pset format unaligned
\pset tuples_only on
\unset QUIET

CREATE EXTENSION pg_agent;

SELECT 'extension-ok'
WHERE EXISTS (
    SELECT 1 FROM pg_extension WHERE extname = 'pg_agent'
);

SELECT 'schema-ok'
WHERE EXISTS (
    SELECT 1 FROM pg_namespace WHERE nspname = 'pg_agent'
);

SELECT c.relname || '|' || c.relkind
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'pg_agent'
  AND c.relkind = 'r'
ORDER BY c.relname;

SELECT p.proname || '|' || pg_get_function_result(p.oid)
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'pg_agent'
  AND p.proname IN (
      'catalog_json',
      'relation_json',
      'check_statement',
      'policy_check',
      'explain_statement',
      'set_object_annotation'
  )
ORDER BY p.proname;

SELECT pg_agent.catalog_json(ARRAY['public']::name[])->>'status';
SELECT pg_agent.relation_json('pg_catalog.pg_class'::regclass)->>'status';
SELECT pg_agent.check_statement('SELECT 1')->>'reason';
SELECT pg_agent.policy_check('SELECT 1')->>'reason';
SELECT pg_agent.explain_statement('SELECT 1')->>'reason';
SELECT pg_agent.set_object_annotation('pg_class', '{"description":"stub"}'::jsonb)->>'reason';

CREATE TABLE public.pg_agent_smoke_orders (
    id bigint PRIMARY KEY,
    user_id bigint NOT NULL,
    created_at timestamp with time zone NOT NULL
);

WITH doc AS (
    SELECT pg_agent.catalog_json(ARRAY['public']::name[]) AS j
)
SELECT 'catalog-relation-ok'
FROM doc
WHERE EXISTS (
    SELECT 1
    FROM jsonb_array_elements(j->'schemas') AS s(schema_obj),
         jsonb_array_elements(schema_obj->'relations') AS r(relation_obj)
    WHERE schema_obj->>'name' = 'public'
      AND relation_obj->>'name' = 'pg_agent_smoke_orders'
);

WITH doc AS (
    SELECT pg_agent.catalog_json(ARRAY['public']::name[]) AS j
)
SELECT 'catalog-attribute-ok'
FROM doc
WHERE EXISTS (
    SELECT 1
    FROM jsonb_array_elements(j->'schemas') AS s(schema_obj),
         jsonb_array_elements(schema_obj->'relations') AS r(relation_obj),
         jsonb_array_elements(relation_obj->'attributes') AS a(attribute_obj)
    WHERE schema_obj->>'name' = 'public'
      AND relation_obj->>'name' = 'pg_agent_smoke_orders'
      AND attribute_obj->>'name' = 'created_at'
);

DROP TABLE public.pg_agent_smoke_orders;

DROP EXTENSION pg_agent;
