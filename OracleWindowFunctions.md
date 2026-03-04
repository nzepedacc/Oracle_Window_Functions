# Oracle Window Functions 
**Nelson** · Fundador y CDO · [Simov Labs](https://simov.io)
---

### Esquema Order Entry (OE) | freesql.com

> **¿Qué es una Window Function?**
> Es una función que realiza un cálculo sobre un **conjunto de filas relacionadas con la fila actual**, sin colapsar el resultado en una sola fila (a diferencia de `GROUP BY`).
>
> ```
> función() OVER (
>     PARTITION BY columna   -- divide en grupos
>     ORDER BY columna       -- define el orden dentro del grupo
>     ROWS/RANGE BETWEEN ... -- define el "frame" o ventana de filas
> )
> ```
> Las tres partes del `OVER()` son **opcionales**, pero su combinación define el comportamiento exacto.

---

## Tabla de contenido

1. [ROW_NUMBER()](#1-row_number)
2. [RANK() y DENSE_RANK()](#2-rank-y-dense_rank)
3. [PARTITION BY](#3-partition-by--ranking-por-grupos)
4. [SUM() OVER — Running Total](#4-sum-over--running-total-acumulado)
5. [AVG() OVER — Media Móvil](#5-avg-over--media-móvil-rolling-average)
6. [LAG() y LEAD()](#6-lag-y-lead)
7. [NTILE()](#7-ntile--segmentación-en-cuartiles)
8. [FIRST_VALUE() y LAST_VALUE()](#8-first_value-y-last_value)
9. [PERCENT_RANK() y CUME_DIST()](#9-percent_rank-y-cume_dist)
10. [Combo Avanzado — Dashboard Ejecutivo](#10-combo-avanzado--dashboard-ejecutivo)

---

## 1. ROW_NUMBER()

### ¿Qué hace?
Asigna un **número secuencial único** a cada fila dentro de un resultado ordenado. Siempre genera números consecutivos: 1, 2, 3, 4... sin importar si hay empates — simplemente rompe el empate de forma arbitraria.

### Analogía
Imagina que organizas una carrera y asignas dorsales en el orden de llegada. Aunque dos corredores lleguen casi al mismo tiempo, uno obtiene el dorsal 3 y el otro el 4. No hay repetidos.

### Sintaxis clave
```sql
ROW_NUMBER() OVER (ORDER BY columna DESC)
```
- No lleva argumentos dentro del `()`
- El `ORDER BY` dentro del `OVER` define el criterio de numeración
- Si agregas `PARTITION BY`, reinicia el contador en cada grupo

### Query — Ranking de clientes por monto total de compras
```sql
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
```

### ¿Qué retorna?
| cliente | total_compras | ranking |
|---|---|---|
| García, Juan | 15,000 | 1 |
| López, María | 15,000 | 2 ← mismo monto, diferente ranking |
| Pérez, Carlos | 12,500 | 3 |

### Caso de uso principal
Filtrar el **Top N** de registros: `WHERE ranking <= 10`

---

## 2. RANK() y DENSE_RANK()

### ¿Qué hacen?
Ambas asignan rankings considerando **empates**, pero se diferencian en cómo manejan los números después de un empate:

| Función | Comportamiento en empate |
|---|---|
| `RANK()` | Deja **huecos** después de un empate (1, 2, 2, **4**) |
| `DENSE_RANK()` | **No deja huecos** (1, 2, 2, **3**) |

### Analogía
- **RANK()** → Podio olímpico: si dos atletas ganan plata, no hay bronce — el siguiente es cuarto lugar.
- **DENSE_RANK()** → Clasificación de liga: si dos equipos tienen los mismos puntos, el siguiente en la tabla es el tercero, no el cuarto.

### Sintaxis clave
```sql
RANK()       OVER (ORDER BY columna DESC)
DENSE_RANK() OVER (ORDER BY columna DESC)
```

### Query — Ranking de productos por ingresos
```sql
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
```

### ¿Qué retorna?
| producto | ingresos | rank_con_huecos | rank_sin_huecos |
|---|---|---|---|
| Producto A | 9,000 | 1 | 1 |
| Producto B | 7,500 | 2 | 2 |
| Producto C | 7,500 | 2 | 2 |
| Producto D | 6,000 | **4** | **3** ← diferencia clave |

### ¿Cuándo usar cada uno?
- **RANK()** → cuando el número de posición importa realmente (rankings deportivos, competencias)
- **DENSE_RANK()** → cuando quieres saber cuántos valores distintos hay por encima (más común en analytics)

---

## 3. PARTITION BY — Ranking por grupos

### ¿Qué hace?
`PARTITION BY` **divide el dataset en grupos independientes** antes de aplicar la función. Es como hacer un `GROUP BY` solo para la ventana, sin afectar las filas del resultado.

### Analogía
Imagina que tienes vendedores de distintas regiones. En lugar de rankear a todos juntos, quieres el top 3 **dentro de cada región**. `PARTITION BY region` hace exactamente eso: reinicia el contador en cada región.

### Sintaxis clave
```sql
RANK() OVER (
    PARTITION BY categoria    -- divide por grupo
    ORDER BY ventas DESC      -- ordena dentro del grupo
)
```

### Query — Top 3 productos por categoría
```sql
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
WHERE rank_en_categoria <= 3
ORDER BY category_id, rank_en_categoria;
```

### ¿Qué retorna?
| categoría | producto | ingresos | rank_en_categoria |
|---|---|---|---|
| Hardware | Mouse Pro | 8,000 | 1 |
| Hardware | Teclado X | 6,500 | 2 |
| Hardware | Monitor Y | 5,200 | 3 |
| Software | App Suite | 12,000 | 1 ← reinicia en nueva categoría |
| Software | Plugin Z | 9,800 | 2 |

### Truco importante
El filtro `WHERE rank_en_categoria <= 3` **debe ir en una subquery** — no puedes usar alias de window functions directamente en el `WHERE` de la misma query.

---

## 4. SUM() OVER — Running Total (Acumulado)

### ¿Qué hace?
Calcula una **suma acumulada progresiva**: cada fila muestra el total de sí misma más todas las filas anteriores según el orden definido.

### Analogía
Es como el saldo de una cuenta bancaria: cada movimiento muestra el nuevo saldo acumulado, no solo el monto de esa transacción.

### Sintaxis clave
```sql
SUM(valor) OVER (
    ORDER BY fecha
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
)
```
- `UNBOUNDED PRECEDING` → desde el inicio absoluto
- `CURRENT ROW` → hasta la fila actual
- `ROWS BETWEEN` → define el frame en filas físicas (vs `RANGE` que considera valores iguales)

### Query — Acumulado de ventas por mes
```sql
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
```

> **Nota:** El doble `SUM(SUM(...))` es necesario porque primero agrupamos por mes (inner SUM) y luego acumulamos (outer SUM sobre la window).

### ¿Qué retorna?
| mes | ventas_mes | ventas_acumuladas |
|---|---|---|
| ENE-2024 | 10,000 | 10,000 |
| FEB-2024 | 8,500 | 18,500 |
| MAR-2024 | 12,000 | 30,500 |

### Variaciones útiles del frame
```sql
-- Total general (mismo valor en todas las filas)
SUM(ventas) OVER ()

-- Acumulado dentro del año (particionado)
SUM(ventas) OVER (PARTITION BY año ORDER BY mes
                  ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
```

---

## 5. AVG() OVER — Media Móvil (Rolling Average)

### ¿Qué hace?
Calcula el **promedio de una ventana deslizante** de N filas. A medida que avanza fila a fila, la ventana "se mueve" descartando las más antiguas e incorporando las nuevas.

### Analogía
Es como el promedio de temperatura de los últimos 3 días: cada día calculas el promedio de ese día y los 2 anteriores. Suaviza picos y valles para ver la tendencia real.

### Sintaxis clave
```sql
AVG(valor) OVER (
    ORDER BY fecha
    ROWS BETWEEN 2 PRECEDING AND CURRENT ROW  -- ventana de 3 filas
)
```
- `2 PRECEDING` → las 2 filas anteriores
- `CURRENT ROW` → la fila actual
- Total: ventana de 3 filas (N-2, N-1, N)

### Query — Media móvil de 3 meses
```sql
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
```

### ¿Qué retorna?
| mes | ventas_mes | media_movil_3m |
|---|---|---|
| ENE | 10,000 | 10,000.00 ← solo 1 fila disponible |
| FEB | 8,500 | 9,250.00 ← promedio de ENE+FEB |
| MAR | 12,000 | 10,166.67 ← promedio de ENE+FEB+MAR |
| ABR | 7,000 | 9,166.67 ← promedio de FEB+MAR+ABR |

### Caso de uso
Ideal para **eliminar ruido** en series temporales de ventas, KPIs operacionales o métricas financieras.

---

## 6. LAG() y LEAD()

### ¿Qué hacen?
Permiten **acceder al valor de otra fila** sin hacer un self-join:
- `LAG()` → mira **hacia atrás** (fila anterior)
- `LEAD()` → mira **hacia adelante** (fila siguiente)

### Analogía
Es como comparar tu nota del examen de hoy con la del examen anterior (LAG) o anticiparte a ver la nota del próximo (LEAD), todo desde la misma fila.

### Sintaxis clave
```sql
LAG(columna, N, valor_default)  OVER (ORDER BY fecha)
LEAD(columna, N, valor_default) OVER (ORDER BY fecha)
```
- `N` → cuántas filas saltar (default = 1)
- `valor_default` → qué retornar si no hay fila anterior/siguiente (evita NULLs)

### Query — Variación MoM (Month over Month)
```sql
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
```

> **⚠️ Truco:** Usa `NULLIF(valor, 0)` en el denominador para evitar el error `ORA-01476: divisor is equal to zero`.

### ¿Qué retorna?
| mes | ventas_mes | ventas_anterior | variacion_pct_mom |
|---|---|---|---|
| ENE | 10,000 | NULL | NULL |
| FEB | 8,500 | 10,000 | -15.00% |
| MAR | 12,000 | 8,500 | +41.18% |

### Casos de uso
- Comparaciones **YoY** (Year over Year): `LAG(ventas, 12)` para comparar con el mismo mes del año anterior
- Detectar **gaps** o discontinuidades en series de tiempo
- Calcular **tasas de crecimiento** encadenadas

---

## 7. NTILE() — Segmentación en Cuartiles

### ¿Qué hace?
Divide el resultado en **N grupos de igual tamaño** y asigna a cada fila el número de su grupo (1, 2, 3... N). Es la base para análisis de percentiles discretos y segmentación de clientes.

### Analogía
Imagina que tienes 100 estudiantes ordenados por calificación y los divides en 4 grupos de 25: el grupo 1 son los mejores, el grupo 4 los que más necesitan apoyo. `NTILE(4)` hace exactamente eso con cualquier métrica.

### Sintaxis clave
```sql
NTILE(4) OVER (ORDER BY columna DESC)
```
- El número dentro de `NTILE()` define en cuántos grupos dividir
- Valores comunes: 4 (cuartiles), 5 (quintiles), 10 (deciles), 100 (percentiles)

### Query — Segmentación RFM base de clientes
```sql
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
```

### ¿Qué retorna?
| cliente | total_compras | cuartil | segmento |
|---|---|---|---|
| García, Juan | 15,000 | 1 | VIP |
| López, María | 14,200 | 1 | VIP |
| Pérez, Carlos | 8,500 | 2 | Alto |
| ... | ... | 4 | Bajo |

### Caso de uso estratégico
Combinar NTILE en múltiples dimensiones (recencia + frecuencia + monto) para construir un **modelo RFM completo** de segmentación de clientes.

---

## 8. FIRST_VALUE() y LAST_VALUE()

### ¿Qué hacen?
Retornan el **primer o último valor** de la ventana definida para cada fila. Permiten comparar cada registro contra el mejor, peor o cualquier valor de referencia del grupo.

- `FIRST_VALUE()` → el valor del primer registro de la ventana (generalmente el mejor si ordenás DESC)
- `LAST_VALUE()` → el valor del último registro (**requiere ajustar el frame** por el comportamiento default)

### Analogía
Imagina que en cada fila de tu reporte quieres saber cuánto gana el empleado mejor pagado de ese departamento. `FIRST_VALUE` lo trae sin necesidad de un JOIN adicional.

### ⚠️ Advertencia crítica con LAST_VALUE
El frame **default** en Oracle es `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`, lo que hace que `LAST_VALUE` retorne el valor de la fila actual, no el último. **Siempre especifica el frame completo:**

```sql
FIRST_VALUE(col) OVER (
    PARTITION BY grupo
    ORDER BY col DESC
    ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING  -- ← obligatorio
)
```

### Query — Brecha de cada producto vs. el líder de su categoría
```sql
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
```

### ¿Qué retorna?
| categoría | producto | ingresos | mejor_producto | pct_vs_lider |
|---|---|---|---|---|
| Hardware | Mouse Pro | 8,000 | Mouse Pro | 100.0% |
| Hardware | Teclado X | 6,500 | Mouse Pro | 81.3% |
| Hardware | Monitor Y | 5,200 | Mouse Pro | 65.0% |

---

## 9. PERCENT_RANK() y CUME_DIST()

### ¿Qué hacen?
Calculan la **posición relativa** de cada fila dentro de su grupo como un valor entre 0 y 1:

| Función | Fórmula | Rango |
|---|---|---|
| `PERCENT_RANK()` | `(rank - 1) / (total_filas - 1)` | 0.0 a 1.0 |
| `CUME_DIST()` | `filas ≤ valor actual / total_filas` | > 0.0 a 1.0 |

### Diferencia clave
- `PERCENT_RANK()` → "¿Qué porcentaje de filas tengo **por debajo** de mí?" (la primera siempre es 0%)
- `CUME_DIST()` → "¿Qué porcentaje de filas son **iguales o menores** que yo?" (nunca llega a 0%)

### Analogía
Si tu salario está en el **percentil 80** (`PERCENT_RANK = 0.80`), significa que el 80% de los empleados gana menos que tú. `CUME_DIST` incluye a los que ganan igual.

### Sintaxis clave
```sql
PERCENT_RANK() OVER (ORDER BY columna)
CUME_DIST()    OVER (ORDER BY columna)
```
Ambas no llevan argumentos. El `ORDER BY` define el criterio de distribución.

### Query — Distribución percentil de órdenes por monto
```sql
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
```

### Caso de uso
Identificar **órdenes en el top 10%** de valor:
```sql
WHERE PERCENT_RANK() OVER (ORDER BY monto DESC) >= 0.90
```

---

## 10. Combo Avanzado — Dashboard 

### ¿Qué hace?
Combina múltiples window functions en una sola query para construir un **reporte ejecutivo completo** de clientes: ranking, segmento, participación en ventas, acumulado y comparación con el siguiente.

### Funciones combinadas
| Función | Columna generada | Propósito |
|---|---|---|
| `ROW_NUMBER()` | ranking_global | Posición absoluta del cliente |
| `NTILE(4)` | cuartil | Segmento VIP/Alto/Medio/Bajo |
| `SUM() OVER` | gasto_acumulado | Running total en orden de ranking |
| División por `SUM() OVER ()` | pct_del_total | % que representa cada cliente |
| `LAG()` | gasto_cliente_anterior | Para calcular brecha entre posiciones |

### Query — Dashboard ejecutivo por cliente
```sql
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
```

### ¿Qué retorna?
| cliente | total_gastado | ranking | cuartil | gasto_acumulado | pct_del_total |
|---|---|---|---|---|---|
| García, Juan | 15,000 | 1 | 1 | 15,000 | 8.5% |
| López, María | 14,200 | 2 | 1 | 29,200 | 8.1% |
| Pérez, Carlos | 8,500 | 3 | 2 | 37,700 | 4.8% |

### Por qué usar subquery
Las window functions **no pueden anidarse directamente**. La subquery interna calcula los agregados (`SUM`, `COUNT`), y la query externa aplica las window functions sobre esos resultados.

---

## Resumen de referencia rápida

| Función | ¿Qué resuelve? | ¿Necesita ORDER BY? | ¿Necesita PARTITION BY? |
|---|---|---|---|
| `ROW_NUMBER()` | Numeración única sin empates | ✅ Sí | Opcional |
| `RANK()` | Ranking con huecos en empates | ✅ Sí | Opcional |
| `DENSE_RANK()` | Ranking sin huecos en empates | ✅ Sí | Opcional |
| `SUM() OVER` | Acumulados y totales móviles | Opcional | Opcional |
| `AVG() OVER` | Medias móviles | ✅ Sí | Opcional |
| `LAG() / LEAD()` | Comparar fila con anterior/siguiente | ✅ Sí | Opcional |
| `NTILE(N)` | Segmentación en N grupos iguales | ✅ Sí | Opcional |
| `FIRST_VALUE()` | Valor del mejor/primero del grupo | ✅ Sí | Recomendado |
| `LAST_VALUE()` | Valor del peor/último (requiere frame) | ✅ Sí | Recomendado |
| `PERCENT_RANK()` | Percentil relativo (0 a 1) | ✅ Sí | Opcional |
| `CUME_DIST()` | Distribución acumulada (0 a 1) | ✅ Sí | Opcional |

## Reglas de oro

1. **Window functions no se pueden anidar** — si necesitas usar el resultado de una como input de otra, usa una subquery o CTE.
2. **Siempre especifica el frame en `FIRST_VALUE`/`LAST_VALUE`** — el default puede dar resultados inesperados.
3. **`PARTITION BY` no reemplaza `GROUP BY`** — son conceptos distintos. `GROUP BY` colapsa filas; `PARTITION BY` solo define grupos para la ventana.
4. **Usa `NULLIF(col, 0)` en denominadores** con `LAG`/`LEAD` para evitar `ORA-01476`.
5. **Los alias de window functions no están disponibles en el `WHERE`** de la misma query — siempre envuelve en subquery.

---

*Esquema: Oracle Order Entry (OE) | freesql.com*
