# Grupo Comercial Andino: hallazgos de calidad de datos y cómo los resolvió el ETL

> Regla del curso: **nunca confiar en los datos**. Cada archivo se perfiló antes de diseñar el ETL.
> El **STAGE** guarda el dato tal como vino (con errores) y el **DWH** guarda el dato limpio.
> Lo que se descarta no se pierde: queda en una tabla `Error...` con el **motivo**.

| Script | Para qué |
|---|---|
| `sql/04_hallazgos_antes.sql` | Muestra en el **STAGE** cada caso sucio (qué hay que limpiar) |
| `sql/05_resultado_despues.sql` | Muestra en el **DWH** cómo quedó cada caso después del ETL |
| `sql/03_validaciones.sql` | Cuadre: STAGE = DWH + tablas de error |

## 1. Patrón principal: copias "disfrazadas" al final de cada archivo

Los registros sucios están **agregados al final** del archivo, con IDs consecutivos. Son **copias exactas de
registros reales** a las que se les cambió el ID y la **fecha**, por eso no aparecen como duplicados a simple vista.

| Archivo | Copias | Cómo están disfrazadas | Ejemplo |
|---|---|---|---|
| Ventas | **609** (`VTA-00180001` a `VTA-00180609`) | Fecha movida ±3 años (2020–2022, 2025–2027) | `VTA-00180001` (29/11/2026) = `VTA-00082604` (15/12/2023) |
| Carrito abandonado | **26,550** (`CRT-00040000` en adelante, 40 % del archivo) | Fecha movida exactamente +1,890 días (2028–2030) | `CRT-00040000` (23/07/2028) = `CRT-00013450` (21/05/2023) |
| Ticket de soporte | **636** (`TK-0025000` en adelante) | Años 1990–1992 y 2035–2037 | `TK-0025000` (22/05/2035) = `TK-0023897` (25/01/2023) |

**Cómo se detectó (método del profesor):** `COUNT(1) ... GROUP BY <todas las columnas menos ID y fecha> ORDER BY 1 DESC`
→ cada grupo tiene exactamente 2 filas: una con fecha dentro del calendario y otra fuera.

**Cómo lo resuelve el ETL (paquetes `FactVenta`, `FactCarrito`, `FactTicketSoporte`):** la consulta de origen calcula
```sql
ROW_NUMBER() OVER (PARTITION BY venta_id ORDER BY FilaOrigen)              -- mismo ID repetido -> se queda la 1.ª
MIN(CASE WHEN fecha dentro del calendario THEN venta_id END)
    OVER (PARTITION BY <contenido sin ID ni fecha>)  AS Gemelo              -- el original válido
MotivoDescarte = 'Duplicado de ' + Gemelo + ' con fecha alterada (...)'     -- si la fila está fuera de rango y tiene gemelo
```
La **División condicional** "bad" envía esas filas a `ErrorFactVenta` / `ErrorFactCarrito` / `ErrorFactTicketSoporte`.
**Se conserva un solo registro: el original.**

## 2. Maestros con filas repetidas

| Maestro | Repetidas | Detalle |
|---|---|---|
| Calendario | 36 | Fechas repetidas idénticas (ene–mar 2023) |
| Producto | 210 | Filas idénticas desde la fila 8,500 |
| Vendedor | 17 | Filas idénticas |
| Cliente | 25 + **3** | 3 IDs (`CLI-000032/33/34`) repetidos **con distinto `canal_origen`** ("Fuerza directa" vs "Paid ads") |

**Cómo lo resuelve el ETL (procedimientos `sp_Dim...`):**
```sql
ROW_NUMBER() OVER (PARTITION BY cliente_id ORDER BY FilaOrigen)  -- rn = 1 se carga (primera aparición)
```
Las filas `rn > 1` quedan en `Comercial.ErrorMaestro` con el motivo:
"Fila repetida idéntica" o "ID repetido con datos distintos: canal_origen "Paid ads" vs "Fuerza directa"".
`FilaOrigen` es el número de fila del archivo, que el STAGE guarda con un `IDENTITY`.

## 3. Importes vacíos: la venta que "sale en 0"

| Caso | Cantidad | Solución |
|---|---|---|
| `venta_neta` vacía (`VTA-00000216` a `VTA-00000425`) | 103 | Recalculada: `cantidad × precio_unitario_neto` |
| `margen_bruto` vacío | 488 | Recalculado: `(venta_neta − costo_total) / venta_neta` |

Antes de recalcular se comprobó que en las otras 180,000 ventas las fórmulas cuadran al centavo
(`precio_unitario_neto = precio_lista × (1 − descuento)` y `venta_neta = cantidad × precio_unitario_neto`).
Ejemplo `VTA-00000216`: 14 × 856.30 = **11,988.20**, margen **33.29 %** (en el archivo: vacío → 0 en Power BI).
En el DWH, `FactVenta[VentaNetaRecalculada] = 1` marca esas filas.

## 4. Columnas corruptas o incoherentes

