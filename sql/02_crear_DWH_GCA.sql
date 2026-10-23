/* =====================================================================
   Grupo Comercial Andino (GCA) - Data Warehouse (modelo estrella)
   Instancia : LAPTOP-IO596P6A\DEV
   Ejecutar DESPUÉS de 01_crear_STAGE_GCA.sql.

   Dónde se limpia cada cosa:
     - Maestros (fecha, cliente, producto, vendedor, canal, región):
         procedimientos [Comercial].[sp_Dim...] de este script (MERGE).
         Duplicados -> ROW_NUMBER() OVER (PARTITION BY <id> ORDER BY FilaOrigen):
         se conserva rn = 1 (primera aparición) y el resto queda registrado en
         [Comercial].[ErrorMaestro] con su motivo.
     - Hechos (venta, oportunidad, llamada, carrito, sesión, encuesta, marketing,
       soporte): paquetes SSIS del proyecto DWH_GCA. La consulta de origen calcula
       [MotivoDescarte] (duplicado, fecha inválida...) y recalcula columnas; luego
       Búsquedas + División condicional "bad" -> tablas Error... con el motivo.
   ===================================================================== */
USE [master]
GO
IF DB_ID(N'DWH_GCA') IS NULL
    CREATE DATABASE [DWH_GCA];
GO
ALTER DATABASE [DWH_GCA] SET RECOVERY SIMPLE;
GO
USE [DWH_GCA]
GO
SET QUOTED_IDENTIFIER ON;
GO
IF SCHEMA_ID(N'GENERICO')  IS NULL EXEC (N'CREATE SCHEMA [GENERICO]');
IF SCHEMA_ID(N'Comercial') IS NULL EXEC (N'CREATE SCHEMA [Comercial]');
GO

/* ------------------------------------------------------------------ limpieza previa */
DROP TABLE IF EXISTS [Comercial].[FactVenta], [Comercial].[FactOportunidad], [Comercial].[FactLlamada],
                     [Comercial].[FactCarrito], [Comercial].[FactSesion], [Comercial].[FactEncuesta],
                     [Comercial].[FactMarketing], [Comercial].[FactTicketSoporte];
DROP TABLE IF EXISTS [Comercial].[ErrorFactVenta], [Comercial].[ErrorFactOportunidad], [Comercial].[ErrorFactLlamada],
                     [Comercial].[ErrorFactCarrito], [Comercial].[ErrorFactSesion], [Comercial].[ErrorFactEncuesta],
                     [Comercial].[ErrorFactMarketing], [Comercial].[ErrorFactTicketSoporte], [Comercial].[ErrorMaestro];
DROP TABLE IF EXISTS [GENERICO].[DimFecha], [Comercial].[DimCliente], [Comercial].[DimProducto],
                     [Comercial].[DimVendedor], [Comercial].[DimCanal], [Comercial].[DimRegion];
DROP TABLE IF EXISTS [dbo].[DIM_AUDIT];
GO

/* ------------------------------------------------------------------ auditoría (lab) */
CREATE TABLE [dbo].[DIM_AUDIT](
    [AuditKey]                INT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_DIM_AUDIT] PRIMARY KEY,
    [TableName]               NVARCHAR(100)    NOT NULL DEFAULT ('Unknown'),
    [PkgName]                 NVARCHAR(100)    NOT NULL DEFAULT ('Unknown'),
    [PkgGUID]                 UNIQUEIDENTIFIER NULL,
    [ExecStartDT]             DATETIME         NOT NULL DEFAULT (GETDATE()),
    [ExecStopDT]              DATETIME         NULL,
    [ExecutionInstanceGUID]   UNIQUEIDENTIFIER NULL,
    [ExtractRowCnt]           BIGINT           NULL,
    [TableInitialRowCnt]      BIGINT           NULL,
    [TableFinalRowCnt]        BIGINT           NULL,
    [SuccessfulProcessingInd] NCHAR(1)         NOT NULL DEFAULT ('N')
);
GO

/* ================================================================== DIMENSIONES */
CREATE TABLE [GENERICO].[DimFecha](
    [FechaKey]    INT          NOT NULL CONSTRAINT [PK_DimFecha] PRIMARY KEY,   -- yyyymmdd
    [Fecha]       DATE         NOT NULL,
    [Anio]        SMALLINT     NOT NULL,
    [Mes]         TINYINT      NOT NULL,
    [NombreMes]   VARCHAR(15)  NOT NULL,
    [Trimestre]   TINYINT      NOT NULL,
    [DiaSemana]   TINYINT      NOT NULL,     -- 1 = lunes ... 7 = domingo
    [NombreDia]   VARCHAR(15)  NOT NULL,
    [EsFinSemana] BIT          NOT NULL,
    [Periodo]     CHAR(7)      NOT NULL,     -- yyyy-mm
    [Fase]        VARCHAR(10)  NOT NULL,     -- antes / despues (del caso)
    [AnioMes]     AS (CONVERT(INT, [Anio]) * 100 + [Mes]) PERSISTED
);

CREATE TABLE [Comercial].[DimCanal](
    [CanalKey] INT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_DimCanal] PRIMARY KEY,
    [Canal]    NVARCHAR(30) NOT NULL CONSTRAINT [UQ_DimCanal] UNIQUE
);

CREATE TABLE [Comercial].[DimRegion](
    [RegionKey] INT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_DimRegion] PRIMARY KEY,
    [Region]    NVARCHAR(30) NOT NULL CONSTRAINT [UQ_DimRegion] UNIQUE,
    [Pais]      NVARCHAR(30) NOT NULL
);

