-- =====================================================================
-- 05_vistas_funciones.sql  |  Capa de consumo para el dashboard
-- Convención: los KPI de pedido se calculan con es_primer_item = 1
-- (1 fila por pedido) para no duplicar por ítems. Porcentajes en escala 0-100.
-- =====================================================================

-- ------------------------------------------------ vista base desnormalizada
CREATE OR REPLACE VIEW dw.vw_ventas_detalle AS
SELECT f.order_id, f.order_item_id, f.es_primer_item,
       tc.fecha AS fecha_compra, te.fecha AS fecha_entrega, tes.fecha AS fecha_estimada,
       tc.anio, tc.trimestre, tc.mes, tc.anio_mes,
       c.customer_unique_id, c.ciudad AS cliente_ciudad, c.estado_uf AS cliente_uf, c.region AS cliente_region,
       v.seller_id, v.ciudad AS vendedor_ciudad, v.estado_uf AS vendedor_uf,
       p.product_id, p.categoria_pt, p.categoria_en,
       pg.tipo_pago, e.order_status, e.es_entregado, e.es_cancelado,
       f.precio, f.valor_flete, f.valor_total_item,
       f.dias_entrega, f.dias_retraso, f.entrega_tardia, f.review_score
FROM dw.fact_ventas_item f
JOIN dw.dim_tiempo tc          ON tc.sk_fecha  = f.sk_fecha_compra
LEFT JOIN dw.dim_tiempo te     ON te.sk_fecha  = f.sk_fecha_entrega
JOIN dw.dim_tiempo tes         ON tes.sk_fecha = f.sk_fecha_estimada
JOIN dw.dim_cliente c          ON c.sk_cliente = f.sk_cliente
JOIN dw.dim_vendedor v         ON v.sk_vendedor = f.sk_vendedor
JOIN dw.dim_producto p         ON p.sk_producto = f.sk_producto
JOIN dw.dim_pago pg            ON pg.sk_pago   = f.sk_pago
JOIN dw.dim_estado_pedido e    ON e.sk_estado  = f.sk_estado;

-- ------------------------------------------------ vistas agregadas
CREATE OR REPLACE VIEW dw.vw_kpi_mensual AS
SELECT anio_mes,
       round(sum(precio),2)                                         AS ventas_totales,
       sum(es_primer_item)                                          AS pedidos,
       round(sum(precio) / nullif(sum(es_primer_item),0), 2)        AS ticket_promedio,
       round(100 * sum(valor_flete) / nullif(sum(precio),0), 2)     AS pct_flete
FROM dw.vw_ventas_detalle WHERE NOT es_cancelado
GROUP BY anio_mes ORDER BY anio_mes;

CREATE OR REPLACE VIEW dw.vw_logistica_estado AS
SELECT cliente_uf, cliente_region,
       count(*)                                         AS pedidos_entregados,
       round(avg(dias_entrega),2)                       AS dias_entrega_prom,
       round(100.0 * sum(entrega_tardia) / count(*), 2) AS pct_tardias
FROM dw.vw_ventas_detalle
WHERE es_primer_item = 1 AND es_entregado AND fecha_entrega IS NOT NULL
GROUP BY cliente_uf, cliente_region ORDER BY pct_tardias DESC;

CREATE OR REPLACE VIEW dw.vw_satisfaccion_entrega AS
SELECT CASE WHEN entrega_tardia = 1 THEN 'Con retraso' ELSE 'A tiempo' END AS entrega,
       count(*)                       AS pedidos,
       round(avg(review_score),2)     AS calificacion_prom,
       round(100.0 * count(*) FILTER (WHERE review_score <= 2) / count(*), 2) AS pct_resenas_negativas
FROM dw.vw_ventas_detalle
WHERE es_primer_item = 1 AND es_entregado AND fecha_entrega IS NOT NULL AND review_score IS NOT NULL
GROUP BY 1;

CREATE OR REPLACE VIEW dw.vw_pagos_resumen AS
SELECT d.tipo_pago, d.descripcion,
       count(*)                          AS pagos,
       count(DISTINCT p.order_id)        AS pedidos,
       round(sum(p.valor_pago),2)        AS valor_total,
       round(avg(p.valor_pago),2)        AS pago_promedio,
       round(avg(p.cuotas),2)            AS cuotas_promedio,
       max(p.cuotas)                     AS cuotas_max
