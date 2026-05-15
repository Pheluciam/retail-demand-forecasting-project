{#
    Override dbt's default generate_schema_name.

    The dbt default concatenates target.schema with the per-folder
    +schema: config, producing schema names like RAW_STAGING. This
    override uses the +schema: value directly, so models land in
    clean schemas (STAGING, INTERMEDIATE, WAREHOUSE, MARTS).

    See DBT_PIPELINE.md for the full walkthrough.
#}

{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- set default_schema = target.schema -%}
    {%- if custom_schema_name is none -%}
        {{ default_schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