CREATE TABLE [Comercial].[DimCliente](
    [ClienteKey]       INT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_DimCliente] PRIMARY KEY,
    [ClienteID]        NVARCHAR(20)  NOT NULL CONSTRAINT [UQ_DimCliente] UNIQUE,
    [Nombre]           NVARCHAR(100) NOT NULL,
    [Tipo]             NVARCHAR(10)  NOT NULL,
    [Segmento]         NVARCHAR(30)  NOT NULL,
    [Pais]             NVARCHAR(30)  NOT NULL,
    [FechaAlta]        DATE          NULL,
    [FechaAltaFutura]  BIT           NOT NULL,   -- alta posterior al calendario del caso (2024-12-31)
    [TieneContrato]    BIT           NOT NULL,
    [TieneEjecutivo]   BIT           NOT NULL,
    [CanalOrigen]      NVARCHAR(40)  NOT NULL,
    [PosibleDuplicado] BIT           NOT NULL    -- mismo nombre y país que otro cliente_id
);

CREATE TABLE [Comercial].[DimProducto](
    [ProductoKey]    INT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_DimProducto] PRIMARY KEY,
    [ProductoID]     NVARCHAR(20)  NOT NULL CONSTRAINT [UQ_DimProducto] UNIQUE,
    [Categoria]      NVARCHAR(40)  NOT NULL,
    [CostoUnitario]  DECIMAL(18,2) NOT NULL,
    [PrecioLista]    DECIMAL(18,2) NOT NULL,
    [MargenObjetivo] DECIMAL(9,4)  NOT NULL
);

CREATE TABLE [Comercial].[DimVendedor](
    [VendedorKey]  INT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_DimVendedor] PRIMARY KEY,
    [VendedorID]   NVARCHAR(20)  NOT NULL CONSTRAINT [UQ_DimVendedor] UNIQUE,
    [Nombre]       NVARCHAR(100) NOT NULL,
    [Canal]        NVARCHAR(30)  NOT NULL,
    [Region]       NVARCHAR(30)  NOT NULL,
    [GerenteID]    NVARCHAR(20)  NOT NULL,
    [Antiguedad]   NVARCHAR(20)  NOT NULL,
    [CuotaAnual]   DECIMAL(18,2) NOT NULL,
    [FechaIngreso] DATE          NULL
);

-- registro de filas de maestros descartadas por duplicado (qué se quitó y por qué)
CREATE TABLE [Comercial].[ErrorMaestro](
    [Tabla]         NVARCHAR(30)  NOT NULL,
    [LlaveNegocio]  NVARCHAR(30)  NOT NULL,
    [FilaOrigen]    INT           NOT NULL,
    [FilaConservada] INT          NOT NULL,
    [Motivo]        NVARCHAR(200) NOT NULL,
    [FechaRegistro] DATETIME      NOT NULL DEFAULT (GETDATE())
);
GO

/* ------------------------------------------------------------------ comodines -1 (lab) */
INSERT INTO [GENERICO].[DimFecha] ([FechaKey],[Fecha],[Anio],[Mes],[NombreMes],[Trimestre],[DiaSemana],[NombreDia],[EsFinSemana],[Periodo],[Fase])
VALUES (-1, '19000101', 1900, 1, 'Sin Datos', 1, 1, 'Sin Datos', 0, '1900-01', 'Sin Datos');
SET IDENTITY_INSERT [Comercial].[DimCanal] ON;
INSERT INTO [Comercial].[DimCanal] ([CanalKey],[Canal]) VALUES (-1, N'Sin Datos');
SET IDENTITY_INSERT [Comercial].[DimCanal] OFF;
SET IDENTITY_INSERT [Comercial].[DimRegion] ON;
INSERT INTO [Comercial].[DimRegion] ([RegionKey],[Region],[Pais]) VALUES (-1, N'Sin Datos', N'Sin Datos');
SET IDENTITY_INSERT [Comercial].[DimRegion] OFF;
SET IDENTITY_INSERT [Comercial].[DimCliente] ON;
INSERT INTO [Comercial].[DimCliente] ([ClienteKey],[ClienteID],[Nombre],[Tipo],[Segmento],[Pais],[FechaAlta],[FechaAltaFutura],[TieneContrato],[TieneEjecutivo],[CanalOrigen],[PosibleDuplicado])
VALUES (-1, N'-1', N'Sin Datos', N'Sin Datos', N'Sin Datos', N'Sin Datos', NULL, 0, 0, 0, N'Sin Datos', 0);
SET IDENTITY_INSERT [Comercial].[DimCliente] OFF;
SET IDENTITY_INSERT [Comercial].[DimProducto] ON;
INSERT INTO [Comercial].[DimProducto] ([ProductoKey],[ProductoID],[Categoria],[CostoUnitario],[PrecioLista],[MargenObjetivo])
VALUES (-1, N'-1', N'Sin Datos', 0, 0, 0);
SET IDENTITY_INSERT [Comercial].[DimProducto] OFF;
SET IDENTITY_INSERT [Comercial].[DimVendedor] ON;
INSERT INTO [Comercial].[DimVendedor] ([VendedorKey],[VendedorID],[Nombre],[Canal],[Region],[GerenteID],[Antiguedad],[CuotaAnual],[FechaIngreso])
VALUES (-1, N'-1', N'Sin Datos', N'Sin Datos', N'Sin Datos', N'Sin Datos', N'Sin Datos', 0, NULL);
SET IDENTITY_INSERT [Comercial].[DimVendedor] OFF;
GO