FROM dw.fact_pagos p JOIN dw.dim_pago d USING (sk_pago)
JOIN dw.dim_estado_pedido e USING (sk_estado)
WHERE NOT e.es_cancelado
GROUP BY d.tipo_pago, d.descripcion ORDER BY valor_total DESC;

-- ------------------------------------------------ funciones KPI (escalares)
-- Parámetros opcionales (NULL = sin filtro): fecha desde/hasta, categoría (inglés), UF del cliente.
CREATE OR REPLACE FUNCTION dw.fn_total_ventas(p_desde date DEFAULT NULL, p_hasta date DEFAULT NULL,
       p_categoria text DEFAULT NULL, p_uf text DEFAULT NULL) RETURNS numeric
LANGUAGE sql STABLE AS $$
  SELECT round(coalesce(sum(precio),0),2) FROM dw.vw_ventas_detalle
  WHERE NOT es_cancelado
    AND (p_desde IS NULL OR fecha_compra >= p_desde) AND (p_hasta IS NULL OR fecha_compra <= p_hasta)
    AND (p_categoria IS NULL OR categoria_en = p_categoria) AND (p_uf IS NULL OR cliente_uf = p_uf)
$$;

CREATE OR REPLACE FUNCTION dw.fn_total_pedidos(p_desde date DEFAULT NULL, p_hasta date DEFAULT NULL,
       p_categoria text DEFAULT NULL, p_uf text DEFAULT NULL) RETURNS bigint
LANGUAGE sql STABLE AS $$
  SELECT coalesce(sum(es_primer_item),0)::bigint FROM dw.vw_ventas_detalle
  WHERE NOT es_cancelado
    AND (p_desde IS NULL OR fecha_compra >= p_desde) AND (p_hasta IS NULL OR fecha_compra <= p_hasta)
    AND (p_categoria IS NULL OR categoria_en = p_categoria) AND (p_uf IS NULL OR cliente_uf = p_uf)
$$;

CREATE OR REPLACE FUNCTION dw.fn_ticket_promedio(p_desde date DEFAULT NULL, p_hasta date DEFAULT NULL,
       p_categoria text DEFAULT NULL, p_uf text DEFAULT NULL) RETURNS numeric
LANGUAGE sql STABLE AS $$
  SELECT round(dw.fn_total_ventas(p_desde,p_hasta,p_categoria,p_uf)
         / nullif(dw.fn_total_pedidos(p_desde,p_hasta,p_categoria,p_uf),0), 2)
$$;

CREATE OR REPLACE FUNCTION dw.fn_tiempo_entrega(p_desde date DEFAULT NULL, p_hasta date DEFAULT NULL,
       p_categoria text DEFAULT NULL, p_uf text DEFAULT NULL) RETURNS numeric
LANGUAGE sql STABLE AS $$
  SELECT round(avg(dias_entrega),2) FROM dw.vw_ventas_detalle
  WHERE es_primer_item = 1 AND es_entregado AND fecha_entrega IS NOT NULL
    AND (p_desde IS NULL OR fecha_compra >= p_desde) AND (p_hasta IS NULL OR fecha_compra <= p_hasta)
    AND (p_categoria IS NULL OR categoria_en = p_categoria) AND (p_uf IS NULL OR cliente_uf = p_uf)
$$;

CREATE OR REPLACE FUNCTION dw.fn_pct_entregas_tardias(p_desde date DEFAULT NULL, p_hasta date DEFAULT NULL,
       p_categoria text DEFAULT NULL, p_uf text DEFAULT NULL) RETURNS numeric
LANGUAGE sql STABLE AS $$
  SELECT round(100.0 * sum(entrega_tardia) / nullif(count(*),0), 2) FROM dw.vw_ventas_detalle
  WHERE es_primer_item = 1 AND es_entregado AND fecha_entrega IS NOT NULL
    AND (p_desde IS NULL OR fecha_compra >= p_desde) AND (p_hasta IS NULL OR fecha_compra <= p_hasta)
    AND (p_categoria IS NULL OR categoria_en = p_categoria) AND (p_uf IS NULL OR cliente_uf = p_uf)
