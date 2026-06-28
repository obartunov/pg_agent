/* pg_agent--1.0.sql */

CREATE SCHEMA pg_agent;

CREATE TABLE pg_agent.object_annotation (
    classid oid NOT NULL,
    objid oid NOT NULL,
    objsubid integer NOT NULL DEFAULT 0,
    key text NOT NULL,
    value jsonb NOT NULL,
    PRIMARY KEY (classid, objid, objsubid, key)
);

CREATE TABLE pg_agent.role_policy (
    role_name name PRIMARY KEY,
    profile text NOT NULL,
    allowed_schemas text[],
    denied_relations regclass[],
    include_comments boolean DEFAULT false,
    include_stats boolean DEFAULT false,
    allow_dml boolean DEFAULT false,
    allow_ddl boolean DEFAULT false,
    max_plan_total_cost double precision,
    max_plan_rows bigint,
    max_result_rows bigint,
    log_all_checks boolean DEFAULT true
);

CREATE TABLE pg_agent.statement_log (
    log_time timestamp with time zone NOT NULL DEFAULT clock_timestamp(),
    database_name name NOT NULL DEFAULT current_database(),
    role_name name NOT NULL DEFAULT current_user,
    application_name text DEFAULT current_setting('application_name', true),
    queryid bigint,
    normalized_query text,
    decision text NOT NULL,
    reason text,
    estimated_cost double precision,
    estimated_rows bigint,
    relations jsonb,
    policy_version bigint,
    catalog_version bigint
);

CREATE TABLE pg_agent.cache_state (
    id boolean PRIMARY KEY DEFAULT true CHECK (id),
    catalog_version bigint NOT NULL DEFAULT 1,
    policy_version bigint NOT NULL DEFAULT 1
);

INSERT INTO pg_agent.cache_state(id) VALUES (true);

CREATE TABLE pg_agent.catalog_cache (
    cache_key text PRIMARY KEY,
    database_oid oid NOT NULL,
    role_oid oid NOT NULL,
    catalog_version bigint NOT NULL,
    policy_version bigint NOT NULL,
    generated_at timestamp with time zone NOT NULL DEFAULT clock_timestamp(),
    payload jsonb NOT NULL
);

REVOKE ALL ON pg_agent.object_annotation FROM PUBLIC;
REVOKE ALL ON pg_agent.role_policy FROM PUBLIC;
REVOKE ALL ON pg_agent.statement_log FROM PUBLIC;
REVOKE ALL ON pg_agent.cache_state FROM PUBLIC;
REVOKE ALL ON pg_agent.catalog_cache FROM PUBLIC;