| Problema | Cantidad | Solución en el ETL |
|---|---|---|
| `fecha_cierre` de soporte viene como `55:34.6` (Excel perdió la fecha) | **todos** | Reconstruida: `fecha_apertura + horas_resolucion` |
| Dos formatos de fecha (`13/11/2023` y `2023-08-11`) | 4 archivos de cada uno | `COALESCE(TRY_CONVERT(DATE, x, 103), TRY_CONVERT(DATE, x, 23))` |
| `ciclo_venta_dias` ≠ cierre − creación | 2,391 oportunidades | Recalculado con las fechas; el original queda en `CicloVentaOrigen` |
| Llamadas de clientes que no existen (`CLI-0919xx`) | 150 | `ErrorFactLlamada`: "Cliente inexistente en el maestro" |
| `es_venta = 1` con "No contactado" o "Rechazo" | 5,373 (5,369 tras quitar las de clientes inexistentes) | Se conservan con la marca `EsVentaInconsistente = 1` |
| `sla_cumplido` = 0 con 24,00 horas exactas | 1 | `SlaRecalculado` = horas ≤ 24 |

## 5. Datos poco confiables que se marcan (no se borran)

| Hallazgo | Cantidad | Marca en el DWH / cubo |
|---|---|---|
| Clientes con `fecha_alta` en el futuro (2025–2026) | 3,580 filas (3,575 clientes únicos) | `DimCliente.FechaAltaFutura` |
| Clientes dados de alta **después** de su primera compra | 7,273 | `vw_DimCliente.AltaPosteriorACompra` (el cubo usa `FechaPrimeraCompra`) |
| Vendedores que venden **antes** de su fecha de ingreso | 127 | `vw_DimVendedor.IngresoPosteriorAVenta` |
| Mismo nombre y país con distinto `cliente_id` | 90 clientes | `DimCliente.PosibleDuplicado` (no se fusionan: distinto segmento, alta y canal) |

## 6. Lo que se validó y está bien

- Ninguna venta tiene cliente, vendedor o producto inexistente; precio y costo coinciden con el maestro.
- Embudo e-commerce coherente (sesiones ≥ carrito ≥ checkout ≥ órdenes) y `venta_total = órdenes × ticket`.
- Marketing: nuevos clientes ≤ leads. Calendario: año, mes, trimestre, día y fin de semana correctos.
- **1,493 ventas con margen negativo son reales** (accesorios con 18–28 % de descuento): es el problema del caso, no un error.
- El NPS por momento y fase reproduce el caso (post-soporte cae de 37 a 22).

## 7. Resultado: archivo = DWH + errores

| Tabla | Archivo / STAGE | DWH | Error | Motivo principal |
|---|---|---|---|---|
| Ventas | 180,609 | 180,000 | 609 | Duplicado con fecha alterada |
| Oportunidades | 25,000 | 25,000 | 0 | – |
| Llamadas | 200,150 | 200,000 | 150 | Cliente inexistente |
| Carritos | 66,550 | 40,000 | 26,550 | Duplicado con fecha alterada |
| Sesiones | 3,655 | 3,655 | 0 | – |
| Encuestas | 15,000 | 15,000 | 0 | – |
| Marketing | 4,386 | 4,386 | 0 | – |
| Tickets de soporte | 25,636 | 25,000 | 636 | Duplicado con fecha alterada |
| Calendario | 767 | 731 | 36 | Fila repetida |
| Clientes | 12,028 | 12,000 | 28 | Repetida (3 con datos distintos) |
| Productos | 8,710 | 8,500 | 210 | Fila repetida |
| Vendedores | 277 | 260 | 17 | Fila repetida |

## 8. Limitaciones de los datos frente al caso

- **Churn:** con la regla "no compra en 12 meses", solo 10 de 11,995 clientes activos en 2023 no compraron en 2024;
  el 15 % del caso no se reproduce con estos datos.
- **Pipeline coverage y forecast:** todas las oportunidades del archivo están cerradas (ganadas o perdidas) y no hay
  forecast; el cubo trae una aproximación de coverage (monto / cuota) y no calcula forecast accuracy.
- **CAC y LTV/CAC:** el archivo de marketing no trae comisiones ni costo de venta directa: el CAC del cubo
  (≈ USD 138) es solo de marketing y por eso el LTV/CAC aproximado sale muy alto (≈ 65x); no es comparable con el 2,1x del caso.
- **Cross-sell:** en los dos años, todos los clientes activos compran más de una categoría (100 %); medido por mes o
  trimestre (filtrando la fecha) el indicador sí discrimina.
- **Cumplimiento de cuota:** la cuota anual de cada vendedor se reparte en 12 meses; con las ventas del archivo el
  cumplimiento global es 47 % (E-commerce 78 %, Inside Sales 72 %, Distribuidor 55 %, Fuerza Directa 36 %), menor que
  el 81 % del caso, pero el orden de los canales es el mismo que describe el caso para los rezagados.
- **NPS:** cada encuesta trae un puntaje de −40 a 100 (no la escala 0–10), por eso el NPS se calcula como promedio.
