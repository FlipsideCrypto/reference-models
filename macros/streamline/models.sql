{% macro decode_logs_history(
        start,
        stop
    ) %}
    WITH look_back AS (
        SELECT
            block_number
        FROM
            {{ ref("_max_block_by_date") }}
            qualify ROW_NUMBER() over (
                ORDER BY
                    block_number DESC
            ) = 1
    )
SELECT
    l.block_number,
    l._log_id,
    A.abi AS abi,
    OBJECT_CONSTRUCT(
        'topics',
        l.topics,
        'data',
        l.data,
        'address',
        l.contract_address
    ) AS DATA
FROM
    {{ ref("silver__logs") }}
    l
    INNER JOIN {{ ref("silver__complete_event_abis") }} A
    ON A.parent_contract_address = l.contract_address
    AND A.event_signature = l.topics[0]:: STRING
    AND l.block_number BETWEEN A.start_block
    AND A.end_block
WHERE
    (
        l.block_number BETWEEN {{ start }}
        AND {{ stop }}
    )
    AND l.block_number <= (
        SELECT
            block_number
        FROM
            look_back
    )
    AND _log_id NOT IN (
        SELECT
            _log_id
        FROM
            {{ ref("streamline__complete_decode_logs") }}
        WHERE
            (
                block_number BETWEEN {{ start }}
                AND {{ stop }}
            )
            AND block_number <= (
                SELECT
                    block_number
                FROM
                    look_back
            )
    )
{% endmacro %}

{% macro block_reorg(reorg_model_list, hours) %}
  {% set models = reorg_model_list.split(",") %}
  
  {% for model in models %}
  {% set sql %}
    DELETE FROM
        {{ ref(model) }}
    WHERE
        _inserted_timestamp > DATEADD(
            'hour',
            -{{ hours }},
            CURRENT_TIMESTAMP
        )
        AND NOT EXISTS (
            SELECT
                1
            FROM
                {{ ref('silver__transactions') }}
            WHERE
                _inserted_timestamp > DATEADD(
                    'hour',
                    -{{ hours }},
                    CURRENT_TIMESTAMP
                )
                AND block_number = block_number
                AND tx_hash = tx_hash
        );
    {% endset %}
    {% do run_query(sql) %}
  {% endfor %}
{% endmacro %}

