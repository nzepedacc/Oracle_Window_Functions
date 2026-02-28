# MODEL en Oracle
**Nelson** · Fundador y CDO · [Simov Labs](https://simov.io)
---


## ¿Qué es la cláusula MODEL?

La cláusula **MODEL** (también llamada *spreadsheet in SQL* o *hoja de cálculo en SQL*) es una extensión de Oracle SQL que permite tratar el resultado de una consulta como un **array multidimensional** y aplicar reglas de cálculo sobre sus celdas, de forma similar a una hoja de cálculo. Con MODEL puedes:

- Crear **nuevas filas** que no existían en los datos originales (por ejemplo, años futuros).
- **Actualizar** o **calcular** valores de celdas usando fórmulas que hacen referencia a otras celdas.
- Realizar **proyecciones**, **pronósticos** y **análisis what-if** directamente en SQL, sin necesidad de exportar a Excel o a otro lenguaje.

En resumen: **MODEL convierte tu conjunto de resultados en una “matriz” y te deja definir reglas que rellenan o modifican celdas usando la sintaxis de referencias por dimensiones.**

---

## ¿Cómo funciona?

La cláusula MODEL se compone de varias partes que definen la “estructura” de la hoja de cálculo y las reglas de cálculo.

### 1. Entrada: el resultado de un SELECT

Solo se aplica sobre el resultado de una subconsulta (o vista). Ese resultado debe tener columnas que actuarán como:

- **Partición (PARTITION BY):** agrupa las filas en bloques independientes. Cada partición se procesa por separado (como hojas distintas).
- **Dimensión (DIMENSION BY):** define los “ejes” que identifican de forma única cada celda dentro de una partición (por ejemplo, el año).
- **Medidas (MEASURES):** son las columnas cuyos valores se pueden leer y escribir con las reglas (como las celdas que editas en Excel).

### 2. Sintaxis básica

```sql
SELECT ...
FROM (
    SELECT ...   -- subconsulta que genera filas: partición, dimensión, medidas
) alias
MODEL
    PARTITION BY (col1, col2, ...)
    DIMENSION BY (dim1, dim2, ...)
    MEASURES (medida1, medida2, ...)
    [RULES] (
        medida[dim_val] = expresión,
        ...
    )
```

- **PARTITION BY:** columnas que dividen los datos en grupos; las reglas se aplican dentro de cada grupo.
- **DIMENSION BY:** columnas que forman la “clave” única dentro de cada partición (por ejemplo, `ano`).
- **MEASURES:** columnas numéricas (u otras) que se pueden actualizar o crear con las reglas.
- **RULES:** cada regla asigna un valor a una “celda” identificada por la medida y el valor de dimensión (por ejemplo, `ventas_totales[2025]`).

### 3. Referencias en las reglas

En las reglas puedes usar:

- **Referencia a una celda:** `ventas_totales[2025]`, `ventas_totales[ano]`.
- **Referencia a varias celdas (agregación):**  
  `MAX(ventas_totales)[ano < 2025]` → máximo de ventas en todos los años anteriores a 2025 dentro de la misma partición.
- **Posición relativa:** `ventas_totales[ano - 1]` (año anterior), etc.

Las reglas se evalúan en un orden que Oracle determina (o puedes controlar con `SEQUENTIAL ORDER` / `AUTOMATIC ORDER`), lo que permite que una celda dependa de otra (por ejemplo, 2026 basado en 2025).

### 4. Orden de evaluación

- **AUTOMATIC ORDER (por defecto):** Oracle detecta dependencias entre celdas y evalúa las reglas en el orden correcto.
- **SEQUENTIAL ORDER:** las reglas se ejecutan en el orden en que las escribes.

Para proyecciones como “2025 y luego 2026”, suele bastar con **AUTOMATIC ORDER**.

---

## ¿Por qué es importante?

1. **Todo en la base de datos:** proyecciones, escenarios y KPIs se calculan en SQL, sin mover datos a hojas de cálculo ni a otros lenguajes.
2. **Rendimiento:** se aprovecha el motor de Oracle (paralelismo, índices, optimizador) en lugar de hacer los cálculos fuera del DB.
3. **Mantenibilidad:** la lógica de negocio (por ejemplo, “crecer 12 % año a año”) queda en una sola consulta, documentada y versionada.
4. **Consistencia:** mismos datos y mismas reglas para todos los reportes o herramientas que usen esa consulta.
5. **Potencia expresiva:** permite what-if, pronósticos, asignaciones y modelos que serían muy engorrosos solo con agregaciones y `CASE`.

---

## ¿Cuándo podríamos usarla?

- **Pronósticos y proyecciones:** ventas futuras, demanda, ingresos (como en tu ejemplo con 2025 y 2026).
- **Presupuestos y escenarios:** distintos supuestos de crecimiento o descuentos aplicados sobre datos históricos.
- **Asignación y reparto:** distribuir totales entre periodos o productos según reglas.
- **Análisis temporal:** rellenar huecos (por ejemplo, meses sin ventas) o alinear periodos.
- **Indicadores derivados:** ratios, márgenes o KPIs que dependen de otras celdas del mismo “cubo”.
- **Modelos simples tipo hoja de cálculo:** cuando la lógica es “celda = f(otras celdas)” y quieres mantenerla en SQL.

---

## Ejemplo práctico: proyección de ventas (esquema OE)

En el esquema **OE (Order Entry)** de Oracle, la siguiente consulta:

1. Obtiene **ventas históricas por cliente y año** (a partir de `orders`, `order_items` y `customers`).
2. Usa **MODEL** para proyectar ventas en **2025** y **2026** con un crecimiento del **12 %**.
3. Filtra y ordena el resultado.

### Consulta completa

```sql
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
```

### Qué hace cada parte

| Parte | Rol |
|-------|-----|
| Subconsulta interna | Agrupa por `customer_id`, año (`EXTRACT(YEAR FROM order_date)`) y calcula `ventas_totales` y `cliente_nombre`. |
| **PARTITION BY (customer_id, cliente_nombre)** | Cada cliente es una “hoja” independiente; las reglas se aplican por separado a cada uno. |
| **DIMENSION BY (ano)** | La dimensión que identifica cada “fila” dentro del cliente es el año. |
| **MEASURES (ventas_totales)** | La única medida que se calcula/modifica en las reglas es `ventas_totales`. |
| **ventas_totales[2025] = ...** | Crea/calcula la celda para el año 2025. |
| **MAX(ventas_totales)[ano < 2025]** | En cada partición (cada cliente), toma el máximo de ventas de todos los años **anteriores** a 2025. |
| **1.12 * MAX(...)** | Aplica un crecimiento del 12 % sobre ese máximo histórico. |
| **ventas_totales[2026] = 1.12 * ventas_totales[2025]** | Proyecta 2026 como 12 % más que la proyección de 2025 (celda que ya fue calculada). |
| **WHERE ventas_totales > 500 OR ano >= 2025** | Excluye filas con ventas ≤ 500, excepto si son años de proyección (2025 o 2026). |

El resultado combina **datos históricos** (por ejemplo 2006, 2007, 2008) con **filas nuevas** para 2025 y 2026, con valores proyectados como en tu captura (p. ej. 120903.44 para el cliente 101 en 2025, 135411.85 en 2026).

---

## Resumen

| Concepto | Descripción |
|----------|-------------|
| **Qué es** | Extensión SQL que trata el resultado de una consulta como un array multidimensional y aplica reglas tipo hoja de cálculo. |
| **Cómo funciona** | PARTITION BY (grupos), DIMENSION BY (ejes), MEASURES (valores a calcular), RULES (fórmulas por celda). |
| **Por qué importa** | Cálculos complejos y proyecciones dentro de la base de datos, con buen rendimiento y lógica centralizada. |
| **Cuándo usarla** | Pronósticos, presupuestos, escenarios what-if, relleno de huecos temporales y cualquier lógica “celda = f(otras celdas)” en SQL. |

Con la consulta en OE tienes un ejemplo concreto de uso de MODEL para **proyectar ventas por cliente** manteniendo histórico y añadiendo años futuros con una regla de crecimiento fija, probablemente 2025 y 2026 no sean los mejores años a usar, pero el ejemplo es funcional.
