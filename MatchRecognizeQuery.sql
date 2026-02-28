SELECT *
FROM (
  SELECT 
    o.customer_id,
    o.order_id,
    o.order_date,
    SUM(oi.unit_price * oi.quantity) AS total_orden
  FROM OE.ORDERS o
  JOIN OE.ORDER_ITEMS oi ON o.order_id = oi.order_id
  GROUP BY o.customer_id, o.order_id, o.order_date
)
MATCH_RECOGNIZE (
  PARTITION BY customer_id
  ORDER BY order_date
  MEASURES
    A.order_id        AS primer_pedido,
    A.total_orden     AS monto_primer_pedido,
    B.order_id        AS segundo_pedido,
    B.total_orden     AS monto_segundo_pedido,
    C.order_id        AS tercer_pedido,
    C.total_orden     AS monto_tercer_pedido,
    MATCH_NUMBER()    AS num_match
  AFTER MATCH SKIP TO NEXT ROW
  PATTERN (A B+ C)
  DEFINE
    A AS total_orden < 5537,
    B AS total_orden >= 5537 
       AND total_orden < 46257,
    C AS total_orden >= 46257
)
ORDER BY customer_id;
