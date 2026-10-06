-- =====================================================================
-- 03_etl.sql  |  Limpieza, transformación y carga (stg -> dw)
-- Es re-ejecutable: vacía las tablas del dw antes de cargar.
-- =====================================================================
TRUNCATE dw.fact_pagos, dw.fact_ventas_item, dw.dim_tiempo, dw.dim_cliente,
         dw.dim_vendedor, dw.dim_producto, dw.dim_pago, dw.dim_estado_pedido,
         dw.log_calidad RESTART IDENTITY CASCADE;

-- ---------------------------------------------------------- funciones auxiliares
-- Normaliza texto de ciudad: minúsculas, sin tildes, sin sufijos "/sp", ", brasil", etc.
CREATE OR REPLACE FUNCTION dw.limpiar_ciudad(p text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN c IS NULL OR c = '' OR c ~ '@' OR c !~ '[a-z]' OR length(c) <= 2 THEN 'desconocida'
        WHEN c = 'sbc' THEN 'sao bernardo do campo'
        ELSE c
    END
    FROM (
        SELECT btrim(regexp_replace(
                 split_part(split_part(split_part(split_part(
                   translate(lower(coalesce(p,'')),
                             'áàâãäéèêëíìîïóòôõöúùûüçñ´’',
                             'aaaaaeeeeiiiiooooouuuucn''''' ),
                 '/',1), ',',1), '\',1), '(',1),
               '\s+',' ','g')) AS c
    ) t
$$;

CREATE OR REPLACE FUNCTION dw.region_de_uf(uf text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN uf IN ('AC','AP','AM','PA','RO','RR','TO')             THEN 'Norte'
        WHEN uf IN ('AL','BA','CE','MA','PB','PE','PI','RN','SE')   THEN 'Nordeste'
        WHEN uf IN ('DF','GO','MT','MS')                            THEN 'Centro-Oeste'
        WHEN uf IN ('ES','MG','RJ','SP')                            THEN 'Sudeste'
        WHEN uf IN ('PR','RS','SC')                                 THEN 'Sul'
        ELSE 'Desconocida' END
$$;

-- ------------------------------------------------------------------ DIM_TIEMPO
INSERT INTO dw.dim_tiempo
SELECT to_char(d,'YYYYMMDD')::int, d::date,
       extract(year FROM d), extract(quarter FROM d), extract(month FROM d),
       (ARRAY['enero','febrero','marzo','abril','mayo','junio','julio','agosto',
              'septiembre','octubre','noviembre','diciembre'])[extract(month FROM d)::int],
       to_char(d,'YYYY-MM'),
       extract(day FROM d),
       extract(isodow FROM d),
       (ARRAY['lunes','martes','miercoles','jueves','viernes','sabado','domingo'])[extract(isodow FROM d)::int],
       extract(isodow FROM d) >= 6,
       -- Feriados nacionales de Brasil: fijos + móviles (Carnaval, Viernes Santo, Corpus Christi) 2016-2018
       to_char(d,'MM-DD') IN ('01-01','04-21','05-01','09-07','10-12','11-02','11-15','12-25')
       OR d::date IN ('2016-02-09','2016-03-25','2016-05-26',
                      '2017-02-28','2017-04-14','2017-06-15',
                      '2018-02-13','2018-03-30','2018-05-31')
FROM generate_series('2016-01-01'::date, '2018-12-31'::date, interval '1 day') AS g(d);

-- ------------------------------------------------------------ DIM_ESTADO_PEDIDO
INSERT INTO dw.dim_estado_pedido (order_status, es_entregado, es_cancelado)
SELECT DISTINCT order_status, order_status = 'delivered', order_status = 'canceled'
FROM stg.orders ORDER BY 1;

-- ------------------------------------------------------------------- DIM_PAGO
INSERT INTO dw.dim_pago (tipo_pago, descripcion) VALUES
 ('credit_card','Tarjeta de crédito'),
 ('boleto','Boleto bancario'),
 ('voucher','Voucher / vale'),
 ('debit_card','Tarjeta de débito'),
 ('not_defined','No definido'),
 ('sin_pago','Pedido sin registro de pago');

-- ---------------------------------------------------------------- DIM_CLIENTE
-- Una fila por customer_id (en Olist cambia en cada pedido).
-- customer_unique_id identifica a la persona real y se usa para la recompra.
INSERT INTO dw.dim_cliente (customer_id, customer_unique_id, cp_prefijo, ciudad, estado_uf, region)
SELECT customer_id, customer_unique_id,
       lpad(customer_zip_code_prefix, 5, '0'),
       dw.limpiar_ciudad(customer_city),
       upper(customer_state),
       dw.region_de_uf(upper(customer_state))
FROM stg.customers;

INSERT INTO dw.log_calidad (tabla, clave, regla, accion)
SELECT 'customers', customer_id, 'ciudad normalizada (minúsculas/sin tildes/sin sufijos)', 'corregido'
FROM stg.customers WHERE dw.limpiar_ciudad(customer_city) <> customer_city;

-- --------------------------------------------------------------- DIM_VENDEDOR
INSERT INTO dw.dim_vendedor (seller_id, cp_prefijo, ciudad, estado_uf, region)
SELECT seller_id, lpad(seller_zip_code_prefix,5,'0'),
       dw.limpiar_ciudad(seller_city), upper(seller_state), dw.region_de_uf(upper(seller_state))
FROM stg.sellers;

INSERT INTO dw.log_calidad (tabla, clave, regla, accion)
SELECT 'sellers', seller_id || ' | "' || seller_city || '" -> "' || dw.limpiar_ciudad(seller_city) || '"', 'ciudad con formato inválido normalizada', 'corregido'
FROM stg.sellers WHERE dw.limpiar_ciudad(seller_city) <> seller_city;

-- --------------------------------------------------------------- DIM_PRODUCTO
-- Traducción: 71 categorías en la tabla vs 73 en products -> se completan 2 a mano.
INSERT INTO dw.dim_producto (product_id, categoria_pt, categoria_en, peso_g, volumen_cm3)
SELECT p.product_id,
       COALESCE(p.product_category_name, 'sin_categoria'),
       CASE
         WHEN p.product_category_name IS NULL THEN 'unknown'
         WHEN t.product_category_name_english IS NOT NULL THEN t.product_category_name_english
         WHEN p.product_category_name = 'pc_gamer' THEN 'pc_gamer'
         WHEN p.product_category_name = 'portateis_cozinha_e_preparadores_de_alimentos' THEN 'portable_kitchen_food_preparers'
         ELSE p.product_category_name
       END,
       NULLIF(NULLIF(p.product_weight_g,'')::numeric, 0),                 -- peso 0 = dato inválido -> NULL
       NULLIF(p.product_length_cm,'')::numeric * NULLIF(p.product_height_cm,'')::numeric * NULLIF(p.product_width_cm,'')::numeric
FROM stg.products p
LEFT JOIN stg.category_translation t USING (product_category_name);

INSERT INTO dw.log_calidad (tabla, clave, regla, accion)
SELECT 'products', product_id, 'sin categoría -> sin_categoria', 'corregido'
FROM stg.products WHERE product_category_name IS NULL;
INSERT INTO dw.log_calidad (tabla, clave, regla, accion)
SELECT 'products', product_id, 'peso = 0 -> NULL', 'corregido'
FROM stg.products WHERE product_weight_g = '0';

-- ------------------------------------------------------------ FACT_VENTAS_ITEM
WITH pago_principal AS (   -- medio de pago de mayor valor en el pedido
    SELECT DISTINCT ON (order_id) order_id, payment_type
    FROM stg.order_payments
    ORDER BY order_id, payment_value::numeric DESC, payment_sequential::int ASC
), resena AS (             -- una reseña por pedido: la más reciente
    SELECT DISTINCT ON (order_id) order_id, review_score::smallint AS review_score
    FROM stg.order_reviews
    ORDER BY order_id, review_answer_timestamp DESC, review_creation_date DESC, review_id
), base AS (
    SELECT i.order_id,
           i.order_item_id::smallint                       AS order_item_id,
           row_number() OVER (PARTITION BY i.order_id ORDER BY i.order_item_id::int) AS rn,
           o.order_purchase_timestamp::timestamp           AS t_compra,
           o.order_delivered_customer_date::timestamp      AS t_entrega,
           o.order_estimated_delivery_date::timestamp      AS t_estimada,
           c.sk_cliente, v.sk_vendedor, p.sk_producto,
           pg.sk_pago, e.sk_estado,
           i.price::numeric AS precio, i.freight_value::numeric AS flete,
           r.review_score
    FROM stg.order_items i
    JOIN stg.orders o            ON o.order_id = i.order_id
    JOIN dw.dim_cliente c        ON c.customer_id = o.customer_id
    JOIN dw.dim_vendedor v       ON v.seller_id = i.seller_id
    JOIN dw.dim_producto p       ON p.product_id = i.product_id
    JOIN dw.dim_estado_pedido e  ON e.order_status = o.order_status
    LEFT JOIN pago_principal pp  ON pp.order_id = i.order_id
    JOIN dw.dim_pago pg          ON pg.tipo_pago = COALESCE(pp.payment_type, 'sin_pago')
    LEFT JOIN resena r           ON r.order_id = i.order_id
)
INSERT INTO dw.fact_ventas_item
SELECT order_id, order_item_id,
       to_char(t_compra,'YYYYMMDD')::int,
       to_char(t_entrega,'YYYYMMDD')::int,
       to_char(t_estimada,'YYYYMMDD')::int,
       sk_cliente, sk_vendedor, sk_producto, sk_pago, sk_estado,
       precio, flete, precio + flete, 1,
       round((extract(epoch FROM t_entrega - t_compra)  / 86400)::numeric, 2),
       round((extract(epoch FROM t_entrega - t_estimada) / 86400)::numeric, 2),
       CASE WHEN t_entrega IS NULL THEN NULL WHEN t_entrega > t_estimada THEN 1 ELSE 0 END,
       review_score,
       CASE WHEN rn = 1 THEN 1 ELSE 0 END
FROM base;

-- ------------------------------------------------------------------ FACT_PAGOS
INSERT INTO dw.fact_pagos
SELECT pa.order_id, pa.payment_sequential::smallint,
       to_char(o.order_purchase_timestamp::timestamp,'YYYYMMDD')::int,
       c.sk_cliente, pg.sk_pago, e.sk_estado,
       pa.payment_value::numeric, pa.payment_installments::smallint
FROM stg.order_payments pa
JOIN stg.orders o            ON o.order_id = pa.order_id
JOIN dw.dim_cliente c        ON c.customer_id = o.customer_id
JOIN dw.dim_pago pg          ON pg.tipo_pago = pa.payment_type
JOIN dw.dim_estado_pedido e  ON e.order_status = o.order_status;

-- ------------------------------------------------- bitácora de calidad (hechos)
INSERT INTO dw.log_calidad (tabla, clave, regla, accion)
SELECT 'orders', o.order_id, 'pedido sin ítems: no tiene granularidad en FACT_VENTAS_ITEM', 'rechazado'
FROM stg.orders o WHERE NOT EXISTS (SELECT 1 FROM stg.order_items i WHERE i.order_id = o.order_id);

INSERT INTO dw.log_calidad (tabla, clave, regla, accion)
SELECT 'orders', order_id, 'estado delivered sin fecha de entrega al cliente', 'marcado'
FROM stg.orders WHERE order_status = 'delivered' AND order_delivered_customer_date IS NULL;

INSERT INTO dw.log_calidad (tabla, clave, regla, accion)
SELECT 'orders', order_id, 'fecha de entrega con estado distinto de delivered', 'marcado'
FROM stg.orders WHERE order_status <> 'delivered' AND order_delivered_customer_date IS NOT NULL;

INSERT INTO dw.log_calidad (tabla, clave, regla, accion)
SELECT 'order_reviews', order_id, 'pedido con más de una reseña: se conserva la más reciente', 'corregido'
FROM stg.order_reviews GROUP BY order_id HAVING count(*) > 1;

INSERT INTO dw.log_calidad (tabla, clave, regla, accion)
SELECT 'order_payments', order_id || '-' || payment_sequential, 'payment_value = 0', 'marcado'
FROM stg.order_payments WHERE payment_value::numeric = 0;

ANALYZE;
SELECT regla, accion, count(*) FROM dw.log_calidad GROUP BY 1,2 ORDER BY 3 DESC;