CREATE FUNCTION pg_agent.catalog_json(
    schemas name[] DEFAULT ARRAY['public']::name[],
    include_comments boolean DEFAULT true,
    include_indexes boolean DEFAULT true,
    include_foreign_keys boolean DEFAULT true,
    include_stats boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, pg_agent
AS $$
WITH visible_namespaces AS (
    SELECT n.oid AS nspoid,
           n.nspname
    FROM pg_namespace n
    WHERE n.nspname = ANY(COALESCE($1, ARRAY['public']::name[]))
      AND has_schema_privilege(n.oid, 'USAGE')
),
visible_relations AS (
    SELECT n.nspoid,
           n.nspname,
           c.oid AS reloid,
           c.relname,
           c.relkind,
           c.reltuples::bigint AS estimated_rows,
           obj_description(c.oid, 'pg_class') AS comment_text
    FROM visible_namespaces n
    JOIN pg_class c ON c.relnamespace = n.nspoid
    WHERE c.relkind IN ('r', 'p', 'v', 'm', 'f')
      AND has_table_privilege(c.oid, 'SELECT')
),
attributes_by_relation AS (
    SELECT r.reloid,
           jsonb_agg(
               jsonb_strip_nulls(
                   jsonb_build_object(
                       'name', a.attname,
                       'attnum', a.attnum,
                       'type', format_type(a.atttypid, a.atttypmod),
                       'not_null', a.attnotnull,
                       'comment',
                           CASE
                               WHEN $2 THEN col_description(r.reloid, a.attnum)
                               ELSE NULL
                           END
                   )
               )
               ORDER BY a.attnum
           ) AS attributes
    FROM visible_relations r
    JOIN pg_attribute a ON a.attrelid = r.reloid
    WHERE a.attnum > 0
      AND NOT a.attisdropped
      AND has_column_privilege(r.reloid, a.attnum, 'SELECT')
    GROUP BY r.reloid
),
indexes_by_relation AS (
    SELECT r.reloid,
           jsonb_agg(
               jsonb_build_object(
                   'name', ic.relname,
                   'unique', i.indisunique,
                   'primary', i.indisprimary,
                   'definition', pg_get_indexdef(ic.oid)
               )
               ORDER BY ic.relname
           ) AS indexes
    FROM visible_relations r
    JOIN pg_index i ON i.indrelid = r.reloid
    JOIN pg_class ic ON ic.oid = i.indexrelid
    WHERE $3
    GROUP BY r.reloid
),
foreign_keys_by_relation AS (
    SELECT r.reloid,
           jsonb_agg(
               jsonb_build_object(
                   'name', con.conname,
                   'references', con.confrelid::regclass::text,
                   'definition', pg_get_constraintdef(con.oid, false)
               )
               ORDER BY con.conname
           ) AS foreign_keys
    FROM visible_relations r
    JOIN pg_constraint con ON con.conrelid = r.reloid
    WHERE $4
      AND con.contype = 'f'
    GROUP BY r.reloid
),
relations_by_schema AS (
    SELECT r.nspoid,
           jsonb_agg(
               jsonb_strip_nulls(
                   jsonb_build_object(
                       'name', r.relname,
                       'relkind', r.relkind::text,
                       'estimated_rows',
                           CASE
                               WHEN $5 THEN r.estimated_rows
                               ELSE NULL
                           END,
                       'comment',
                           CASE
                               WHEN $2 AND r.comment_text IS NOT NULL
                               THEN jsonb_build_object(
                                   'text', r.comment_text,
                                   'source', 'pg_description',
                                   'trusted_as_instruction', false
                               )
                               ELSE NULL
                           END,
                       'attributes', COALESCE(a.attributes, '[]'::jsonb),
                       'indexes',
                           CASE
                               WHEN $3 THEN COALESCE(i.indexes, '[]'::jsonb)
                               ELSE NULL
                           END,
                       'foreign_keys',
                           CASE
                               WHEN $4 THEN COALESCE(f.foreign_keys, '[]'::jsonb)
                               ELSE NULL
                           END
                   )
               )
               ORDER BY r.relname
           ) AS relations
    FROM visible_relations r
    LEFT JOIN attributes_by_relation a ON a.reloid = r.reloid
    LEFT JOIN indexes_by_relation i ON i.reloid = r.reloid
    LEFT JOIN foreign_keys_by_relation f ON f.reloid = r.reloid
    GROUP BY r.nspoid
)
SELECT jsonb_build_object(
    'extension', 'pg_agent',
    'status', 'ok',
    'schemas',
        COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'name', n.nspname,
                    'relations', COALESCE(r.relations, '[]'::jsonb)
                )
                ORDER BY n.nspname
            ),
            '[]'::jsonb
        )
)
FROM visible_namespaces n
LEFT JOIN relations_by_schema r ON r.nspoid = n.nspoid;
$$;

CREATE FUNCTION pg_agent.relation_json(relation_oid regclass)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, pg_agent
AS $$
    SELECT jsonb_build_object(
        'extension', 'pg_agent',
        'status', 'stub',
        'relation', $1::text
    );
$$;

CREATE FUNCTION pg_agent.check_statement(statement_sql text)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, pg_agent
AS $$
    SELECT jsonb_build_object(
        'ok', false,
        'reason', 'not_implemented',
        'hint', 'pg_agent.check_statement is a SQL stub in version 1.0',
        'statement_length', length($1)
    );
$$;

CREATE FUNCTION pg_agent.explain_statement(statement_sql text)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, pg_agent
AS $$
    SELECT jsonb_build_object(
        'ok', false,
        'reason', 'not_implemented',
        'hint', 'pg_agent.explain_statement is a SQL stub in version 1.0',
        'statement_length', length($1)
    );
$$;

CREATE FUNCTION pg_agent.policy_check(statement_sql text)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, pg_agent
AS $$
    SELECT jsonb_build_object(
        'ok', false,
        'reason', 'not_implemented',
        'hint', 'pg_agent.policy_check is a SQL stub in version 1.0',
        'statement_length', length($1)
    );
$$;

CREATE FUNCTION pg_agent.set_object_annotation(object_name text, annotation jsonb)
RETURNS jsonb
LANGUAGE sql
VOLATILE
SECURITY INVOKER
SET search_path = pg_catalog, pg_agent
AS $$
    SELECT jsonb_build_object(
        'ok', false,
        'reason', 'not_implemented',
        'hint', 'pg_agent.set_object_annotation is a SQL stub in version 1.0',
        'object_name', $1,
        'annotation', $2
    );
$$;
