-- ============================================================
-- ORACLE WINDOW FUNCTIONS - ESQUEMA ORDER ENTRY (OE)
-- freesql.com | Claudio CDO Reference
-- ============================================================

-- ============================================================
-- 1. ROW_NUMBER() — Ranking de clientes por monto total de compras
--    Caso de uso: identificar el top N de clientes por ventas
-- ============================================================
SELECT
    c.customer_id,
    c.cust_last_name || ', ' || c.cust_first_name AS cliente,
    SUM(oi.unit_price * oi.quantity)              AS total_compras,
    ROW_NUMBER() OVER (
        ORDER BY SUM(oi.unit_price * oi.quantity) DESC
    ) AS ranking
FROM oe.customers     c
JOIN oe.orders        o  ON o.customer_id  = c.customer_id
JOIN oe.order_items   oi ON oi.order_id    = o.order_id
GROUP BY c.customer_id, c.cust_last_name, c.cust_first_name
ORDER BY ranking;


-- ============================================================
-- 2. RANK() / DENSE_RANK() — Ranking de productos por ingresos
--    Diferencia: RANK deja huecos en empates, DENSE_RANK no
-- ============================================================
SELECT
    p.product_id,
    p.product_name,
    SUM(oi.unit_price * oi.quantity)   AS ingresos_totales,
    RANK()       OVER (ORDER BY SUM(oi.unit_price * oi.quantity) DESC) AS rank_con_huecos,
    DENSE_RANK() OVER (ORDER BY SUM(oi.unit_price * oi.quantity) DESC) AS rank_sin_huecos
FROM oe.product_information p
JOIN oe.order_items          oi ON oi.product_id = p.product_id
GROUP BY p.product_id, p.product_name
ORDER BY ingresos_totales DESC;


-- ============================================================
-- 3. PARTITION BY — Ranking de productos POR CATEGORÍA
--    Caso de uso: top producto dentro de cada categoría
-- ============================================================
SELECT *
FROM (
    SELECT
        p.category_id,
        cat.category_name,
        p.product_name,
        SUM(oi.unit_price * oi.quantity)   AS ingresos,
        RANK() OVER (
            PARTITION BY p.category_id
            ORDER BY SUM(oi.unit_price * oi.quantity) DESC
        ) AS rank_en_categoria
    FROM oe.product_information p
    JOIN oe.order_items          oi  ON oi.product_id  = p.product_id
    JOIN oe.categories_tab       cat ON cat.category_id = p.category_id
    GROUP BY p.category_id, cat.category_name, p.product_name
)
WHERE rank_en_categoria <= 3   -- Top 3 por categoría
ORDER BY category_id, rank_en_categoria;


-- ============================================================
-- 4. SUM() OVER — Acumulado de ventas por fecha (Running Total)
--    Caso de uso: seguimiento de ingresos acumulados en el tiempo
-- ============================================================
SELECT
    TRUNC(o.order_date, 'MM')                      AS mes,
    SUM(oi.unit_price * oi.quantity)               AS ventas_mes,
    SUM(SUM(oi.unit_price * oi.quantity)) OVER (
        ORDER BY TRUNC(o.order_date, 'MM')
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )                                              AS ventas_acumuladas
FROM oe.orders      o
JOIN oe.order_items oi ON oi.order_id = o.order_id
GROUP BY TRUNC(o.order_date, 'MM')
ORDER BY mes;


-- ============================================================
-- 5. AVG() OVER — Media móvil de 3 meses (Rolling Average)
--    Caso de uso: suavizar tendencias de ventas
-- ============================================================
SELECT
    TRUNC(o.order_date, 'MM')                      AS mes,
    SUM(oi.unit_price * oi.quantity)               AS ventas_mes,
    ROUND(
        AVG(SUM(oi.unit_price * oi.quantity)) OVER (
            ORDER BY TRUNC(o.order_date, 'MM')
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ), 2
    )                                              AS media_movil_3m
FROM oe.orders      o
JOIN oe.order_items oi ON oi.order_id = o.order_id
GROUP BY TRUNC(o.order_date, 'MM')
ORDER BY mes;


-- ============================================================
-- 6. LAG() / LEAD() — Comparación mes a mes (MoM)
--    Caso de uso: variación de ventas respecto al mes anterior
-- ============================================================
SELECT
    mes,
    ventas_mes,
    LAG(ventas_mes)  OVER (ORDER BY mes)           AS ventas_mes_anterior,
    LEAD(ventas_mes) OVER (ORDER BY mes)           AS ventas_mes_siguiente,
    ROUND(
        (ventas_mes - LAG(ventas_mes) OVER (ORDER BY mes))
        / NULLIF(LAG(ventas_mes) OVER (ORDER BY mes), 0) * 100
    , 2)                                           AS variacion_pct_mom
