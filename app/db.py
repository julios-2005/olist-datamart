"""Acceso a PostgreSQL. TODOS los datos del dashboard salen del Data Mart (esquema dw):
la aplicación nunca lee los CSV originales."""
import os

import pandas as pd
import streamlit as st
from sqlalchemy import create_engine, text


@st.cache_resource
def get_engine():
    """Una sola conexión (pool) reutilizada por toda la aplicación.
    Los valores por defecto coinciden con docker-compose.yml; pueden cambiarse con variables de entorno."""
    url = "postgresql+psycopg2://{u}:{p}@{h}:{port}/{d}".format(
        u=os.getenv("PGUSER", "bi_user"),
        p=os.getenv("PGPASSWORD", "bi_password"),
        h=os.getenv("PGHOST", "localhost"),
        port=os.getenv("PGPORT", "5432"),
        d=os.getenv("PGDATABASE", "bi_database"),
    )
    return create_engine(url, pool_pre_ping=True)


@st.cache_data(ttl=300, show_spinner=False)
def run(sql: str, params: dict | None = None) -> pd.DataFrame:
    """Ejecuta una consulta con parámetros (evita inyección SQL) y devuelve un DataFrame."""
    with get_engine().connect() as conn:
        return pd.read_sql(text(sql), conn, params=params or {})


# Los cuatro filtros viajan como parámetros :d (desde), :h (hasta), :c (categoría), :u (estado).
# NULL = sin filtro, igual que en las funciones SQL.
ARGS = "CAST(:d AS date), CAST(:h AS date), CAST(:c AS text), CAST(:u AS text)"
ARGS_FECHA_CAT = "CAST(:d AS date), CAST(:h AS date), CAST(:c AS text)"
ARGS_FECHA = "CAST(:d AS date), CAST(:h AS date)"

SQL = {
    "opciones_fechas": "SELECT min(fecha_compra) AS desde, max(fecha_compra) AS hasta FROM dw.vw_ventas_detalle",
    "opciones_categorias": "SELECT DISTINCT categoria_en AS v FROM dw.dim_producto ORDER BY 1",
    "opciones_uf": "SELECT DISTINCT estado_uf AS v FROM dw.dim_cliente ORDER BY 1",
    "kpi_comercial": f"""SELECT dw.fn_total_ventas({ARGS}) AS ventas, dw.fn_total_pedidos({ARGS}) AS pedidos,
        dw.fn_ticket_promedio({ARGS}) AS ticket, dw.fn_participacion_flete({ARGS}) AS flete""",
    "ventas_mensuales": f"SELECT * FROM dw.fn_ventas_mensuales({ARGS})",
    "top_categorias": f"SELECT * FROM dw.fn_top_categorias(CAST(:d AS date), CAST(:h AS date), CAST(:u AS text), :n)",
    "detalle": f"SELECT * FROM dw.fn_detalle_pedidos({ARGS}, :n)",
    "kpi_logistica": f"""SELECT dw.fn_tiempo_entrega({ARGS}) AS dias, dw.fn_pct_entregas_tardias({ARGS}) AS tardias,
        dw.fn_calificacion_promedio({ARGS}) AS calificacion, dw.fn_pct_resenas_negativas({ARGS}) AS negativas""",
    "logistica_estado": f"SELECT * FROM dw.fn_logistica_por_estado({ARGS_FECHA_CAT})",
    "satisfaccion": f"SELECT * FROM dw.fn_satisfaccion_entrega({ARGS_FECHA_CAT})",
    "kpi_vendedores": f"""SELECT dw.fn_pct_top10_vendedores({ARGS}) AS top10, dw.fn_tasa_recompra({ARGS}) AS recompra,
        dw.fn_total_pedidos({ARGS}) AS pedidos""",
    "pagos": f"SELECT * FROM dw.fn_pagos_resumen({ARGS_FECHA})",
    "ranking": f"SELECT * FROM dw.fn_ranking_vendedores({ARGS_FECHA}, :n)",
}


def consulta(nombre: str, filtros: dict, **extra) -> pd.DataFrame:
    return run(SQL[nombre], {**filtros, **extra})
