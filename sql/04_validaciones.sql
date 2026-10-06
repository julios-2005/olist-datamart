-- =====================================================================
-- 04_validaciones.sql  |  Consultas de validación del Data Mart
-- =====================================================================
\echo '=== V1. Cantidad de registros: origen (stg) vs destino (dw) ==='
SELECT 'fact_ventas_item' AS tabla,
       (SELECT count(*) FROM stg.order_items) AS origen,
       (SELECT count(*) FROM dw.fact_ventas_item) AS destino,
       (SELECT count(*) FROM stg.order_items) - (SELECT count(*) FROM dw.fact_ventas_item) AS diferencia
UNION ALL SELECT 'fact_pagos', (SELECT count(*) FROM stg.order_payments), (SELECT count(*) FROM dw.fact_pagos), 0
UNION ALL SELECT 'dim_cliente', (SELECT count(*) FROM stg.customers), (SELECT count(*) FROM dw.dim_cliente), 0
UNION ALL SELECT 'dim_vendedor', (SELECT count(*) FROM stg.sellers), (SELECT count(*) FROM dw.dim_vendedor), 0
UNION ALL SELECT 'dim_producto', (SELECT count(*) FROM stg.products), (SELECT count(*) FROM dw.dim_producto), 0
UNION ALL SELECT 'dim_estado_pedido', (SELECT count(DISTINCT order_status) FROM stg.orders), (SELECT count(*) FROM dw.dim_estado_pedido), 0
UNION ALL SELECT 'dim_pago (5 tipos + sin_pago)', 6, (SELECT count(*) FROM dw.dim_pago), 0
UNION ALL SELECT 'dim_tiempo (2016-2018)', 1096, (SELECT count(*) FROM dw.dim_tiempo), 0;

\echo '=== V2. Integridad referencial: hechos sin dimensión (esperado 0) ==='
SELECT 'ventas sin cliente'   AS prueba, count(*) AS huerfanos FROM dw.fact_ventas_item f LEFT JOIN dw.dim_cliente  d USING (sk_cliente)  WHERE d.sk_cliente  IS NULL
UNION ALL SELECT 'ventas sin vendedor',  count(*) FROM dw.fact_ventas_item f LEFT JOIN dw.dim_vendedor d USING (sk_vendedor) WHERE d.sk_vendedor IS NULL
UNION ALL SELECT 'ventas sin producto',  count(*) FROM dw.fact_ventas_item f LEFT JOIN dw.dim_producto d USING (sk_producto) WHERE d.sk_producto IS NULL
UNION ALL SELECT 'ventas sin fecha compra', count(*) FROM dw.fact_ventas_item f LEFT JOIN dw.dim_tiempo d ON d.sk_fecha = f.sk_fecha_compra WHERE d.sk_fecha IS NULL
UNION ALL SELECT 'ventas con fecha entrega inexistente', count(*) FROM dw.fact_ventas_item f LEFT JOIN dw.dim_tiempo d ON d.sk_fecha = f.sk_fecha_entrega WHERE f.sk_fecha_entrega IS NOT NULL AND d.sk_fecha IS NULL
UNION ALL SELECT 'pagos sin cliente', count(*) FROM dw.fact_pagos f LEFT JOIN dw.dim_cliente d USING (sk_cliente) WHERE d.sk_cliente IS NULL
UNION ALL SELECT 'pedidos con ítems en stg y sin fila en hechos', count(DISTINCT i.order_id)
          FROM stg.order_items i LEFT JOIN dw.fact_ventas_item f ON f.order_id = i.order_id WHERE f.order_id IS NULL;

\echo '=== V3. Unicidad de la granularidad (esperado 0 duplicados) ==='
SELECT count(*) - count(DISTINCT (order_id, order_item_id)) AS duplicados_en_fact_ventas FROM dw.fact_ventas_item;
SELECT count(*) - count(DISTINCT order_id) AS items_primer_item_extra FROM dw.fact_ventas_item WHERE es_primer_item = 1;