$$;

CREATE OR REPLACE FUNCTION dw.fn_calificacion_promedio(p_desde date DEFAULT NULL, p_hasta date DEFAULT NULL,
       p_categoria text DEFAULT NULL, p_uf text DEFAULT NULL) RETURNS numeric
LANGUAGE sql STABLE AS $$
  SELECT round(avg(review_score),2) FROM dw.vw_ventas_detalle
  WHERE es_primer_item = 1 AND review_score IS NOT NULL AND NOT es_cancelado
    AND (p_desde IS NULL OR fecha_compra >= p_desde) AND (p_hasta IS NULL OR fecha_compra <= p_hasta)
    AND (p_categoria IS NULL OR categoria_en = p_categoria) AND (p_uf IS NULL OR cliente_uf = p_uf)
$$;

CREATE OR REPLACE FUNCTION dw.fn_pct_resenas_negativas(p_desde date DEFAULT NULL, p_hasta date DEFAULT NULL,
       p_categoria text DEFAULT NULL, p_uf text DEFAULT NULL) RETURNS numeric
LANGUAGE sql STABLE AS $$
  SELECT round(100.0 * count(*) FILTER (WHERE review_score <= 2) / nullif(count(*),0), 2)
  FROM dw.vw_ventas_detalle
  WHERE es_primer_item = 1 AND review_score IS NOT NULL AND NOT es_cancelado
    AND (p_desde IS NULL OR fecha_compra >= p_desde) AND (p_hasta IS NULL OR fecha_compra <= p_hasta)
    AND (p_categoria IS NULL OR categoria_en = p_categoria) AND (p_uf IS NULL OR cliente_uf = p_uf)
$$;

CREATE OR REPLACE FUNCTION dw.fn_participacion_flete(p_desde date DEFAULT NULL, p_hasta date DEFAULT NULL,
       p_categoria text DEFAULT NULL, p_uf text DEFAULT NULL) RETURNS numeric
LANGUAGE sql STABLE AS $$
  SELECT round(100 * sum(valor_flete) / nullif(sum(precio),0), 2) FROM dw.vw_ventas_detalle
  WHERE NOT es_cancelado
    AND (p_desde IS NULL OR fecha_compra >= p_desde) AND (p_hasta IS NULL OR fecha_compra <= p_hasta)
    AND (p_categoria IS NULL OR categoria_en = p_categoria) AND (p_uf IS NULL OR cliente_uf = p_uf)
$$;

CREATE OR REPLACE FUNCTION dw.fn_pct_top10_vendedores(p_desde date DEFAULT NULL, p_hasta date DEFAULT NULL,
       p_categoria text DEFAULT NULL, p_uf text DEFAULT NULL) RETURNS numeric
LANGUAGE sql STABLE AS $$
  WITH v AS (
    SELECT seller_id, sum(precio) AS s FROM dw.vw_ventas_detalle
    WHERE NOT es_cancelado
      AND (p_desde IS NULL OR fecha_compra >= p_desde) AND (p_hasta IS NULL OR fecha_compra <= p_hasta)
      AND (p_categoria IS NULL OR categoria_en = p_categoria) AND (p_uf IS NULL OR cliente_uf = p_uf)
    GROUP BY seller_id)
  SELECT round(100 * (SELECT sum(s) FROM (SELECT s FROM v ORDER BY s DESC LIMIT 10) t)
               / nullif((SELECT sum(s) FROM v),0), 2)
$$;

CREATE OR REPLACE FUNCTION dw.fn_tasa_recompra(p_desde date DEFAULT NULL, p_hasta date DEFAULT NULL,
       p_categoria text DEFAULT NULL, p_uf text DEFAULT NULL) RETURNS numeric
