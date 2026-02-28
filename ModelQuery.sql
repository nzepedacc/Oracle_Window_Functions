SELECT customer_id, ano, ventas_totales, cliente_nombre
FROM (
    SELECT 
        customer_id,
        ano,
        ventas_totales,
        cliente_nombre
    FROM (
        SELECT 
            o.customer_id,
            EXTRACT(YEAR FROM o.order_date) AS ano,
            SUM(oi.quantity * oi.unit_price) AS ventas_totales,
            c.cust_first_name || ' ' || c.cust_last_name AS cliente_nombre
        FROM oe.orders o
        JOIN oe.order_items oi ON o.order_id = oi.order_id
        JOIN oe.customers c ON o.customer_id = c.customer_id
        GROUP BY o.customer_id, EXTRACT(YEAR FROM o.order_date),
                 c.cust_first_name, c.cust_last_name
    ) datos
    MODEL
        PARTITION BY (customer_id, cliente_nombre)
        DIMENSION BY (ano)
        MEASURES (ventas_totales)
        RULES (
            ventas_totales[2025] = ROUND(
                1.12 * MAX(ventas_totales)[ano < 2025],
                2
            ),
            
            ventas_totales[2026] = ROUND(
                1.12 * ventas_totales[2025],
                2
            )
        )
) modelo_resultado
WHERE ventas_totales > 500
   OR ano >= 2025
ORDER BY customer_id, ano;
