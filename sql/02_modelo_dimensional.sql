-- =====================================================================
-- 02_modelo_dimensional.sql  |  Data Mart Olist (esquema en estrella)
-- GRANULARIDAD de FACT_VENTAS_ITEM:
--   "Una fila representa un ítem (unidad vendida) dentro de un pedido:
--    clave natural (order_id, order_item_id)."
-- GRANULARIDAD de FACT_PAGOS:
--   "Una fila representa un pago parcial de un pedido:
--    clave natural (order_id, payment_sequential)."
-- =====================================================================
DROP SCHEMA IF EXISTS dw CASCADE;
CREATE SCHEMA dw;

-- ---------------------------------------------------------------- DIMENSIONES
CREATE TABLE dw.dim_tiempo (
    sk_fecha        integer  PRIMARY KEY,          -- formato AAAAMMDD
    fecha           date     NOT NULL UNIQUE,
    anio            smallint NOT NULL,
    trimestre       smallint NOT NULL CHECK (trimestre BETWEEN 1 AND 4),
    mes             smallint NOT NULL CHECK (mes BETWEEN 1 AND 12),
    nombre_mes      text     NOT NULL,
    anio_mes        char(7)  NOT NULL,             -- 'AAAA-MM' (ordena bien en gráficos)
    dia             smallint NOT NULL,
    dia_semana      smallint NOT NULL,             -- 1 = lunes ... 7 = domingo
    nombre_dia      text     NOT NULL,
    es_fin_semana   boolean  NOT NULL,
    es_feriado      boolean  NOT NULL
);

CREATE TABLE dw.dim_cliente (
    sk_cliente          serial   PRIMARY KEY,
    customer_id         text     NOT NULL UNIQUE,  -- cambia en cada pedido
    customer_unique_id  text     NOT NULL,         -- persona real (para recompra)
    cp_prefijo          char(5),                   -- texto: conserva ceros iniciales
    ciudad              text     NOT NULL,
    estado_uf           char(2)  NOT NULL,
    region              text     NOT NULL
);
CREATE INDEX ix_dim_cliente_unique ON dw.dim_cliente (customer_unique_id);

CREATE TABLE dw.dim_vendedor (
    sk_vendedor   serial   PRIMARY KEY,
    seller_id     text     NOT NULL UNIQUE,
    cp_prefijo    char(5),
    ciudad        text     NOT NULL,
    estado_uf     char(2)  NOT NULL,
    region        text     NOT NULL
);

CREATE TABLE dw.dim_producto (
    sk_producto     serial  PRIMARY KEY,
    product_id      text    NOT NULL UNIQUE,
    categoria_pt    text    NOT NULL,
    categoria_en    text    NOT NULL,
    peso_g          numeric(10,2),
    volumen_cm3     numeric(14,2)
);

CREATE TABLE dw.dim_pago (
    sk_pago        serial  PRIMARY KEY,
    tipo_pago      text    NOT NULL UNIQUE,        -- credit_card, boleto, ...
    descripcion    text    NOT NULL
);

CREATE TABLE dw.dim_estado_pedido (
    sk_estado      serial  PRIMARY KEY,
    order_status   text    NOT NULL UNIQUE,
    es_entregado   boolean NOT NULL,
    es_cancelado   boolean NOT NULL
);

-- ------------------------------------------------------------- TABLAS DE HECHOS
CREATE TABLE dw.fact_ventas_item (
    order_id            text     NOT NULL,
    order_item_id       smallint NOT NULL,
    -- claves foráneas (dimensiones)
    sk_fecha_compra     integer  NOT NULL REFERENCES dw.dim_tiempo (sk_fecha),
    sk_fecha_entrega    integer           REFERENCES dw.dim_tiempo (sk_fecha),  -- rol 2 (NULL si no entregado)
    sk_fecha_estimada   integer  NOT NULL REFERENCES dw.dim_tiempo (sk_fecha),  -- rol 3
    sk_cliente          integer  NOT NULL REFERENCES dw.dim_cliente (sk_cliente),
    sk_vendedor         integer  NOT NULL REFERENCES dw.dim_vendedor (sk_vendedor),
    sk_producto         integer  NOT NULL REFERENCES dw.dim_producto (sk_producto),
    sk_pago             integer  NOT NULL REFERENCES dw.dim_pago (sk_pago),     -- medio de pago principal del pedido
    sk_estado           integer  NOT NULL REFERENCES dw.dim_estado_pedido (sk_estado),
    -- medidas
    precio              numeric(10,2) NOT NULL CHECK (precio >= 0),
    valor_flete         numeric(10,2) NOT NULL CHECK (valor_flete >= 0),
    valor_total_item    numeric(10,2) NOT NULL,                  -- precio + flete
    cantidad            smallint      NOT NULL DEFAULT 1,
    dias_entrega        numeric(8,2),                            -- entrega - compra (NULL si no hay entrega)
    dias_retraso        numeric(8,2),                            -- entrega - estimada (>0 = tarde)
    entrega_tardia      smallint,                                -- 1 / 0 (NULL si no hay entrega)
    review_score        smallint CHECK (review_score BETWEEN 1 AND 5),
    es_primer_item      smallint      NOT NULL,                  -- 1 en el ítem #1 de cada pedido: permite contar pedidos sin DISTINCT
    PRIMARY KEY (order_id, order_item_id)
);
CREATE INDEX ix_fvi_fcompra   ON dw.fact_ventas_item (sk_fecha_compra);
CREATE INDEX ix_fvi_cliente   ON dw.fact_ventas_item (sk_cliente);
CREATE INDEX ix_fvi_vendedor  ON dw.fact_ventas_item (sk_vendedor);
CREATE INDEX ix_fvi_producto  ON dw.fact_ventas_item (sk_producto);
CREATE INDEX ix_fvi_estado    ON dw.fact_ventas_item (sk_estado);

CREATE TABLE dw.fact_pagos (
    order_id            text     NOT NULL,
    payment_sequential  smallint NOT NULL,
    sk_fecha_compra     integer  NOT NULL REFERENCES dw.dim_tiempo (sk_fecha),
    sk_cliente          integer  NOT NULL REFERENCES dw.dim_cliente (sk_cliente),
    sk_pago             integer  NOT NULL REFERENCES dw.dim_pago (sk_pago),
    sk_estado           integer  NOT NULL REFERENCES dw.dim_estado_pedido (sk_estado),
    valor_pago          numeric(10,2) NOT NULL CHECK (valor_pago >= 0),
    cuotas              smallint      NOT NULL CHECK (cuotas >= 0),
    PRIMARY KEY (order_id, payment_sequential)
);

-- Bitácora de registros descartados o corregidos por el ETL
CREATE TABLE dw.log_calidad (
    id          serial PRIMARY KEY,
    tabla       text NOT NULL,
    clave       text,
    regla       text NOT NULL,
    accion      text NOT NULL,        -- 'rechazado' | 'corregido' | 'marcado'
    registrado  timestamp NOT NULL DEFAULT now()
);
