# Data Mart Olist: Entregable 2

**Universidad Estatal Península de Santa Elena** · Facultad de Sistemas y Telecomunicaciones · Carrera de Software
**Materia:** Inteligencia de Negocios · **Docente:** Ing. Anthony Abrahan Pachay Espinoza, MSc.
**Estudiante:** Julio Jose Del Pezo Rodriguez

Data Mart en PostgreSQL con esquema en estrella, construido a partir del dataset público
[Brazilian E-Commerce by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)
(unos 100 mil pedidos entre 2016 y 2018). Permite analizar ventas, logística y satisfacción del cliente
y alimenta un dashboard de tres pestañas.

## Estructura del repositorio

```
olist-datamart/
├── docker-compose.yml          # PostgreSQL 16 en Docker
├── sql/
│   ├── 01_staging.sql          # carga de los CSV tal cual (esquema stg)
│   ├── 02_modelo_dimensional.sql  # tablas, claves y restricciones (esquema dw)
│   ├── 03_etl.sql              # limpieza, transformación y carga
│   ├── 04_validaciones.sql     # consultas de validación
│   └── 05_vistas_funciones.sql # vistas y funciones para el dashboard
├── docs/
│   ├── Entregable2_Olist_DataMart.docx   # informe completo
│   └── Mockup_Dashboard_Olist.html       # mockup del dashboard (abrir en el navegador)
└── evidencia/                  # capturas y salida de las validaciones
```

La carpeta `archive/` con los CSV **no se sube al repositorio** (pesa más de 100 MB); se descarga de Kaggle.

## Requisitos

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) instalado y en ejecución.
- Los 9 archivos CSV del dataset.

## Cómo reproducir el proyecto

### 1. Preparar los datos

Descarga el dataset desde Kaggle, descomprime el zip y deja los CSV **directamente** dentro de una carpeta `archive/`
en la raíz del proyecto (sin carpetas intermedias):

```
olist-datamart/archive/olist_orders_dataset.csv
olist-datamart/archive/olist_customers_dataset.csv
... (9 archivos .csv en total)
```

### 2. Levantar PostgreSQL

Desde la carpeta raíz del proyecto (donde está `docker-compose.yml`):

```bash
docker compose up -d
```

Datos de conexión:

| Parámetro | Valor |
|---|---|
| Host | localhost |
| Puerto | 5432 |
| Base de datos | bi_database |
| Usuario | bi_user |
| Contraseña | bi_password |

> Si ya tienes otro PostgreSQL usando el puerto 5432, detenlo o cambia en `docker-compose.yml`
> la línea `"5432:5432"` por `"5433:5432"` y conéctate a `localhost:5433`.

### 3. Ejecutar los scripts, en este orden

```bash
docker compose exec -w /data/archive db psql -U bi_user -d bi_database -v ON_ERROR_STOP=1 -f /data/sql/01_staging.sql
docker compose exec -w /data/archive db psql -U bi_user -d bi_database -v ON_ERROR_STOP=1 -f /data/sql/02_modelo_dimensional.sql
docker compose exec -w /data/archive db psql -U bi_user -d bi_database -v ON_ERROR_STOP=1 -f /data/sql/03_etl.sql
docker compose exec -w /data/archive db psql -U bi_user -d bi_database -v ON_ERROR_STOP=1 -f /data/sql/05_vistas_funciones.sql
docker compose exec -w /data/archive db psql -U bi_user -d bi_database -f /data/sql/04_validaciones.sql
```

El orden es 01, 02, 03, 05 y al final 04 (las validaciones usan las funciones creadas en el 05).
`-w /data/archive` es necesario para que el script 01 encuentre los CSV. Los scripts son re-ejecutables.

Para guardar la salida de las validaciones en PowerShell:

```powershell
docker compose exec -w /data/archive db psql -U bi_user -d bi_database -f /data/sql/04_validaciones.sql | Out-File -Encoding utf8 evidencia/evidencia_validacion.txt
```

### 4. Comprobar que quedó bien

Los resultados esperados de `04_validaciones.sql`:

| Comprobación | Resultado esperado |
|---|---|
| Filas en `dw.fact_ventas_item` | 112.650 |
| Filas en `dw.fact_pagos` | 103.886 |
| Filas en `dw.dim_cliente` / `dim_vendedor` / `dim_producto` | 99.441 / 3.095 / 32.951 |
| Registros huérfanos en integridad referencial | 0 |
| Ventas totales (sin cancelados) | R$ 13.496.408,43 |
| Pedidos con al menos un ítem | 98.666 |

## Modelo dimensional

- **Tabla de hechos principal:** `dw.fact_ventas_item`. Una fila representa un ítem (unidad vendida) dentro de un pedido,
  identificado por `(order_id, order_item_id)`.
- **Segunda tabla de hechos:** `dw.fact_pagos`. Una fila representa un pago parcial de un pedido,
  identificado por `(order_id, payment_sequential)`.
- **Dimensiones:** `dim_tiempo` (con tres roles: compra, entrega y fecha estimada), `dim_cliente`, `dim_vendedor`,
  `dim_producto`, `dim_pago` y `dim_estado_pedido`.
- **Esquemas:** `stg` guarda los datos crudos; `dw` contiene el Data Mart.
- La tabla `dw.log_calidad` registra los datos corregidos, marcados o rechazados por el ETL.

El diagrama estrella completo está en el informe (`docs/`).

## Capa de consumo para el dashboard

La aplicación debe leer vistas y funciones, no las tablas directamente.

| Objeto | Para qué sirve |
|---|---|
| `dw.vw_ventas_detalle` | Hecho unido a todas las dimensiones |
| `dw.vw_kpi_mensual`, `vw_logistica_estado`, `vw_satisfaccion_entrega`, `vw_pagos_resumen` | Agregados sin filtros |
| `dw.fn_total_ventas()`, `fn_ticket_promedio()`, `fn_tiempo_entrega()`, `fn_pct_entregas_tardias()`, `fn_calificacion_promedio()`, ... | KPI con filtros |
| `dw.fn_ventas_mensuales()`, `fn_top_categorias()`, `fn_logistica_por_estado()`, `fn_satisfaccion_entrega()`, `fn_pagos_resumen()` | Datos para gráficos |
| `dw.fn_ranking_vendedores()`, `fn_detalle_pedidos()` | Tablas de detalle |

Las funciones de KPI reciben cuatro parámetros opcionales (`NULL` = sin filtro):
fecha desde, fecha hasta, categoría (en inglés) y estado (UF) del cliente.

```sql
-- Ventas de 2018 en la categoría health_beauty para clientes de SP
SELECT dw.fn_total_ventas('2018-01-01', '2018-08-31', 'health_beauty', 'SP');

-- Top 5 categorías de todo el período
SELECT * FROM dw.fn_top_categorias(NULL, NULL, NULL, 5);
```

La matriz de trazabilidad (componente → KPI → filtros → objeto SQL) está en la sección 10 del informe.

## Comandos útiles de Docker

| Acción | Comando |
|---|---|
| Ver el estado del contenedor | `docker compose ps` |
| Detener (conserva los datos) | `docker compose down` |
| Borrar todo y empezar de cero | `docker compose down -v` |
| Abrir una consola SQL | `docker compose exec db psql -U bi_user -d bi_database` |

## Datos

Dataset original: Olist, *Brazilian E-Commerce Public Dataset by Olist* (Kaggle). Los datos están anonimizados
y se usan con fines académicos.