/* ================================================================== HECHOS */
CREATE TABLE [Comercial].[FactVenta](
    [VentaID]              NVARCHAR(20)  NOT NULL,
    [OportunidadID]        NVARCHAR(20)  NULL,
    [FechaKey]             INT NOT NULL CONSTRAINT [FK_FactVenta_Fecha]    REFERENCES [GENERICO].[DimFecha]([FechaKey]),
    [ClienteKey]           INT NOT NULL CONSTRAINT [FK_FactVenta_Cliente]  REFERENCES [Comercial].[DimCliente]([ClienteKey]),
    [VendedorKey]          INT NOT NULL CONSTRAINT [FK_FactVenta_Vendedor] REFERENCES [Comercial].[DimVendedor]([VendedorKey]),
    [ProductoKey]          INT NOT NULL CONSTRAINT [FK_FactVenta_Producto] REFERENCES [Comercial].[DimProducto]([ProductoKey]),
    [CanalKey]             INT NOT NULL CONSTRAINT [FK_FactVenta_Canal]    REFERENCES [Comercial].[DimCanal]([CanalKey]),
    [RegionKey]            INT NOT NULL CONSTRAINT [FK_FactVenta_Region]   REFERENCES [Comercial].[DimRegion]([RegionKey]),
    [Cantidad]             INT           NOT NULL,
    [PrecioLista]          DECIMAL(18,2) NOT NULL,
    [Descuento]            DECIMAL(9,4)  NOT NULL,
    [PrecioUnitarioNeto]   DECIMAL(18,2) NOT NULL,
    [VentaNeta]            DECIMAL(18,2) NOT NULL,   -- recalculada: Cantidad x PrecioUnitarioNeto
    [CostoTotal]           DECIMAL(18,2) NOT NULL,
    [MargenBruto]          DECIMAL(18,2) NOT NULL,   -- importe: VentaNeta - CostoTotal
    [MargenPct]            DECIMAL(9,4)  NOT NULL,   -- (VentaNeta - Costo) / VentaNeta
    [VentaNetaRecalculada] BIT           NOT NULL,   -- 1 = en el archivo venía vacía o distinta
    [MargenRecalculado]    BIT           NOT NULL,
    CONSTRAINT [PK_FactVenta] PRIMARY KEY ([VentaID])
);

CREATE TABLE [Comercial].[FactOportunidad](
    [OportunidadID]       NVARCHAR(20)  NOT NULL CONSTRAINT [PK_FactOportunidad] PRIMARY KEY,
    [FechaCreacionKey]    INT NOT NULL CONSTRAINT [FK_FactOpp_FechaCrea]  REFERENCES [GENERICO].[DimFecha]([FechaKey]),
    [FechaCierreKey]      INT NOT NULL CONSTRAINT [FK_FactOpp_FechaCierre] REFERENCES [GENERICO].[DimFecha]([FechaKey]),
    [ClienteKey]          INT NOT NULL CONSTRAINT [FK_FactOpp_Cliente]  REFERENCES [Comercial].[DimCliente]([ClienteKey]),
    [VendedorKey]         INT NOT NULL CONSTRAINT [FK_FactOpp_Vendedor] REFERENCES [Comercial].[DimVendedor]([VendedorKey]),
    [CanalKey]            INT NOT NULL CONSTRAINT [FK_FactOpp_Canal]    REFERENCES [Comercial].[DimCanal]([CanalKey]),
    [RegionKey]           INT NOT NULL CONSTRAINT [FK_FactOpp_Region]   REFERENCES [Comercial].[DimRegion]([RegionKey]),
    [GerenteID]           NVARCHAR(20)  NOT NULL,
    [Etapa]               NVARCHAR(30)  NOT NULL,
    [Resultado]           NVARCHAR(30)  NOT NULL,
    [Facturada]           BIT           NOT NULL,   -- regla: ganada = facturada
    [MotivoPerdida]       NVARCHAR(40)  NOT NULL,   -- 'No aplica' en ganadas
    [Monto]               DECIMAL(18,2) NOT NULL,
    [DescuentoSolicitado] DECIMAL(9,4)  NOT NULL,
    [FueraPolitica]       BIT           NOT NULL,
    [Touchpoints]         TINYINT       NOT NULL,
    [TieneDemoTecnica]    BIT           NOT NULL,
    [CicloVentaDias]      INT           NOT NULL,   -- recalculado: cierre - creación
    [CicloVentaOrigen]    INT           NULL,       -- valor del archivo
    [CicloCorregido]      BIT           NOT NULL,
    [DiasSinActividad]    INT           NOT NULL,
    [Zombie]              BIT           NOT NULL    -- más de 180 días sin actividad
);

CREATE TABLE [Comercial].[FactLlamada](
    [LlamadaID]            NVARCHAR(20) NOT NULL CONSTRAINT [PK_FactLlamada] PRIMARY KEY,
    [FechaKey]             INT NOT NULL CONSTRAINT [FK_FactLlamada_Fecha]    REFERENCES [GENERICO].[DimFecha]([FechaKey]),
    [VendedorKey]          INT NOT NULL CONSTRAINT [FK_FactLlamada_Vendedor] REFERENCES [Comercial].[DimVendedor]([VendedorKey]),
    [ClienteKey]           INT NOT NULL CONSTRAINT [FK_FactLlamada_Cliente]  REFERENCES [Comercial].[DimCliente]([ClienteKey]),
    [DuracionSeg]          INT          NOT NULL,
    [Disposicion]          NVARCHAR(40) NOT NULL,
    [EsVenta]              BIT          NOT NULL,
    [EsVentaInconsistente] BIT          NOT NULL    -- es_venta = 1 con "No contactado" o "Rechazo"
);

