/* =====================================================================
   GCA - ANTES: datos sucios encontrados en el STAGE (copia fiel de los archivos)
   Cada bloque responde "¿qué hay que limpiar?". Ejecutar bloque por bloque (seleccionar + F5).
   El resultado DESPUÉS del ETL está en 05_resultado_despues.sql (mismo orden de bloques).
   ===================================================================== */
USE [STAGE_GCA];
SET NOCOUNT ON;

/* ---------- A. Venta con importe vacío (en Power BI sale 0) ---------- */
SELECT [venta_id], [cantidad], [precio_lista], [descuento], [precio_unitario_neto], [venta_neta], [costo_total], [margen_bruto]
  FROM [GCA].[StageVenta] WHERE [venta_id] = 'VTA-00000216';

SELECT SUM(CASE WHEN NULLIF([venta_neta], N'') IS NULL THEN 1 ELSE 0 END)   AS VentaNetaVacia,
       SUM(CASE WHEN NULLIF([margen_bruto], N'') IS NULL THEN 1 ELSE 0 END) AS MargenVacio
  FROM [GCA].[StageVenta];

-- ¿Se puede recalcular? Las fórmulas cuadran en todas las ventas que sí traen importe (diferencias = 0)
SELECT SUM(CASE WHEN ABS(TRY_CONVERT(DECIMAL(18,2), [precio_unitario_neto])
                         - ROUND(TRY_CONVERT(DECIMAL(18,2), [precio_lista]) * (1 - TRY_CONVERT(DECIMAL(9,4), [descuento])), 2)) > 0.02
                THEN 1 ELSE 0 END) AS PrecioNetoNoCuadra,
       SUM(CASE WHEN ABS(TRY_CONVERT(DECIMAL(18,2), [venta_neta])
                         - TRY_CONVERT(INT, [cantidad]) * TRY_CONVERT(DECIMAL(18,2), [precio_unitario_neto])) > 1
                THEN 1 ELSE 0 END) AS VentaNetaNoCuadra
  FROM [GCA].[StageVenta];

/* ---------- B. Duplicados (método del profesor: COUNT(1) ... GROUP BY ... ORDER BY 1 DESC) ---------- */
-- B1. Maestros: el mismo ID aparece más de una vez
SELECT TOP 10 COUNT(1) AS Veces, [cliente_id] FROM [GCA].[StageCliente] GROUP BY [cliente_id] ORDER BY 1 DESC;
SELECT 'Calendario' AS Tabla, COUNT(*) - COUNT(DISTINCT [fecha]) AS Repetidos FROM [GCA].[StageCalendario]
UNION ALL SELECT 'Cliente',  COUNT(*) - COUNT(DISTINCT [cliente_id])  FROM [GCA].[StageCliente]
UNION ALL SELECT 'Producto', COUNT(*) - COUNT(DISTINCT [producto_id]) FROM [GCA].[StageProducto]
UNION ALL SELECT 'Vendedor', COUNT(*) - COUNT(DISTINCT [vendedor_id]) FROM [GCA].[StageVendedor];

-- B2. Cliente repetido con datos DISTINTOS (hay que decidir cuál se queda: la primera aparición)
SELECT [FilaOrigen], [cliente_id], [nombre], [canal_origen]
  FROM [GCA].[StageCliente]
 WHERE [cliente_id] IN (SELECT [cliente_id] FROM [GCA].[StageCliente] GROUP BY [cliente_id]
                         HAVING COUNT(DISTINCT [canal_origen]) > 1)
 ORDER BY [cliente_id], [FilaOrigen];

