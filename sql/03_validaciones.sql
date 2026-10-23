/* =====================================================================
   GCA - Validaciones después del ETL (MasterExecuteStage y MasterExecuteDWH)
   Cuadre: filas del archivo = STAGE  y  STAGE = DWH + tablas de error
   ===================================================================== */
SET NOCOUNT ON;

PRINT '1) Archivo -> STAGE (esperado = filas del CSV sin cabecera)';
SELECT 'Calendario' AS Tabla, COUNT(*) AS Stage, 767 AS Esperado FROM [STAGE_GCA].[GCA].[StageCalendario]
UNION ALL SELECT 'Cliente',     COUNT(*), 12028  FROM [STAGE_GCA].[GCA].[StageCliente]
UNION ALL SELECT 'Producto',    COUNT(*), 8710   FROM [STAGE_GCA].[GCA].[StageProducto]
UNION ALL SELECT 'Vendedor',    COUNT(*), 277    FROM [STAGE_GCA].[GCA].[StageVendedor]
UNION ALL SELECT 'Venta',       COUNT(*), 180609 FROM [STAGE_GCA].[GCA].[StageVenta]
UNION ALL SELECT 'Oportunidad', COUNT(*), 25000  FROM [STAGE_GCA].[GCA].[StageOportunidad]
UNION ALL SELECT 'Llamada',     COUNT(*), 200150 FROM [STAGE_GCA].[GCA].[StageLlamada]
UNION ALL SELECT 'Carrito',     COUNT(*), 66550  FROM [STAGE_GCA].[GCA].[StageCarrito]
UNION ALL SELECT 'Sesion',      COUNT(*), 3655   FROM [STAGE_GCA].[GCA].[StageSesion]
UNION ALL SELECT 'Encuesta',    COUNT(*), 15000  FROM [STAGE_GCA].[GCA].[StageEncuesta]
UNION ALL SELECT 'Marketing',   COUNT(*), 4386   FROM [STAGE_GCA].[GCA].[StageMarketing]
UNION ALL SELECT 'Soporte',     COUNT(*), 25636  FROM [STAGE_GCA].[GCA].[StageTicketSoporte];

PRINT '2) Maestros: STAGE = DWH (sin comodín -1) + filas descartadas en ErrorMaestro';
SELECT m.Tabla, m.Stage, m.DWH, ISNULL(e.Descartadas, 0) AS Descartadas,
       m.Stage - m.DWH - ISNULL(e.Descartadas, 0) AS Diferencia      -- debe ser 0
FROM (SELECT 'Calendario' AS Tabla, (SELECT COUNT(*) FROM [STAGE_GCA].[GCA].[StageCalendario]) AS Stage,
             (SELECT COUNT(*) FROM [DWH_GCA].[GENERICO].[DimFecha] WHERE [FechaKey] > 0) AS DWH
      UNION ALL SELECT 'Cliente', (SELECT COUNT(*) FROM [STAGE_GCA].[GCA].[StageCliente]),
             (SELECT COUNT(*) FROM [DWH_GCA].[Comercial].[DimCliente] WHERE [ClienteKey] > 0)
      UNION ALL SELECT 'Producto', (SELECT COUNT(*) FROM [STAGE_GCA].[GCA].[StageProducto]),
             (SELECT COUNT(*) FROM [DWH_GCA].[Comercial].[DimProducto] WHERE [ProductoKey] > 0)
      UNION ALL SELECT 'Vendedor', (SELECT COUNT(*) FROM [STAGE_GCA].[GCA].[StageVendedor]),
             (SELECT COUNT(*) FROM [DWH_GCA].[Comercial].[DimVendedor] WHERE [VendedorKey] > 0)) m
LEFT JOIN (SELECT [Tabla], COUNT(*) AS Descartadas FROM [DWH_GCA].[Comercial].[ErrorMaestro] GROUP BY [Tabla]) e ON e.[Tabla] = m.[Tabla];