CREATE TABLE [Comercial].[FactCarrito](
    [CarritoID]    NVARCHAR(20)  NOT NULL CONSTRAINT [PK_FactCarrito] PRIMARY KEY,
    [FechaKey]     INT NOT NULL CONSTRAINT [FK_FactCarrito_Fecha]   REFERENCES [GENERICO].[DimFecha]([FechaKey]),
    [ClienteKey]   INT NOT NULL CONSTRAINT [FK_FactCarrito_Cliente] REFERENCES [Comercial].[DimCliente]([ClienteKey]),
    [Monto]        DECIMAL(18,2) NOT NULL,
    [PasoAbandono] NVARCHAR(30)  NOT NULL,
    [Recuperado]   BIT           NOT NULL
);

CREATE TABLE [Comercial].[FactSesion](
    [FechaKey]       INT NOT NULL CONSTRAINT [FK_FactSesion_Fecha] REFERENCES [GENERICO].[DimFecha]([FechaKey]),
    [CanalDigital]   NVARCHAR(30)  NOT NULL,
    [Dispositivo]    NVARCHAR(20)  NOT NULL,
    [Sesiones]       INT           NOT NULL,
    [AddToCart]      INT           NOT NULL,
    [CheckoutIniciado] INT         NOT NULL,
    [Ordenes]        INT           NOT NULL,
    [TicketPromedio] DECIMAL(18,2) NOT NULL,
    [VentaTotal]     DECIMAL(18,2) NOT NULL,
    CONSTRAINT [PK_FactSesion] PRIMARY KEY ([FechaKey], [CanalDigital], [Dispositivo])
);

CREATE TABLE [Comercial].[FactEncuesta](
    [EncuestaID] NVARCHAR(20) NOT NULL CONSTRAINT [PK_FactEncuesta] PRIMARY KEY,
    [FechaKey]   INT NOT NULL CONSTRAINT [FK_FactEncuesta_Fecha]   REFERENCES [GENERICO].[DimFecha]([FechaKey]),
    [ClienteKey] INT NOT NULL CONSTRAINT [FK_FactEncuesta_Cliente] REFERENCES [Comercial].[DimCliente]([ClienteKey]),
    [Momento]    NVARCHAR(30) NOT NULL,
    [NPS]        INT          NOT NULL,      -- puntaje NPS de la medición (-100..100)
    [CSAT]       DECIMAL(5,2) NOT NULL       -- 1..5
);

CREATE TABLE [Comercial].[FactMarketing](
    [FechaKey]       INT NOT NULL CONSTRAINT [FK_FactMarketing_Fecha] REFERENCES [GENERICO].[DimFecha]([FechaKey]),
    [CanalDigital]   NVARCHAR(30)  NOT NULL,
    [Campana]        NVARCHAR(20)  NOT NULL,
    [Inversion]      DECIMAL(18,2) NOT NULL,
    [Leads]          INT           NOT NULL,
    [NuevosClientes] INT           NOT NULL,
    CONSTRAINT [PK_FactMarketing] PRIMARY KEY ([FechaKey], [CanalDigital], [Campana])
);

CREATE TABLE [Comercial].[FactTicketSoporte](
    [TicketID]          NVARCHAR(20)  NOT NULL CONSTRAINT [PK_FactTicketSoporte] PRIMARY KEY,
    [ClienteKey]        INT NOT NULL CONSTRAINT [FK_FactTicket_Cliente] REFERENCES [Comercial].[DimCliente]([ClienteKey]),
    [FechaAperturaKey]  INT NOT NULL CONSTRAINT [FK_FactTicket_Fecha]   REFERENCES [GENERICO].[DimFecha]([FechaKey]),
    [FechaCierre]       DATETIME2(0)  NOT NULL,   -- reconstruida: apertura + horas_resolucion
    [HorasResolucion]   DECIMAL(9,2)  NOT NULL,
    [Categoria]         NVARCHAR(30)  NOT NULL,
    [SlaCumplido]       BIT           NOT NULL,   -- valor del archivo
    [SlaRecalculado]    BIT           NOT NULL    -- horas <= 24
);
GO

/* ------------------------------------------------------------------ tablas de error (lab: ErrorFactSales)
   Guardan la fila del STAGE tal como venía + las llaves encontradas + el MOTIVO del descarte. */
