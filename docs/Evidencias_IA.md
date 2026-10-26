# Evidencias de uso de Inteligencia Artificial

> **Borrador para que lo revises y lo escribas con tus palabras.** Los tres usos describen hechos reales del desarrollo
> de este proyecto, pero el docente puede pedirte que expliques cualquiera: ajusta lo que no coincida con lo que tú hiciste
> y asegúrate de poder explicar cada punto. Reemplaza los prompts por los que realmente escribiste si difieren.

## Uso 1 · Diseño y construcción del Data Mart a partir de la consigna del Entregable 2

| | |
|---|---|
| **Problema** | Pasar de 9 CSV relacionados a un modelo dimensional en PostgreSQL, sin experiencia previa en SQL de carga (ETL). |
| **Prompt** | Se entregó a la IA la consigna del Entregable 2, el informe del Entregable 1 y el `archive.zip` con los CSV. |
| **Solución propuesta** | Dos capas (`stg` para datos crudos y `dw` para el Data Mart), tabla de hechos `fact_ventas_item` (una fila por ítem de pedido), seis dimensiones, una segunda tabla de hechos `fact_pagos` y scripts SQL 01 a 05 (carga, modelo, ETL, validaciones, vistas y funciones). |
| **Qué se utilizó o modificó** | Se mantuvo el modelo en estrella del Entregable 1. Cambios propios o decididos tras revisar: `dim_cliente` a nivel de `customer_id` (porque cambia en cada pedido), la columna `es_primer_item` (evita contar un pedido varias veces) y la bitácora `dw.log_calidad`. |
| **Cómo se comprobó** | Con `04_validaciones.sql`: mismas filas en origen y destino (112.650 ítems), 0 huérfanos en las relaciones, 0 duplicados en la granularidad y totales idénticos al centavo (GMV R$ 13.496.408,43 en `stg` y en `dw`). Los scripts se ejecutaron de cero sin errores. |

## Uso 2 · Cifras que no coincidían con el Entregable 1

| | |
|---|---|
| **Problema** | El tiempo medio de entrega del Entregable 1 (12,1 días) no coincidía con el calculado en el Data Mart (12,56 días). |
| **Prompt** | Se pidió a la IA validar las cifras del Entregable 1 contra los datos cargados en PostgreSQL. |
| **Solución propuesta** | La IA contrastó definiciones: el 12,1 salía de truncar cada entrega a días enteros (promedio 12,09), mientras que el modelo usa fracciones de día. Las 7.827 entregas tardías sí coincidían al comparar fecha y hora. |
| **Qué se utilizó o modificó** | Se adoptó el cálculo con fracciones de día y se documentó la diferencia en el informe. También se explicó que calificación, % de reseñas negativas y recompra cambian levemente porque ahora se calculan por pedido y sin cancelados. |
| **Cómo se comprobó** | Consulta directa sobre `stg.orders` con ambas definiciones (12,09 truncando; 12,56 con fracciones) y conteo de tardías (7.827 de 96.476). |

## Uso 3 · Aplicación Streamlit conectada a PostgreSQL

| | |
|---|---|
| **Problema** | Construir un dashboard con filtros que afecten de verdad a las consultas, sin leer nunca los CSV. |
| **Prompt** | Se entregó a la IA la consigna del Entregable 3 y se pidió una aplicación Streamlit sobre las funciones SQL del Entregable 2. |
| **Solución propuesta** | `db.py` (conexión con SQLAlchemy, consultas parametrizadas y caché) y `app.py` (3 vistas, 3 filtros en el panel lateral, KPI, gráficos con Plotly y tabla de detalle). Los filtros viajan como parámetros a las funciones SQL. |
| **Qué se utilizó o modificó** | Se corrigió una nota errónea de la IA que decía que el ranking de categorías respondía al filtro de categoría (la función SQL no lo recibe); ahora la aplicación indica qué filtro no aplica en cada consulta. Se agregó una nota sobre los meses incompletos del dataset, para que la caída final del gráfico no se interprete como caída real de ventas. |
| **Cómo se comprobó** | Prueba automática y manual: con los filtros por defecto los KPI coinciden con `04_validaciones.sql`; al elegir la categoría `health_beauty` el GMV baja de R$ 13.496.408 a R$ 1.255.695, y con la categoría más el estado SP baja a R$ 460.474. Además se revisó que la aplicación no importa ni abre ningún CSV. |

## Declaración

La IA se usó como apoyo para proponer estructura y código. Todo el código se ejecutó sobre los datos reales y sus
resultados se contrastaron con el origen. Las decisiones de modelado y las correcciones indicadas arriba fueron revisadas por el estudiante.
