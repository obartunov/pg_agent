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
    SELECT jsonb_build_object(
        'extension', 'pg_agent',
        'status', 'stub',
        'schemas', COALESCE(to_jsonb($1), '[]'::jsonb),
        'include_comments', $2,
        'include_indexes', $3,
        'include_foreign_keys', $4,
        'include_stats', $5
    );
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