CREATE TABLE [Comercial].[ErrorFactVenta](
    [FilaOrigen] INT NULL, [venta_id] NVARCHAR(20) NULL, [oportunidad_id] NVARCHAR(20) NULL, [cliente_id] NVARCHAR(20) NULL,
    [vendedor_id] NVARCHAR(20) NULL, [producto_id] NVARCHAR(20) NULL, [fecha_venta] NVARCHAR(20) NULL,
    [cantidad_origen] NVARCHAR(10) NULL, [venta_neta] NVARCHAR(20) NULL, [canal] NVARCHAR(30) NULL, [region] NVARCHAR(30) NULL,
    [FechaKey] INT NULL, [ClienteKey] INT NULL, [VendedorKey] INT NULL, [ProductoKey] INT NULL, [CanalKey] INT NULL, [RegionKey] INT NULL,
    [Motivo] NVARCHAR(200) NULL, [FechaRegistro] DATETIME NOT NULL DEFAULT (GETDATE())
);
CREATE TABLE [Comercial].[ErrorFactOportunidad](
    [FilaOrigen] INT NULL, [oportunidad_id] NVARCHAR(20) NULL, [cliente_id] NVARCHAR(20) NULL, [vendedor_id] NVARCHAR(20) NULL,
    [fecha_creacion] NVARCHAR(20) NULL, [fecha_cierre] NVARCHAR(20) NULL, [canal] NVARCHAR(30) NULL, [region] NVARCHAR(30) NULL,
    [FechaCreacionKey] INT NULL, [FechaCierreKey] INT NULL, [ClienteKey] INT NULL, [VendedorKey] INT NULL, [CanalKey] INT NULL, [RegionKey] INT NULL,
    [Motivo] NVARCHAR(200) NULL, [FechaRegistro] DATETIME NOT NULL DEFAULT (GETDATE())
);
CREATE TABLE [Comercial].[ErrorFactLlamada](
    [FilaOrigen] INT NULL, [llamada_id] NVARCHAR(20) NULL, [fecha] NVARCHAR(20) NULL, [vendedor_id] NVARCHAR(20) NULL,
    [cliente_id] NVARCHAR(20) NULL, [disposicion_origen] NVARCHAR(40) NULL,
    [FechaKey] INT NULL, [VendedorKey] INT NULL, [ClienteKey] INT NULL,
    [Motivo] NVARCHAR(200) NULL, [FechaRegistro] DATETIME NOT NULL DEFAULT (GETDATE())
);
CREATE TABLE [Comercial].[ErrorFactCarrito](
    [FilaOrigen] INT NULL, [carrito_id] NVARCHAR(20) NULL, [fecha] NVARCHAR(20) NULL, [cliente_id] NVARCHAR(20) NULL,
    [monto_origen] NVARCHAR(20) NULL, [paso_abandono] NVARCHAR(30) NULL,
    [FechaKey] INT NULL, [ClienteKey] INT NULL,
    [Motivo] NVARCHAR(200) NULL, [FechaRegistro] DATETIME NOT NULL DEFAULT (GETDATE())
);
CREATE TABLE [Comercial].[ErrorFactSesion](
    [FilaOrigen] INT NULL, [fecha] NVARCHAR(20) NULL, [canal] NVARCHAR(30) NULL, [dispositivo_origen] NVARCHAR(20) NULL,
    [FechaKey] INT NULL,
    [Motivo] NVARCHAR(200) NULL, [FechaRegistro] DATETIME NOT NULL DEFAULT (GETDATE())
);
CREATE TABLE [Comercial].[ErrorFactEncuesta](
    [FilaOrigen] INT NULL, [encuesta_id] NVARCHAR(20) NULL, [fecha] NVARCHAR(20) NULL, [cliente_id] NVARCHAR(20) NULL,
    [FechaKey] INT NULL, [ClienteKey] INT NULL,
    [Motivo] NVARCHAR(200) NULL, [FechaRegistro] DATETIME NOT NULL DEFAULT (GETDATE())
);
CREATE TABLE [Comercial].[ErrorFactMarketing](
    [FilaOrigen] INT NULL, [fecha] NVARCHAR(20) NULL, [canal] NVARCHAR(30) NULL, [campana_origen] NVARCHAR(20) NULL,
    [FechaKey] INT NULL,
    [Motivo] NVARCHAR(200) NULL, [FechaRegistro] DATETIME NOT NULL DEFAULT (GETDATE())
);
CREATE TABLE [Comercial].[ErrorFactTicketSoporte](
    [FilaOrigen] INT NULL, [ticket_id] NVARCHAR(20) NULL, [cliente_id] NVARCHAR(20) NULL, [fecha_apertura] NVARCHAR(20) NULL,
    [fecha_cierre] NVARCHAR(20) NULL, [horas_resolucion] NVARCHAR(10) NULL,
    [FechaAperturaKey] INT NULL, [ClienteKey] INT NULL,
    [Motivo] NVARCHAR(200) NULL, [FechaRegistro] DATETIME NOT NULL DEFAULT (GETDATE())
);
GO

/* ================================================================== PROCEDIMIENTOS DE DIMENSIONES
   Patrón común:
     1) Fuente = STAGE con ROW_NUMBER() OVER (PARTITION BY <id> ORDER BY FilaOrigen)  -> rn = 1 se queda
     2) Las filas rn > 1 se registran en ErrorMaestro:
          "Fila repetida idéntica"                     si el contenido es igual a la conservada
          "ID repetido con datos distintos (...)"      si el contenido cambia
     3) MERGE de rn = 1 (inserta nuevos, actualiza cambiados) - igual que el laboratorio */