LANGUAGE sql STABLE AS $$
  WITH c AS (
    SELECT customer_unique_id, count(DISTINCT order_id) AS n FROM dw.vw_ventas_detalle
    WHERE NOT es_cancelado
      AND (p_desde IS NULL OR fecha_compra >= p_desde) AND (p_hasta IS NULL OR fecha_compra <= p_hasta)
      AND (p_categoria IS NULL OR categoria_en = p_categoria) AND (p_uf IS NULL OR cliente_uf = p_uf)
    GROUP BY customer_unique_id)
  SELECT round(100.0 * count(*) FILTER (WHERE n > 1) / nullif(count(*),0), 2) FROM c
$$;

-- ------------------------------------------------ funciones de tabla (gráficos y detalle)
CREATE OR REPLACE FUNCTION dw.fn_ventas_mensuales(p_desde date DEFAULT NULL, p_hasta date DEFAULT NULL,
       p_categoria text DEFAULT NULL, p_uf text DEFAULT NULL)
RETURNS TABLE (anio_mes char(7), ventas_totales numeric, pedidos bigint, ticket_promedio numeric)
LANGUAGE sql STABLE AS $$
  SELECT v.anio_mes, round(sum(precio),2), sum(es_primer_item)::bigint,
         round(sum(precio)/nullif(sum(es_primer_item),0),2)
  FROM dw.vw_ventas_detalle v
  WHERE NOT es_cancelado
    AND (p_desde IS NULL OR fecha_compra >= p_desde) AND (p_hasta IS NULL OR fecha_compra <= p_hasta)
    AND (p_categoria IS NULL OR categoria_en = p_categoria) AND (p_uf IS NULL OR cliente_uf = p_uf)
  GROUP BY v.anio_mes ORDER BY v.anio_mes
$$;

CREATE OR REPLACE FUNCTION dw.fn_top_categorias(p_desde date DEFAULT NULL, p_hasta date DEFAULT NULL,
       p_uf text DEFAULT NULL, p_top int DEFAULT 10)
RETURNS TABLE (categoria text, ventas_totales numeric, pedidos bigint, participacion_pct numeric)
LANGUAGE sql STABLE AS $$
  WITH x AS (
    SELECT categoria_en AS cat, sum(precio) AS s, sum(es_primer_item) AS n FROM dw.vw_ventas_detalle
    WHERE NOT es_cancelado
      AND (p_desde IS NULL OR fecha_compra >= p_desde) AND (p_hasta IS NULL OR fecha_compra <= p_hasta)
      AND (p_uf IS NULL OR cliente_uf = p_uf)
    GROUP BY categoria_en)
  SELECT cat, round(s,2), n::bigint, round(100 * s / sum(s) OVER (), 2)
  FROM x ORDER BY s DESC LIMIT p_top
$$;

CREATE OR REPLACE FUNCTION dw.fn_logistica_por_estado(p_desde date DEFAULT NULL, p_hasta date DEFAULT NULL,
       p_categoria text DEFAULT NULL)
RETURNS TABLE (uf text, pedidos bigint, dias_entrega_prom numeric, pct_tardias numeric)
LANGUAGE sql STABLE AS $$
  SELECT cliente_uf, count(*), round(avg(dias_entrega),2), round(100.0*sum(entrega_tardia)/count(*),2)
  FROM dw.vw_ventas_detalle
  WHERE es_primer_item = 1 AND es_entregado AND fecha_entrega IS NOT NULL
    AND (p_desde IS NULL OR fecha_compra >= p_desde) AND (p_hasta IS NULL OR fecha_compra <= p_hasta)
    AND (p_categoria IS NULL OR categoria_en = p_categoria)
  GROUP BY cliente_uf ORDER BY 4 DESC
$$;

CREATE OR REPLACE FUNCTION dw.fn_ranking_vendedores(p_desde date DEFAULT NULL, p_hasta date DEFAULT NULL,
       p_top int DEFAULT 10)
RETURNS TABLE (seller_id text, uf text, ventas_totales numeric, pedidos bigint, pct_tardias numeric, calificacion_prom numeric)
LANGUAGE sql STABLE AS $$
  SELECT v.seller_id, v.vendedor_uf, round(sum(precio),2), count(DISTINCT order_id),
         round(100.0 * sum(entrega_tardia) FILTER (WHERE es_entregado) / nullif(count(entrega_tardia) FILTER (WHERE es_entregado),0), 2),
         round(avg(review_score),2)
  FROM dw.vw_ventas_detalle v
  WHERE NOT es_cancelado
    AND (p_desde IS NULL OR fecha_compra >= p_desde) AND (p_hasta IS NULL OR fecha_compra <= p_hasta)
  GROUP BY v.seller_id, v.vendedor_uf ORDER BY sum(precio) DESC LIMIT p_top
