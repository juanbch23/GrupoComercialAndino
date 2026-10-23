/* =====================================================================
   GCA - Vistas que lee el cubo tabular (Tabular_GCA)
   Ejecutar después del ETL (MasterExecuteDWH). sqlcmd -I -f 65001
   ===================================================================== */
USE [DWH_GCA]
GO
SET QUOTED_IDENTIFIER ON;
GO

/* Cliente + comportamiento real de compra (la fecha_alta del archivo no es confiable:
   3,580 altas en el futuro y 7,356 clientes dados de alta después de su primera compra). */
CREATE OR ALTER VIEW [Comercial].[vw_DimCliente]
AS
SELECT c.[ClienteKey], c.[ClienteID], c.[Nombre], c.[Tipo], c.[Segmento], c.[Pais], c.[FechaAlta],
       c.[TieneContrato], c.[TieneEjecutivo], c.[CanalOrigen], c.[PosibleDuplicado], c.[FechaAltaFutura],
       v.[FechaPrimeraCompra], v.[FechaUltimaCompra],
       CAST(CASE WHEN c.[FechaAlta] > v.[FechaPrimeraCompra] THEN 1 ELSE 0 END AS BIT) AS [AltaPosteriorACompra],
       CAST(ISNULL(v.[Compra2023], 0) AS BIT) AS [Compra2023],
       CAST(ISNULL(v.[Compra2024], 0) AS BIT) AS [Compra2024],
       -- churn (regla del caso: cliente que no compra en 12 meses): activo en 2023 y sin compras en 2024
       CAST(CASE WHEN v.[Compra2023] = 1 AND ISNULL(v.[Compra2024], 0) = 0 THEN 1 ELSE 0 END AS BIT) AS [Churn2024],
       CASE WHEN c.[TieneContrato] = 1 THEN N'Con contrato' ELSE N'Sin contrato' END AS [Contrato],
       CASE WHEN c.[TieneEjecutivo] = 1 THEN N'Con ejecutivo' ELSE N'Sin ejecutivo' END AS [Ejecutivo]
  FROM [Comercial].[DimCliente] c
  LEFT JOIN (SELECT f.[ClienteKey], MIN(d.[Fecha]) AS [FechaPrimeraCompra], MAX(d.[Fecha]) AS [FechaUltimaCompra],
                    MAX(CASE WHEN d.[Anio] = 2023 THEN 1 ELSE 0 END) AS [Compra2023],
                    MAX(CASE WHEN d.[Anio] = 2024 THEN 1 ELSE 0 END) AS [Compra2024]
               FROM [Comercial].[FactVenta] f JOIN [GENERICO].[DimFecha] d ON d.[FechaKey] = f.[FechaKey]
              GROUP BY f.[ClienteKey]) v ON v.[ClienteKey] = c.[ClienteKey]
 WHERE c.[ClienteKey] > 0;
GO

/* Vendedor + primera venta (161 vendedores venden antes de su fecha de ingreso). */
CREATE OR ALTER VIEW [Comercial].[vw_DimVendedor]
AS
SELECT d.[VendedorKey], d.[VendedorID], d.[Nombre], d.[Canal], d.[Region], d.[GerenteID], d.[Antiguedad],
       d.[CuotaAnual], d.[FechaIngreso], v.[FechaPrimeraVenta],
       CAST(CASE WHEN d.[FechaIngreso] > v.[FechaPrimeraVenta] THEN 1 ELSE 0 END AS BIT) AS [IngresoPosteriorAVenta]
  FROM [Comercial].[DimVendedor] d
  LEFT JOIN (SELECT f.[VendedorKey], MIN(x.[Fecha]) AS [FechaPrimeraVenta]
               FROM [Comercial].[FactVenta] f JOIN [GENERICO].[DimFecha] x ON x.[FechaKey] = f.[FechaKey]
              GROUP BY f.[VendedorKey]) v ON v.[VendedorKey] = d.[VendedorKey]
 WHERE d.[VendedorKey] > 0;
GO

/* Cuota: el archivo trae cuota ANUAL por vendedor; se reparte en 12 meses iguales
   (una fila por vendedor y mes del calendario, en el primer día del mes). */
CREATE OR ALTER VIEW [Comercial].[vw_FactCuota]
AS
SELECT v.[VendedorKey], m.[FechaKey], CAST(v.[CuotaAnual] / 12.0 AS DECIMAL(18,2)) AS [CuotaMensual]
  FROM [Comercial].[DimVendedor] v
 CROSS JOIN (SELECT MIN([FechaKey]) AS [FechaKey] FROM [GENERICO].[DimFecha] WHERE [FechaKey] > 0 GROUP BY [AnioMes]) m
 WHERE v.[VendedorKey] > 0;
GO

/* Permiso para que Analysis Services lea el DWH al procesar el cubo */
USE [master];
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'NT Service\MSOLAP$TABULAR')
    CREATE LOGIN [NT Service\MSOLAP$TABULAR] FROM WINDOWS;
GO
USE [DWH_GCA];
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'NT Service\MSOLAP$TABULAR')
    CREATE USER [NT Service\MSOLAP$TABULAR] FOR LOGIN [NT Service\MSOLAP$TABULAR];
ALTER ROLE [db_datareader] ADD MEMBER [NT Service\MSOLAP$TABULAR];
GO