CREATE OR ALTER PROCEDURE [GENERICO].[sp_DimFecha]
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM [Comercial].[ErrorMaestro] WHERE [Tabla] = N'Calendario';
    WITH S AS (
        SELECT *, COALESCE(TRY_CONVERT(DATE, [fecha], 103), TRY_CONVERT(DATE, [fecha], 23)) AS [FechaD],
               ROW_NUMBER() OVER (PARTITION BY [fecha] ORDER BY [FilaOrigen]) AS [rn],
               FIRST_VALUE([FilaOrigen]) OVER (PARTITION BY [fecha] ORDER BY [FilaOrigen]) AS [FilaConservada]
          FROM [STAGE_GCA].[GCA].[StageCalendario])
    INSERT INTO [Comercial].[ErrorMaestro] ([Tabla],[LlaveNegocio],[FilaOrigen],[FilaConservada],[Motivo])
    SELECT N'Calendario', [fecha], [FilaOrigen], [FilaConservada], N'Fila repetida idéntica (se conservó la primera aparición)'
      FROM S WHERE [rn] > 1;

    MERGE [GENERICO].[DimFecha] AS T
    USING (
        SELECT CONVERT(INT, CONVERT(CHAR(8), d.[FechaD], 112)) AS [FechaKey], d.[FechaD] AS [Fecha],
               YEAR(d.[FechaD]) AS [Anio], MONTH(d.[FechaD]) AS [Mes],
               CHOOSE(MONTH(d.[FechaD]), 'Enero','Febrero','Marzo','Abril','Mayo','Junio','Julio','Agosto',
                      'Septiembre','Octubre','Noviembre','Diciembre') AS [NombreMes],
               DATEPART(QUARTER, d.[FechaD]) AS [Trimestre],
               DATEDIFF(DAY, '19000101', d.[FechaD]) % 7 + 1 AS [DiaSemana],          -- 1900-01-01 fue lunes
               CHOOSE(DATEDIFF(DAY, '19000101', d.[FechaD]) % 7 + 1,
                      'Lunes','Martes','Miércoles','Jueves','Viernes','Sábado','Domingo') AS [NombreDia],
               CASE WHEN DATEDIFF(DAY, '19000101', d.[FechaD]) % 7 >= 5 THEN 1 ELSE 0 END AS [EsFinSemana],
               CONVERT(CHAR(7), d.[FechaD], 126) AS [Periodo],
               LOWER(LTRIM(RTRIM(d.[fase]))) AS [Fase]
          FROM (SELECT *, COALESCE(TRY_CONVERT(DATE, [fecha], 103), TRY_CONVERT(DATE, [fecha], 23)) AS [FechaD],
                       ROW_NUMBER() OVER (PARTITION BY [fecha] ORDER BY [FilaOrigen]) AS [rn]
                  FROM [STAGE_GCA].[GCA].[StageCalendario]) d
         WHERE d.[rn] = 1 AND d.[FechaD] IS NOT NULL) AS S
       ON T.[FechaKey] = S.[FechaKey]
    WHEN MATCHED AND T.[Fase] <> S.[Fase] THEN UPDATE SET T.[Fase] = S.[Fase]
    WHEN NOT MATCHED THEN
        INSERT ([FechaKey],[Fecha],[Anio],[Mes],[NombreMes],[Trimestre],[DiaSemana],[NombreDia],[EsFinSemana],[Periodo],[Fase])
        VALUES (S.[FechaKey],S.[Fecha],S.[Anio],S.[Mes],S.[NombreMes],S.[Trimestre],S.[DiaSemana],S.[NombreDia],S.[EsFinSemana],S.[Periodo],S.[Fase]);
END
GO

CREATE OR ALTER PROCEDURE [Comercial].[sp_DimCanal]
AS
BEGIN
    SET NOCOUNT ON;
    MERGE [Comercial].[DimCanal] AS T
    USING (SELECT DISTINCT LTRIM(RTRIM([canal])) AS [Canal] FROM [STAGE_GCA].[GCA].[StageVendedor] WHERE NULLIF(LTRIM([canal]), N'') IS NOT NULL
           UNION SELECT DISTINCT LTRIM(RTRIM([canal])) FROM [STAGE_GCA].[GCA].[StageVenta] WHERE NULLIF(LTRIM([canal]), N'') IS NOT NULL
           UNION SELECT DISTINCT LTRIM(RTRIM([canal])) FROM [STAGE_GCA].[GCA].[StageOportunidad] WHERE NULLIF(LTRIM([canal]), N'') IS NOT NULL) AS S
       ON T.[Canal] = S.[Canal]
    WHEN NOT MATCHED THEN INSERT ([Canal]) VALUES (S.[Canal]);
END
GO

CREATE OR ALTER PROCEDURE [Comercial].[sp_DimRegion]
AS
BEGIN
    SET NOCOUNT ON;
    MERGE [Comercial].[DimRegion] AS T
    USING (SELECT r.[Region],
                  CASE r.[Region] WHEN N'Lima' THEN N'Perú' WHEN N'Provincia' THEN N'Perú' WHEN N'Bogotá' THEN N'Colombia'
                                  WHEN N'Quito' THEN N'Ecuador' WHEN N'Santiago' THEN N'Chile' ELSE N'Sin Datos' END AS [Pais]
             FROM (SELECT DISTINCT LTRIM(RTRIM([region])) AS [Region] FROM [STAGE_GCA].[GCA].[StageVendedor] WHERE NULLIF(LTRIM([region]), N'') IS NOT NULL
                   UNION SELECT DISTINCT LTRIM(RTRIM([region])) FROM [STAGE_GCA].[GCA].[StageVenta] WHERE NULLIF(LTRIM([region]), N'') IS NOT NULL
                   UNION SELECT DISTINCT LTRIM(RTRIM([region])) FROM [STAGE_GCA].[GCA].[StageOportunidad] WHERE NULLIF(LTRIM([region]), N'') IS NOT NULL) r) AS S
       ON T.[Region] = S.[Region]
    WHEN MATCHED AND T.[Pais] <> S.[Pais] THEN UPDATE SET T.[Pais] = S.[Pais]
    WHEN NOT MATCHED THEN INSERT ([Region],[Pais]) VALUES (S.[Region], S.[Pais]);
END
GO