FROM (
    SELECT
        TRUNC(o.order_date, 'MM')             AS mes,
        SUM(oi.unit_price * oi.quantity)      AS ventas_mes
    FROM oe.orders      o
    JOIN oe.order_items oi ON oi.order_id = o.order_id
    GROUP BY TRUNC(o.order_date, 'MM')
)
ORDER BY mes;


-- ============================================================
-- 7. NTILE() — Segmentación de clientes en cuartiles (RFM base)
--    Caso de uso: clasificar clientes por valor (quartile analysis)
-- ============================================================
SELECT
    customer_id,
    cliente,
    total_compras,
    NTILE(4) OVER (ORDER BY total_compras DESC) AS cuartil,
    CASE NTILE(4) OVER (ORDER BY total_compras DESC)
        WHEN 1 THEN 'VIP'
        WHEN 2 THEN 'Alto'
        WHEN 3 THEN 'Medio'
        WHEN 4 THEN 'Bajo'
    END AS segmento_cliente
FROM (
    SELECT
        c.customer_id,
        c.cust_last_name || ', ' || c.cust_first_name AS cliente,
        SUM(oi.unit_price * oi.quantity)              AS total_compras
    FROM oe.customers     c
    JOIN oe.orders        o  ON o.customer_id = c.customer_id
    JOIN oe.order_items   oi ON oi.order_id   = o.order_id
    GROUP BY c.customer_id, c.cust_last_name, c.cust_first_name
)
ORDER BY total_compras DESC;


-- ============================================================
-- 8. FIRST_VALUE() / LAST_VALUE() — Comparar con el mejor/peor
--    Caso de uso: brecha entre cada producto y el líder de categoría
-- ============================================================
SELECT
    category_name,
    product_name,
    ingresos,
    FIRST_VALUE(product_name) OVER (
        PARTITION BY category_id
        ORDER BY ingresos DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS mejor_producto,
    FIRST_VALUE(ingresos) OVER (
        PARTITION BY category_id
        ORDER BY ingresos DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS ingresos_lider,
    ROUND(ingresos / FIRST_VALUE(ingresos) OVER (
        PARTITION BY category_id
        ORDER BY ingresos DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) * 100, 1) AS pct_vs_lider
FROM (
    SELECT
        p.category_id,
        cat.category_name,
        p.product_name,
        SUM(oi.unit_price * oi.quantity) AS ingresos
    FROM oe.product_information p
    JOIN oe.order_items          oi  ON oi.product_id  = p.product_id
    JOIN oe.categories_tab       cat ON cat.category_id = p.category_id
    GROUP BY p.category_id, cat.category_name, p.product_name
)
ORDER BY category_id, ingresos DESC;


-- ============================================================
-- 9. PERCENT_RANK() / CUME_DIST() — Distribución percentil
--    Caso de uso: posición relativa de cada orden en el histograma
-- ============================================================
SELECT
    o.order_id,
    o.order_date,
    SUM(oi.unit_price * oi.quantity)                    AS monto_orden,
    ROUND(PERCENT_RANK() OVER (
        ORDER BY SUM(oi.unit_price * oi.quantity)
    ) * 100, 2)                                         AS percentil,
    ROUND(CUME_DIST() OVER (
        ORDER BY SUM(oi.unit_price * oi.quantity)
    ) * 100, 2)                                         AS distribucion_acum_pct
FROM oe.orders      o
JOIN oe.order_items oi ON oi.order_id = o.order_id
GROUP BY o.order_id, o.order_date
ORDER BY monto_orden DESC;


-- ============================================================
-- 10. COMBO AVANZADO — Dashboard ejecutivo por cliente
--     ROW_NUMBER + SUM acumulado + LAG + NTILE en una sola query
-- ============================================================
SELECT
    cliente,
    num_ordenes,
    total_gastado,
    ROW_NUMBER() OVER (ORDER BY total_gastado DESC)           AS ranking_global,
    NTILE(4)     OVER (ORDER BY total_gastado DESC)           AS cuartil,
    SUM(total_gastado) OVER (
        ORDER BY total_gastado DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )                                                         AS gasto_acumulado,
    ROUND(total_gastado / SUM(total_gastado) OVER () * 100, 2) AS pct_del_total,
    LAG(total_gastado) OVER (ORDER BY total_gastado DESC)     AS gasto_cliente_anterior
FROM (
    SELECT
        c.cust_last_name || ', ' || c.cust_first_name AS cliente,
        COUNT(DISTINCT o.order_id)                    AS num_ordenes,
        SUM(oi.unit_price * oi.quantity)              AS total_gastado
    FROM oe.customers     c
    JOIN oe.orders        o  ON o.customer_id = c.customer_id
    JOIN oe.order_items   oi ON oi.order_id   = o.order_id
    GROUP BY c.customer_id, c.cust_last_name, c.cust_first_name
)
ORDER BY ranking_global;