$$;

CREATE OR REPLACE FUNCTION dw.fn_detalle_pedidos(p_desde date DEFAULT NULL, p_hasta date DEFAULT NULL,
       p_categoria text DEFAULT NULL, p_uf text DEFAULT NULL, p_limite int DEFAULT 100)
RETURNS TABLE (order_id text, fecha_compra date, cliente_uf text, categoria text, estado text,
               precio numeric, flete numeric, dias_entrega numeric, entrega_tardia smallint, review_score smallint)
LANGUAGE sql STABLE AS $$
  SELECT v.order_id, v.fecha_compra, v.cliente_uf, v.categoria_en, v.order_status,
         v.precio, v.valor_flete, v.dias_entrega, v.entrega_tardia, v.review_score
  FROM dw.vw_ventas_detalle v
  WHERE (p_desde IS NULL OR fecha_compra >= p_desde) AND (p_hasta IS NULL OR fecha_compra <= p_hasta)
    AND (p_categoria IS NULL OR categoria_en = p_categoria) AND (p_uf IS NULL OR cliente_uf = p_uf)
  ORDER BY v.fecha_compra DESC, v.order_id, v.order_item_id LIMIT p_limite
$$;

-- Satisfacción vs. puntualidad con filtros (alimenta los gráficos C10 y C11)
CREATE OR REPLACE FUNCTION dw.fn_satisfaccion_entrega(p_desde date DEFAULT NULL, p_hasta date DEFAULT NULL,
       p_categoria text DEFAULT NULL)
RETURNS TABLE (entrega text, pedidos bigint, calificacion_prom numeric, pct_resenas_negativas numeric)
LANGUAGE sql STABLE AS $$
  SELECT CASE WHEN entrega_tardia = 1 THEN 'Con retraso' ELSE 'A tiempo' END,
         count(*), round(avg(review_score),2),
         round(100.0 * count(*) FILTER (WHERE review_score <= 2) / count(*), 2)
  FROM dw.vw_ventas_detalle
  WHERE es_primer_item = 1 AND es_entregado AND fecha_entrega IS NOT NULL AND review_score IS NOT NULL
    AND (p_desde IS NULL OR fecha_compra >= p_desde) AND (p_hasta IS NULL OR fecha_compra <= p_hasta)
    AND (p_categoria IS NULL OR categoria_en = p_categoria)
  GROUP BY 1 ORDER BY 1
$$;

-- Medios de pago y cuotas con filtro de fecha (alimenta los gráficos C19 y C20)
CREATE OR REPLACE FUNCTION dw.fn_pagos_resumen(p_desde date DEFAULT NULL, p_hasta date DEFAULT NULL)
RETURNS TABLE (tipo_pago text, descripcion text, pagos bigint, pedidos bigint, valor_total numeric,
               pago_promedio numeric, cuotas_promedio numeric, cuotas_max smallint)
LANGUAGE sql STABLE AS $$
  SELECT d.tipo_pago, d.descripcion, count(*), count(DISTINCT p.order_id),
         round(sum(p.valor_pago),2), round(avg(p.valor_pago),2), round(avg(p.cuotas),2), max(p.cuotas)
  FROM dw.fact_pagos p
  JOIN dw.dim_pago d ON d.sk_pago = p.sk_pago
  JOIN dw.dim_estado_pedido e ON e.sk_estado = p.sk_estado
  JOIN dw.dim_tiempo t ON t.sk_fecha = p.sk_fecha_compra
  WHERE NOT e.es_cancelado
    AND (p_desde IS NULL OR t.fecha >= p_desde) AND (p_hasta IS NULL OR t.fecha <= p_hasta)
  GROUP BY d.tipo_pago, d.descripcion ORDER BY 5 DESC
$$;