CREATE OR ALTER PROCEDURE [Comercial].[sp_DimCliente]
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM [Comercial].[ErrorMaestro] WHERE [Tabla] = N'Cliente';
    WITH S AS (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY [cliente_id] ORDER BY [FilaOrigen]) AS [rn],
               FIRST_VALUE([FilaOrigen]) OVER (PARTITION BY [cliente_id] ORDER BY [FilaOrigen]) AS [FilaConservada],
               -- huella del contenido para saber si la repetida es idéntica o distinta
               CHECKSUM([nombre],[tipo],[segmento],[pais],[fecha_alta],[tiene_contrato],[tiene_ejecutivo],[canal_origen]) AS [Huella]
          FROM [STAGE_GCA].[GCA].[StageCliente])
    INSERT INTO [Comercial].[ErrorMaestro] ([Tabla],[LlaveNegocio],[FilaOrigen],[FilaConservada],[Motivo])
    SELECT N'Cliente', s.[cliente_id], s.[FilaOrigen], s.[FilaConservada],
           CASE WHEN s.[Huella] = k.[Huella] THEN N'Fila repetida idéntica (se conservó la primera aparición)'
                ELSE N'ID repetido con datos distintos: canal_origen "' + s.[canal_origen] + N'" vs "' + k.[canal_origen]
                     + N'" (se conservó la primera aparición)' END
      FROM S s JOIN S k ON k.[cliente_id] = s.[cliente_id] AND k.[rn] = 1
     WHERE s.[rn] > 1;

    MERGE [Comercial].[DimCliente] AS T
    USING (
        SELECT c.[cliente_id] AS [ClienteID], LTRIM(RTRIM(c.[nombre])) AS [Nombre], LTRIM(RTRIM(c.[tipo])) AS [Tipo],
               ISNULL(NULLIF(LTRIM(RTRIM(c.[segmento])), N''), N'Sin Datos') AS [Segmento],
               ISNULL(NULLIF(LTRIM(RTRIM(c.[pais])), N''), N'Sin Datos') AS [Pais],
               c.[FechaAltaD] AS [FechaAlta],
               CASE WHEN c.[FechaAltaD] > '20241231' THEN 1 ELSE 0 END AS [FechaAltaFutura],
               CASE WHEN c.[tiene_contrato] = N'1' THEN 1 ELSE 0 END AS [TieneContrato],
               CASE WHEN c.[tiene_ejecutivo] = N'1' THEN 1 ELSE 0 END AS [TieneEjecutivo],
               ISNULL(NULLIF(LTRIM(RTRIM(c.[canal_origen])), N''), N'Sin Datos') AS [CanalOrigen],
               CASE WHEN COUNT(*) OVER (PARTITION BY LTRIM(RTRIM(c.[nombre])), c.[pais]) > 1 THEN 1 ELSE 0 END AS [PosibleDuplicado]
          FROM (SELECT *, COALESCE(TRY_CONVERT(DATE, [fecha_alta], 103), TRY_CONVERT(DATE, [fecha_alta], 23)) AS [FechaAltaD],
                       ROW_NUMBER() OVER (PARTITION BY [cliente_id] ORDER BY [FilaOrigen]) AS [rn]
                  FROM [STAGE_GCA].[GCA].[StageCliente]) c
         WHERE c.[rn] = 1) AS S
       ON T.[ClienteID] = S.[ClienteID]
    WHEN MATCHED AND (T.[Nombre] <> S.[Nombre] OR T.[Tipo] <> S.[Tipo] OR T.[Segmento] <> S.[Segmento] OR T.[Pais] <> S.[Pais]
                      OR ISNULL(T.[FechaAlta], '19000101') <> ISNULL(S.[FechaAlta], '19000101') OR T.[TieneContrato] <> S.[TieneContrato]
                      OR T.[TieneEjecutivo] <> S.[TieneEjecutivo] OR T.[CanalOrigen] <> S.[CanalOrigen]
                      OR T.[PosibleDuplicado] <> S.[PosibleDuplicado]) THEN
        UPDATE SET T.[Nombre] = S.[Nombre], T.[Tipo] = S.[Tipo], T.[Segmento] = S.[Segmento], T.[Pais] = S.[Pais],
                   T.[FechaAlta] = S.[FechaAlta], T.[FechaAltaFutura] = S.[FechaAltaFutura], T.[TieneContrato] = S.[TieneContrato],
                   T.[TieneEjecutivo] = S.[TieneEjecutivo], T.[CanalOrigen] = S.[CanalOrigen], T.[PosibleDuplicado] = S.[PosibleDuplicado]
    WHEN NOT MATCHED THEN
        INSERT ([ClienteID],[Nombre],[Tipo],[Segmento],[Pais],[FechaAlta],[FechaAltaFutura],[TieneContrato],[TieneEjecutivo],[CanalOrigen],[PosibleDuplicado])
        VALUES (S.[ClienteID],S.[Nombre],S.[Tipo],S.[Segmento],S.[Pais],S.[FechaAlta],S.[FechaAltaFutura],S.[TieneContrato],S.[TieneEjecutivo],S.[CanalOrigen],S.[PosibleDuplicado]);
END
GO

