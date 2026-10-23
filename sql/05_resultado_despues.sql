/* =====================================================================
   GCA - DESPUÉS: cómo quedó cada caso sucio en el DWH (mismo orden que 04_hallazgos_antes.sql)
   ===================================================================== */
USE [DWH_GCA];
SET NOCOUNT ON;

/* ---------- A. Venta con importe vacío -> recalculada ---------- */
SELECT [VentaID], [Cantidad], [PrecioUnitarioNeto], [VentaNeta], [CostoTotal], [MargenBruto], [MargenPct],
       [VentaNetaRecalculada], [MargenRecalculado]
  FROM [Comercial].[FactVenta] WHERE [VentaID] = 'VTA-00000216';

SELECT SUM(CAST([VentaNetaRecalculada] AS INT)) AS VentasRecalculadas,
       SUM(CAST([MargenRecalculado] AS INT))    AS MargenesRecalculados,
       SUM(CASE WHEN [VentaNeta] = 0 THEN 1 ELSE 0 END) AS VentasEnCero          -- debe ser 0
  FROM [Comercial].[FactVenta];

/* ---------- B. Duplicados -> se quedó uno solo ---------- */
-- B1. Maestros: ya no hay ID repetido (la primera fila debe decir 1)
SELECT TOP 3 COUNT(1) AS Veces, [ClienteID] FROM [Comercial].[DimCliente] GROUP BY [ClienteID] ORDER BY 1 DESC;
-- Qué se descartó y por qué
SELECT [Tabla], [Motivo], COUNT(*) AS Filas FROM [Comercial].[ErrorMaestro] GROUP BY [Tabla], [Motivo] ORDER BY [Tabla];

-- B2. El cliente con datos distintos quedó con la primera aparición (canal "Fuerza directa")
SELECT [ClienteID], [Nombre], [CanalOrigen] FROM [Comercial].[DimCliente] WHERE [ClienteID] IN ('CLI-000032', 'CLI-000033', 'CLI-000034');
SELECT [LlaveNegocio], [FilaOrigen], [FilaConservada], [Motivo] FROM [Comercial].[ErrorMaestro]
 WHERE [LlaveNegocio] IN ('CLI-000032', 'CLI-000033', 'CLI-000034');

-- B3. Ventas copiadas -> en ErrorFactVenta con el original identificado; en FactVenta solo queda el original
SELECT TOP 5 [venta_id], [fecha_venta], [Motivo] FROM [Comercial].[ErrorFactVenta] ORDER BY [venta_id];
SELECT [VentaID], f.[Fecha] FROM [Comercial].[FactVenta] v JOIN [GENERICO].[DimFecha] f ON f.[FechaKey] = v.[FechaKey]
 WHERE [VentaID] IN ('VTA-00082604', 'VTA-00180001');                                -- solo aparece el original
-- Método del profesor sobre el DWH: ya no hay contenido repetido con otro ID (la primera fila debe decir 1)
SELECT TOP 3 COUNT(1) AS Veces, [ClienteKey], [ProductoKey], [Cantidad], [VentaNeta]
  FROM [Comercial].[FactVenta]
 GROUP BY [OportunidadID], [ClienteKey], [VendedorKey], [ProductoKey], [CanalKey], [RegionKey], [Cantidad], [PrecioLista], [Descuento], [VentaNeta], [CostoTotal]
 ORDER BY 1 DESC;

/* ---------- C. Fechas -> todas dentro del calendario ---------- */
SELECT 'FactVenta' AS Hecho, MIN(f.[Fecha]) AS Desde, MAX(f.[Fecha]) AS Hasta
  FROM [Comercial].[FactVenta] v JOIN [GENERICO].[DimFecha] f ON f.[FechaKey] = v.[FechaKey]
UNION ALL SELECT 'FactCarrito', MIN(f.[Fecha]), MAX(f.[Fecha])
  FROM [Comercial].[FactCarrito] c JOIN [GENERICO].[DimFecha] f ON f.[FechaKey] = c.[FechaKey]
