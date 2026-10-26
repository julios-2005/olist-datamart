"""Dashboard de Business Intelligence · Olist Marketplace
Ejecutar:  streamlit run app/app.py
"""
import pandas as pd
import plotly.express as px
import streamlit as st

import db

st.set_page_config(page_title="Olist · Panel analítico", page_icon="📊", layout="wide")
TEAL, ORANGE, RED = "#0F6B6B", "#C77700", "#B5352A"


def num(v, dec=0, pre="", suf=""):
    """Formato con punto de miles y coma decimal (1.234,56). None -> guion."""
    if v is None or pd.isna(v):
        return "—"
    s = f"{v:,.{dec}f}".replace(",", "X").replace(".", ",").replace("X", ".")
    return f"{pre}{s}{suf}"


# ------------------------------------------------------------------ conexión
try:
    fechas = db.run(db.SQL["opciones_fechas"]).iloc[0]
    categorias = db.run(db.SQL["opciones_categorias"])["v"].tolist()
    ufs = db.run(db.SQL["opciones_uf"])["v"].tolist()
except Exception as e:  # base apagada, credenciales erróneas, datos sin cargar
    st.error("No se pudo consultar PostgreSQL. Verifica que el contenedor esté activo "
             "(`docker compose up -d`) y que los scripts SQL 01 a 05 se hayan ejecutado.")
    st.code(str(e)[:400])
    st.stop()

# ------------------------------------------------------------------- filtros
st.sidebar.title("Filtros")
rango = st.sidebar.date_input("Fecha de compra", value=(fechas["desde"], fechas["hasta"]),
                              min_value=fechas["desde"], max_value=fechas["hasta"])
cat = st.sidebar.selectbox("Categoría de producto", ["Todas"] + categorias)
uf = st.sidebar.selectbox("Estado del cliente (UF)", ["Todos"] + ufs)
if not (isinstance(rango, (tuple, list)) and len(rango) == 2):
    st.info("Selecciona la fecha de fin del rango en el panel lateral.")
    st.stop()
F = {"d": rango[0], "h": rango[1], "c": None if cat == "Todas" else cat, "u": None if uf == "Todos" else uf}
st.sidebar.caption("Los filtros se envían como parámetros a las funciones SQL del esquema `dw`. "
                   "Dónde un filtro no aplica a una consulta, se indica en la sección.")

st.title("📊 Olist · Panel analítico")
vista = st.radio("Vista", ["Resumen comercial", "Logística y satisfacción", "Vendedores y pagos"],
                 horizontal=True, label_visibility="collapsed")


def sql_expander(*nombres):
    with st.expander("Ver consulta SQL utilizada"):
        for n in nombres:
            st.code(db.SQL[n], language="sql")
        st.caption(f"Parámetros actuales: {F}")


def sin_datos(df):
    if df.empty:
        st.info("No hay datos para los filtros seleccionados.")
        return True
    return False


# ---------------------------------------------------------- 1. resumen comercial
if vista == "Resumen comercial":
    k = db.consulta("kpi_comercial", F).iloc[0]
    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Ventas totales (GMV)", num(k.ventas, 0, "R$ "))
    c2.metric("Pedidos", num(k.pedidos))
    c3.metric("Ticket promedio", num(k.ticket, 2, "R$ "))
    c4.metric("Participación del flete", num(k.flete, 2, suf=" %"))

    izq, der = st.columns([3, 2])
    with izq:
        st.subheader("Evolución mensual de ventas")
        m = db.consulta("ventas_mensuales", F)
        if not sin_datos(m):
            fig = px.line(m, x="anio_mes", y="ventas_totales", markers=True,
                          labels={"anio_mes": "Mes", "ventas_totales": "Ventas (R$)"})
            fig.update_traces(line_color=TEAL)
            st.plotly_chart(fig, width="stretch")
            st.caption("Los meses extremos del dataset están incompletos (finales de 2016 y septiembre-octubre de 2018): la caída final refleja datos parciales, no una caída real de ventas.")
    with der:
        n = st.slider("Categorías a mostrar", 3, 15, 8)
        st.subheader(f"Top {n} categorías")
        t = db.consulta("top_categorias", F, n=n)
        if not sin_datos(t):
            fig = px.bar(t.iloc[::-1], x="ventas_totales", y="categoria", orientation="h",
                         text="participacion_pct", labels={"ventas_totales": "Ventas (R$)", "categoria": ""})
            fig.update_traces(marker_color=TEAL, texttemplate="%{text:.1f}%")
            st.plotly_chart(fig, width="stretch")
        st.caption("El ranking compara categorías entre sí, por eso usa el rango de fechas y el estado, pero no el filtro de categoría.")

    st.subheader("Detalle de pedidos")
    filas = st.select_slider("Filas a mostrar", [25, 50, 100, 500, 1000], value=100)
    d = db.consulta("detalle", F, n=filas)
    if not sin_datos(d):
        st.dataframe(d, hide_index=True, width="stretch")
        st.download_button("Descargar CSV", d.to_csv(index=False).encode("utf-8"), "detalle_pedidos.csv", "text/csv")
    sql_expander("kpi_comercial", "ventas_mensuales", "top_categorias", "detalle")