-- B3. Ventas: mismo contenido con OTRO venta_id y otra fecha (copia disfrazada)
SELECT TOP 10 COUNT(1) AS Veces,
       STRING_AGG([venta_id] + N' (' + [fecha_venta] + N')', N'  /  ') WITHIN GROUP (ORDER BY [venta_id]) AS VentasYFechas,
       [cliente_id], [producto_id], [cantidad], [venta_neta]
  FROM [GCA].[StageVenta]
 GROUP BY [oportunidad_id], [cliente_id], [vendedor_id], [producto_id], [categoria], [cantidad], [precio_lista], [descuento],
          [precio_unitario_neto], [venta_neta], [costo_total], [margen_bruto], [canal], [region], [tipo_cliente]
 ORDER BY 1 DESC, MAX([venta_id]) DESC;

/* ---------- C. Fechas fuera del calendario del caso (2023-01-01 .. 2024-12-31) ---------- */
SELECT 'Venta' AS Archivo, YEAR(COALESCE(TRY_CONVERT(DATE, [fecha_venta], 103), TRY_CONVERT(DATE, [fecha_venta], 23))) AS Anio, COUNT(*) AS Filas
  FROM [GCA].[StageVenta] GROUP BY YEAR(COALESCE(TRY_CONVERT(DATE, [fecha_venta], 103), TRY_CONVERT(DATE, [fecha_venta], 23)))
UNION ALL
SELECT 'Carrito', YEAR(TRY_CONVERT(DATE, [fecha], 103)), COUNT(*) FROM [GCA].[StageCarrito] GROUP BY YEAR(TRY_CONVERT(DATE, [fecha], 103))
UNION ALL
SELECT 'Soporte', YEAR(TRY_CONVERT(DATE, [fecha_apertura], 103)), COUNT(*) FROM [GCA].[StageTicketSoporte] GROUP BY YEAR(TRY_CONVERT(DATE, [fecha_apertura], 103))
ORDER BY Archivo, Anio;

/* ---------- D. Columnas corruptas o incoherentes ---------- */
-- D1. fecha_cierre de soporte: hora sin fecha
SELECT TOP 5 [ticket_id], [fecha_apertura], [fecha_cierre], [horas_resolucion] FROM [GCA].[StageTicketSoporte];
-- D2. Dos formatos de fecha
SELECT 'Venta (dd/mm/yyyy)' AS Ejemplo, MIN([fecha_venta]) AS Valor FROM [GCA].[StageVenta]
UNION ALL SELECT 'Oportunidad (yyyy-mm-dd)', MIN([fecha_creacion]) FROM [GCA].[StageOportunidad];
-- D3. ciclo_venta_dias distinto de cierre - creación
SELECT COUNT(*) AS CicloNoCuadra FROM [GCA].[StageOportunidad]
 WHERE TRY_CONVERT(INT, [ciclo_venta_dias]) <> DATEDIFF(DAY, TRY_CONVERT(DATE, [fecha_creacion], 23), TRY_CONVERT(DATE, [fecha_cierre], 23));
-- D4. Llamadas de clientes que no existen y llamadas "venta" sin contacto
SELECT COUNT(*) AS LlamadasClienteInexistente FROM [GCA].[StageLlamada] l
 WHERE NOT EXISTS (SELECT 1 FROM [GCA].[StageCliente] c WHERE c.[cliente_id] = l.[cliente_id]);
SELECT [disposicion], COUNT(*) AS EsVentaConEstaDisposicion FROM [GCA].[StageLlamada]
 WHERE [es_venta] = N'1' AND [disposicion] IN (N'No contactado', N'Rechazo') GROUP BY [disposicion];

/* ---------- E. Fechas poco confiables en maestros ---------- */
SELECT SUM(CASE WHEN TRY_CONVERT(DATE, [fecha_alta], 103) > '20241231' THEN 1 ELSE 0 END) AS ClientesAltaFutura
  FROM [GCA].[StageCliente];
SELECT SUM(CASE WHEN TRY_CONVERT(DATE, [fecha_ingreso], 103) > '20241231' THEN 1 ELSE 0 END) AS VendedoresIngresoFuturo
  FROM [GCA].[StageVendedor];
