# Guion del video (objetivo: 4 min 30 s; mínimo 3, máximo 5)

Graba la pantalla con tu voz. Antes de empezar: Docker activo, PostgreSQL con los datos cargados, pgAdmin abierto y la
app en `localhost:8501`. **No es solo diapositivas: debe verse todo funcionando.**

| Tiempo | Qué mostrar | Qué decir (idea, con tus palabras) |
|---|---|---|
| 0:00 – 0:30 | Portada o README | "Soy ... Analicé el marketplace Olist: unos 100 mil pedidos de 2016 a 2018 en 9 tablas. Quiero ayudar a decidir en qué categorías y regiones enfocarse, dónde corregir retrasos y cómo mejorar la experiencia del cliente." |
| 0:30 – 1:15 | Diagrama estrella (informe) | "Modelo en estrella. La tabla de hechos `fact_ventas_item`: **una fila representa un ítem dentro de un pedido**. Seis dimensiones: tiempo (con tres roles), cliente, vendedor, producto, pago y estado del pedido. Hay una segunda tabla de hechos para pagos." |
| 1:15 – 2:00 | **pgAdmin** | Mostrar el esquema `dw` con las tablas cargadas y `SELECT count(*) FROM dw.fact_ventas_item;` (112.650). Ejecutar una función, por ejemplo `SELECT dw.fn_total_ventas(NULL,NULL,'health_beauty','SP');`. Decir que la app usa estas funciones. |
| 2:00 – 3:30 | **App Streamlit** | Recorrer las 3 vistas señalando KPI, gráficos y tabla. **Cambiar un filtro** (por ejemplo, categoría `health_beauty` y estado `SP`) y mostrar cómo cambian el GMV y los gráficos. Abrir "Ver consulta SQL utilizada". |
| 3:30 – 4:10 | Vista "Logística y satisfacción" | Explicar un resultado: "Los pedidos con retraso reciben una calificación media de 2,57 contra 4,29 de los puntuales, y 54 % de sus reseñas son negativas. Logística podría renegociar transportistas o ajustar plazos en los estados con más retrasos, como AL o MA." |
| 4:10 – 4:40 | Evidencias de IA | "Usé IA para construir el modelo y la app. Por ejemplo, el tiempo de entrega no coincidía con el Entregable 1 (12,1 contra 12,56 días); lo validé contra los datos y descubrí que antes se truncaban los días. También corregí una nota errónea de la IA sobre un filtro." |

Consejos: practica una vez antes; cuida el tiempo; verifica que se escuche bien; y prepárate para que el docente te pida
explicar una consulta o modificar un filtro en vivo.