UNION ALL SELECT 'FactTicketSoporte', MIN(f.[Fecha]), MAX(f.[Fecha])
  FROM [Comercial].[FactTicketSoporte] t JOIN [GENERICO].[DimFecha] f ON f.[FechaKey] = t.[FechaAperturaKey];
-- Motivos agrupados por tipo (el texto completo trae el ID del original, ej. "Duplicado de VTA-00082604 ...")
WITH E AS (
    SELECT 'ErrorFactVenta' AS Tabla, [Motivo] FROM [Comercial].[ErrorFactVenta]
    UNION ALL SELECT 'ErrorFactCarrito', [Motivo] FROM [Comercial].[ErrorFactCarrito]
    UNION ALL SELECT 'ErrorFactTicketSoporte', [Motivo] FROM [Comercial].[ErrorFactTicketSoporte]
    UNION ALL SELECT 'ErrorFactLlamada', [Motivo] FROM [Comercial].[ErrorFactLlamada])
SELECT Tabla,
       CASE WHEN [Motivo] LIKE N'Duplicado de %' THEN N'Duplicado de otro registro con fecha alterada'
            WHEN [Motivo] LIKE N'Cliente inexistente%' THEN N'Cliente inexistente en el maestro'
            ELSE [Motivo] END AS TipoMotivo,
       COUNT(*) AS Filas
  FROM E
 GROUP BY Tabla, CASE WHEN [Motivo] LIKE N'Duplicado de %' THEN N'Duplicado de otro registro con fecha alterada'
                      WHEN [Motivo] LIKE N'Cliente inexistente%' THEN N'Cliente inexistente en el maestro'
                      ELSE [Motivo] END;

/* ---------- D. Columnas corregidas ---------- */
-- D1. fecha_cierre reconstruida
SELECT TOP 5 t.[TicketID], f.[Fecha] AS Apertura, t.[HorasResolucion], t.[FechaCierre], t.[SlaCumplido], t.[SlaRecalculado]
  FROM [Comercial].[FactTicketSoporte] t JOIN [GENERICO].[DimFecha] f ON f.[FechaKey] = t.[FechaAperturaKey]
 ORDER BY t.[TicketID];
-- D3. ciclo de venta corregido
SELECT SUM(CAST([CicloCorregido] AS INT)) AS CiclosCorregidos,
       SUM(CASE WHEN [CicloVentaDias] <> DATEDIFF(DAY, fc.[Fecha], fz.[Fecha]) THEN 1 ELSE 0 END) AS CicloNoCuadra   -- debe ser 0
  FROM [Comercial].[FactOportunidad] o
  JOIN [GENERICO].[DimFecha] fc ON fc.[FechaKey] = o.[FechaCreacionKey]
  JOIN [GENERICO].[DimFecha] fz ON fz.[FechaKey] = o.[FechaCierreKey];
-- D4. llamadas: inexistentes en error, inconsistentes marcadas
SELECT COUNT(*) AS LlamadasEnError FROM [Comercial].[ErrorFactLlamada];
SELECT SUM(CAST([EsVentaInconsistente] AS INT)) AS LlamadasMarcadasInconsistentes FROM [Comercial].[FactLlamada];

/* ---------- E. Fechas poco confiables: marcadas (no borradas) ---------- */
SELECT SUM(CAST([FechaAltaFutura] AS INT)) AS ClientesAltaFutura, SUM(CAST([AltaPosteriorACompra] AS INT)) AS AltaPosteriorACompra,
       SUM(CAST([PosibleDuplicado] AS INT)) AS PosiblesDuplicados
  FROM [Comercial].[vw_DimCliente];
SELECT SUM(CAST([IngresoPosteriorAVenta] AS INT)) AS VendedoresIngresoPosteriorAVenta FROM [Comercial].[vw_DimVendedor];