PRINT '3) Hechos: STAGE = Fact + Error';
SELECT h.Hecho, h.Stage, h.Fact, h.Error, h.Stage - h.Fact - h.Error AS Diferencia   -- debe ser 0
FROM (
    SELECT 'Venta' AS Hecho, (SELECT COUNT(*) FROM [STAGE_GCA].[GCA].[StageVenta]) AS Stage,
           (SELECT COUNT(*) FROM [DWH_GCA].[Comercial].[FactVenta]) AS Fact, (SELECT COUNT(*) FROM [DWH_GCA].[Comercial].[ErrorFactVenta]) AS Error
    UNION ALL SELECT 'Oportunidad', (SELECT COUNT(*) FROM [STAGE_GCA].[GCA].[StageOportunidad]),
           (SELECT COUNT(*) FROM [DWH_GCA].[Comercial].[FactOportunidad]), (SELECT COUNT(*) FROM [DWH_GCA].[Comercial].[ErrorFactOportunidad])
    UNION ALL SELECT 'Llamada', (SELECT COUNT(*) FROM [STAGE_GCA].[GCA].[StageLlamada]),
           (SELECT COUNT(*) FROM [DWH_GCA].[Comercial].[FactLlamada]), (SELECT COUNT(*) FROM [DWH_GCA].[Comercial].[ErrorFactLlamada])
    UNION ALL SELECT 'Carrito', (SELECT COUNT(*) FROM [STAGE_GCA].[GCA].[StageCarrito]),
           (SELECT COUNT(*) FROM [DWH_GCA].[Comercial].[FactCarrito]), (SELECT COUNT(*) FROM [DWH_GCA].[Comercial].[ErrorFactCarrito])
    UNION ALL SELECT 'Sesion', (SELECT COUNT(*) FROM [STAGE_GCA].[GCA].[StageSesion]),
           (SELECT COUNT(*) FROM [DWH_GCA].[Comercial].[FactSesion]), (SELECT COUNT(*) FROM [DWH_GCA].[Comercial].[ErrorFactSesion])
    UNION ALL SELECT 'Encuesta', (SELECT COUNT(*) FROM [STAGE_GCA].[GCA].[StageEncuesta]),
           (SELECT COUNT(*) FROM [DWH_GCA].[Comercial].[FactEncuesta]), (SELECT COUNT(*) FROM [DWH_GCA].[Comercial].[ErrorFactEncuesta])
    UNION ALL SELECT 'Marketing', (SELECT COUNT(*) FROM [STAGE_GCA].[GCA].[StageMarketing]),
           (SELECT COUNT(*) FROM [DWH_GCA].[Comercial].[FactMarketing]), (SELECT COUNT(*) FROM [DWH_GCA].[Comercial].[ErrorFactMarketing])
    UNION ALL SELECT 'Soporte', (SELECT COUNT(*) FROM [STAGE_GCA].[GCA].[StageTicketSoporte]),
           (SELECT COUNT(*) FROM [DWH_GCA].[Comercial].[FactTicketSoporte]), (SELECT COUNT(*) FROM [DWH_GCA].[Comercial].[ErrorFactTicketSoporte])) h;

PRINT '4) Montos de venta: STAGE (solo filas cargadas) vs DWH';
SELECT (SELECT SUM(TRY_CONVERT(DECIMAL(18,2), [cantidad]) * TRY_CONVERT(DECIMAL(18,2), [precio_unitario_neto]))
          FROM [STAGE_GCA].[GCA].[StageVenta] s
         WHERE NOT EXISTS (SELECT 1 FROM [DWH_GCA].[Comercial].[ErrorFactVenta] e WHERE e.[venta_id] = s.[venta_id])) AS VentaStageRecalculada,
       (SELECT SUM([VentaNeta]) FROM [DWH_GCA].[Comercial].[FactVenta]) AS VentaDWH;

PRINT '5) Auditoría: ejecuciones fallidas (debe ser 0)';
SELECT COUNT(*) AS EjecucionesFallidas FROM [DWH_GCA].[dbo].[DIM_AUDIT] WHERE [SuccessfulProcessingInd] <> 'Y';
SELECT TOP 30 [AuditKey], [TableName], [ExecStartDT], DATEDIFF(SECOND, [ExecStartDT], [ExecStopDT]) AS Segundos,
       [TableInitialRowCnt], [TableFinalRowCnt], [SuccessfulProcessingInd]
  FROM [DWH_GCA].[dbo].[DIM_AUDIT] ORDER BY [AuditKey] DESC;