\echo '=== V4. Valores nulos relevantes en la tabla de hechos ==='
SELECT count(*) AS filas,
       count(*) FILTER (WHERE sk_fecha_entrega IS NULL) AS sin_fecha_entrega,
       count(*) FILTER (WHERE dias_entrega IS NULL)     AS sin_dias_entrega,
       count(*) FILTER (WHERE review_score IS NULL)     AS sin_resena,
       count(*) FILTER (WHERE precio IS NULL OR valor_flete IS NULL) AS sin_precio_o_flete
FROM dw.fact_ventas_item;

SELECT count(*) FILTER (WHERE sk_fecha_entrega IS NULL AND e.order_status = 'delivered') AS delivered_sin_fecha,
       count(*) FILTER (WHERE sk_fecha_entrega IS NULL AND e.order_status IN ('canceled','unavailable')) AS sin_fecha_cancel_o_no_disp,
       count(*) FILTER (WHERE sk_fecha_entrega IS NULL AND e.order_status NOT IN ('delivered','canceled','unavailable')) AS sin_fecha_en_proceso
FROM dw.fact_ventas_item f JOIN dw.dim_estado_pedido e USING (sk_estado);

SELECT count(*) FILTER (WHERE categoria_pt = 'sin_categoria') AS productos_sin_categoria,
       count(*) FILTER (WHERE peso_g IS NULL)                  AS productos_sin_peso,
       (SELECT count(DISTINCT p.categoria_pt) FROM dw.dim_producto p
         WHERE p.categoria_pt <> 'sin_categoria'
           AND NOT EXISTS (SELECT 1 FROM stg.category_translation t WHERE t.product_category_name = p.categoria_pt))
                                                               AS categorias_completadas_a_mano
FROM dw.dim_producto;

\echo '=== V5. Totales principales: dw vs consulta directa sobre staging ==='
SELECT 'GMV (sin cancelados)' AS medida,
       (SELECT round(sum(i.price::numeric),2) FROM stg.order_items i JOIN stg.orders o USING (order_id) WHERE o.order_status <> 'canceled') AS origen,
       (SELECT sum(precio) FROM dw.fact_ventas_item f JOIN dw.dim_estado_pedido e USING (sk_estado) WHERE NOT e.es_cancelado) AS dw
UNION ALL SELECT 'Flete total (todos)',
       (SELECT sum(freight_value::numeric) FROM stg.order_items), (SELECT sum(valor_flete) FROM dw.fact_ventas_item)
UNION ALL SELECT 'Valor de pagos (todos)',
       (SELECT sum(payment_value::numeric) FROM stg.order_payments), (SELECT sum(valor_pago) FROM dw.fact_pagos)
UNION ALL SELECT 'Pedidos con ítems',
       (SELECT count(DISTINCT order_id) FROM stg.order_items), (SELECT sum(es_primer_item) FROM dw.fact_ventas_item);

\echo '=== V6. Resumen de medidas y KPI ==='
SELECT dw.fn_total_ventas()          AS ventas_totales,
       dw.fn_total_pedidos()         AS pedidos,
       dw.fn_ticket_promedio()       AS ticket_prom,
       dw.fn_tiempo_entrega()        AS dias_entrega_prom,
       dw.fn_pct_entregas_tardias()  AS pct_tardias,
       dw.fn_calificacion_promedio() AS calif_prom,
       dw.fn_pct_resenas_negativas() AS pct_resenas_neg,
       dw.fn_participacion_flete()   AS pct_flete,
       dw.fn_pct_top10_vendedores()  AS pct_top10_vend,
       dw.fn_tasa_recompra()         AS tasa_recompra;

\echo '=== V7. Bitácora de calidad (por regla y acción) ==='
SELECT tabla, accion, count(*) AS registros,
       min(regla) AS ejemplo_regla
FROM dw.log_calidad GROUP BY tabla, accion ORDER BY registros DESC;
