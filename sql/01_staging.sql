-- =====================================================================
-- 01_staging.sql  |  Carga cruda de los CSV de Olist (todo como texto)
-- Ejecutar DESDE la carpeta donde están los CSV:
--   cd C:\Users\<usuario>\Downloads\archive
--   psql -U postgres -d olist_dm -f 01_staging.sql
-- Principio: staging no transforma nada; los tipos se corrigen en el ETL.
-- =====================================================================
DROP SCHEMA IF EXISTS stg CASCADE;
CREATE SCHEMA stg;

CREATE TABLE stg.customers (
    customer_id text, customer_unique_id text,
    customer_zip_code_prefix text, customer_city text, customer_state text);

CREATE TABLE stg.orders (
    order_id text, customer_id text, order_status text,
    order_purchase_timestamp text, order_approved_at text,
    order_delivered_carrier_date text, order_delivered_customer_date text,
    order_estimated_delivery_date text);

CREATE TABLE stg.order_items (
    order_id text, order_item_id text, product_id text, seller_id text,
    shipping_limit_date text, price text, freight_value text);

CREATE TABLE stg.order_payments (
    order_id text, payment_sequential text, payment_type text,
    payment_installments text, payment_value text);

CREATE TABLE stg.order_reviews (
    review_id text, order_id text, review_score text,
    review_comment_title text, review_comment_message text,
    review_creation_date text, review_answer_timestamp text);

CREATE TABLE stg.products (
    product_id text, product_category_name text, product_name_lenght text,
    product_description_lenght text, product_photos_qty text,
    product_weight_g text, product_length_cm text, product_height_cm text,
    product_width_cm text);

CREATE TABLE stg.sellers (
    seller_id text, seller_zip_code_prefix text, seller_city text, seller_state text);

CREATE TABLE stg.category_translation (
    product_category_name text, product_category_name_english text);

-- Carga (\copy es de psql y lee el archivo desde TU computador)
\copy stg.customers          FROM 'olist_customers_dataset.csv'          WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy stg.orders             FROM 'olist_orders_dataset.csv'             WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy stg.order_items        FROM 'olist_order_items_dataset.csv'        WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy stg.order_payments     FROM 'olist_order_payments_dataset.csv'     WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy stg.order_reviews      FROM 'olist_order_reviews_dataset.csv'      WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy stg.products           FROM 'olist_products_dataset.csv'           WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy stg.sellers            FROM 'olist_sellers_dataset.csv'            WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
-- El CSV de traducción trae BOM al inicio; se carga sin HEADER y se descarta la fila 1.
\copy stg.category_translation FROM 'product_category_name_translation.csv' WITH (FORMAT csv, HEADER false, ENCODING 'UTF8')
DELETE FROM stg.category_translation WHERE product_category_name LIKE '%product_category_name';

-- La geolocalización (1.000.163 filas) no entra en la versión 1 del modelo
-- (decisión (c) del Entregable 1: la geografía se modela por estado y ciudad).

SELECT 'customers' t, count(*) FROM stg.customers UNION ALL
SELECT 'orders', count(*) FROM stg.orders UNION ALL
SELECT 'order_items', count(*) FROM stg.order_items UNION ALL
SELECT 'order_payments', count(*) FROM stg.order_payments UNION ALL
SELECT 'order_reviews', count(*) FROM stg.order_reviews UNION ALL
SELECT 'products', count(*) FROM stg.products UNION ALL
SELECT 'sellers', count(*) FROM stg.sellers UNION ALL
SELECT 'category_translation', count(*) FROM stg.category_translation;