# ------------------------------------------------- 2. logística y satisfacción
elif vista == "Logística y satisfacción":
    k = db.consulta("kpi_logistica", F).iloc[0]
    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Tiempo medio de entrega", num(k.dias, 1, suf=" días"))
    c2.metric("% entregas tardías", num(k.tardias, 2, suf=" %"))
    c3.metric("Calificación promedio", num(k.calificacion, 2, suf=" / 5"))
    c4.metric("% reseñas negativas (1-2)", num(k.negativas, 2, suf=" %"))

    izq, der = st.columns([3, 2])
    with izq:
        st.subheader("Entregas tardías por estado del cliente")
        e = db.consulta("logistica_estado", F)
        if not sin_datos(e):
            top = st.slider("Estados a mostrar", 5, 27, 12)
            e = e.head(top).iloc[::-1]
            fig = px.bar(e, x="pct_tardias", y="uf", orientation="h", hover_data=["pedidos", "dias_entrega_prom"],
                         labels={"pct_tardias": "% pedidos tardíos", "uf": "Estado"})
            fig.update_traces(marker_color=RED)
            st.plotly_chart(fig, width="stretch")
        st.caption("Esta consulta agrupa por estado, por eso no usa el filtro de estado (UF).")
    with der:
        st.subheader("Calificación según puntualidad")
        s = db.consulta("satisfaccion", F)
        if not sin_datos(s):
            fig = px.bar(s, x="entrega", y="calificacion_prom", text="calificacion_prom",
                         color="entrega", color_discrete_map={"A tiempo": TEAL, "Con retraso": RED},
                         labels={"entrega": "", "calificacion_prom": "Calificación promedio"})
            fig.update_layout(showlegend=False, yaxis_range=[0, 5])
            st.plotly_chart(fig, width="stretch")
            st.dataframe(s.rename(columns={"calificacion_prom": "calificación prom.",
                                           "pct_resenas_negativas": "% reseñas negativas"}),
                         hide_index=True, width="stretch")
    sql_expander("kpi_logistica", "logistica_estado", "satisfaccion")

# ------------------------------------------------------ 3. vendedores y pagos
else:
    k = db.consulta("kpi_vendedores", F).iloc[0]
    c1, c2, c3 = st.columns(3)
    c1.metric("% ventas del top 10 de vendedores", num(k.top10, 2, suf=" %"))
    c2.metric("Tasa de recompra", num(k.recompra, 2, suf=" %"))
    c3.metric("Pedidos", num(k.pedidos))

    st.subheader("Medios de pago")
    p = db.consulta("pagos", F)
    if not sin_datos(p):
        a, b = st.columns(2)
        fig = px.bar(p, x="tipo_pago", y="valor_total", labels={"tipo_pago": "", "valor_total": "Valor pagado (R$)"})
        fig.update_traces(marker_color=TEAL)
        a.plotly_chart(fig, width="stretch")
        fig = px.bar(p, x="tipo_pago", y="pago_promedio", hover_data=["cuotas_promedio", "cuotas_max"],
                     labels={"tipo_pago": "", "pago_promedio": "Pago promedio (R$)"})
        fig.update_traces(marker_color=ORANGE)
        b.plotly_chart(fig, width="stretch")
    st.caption("Medios de pago y ranking usan el rango de fechas; los filtros de categoría y estado no aplican a estas consultas.")

    st.subheader("Ranking de vendedores")
    n = st.slider("Vendedores a mostrar", 5, 50, 10)
    r = db.consulta("ranking", F, n=n)
    if not sin_datos(r):
        st.dataframe(r, hide_index=True, width="stretch")
    sql_expander("kpi_vendedores", "pagos", "ranking")