CREATE OR ALTER PROCEDURE [Comercial].[sp_DimProducto]
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM [Comercial].[ErrorMaestro] WHERE [Tabla] = N'Producto';
    WITH S AS (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY [producto_id] ORDER BY [FilaOrigen]) AS [rn],
               FIRST_VALUE([FilaOrigen]) OVER (PARTITION BY [producto_id] ORDER BY [FilaOrigen]) AS [FilaConservada],
               CHECKSUM([categoria],[costo_unitario],[precio_lista],[margen_objetivo]) AS [Huella]
          FROM [STAGE_GCA].[GCA].[StageProducto])
    INSERT INTO [Comercial].[ErrorMaestro] ([Tabla],[LlaveNegocio],[FilaOrigen],[FilaConservada],[Motivo])
    SELECT N'Producto', s.[producto_id], s.[FilaOrigen], s.[FilaConservada],
           CASE WHEN s.[Huella] = k.[Huella] THEN N'Fila repetida idéntica (se conservó la primera aparición)'
                ELSE N'ID repetido con datos distintos (se conservó la primera aparición)' END
      FROM S s JOIN S k ON k.[producto_id] = s.[producto_id] AND k.[rn] = 1
     WHERE s.[rn] > 1;

    MERGE [Comercial].[DimProducto] AS T
    USING (
        SELECT p.[producto_id] AS [ProductoID], LTRIM(RTRIM(p.[categoria])) AS [Categoria],
               TRY_CONVERT(DECIMAL(18,2), p.[costo_unitario]) AS [CostoUnitario],
               TRY_CONVERT(DECIMAL(18,2), p.[precio_lista]) AS [PrecioLista],
               TRY_CONVERT(DECIMAL(9,4), p.[margen_objetivo]) AS [MargenObjetivo]
          FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY [producto_id] ORDER BY [FilaOrigen]) AS [rn]
                  FROM [STAGE_GCA].[GCA].[StageProducto]) p
         WHERE p.[rn] = 1) AS S
       ON T.[ProductoID] = S.[ProductoID]
    WHEN MATCHED AND (T.[Categoria] <> S.[Categoria] OR T.[CostoUnitario] <> S.[CostoUnitario]
                      OR T.[PrecioLista] <> S.[PrecioLista] OR T.[MargenObjetivo] <> S.[MargenObjetivo]) THEN
        UPDATE SET T.[Categoria] = S.[Categoria], T.[CostoUnitario] = S.[CostoUnitario],
                   T.[PrecioLista] = S.[PrecioLista], T.[MargenObjetivo] = S.[MargenObjetivo]
    WHEN NOT MATCHED THEN
        INSERT ([ProductoID],[Categoria],[CostoUnitario],[PrecioLista],[MargenObjetivo])
        VALUES (S.[ProductoID],S.[Categoria],S.[CostoUnitario],S.[PrecioLista],S.[MargenObjetivo]);
END
GO

CREATE OR ALTER PROCEDURE [Comercial].[sp_DimVendedor]
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM [Comercial].[ErrorMaestro] WHERE [Tabla] = N'Vendedor';
    WITH S AS (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY [vendedor_id] ORDER BY [FilaOrigen]) AS [rn],
               FIRST_VALUE([FilaOrigen]) OVER (PARTITION BY [vendedor_id] ORDER BY [FilaOrigen]) AS [FilaConservada],
               CHECKSUM([nombre],[canal],[region],[gerente_id],[antiguedad],[cuota_anual],[fecha_ingreso]) AS [Huella]
          FROM [STAGE_GCA].[GCA].[StageVendedor])
    INSERT INTO [Comercial].[ErrorMaestro] ([Tabla],[LlaveNegocio],[FilaOrigen],[FilaConservada],[Motivo])
    SELECT N'Vendedor', s.[vendedor_id], s.[FilaOrigen], s.[FilaConservada],
           CASE WHEN s.[Huella] = k.[Huella] THEN N'Fila repetida idéntica (se conservó la primera aparición)'
                ELSE N'ID repetido con datos distintos (se conservó la primera aparición)' END
      FROM S s JOIN S k ON k.[vendedor_id] = s.[vendedor_id] AND k.[rn] = 1
     WHERE s.[rn] > 1;

    MERGE [Comercial].[DimVendedor] AS T
    USING (
        SELECT v.[vendedor_id] AS [VendedorID], LTRIM(RTRIM(v.[nombre])) AS [Nombre], LTRIM(RTRIM(v.[canal])) AS [Canal],
               LTRIM(RTRIM(v.[region])) AS [Region], LTRIM(RTRIM(v.[gerente_id])) AS [GerenteID],
               LTRIM(RTRIM(v.[antiguedad])) AS [Antiguedad], TRY_CONVERT(DECIMAL(18,2), v.[cuota_anual]) AS [CuotaAnual],
               COALESCE(TRY_CONVERT(DATE, v.[fecha_ingreso], 103), TRY_CONVERT(DATE, v.[fecha_ingreso], 23)) AS [FechaIngreso]
          FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY [vendedor_id] ORDER BY [FilaOrigen]) AS [rn]
                  FROM [STAGE_GCA].[GCA].[StageVendedor]) v
         WHERE v.[rn] = 1) AS S
       ON T.[VendedorID] = S.[VendedorID]
    WHEN MATCHED AND (T.[Nombre] <> S.[Nombre] OR T.[Canal] <> S.[Canal] OR T.[Region] <> S.[Region] OR T.[GerenteID] <> S.[GerenteID]
                      OR T.[Antiguedad] <> S.[Antiguedad] OR T.[CuotaAnual] <> S.[CuotaAnual]
                      OR ISNULL(T.[FechaIngreso], '19000101') <> ISNULL(S.[FechaIngreso], '19000101')) THEN
        UPDATE SET T.[Nombre] = S.[Nombre], T.[Canal] = S.[Canal], T.[Region] = S.[Region], T.[GerenteID] = S.[GerenteID],
                   T.[Antiguedad] = S.[Antiguedad], T.[CuotaAnual] = S.[CuotaAnual], T.[FechaIngreso] = S.[FechaIngreso]
    WHEN NOT MATCHED THEN
        INSERT ([VendedorID],[Nombre],[Canal],[Region],[GerenteID],[Antiguedad],[CuotaAnual],[FechaIngreso])
        VALUES (S.[VendedorID],S.[Nombre],S.[Canal],S.[Region],S.[GerenteID],S.[Antiguedad],S.[CuotaAnual],S.[FechaIngreso]);
END
GO
