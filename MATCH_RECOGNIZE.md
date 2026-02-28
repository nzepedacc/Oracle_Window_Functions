# MATCH_RECOGNIZE en Oracle
**Nelson** · Fundador y CDO · [Simov Labs](https://simov.io)
---

## ¿Qué es MATCH_RECOGNIZE?

`MATCH_RECOGNIZE` es una cláusula de Oracle SQL que permite **detectar patrones en secuencias de filas**, de la misma forma en que una expresión regular detecta patrones en texto.

Fue introducida en **Oracle 12c** y es parte del estándar **SQL:2016**. A pesar de su potencia, es una de las funcionalidades menos conocidas y utilizadas del ecosistema Oracle.

> En pocas palabras: es como hacer una **regex sobre tus datos tabulares**, fila por fila, dentro del motor de base de datos.

---

## ¿Por qué es tan poderosa?

Normalmente, detectar patrones de comportamiento en datos requiere:

- **Python + Pandas** con lógica compleja de loops y condicionales
- **Apache Spark** con window functions encadenadas
- O incluso **modelos de Machine Learning** para detección de secuencias

`MATCH_RECOGNIZE` te permite hacer todo eso **directamente en SQL**, dentro del motor Oracle, lo que significa:

- Sin mover datos fuera de la base de datos
- Mucho más eficiente en performance
- Reproducible y auditable
- Sin dependencias externas (no necesitas Python, Spark, ni ML)
- Accesible para cualquier analista que sepa SQL

---

## Anatomía de MATCH_RECOGNIZE

```sql
SELECT *
FROM tabla_o_subquery
MATCH_RECOGNIZE (
  PARTITION BY columna_particion       -- como un GROUP BY para el patrón
  ORDER BY columna_orden               -- orden cronológico o lógico
  MEASURES                             -- qué quieres extraer del patrón
    A.columna  AS alias,
    ...
  ONE ROW PER MATCH                    -- una fila resumen por patrón encontrado
  -- o ALL ROWS PER MATCH              -- una fila por cada fila participante
  AFTER MATCH SKIP TO NEXT ROW        -- cómo avanzar después de un match
  PATTERN (A B+ C)                     -- el patrón a detectar
  DEFINE                               -- definición de cada variable del patrón
    A AS condicion_a,
    B AS condicion_b,
    C AS condicion_c
)
```

### Componentes explicados

| Componente | Descripción |
|------------|-------------|
| `PARTITION BY` | Divide los datos por cliente, producto, etc. El patrón se busca dentro de cada partición |
| `ORDER BY` | Define el orden en que se evalúan las filas (generalmente fecha) |
| `MEASURES` | Las columnas que quieres en el resultado: valores, conteos, primeros/últimos |
| `PATTERN` | La secuencia de variables que defines, como una regex |
| `DEFINE` | Las condiciones que cada variable del patrón debe cumplir |

---

## Los Cuantificadores del PATTERN

Igual que en expresiones regulares:

| Símbolo | Significado | Ejemplo | Matchea |
|---------|-------------|---------|---------|
| (sin símbolo) | exactamente 1 vez | `A` | Solo 1 fila A |
| `+` | uno o más | `B+` | 1, 2, 3... filas B |
| `*` | cero o más | `B*` | 0, 1, 2... filas B |
| `?` | cero o uno | `B?` | 0 o 1 fila B |
| `{n}` | exactamente n | `B{3}` | Exactamente 3 filas B |
| `{n,m}` | entre n y m | `B{2,4}` | Entre 2 y 4 filas B |

### Ejemplos de patrones

```
PATTERN (A B+ C)       -- pequeño, uno o más medianos, grande
PATTERN (A B{2,4} C)   -- pequeño, entre 2 y 4 medianos, grande
PATTERN (A B* C)       -- pequeño, opcionalmente medianos, grande
PATTERN (A+ B+ C+)     -- varios pequeños, varios medianos, varios grandes
```

---

## ONE ROW PER MATCH vs ALL ROWS PER MATCH

### ONE ROW PER MATCH (resumen)

Devuelve **una sola fila por patrón encontrado**. Vista condensada.

```
Cliente | Pedido_A | Monto_A | Pedido_B | Monto_B | Pedido_C | Monto_C
999     | 1        | 3,000   | 2        | 10,000  | 4        | 80,000
```

> El pedido 3 ($20,000) participó como B pero no aparece en la fila resumen.

### ALL ROWS PER MATCH (detalle)

Devuelve **una fila por cada pedido que participó** en el patrón.

```
Cliente | Order_ID | Total   | CLASSIFIER | NUM_MATCH
999     | 1        | 3,000   | A          | 1
999     | 2        | 10,000  | B          | 1
999     | 3        | 20,000  | B          | 1
999     | 4        | 80,000  | C          | 1
```

`CLASSIFIER()` te dice el rol que jugó cada fila en el patrón (A, B o C).

---

## AFTER MATCH SKIP — ¿Cómo avanza Oracle?

Controla qué hace Oracle después de encontrar un match:

| Opción | Comportamiento |
|--------|---------------|
| `AFTER MATCH SKIP TO NEXT ROW` | Retrocede una fila y busca más patrones (puede solapar) |
| `AFTER MATCH SKIP PAST LAST ROW` | Salta al final del match y continúa (sin solapamiento) |

Con `SKIP TO NEXT ROW` encuentras más matches posibles por cliente.

---

## El Query Completo — Caso de Uso Real

**Objetivo:** Detectar clientes que escalaron su gasto: empezaron con pedidos pequeños, luego medianos, y terminaron con pedidos grandes. Ideal para identificar clientes con potencial de upsell.

### Paso 1: Explorar la distribución de montos

Antes de definir los umbrales del patrón, hay que conocer los datos reales:

```sql
SELECT 
  MIN(total_orden)                                           AS minimo,
  MAX(total_orden)                                           AS maximo,
  AVG(total_orden)                                           AS promedio,
  MEDIAN(total_orden)                                        AS mediana,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY total_orden)  AS p25,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY total_orden)  AS p75
FROM (
  SELECT 
    o.order_id,
    SUM(oi.unit_price * oi.quantity) AS total_orden
  FROM OE.ORDERS o
  JOIN OE.ORDER_ITEMS oi ON o.order_id = oi.order_id
  GROUP BY o.order_id
);
```

**Resultado en el dataset OE:**

| MINIMO | MAXIMO | PROMEDIO | MEDIANA | P25 | P75 |
|--------|--------|----------|---------|-----|-----|
| 48 | 295,892 | 14,933 | 16,447 | 5,537 | 46,257 |

> Usamos P25 y P75 como umbrales naturales del negocio.

### Paso 2: El Query Principal

```sql
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
```

### Interpretación de Resultados

| CUSTOMER_ID | PRIMER_PEDIDO | MONTO_BAJO | SEGUNDO_PEDIDO | MONTO_MEDIO | TERCER_PEDIDO | MONTO_ALTO | NUM_MATCH |
|-------------|--------------|------------|----------------|-------------|---------------|------------|-----------|
| 108 | 2443 | 3,646 | 2420 | 29,750 | 2361 | 120,131 | 1 |
| 147 | 2450 | 1,636 | 2366 | 37,319 | 2385 | 295,892 | 1 |
| 148 | 2406 | 2,854 | 2451 | 10,474 | 2367 | 144,054 | 1 |

**Cliente 147** es el más interesante: comenzó con $1,636 y terminó en $295,892 (el monto máximo del dataset). Es el cliente con mayor crecimiento relativo.

---

## Variante con ALL ROWS PER MATCH

Para ver el detalle completo de cada pedido que participó en el patrón:

```sql
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
    MATCH_NUMBER()          AS num_match,
    CLASSIFIER()            AS rol_en_patron,
    FIRST(A.order_date)     AS inicio_patron,
    LAST(C.order_date)      AS fin_patron,
    COUNT(B.order_id)       AS pedidos_medios,
    SUM(B.total_orden)      AS suma_pedidos_medios
  ALL ROWS PER MATCH
  AFTER MATCH SKIP TO NEXT ROW
  PATTERN (A B+ C)
  DEFINE
    A AS total_orden < 5537,
    B AS total_orden >= 5537 
       AND total_orden < 46257,
    C AS total_orden >= 46257
)
ORDER BY customer_id, num_match, order_date;
```

---

## ¿Qué pasa si el cliente tiene 10 pedidos?

Oracle no requiere que sean exactamente 3 pedidos. Busca el patrón `A B+ C` **dentro de todos los pedidos** del cliente, en orden cronológico.

Con 10 pedidos puede encontrar **múltiples matches**:

```
Pedido 1:  $2,000   → A
Pedido 2:  $10,000  → B
Pedido 3:  $8,000   → B
Pedido 4:  $60,000  → C   ✓ MATCH 1 (pedidos 1-4)
Pedido 5:  $3,000   → A
Pedido 6:  $15,000  → B
Pedido 7:  $80,000  → C   ✓ MATCH 2 (pedidos 5-7)
Pedido 8:  $1,000   → A
Pedido 9:  $200,000 → C   ✗ NO MATCH (falta B entre A y C)
Pedido 10: $4,000   → A   ✗ NO MATCH (no hay B ni C después)
```

El campo `NUM_MATCH` en el resultado te indica el número de match dentro de ese cliente.

---

## Casos de Uso en Producción

| Industria | Caso de Uso | Patrón |
|-----------|-------------|--------|
| **Retail / eCommerce** | Clientes con upsell journey | `A B+ C` (bajo → medio → alto) |
| **Banca** | Detección de fraude | `NORMAL SOSPECHOSA+ FRAUDE` |
| **SaaS** | Detección de churn | `ACTIVO+ INACTIVO` |
| **Ventas** | Análisis de funnel | `LEAD CONTACTO+ CIERRE` |
| **IoT** | Anomalías en sensores | `NORMAL ALTO+ CRITICO` |
| **Marketing** | Reactivación de clientes | `ACTIVO+ CAIDA+ RECUPERACION` (patrón V) |

---

## Cómo correrlo en FreeSQL (freesql.com)

1. Entra a **[freesql.com](https://freesql.com)**
2. En el Navigator selecciona el schema **Order Entry (OE)**
3. Haz click en **Worksheet** (ícono `>_` en la barra superior)
4. Pega el query en el editor
5. Presiona el botón **Run** o usa el atajo `Ctrl + Enter`
6. Los resultados aparecen en la pestaña **Query result**

> FreeSQL es un entorno Oracle gratuito online con el schema OE ya instalado, ideal para practicar sin necesidad de instalar Oracle localmente.

---

## Resumen

`MATCH_RECOGNIZE` es la funcionalidad más disruptiva de Oracle SQL para análisis de comportamiento. Combina el poder de las expresiones regulares con la eficiencia del motor relacional, permitiendo detectar patrones complejos en secuencias de datos sin salir del SQL.

Si trabajas con datos de clientes, transacciones, eventos o cualquier dato secuencial, esta función debería estar en tu toolkit como analista o ingeniero de datos.

---

*Elaborado con Oracle SQL sobre el schema OE (Order Entry) en freesql.com*
