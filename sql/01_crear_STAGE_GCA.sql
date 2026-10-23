/* =====================================================================
   Grupo Comercial Andino (GCA) - Base de datos STAGE
   Instancia : LAPTOP-IO596P6A\DEV
   Origen    : data_ventas\Maestros y data_ventas\Transacciones (CSV UTF-8)
   Regla     : el STAGE es copia FIEL del archivo. Todo se guarda como texto
               (NVARCHAR) para conservar los errores tal como vienen: fechas en
               dos formatos, importes vacíos, fechas corruptas ("55:34.6"), etc.
               La limpieza se hace al pasar al DWH (02_crear_DWH_GCA.sql + SSIS).
   FilaOrigen: número de fila del archivo (IDENTITY en el orden de carga). Sirve
               para la regla "si hay duplicados, se conserva la primera aparición".
   ===================================================================== */
USE [master]
GO
IF DB_ID(N'STAGE_GCA') IS NULL
    CREATE DATABASE [STAGE_GCA];
GO
ALTER DATABASE [STAGE_GCA] SET RECOVERY SIMPLE;
GO
USE [STAGE_GCA]
GO
IF SCHEMA_ID(N'GCA') IS NULL EXEC (N'CREATE SCHEMA [GCA]');
GO

/* ============================ MAESTROS ============================ */
DROP TABLE IF EXISTS [GCA].[StageCalendario];
CREATE TABLE [GCA].[StageCalendario](
    [FilaOrigen]    INT IDENTITY(1,1) NOT NULL,
    [fecha]         NVARCHAR(20) NULL,
    [anio]          NVARCHAR(10) NULL,
    [mes]           NVARCHAR(10) NULL,
    [trimestre]     NVARCHAR(10) NULL,
    [dia_semana]    NVARCHAR(10) NULL,
    [es_fin_semana] NVARCHAR(10) NULL,
    [periodo]       NVARCHAR(10) NULL,
    [fase]          NVARCHAR(20) NULL
);

DROP TABLE IF EXISTS [GCA].[StageCliente];
CREATE TABLE [GCA].[StageCliente](
    [FilaOrigen]      INT IDENTITY(1,1) NOT NULL,
    [cliente_id]      NVARCHAR(20)  NULL,
    [nombre]          NVARCHAR(100) NULL,
    [tipo]            NVARCHAR(10)  NULL,
    [segmento]        NVARCHAR(30)  NULL,
    [pais]            NVARCHAR(30)  NULL,
    [fecha_alta]      NVARCHAR(20)  NULL,
    [tiene_contrato]  NVARCHAR(10)  NULL,
    [tiene_ejecutivo] NVARCHAR(10)  NULL,
    [canal_origen]    NVARCHAR(40)  NULL
);

DROP TABLE IF EXISTS [GCA].[StageProducto];
CREATE TABLE [GCA].[StageProducto](
    [FilaOrigen]      INT IDENTITY(1,1) NOT NULL,
    [producto_id]     NVARCHAR(20) NULL,
    [categoria]       NVARCHAR(40) NULL,
    [costo_unitario]  NVARCHAR(20) NULL,
    [precio_lista]    NVARCHAR(20) NULL,
    [margen_objetivo] NVARCHAR(20) NULL
);

DROP TABLE IF EXISTS [GCA].[StageVendedor];
CREATE TABLE [GCA].[StageVendedor](
    [FilaOrigen]    INT IDENTITY(1,1) NOT NULL,
    [vendedor_id]   NVARCHAR(20)  NULL,
    [nombre]        NVARCHAR(100) NULL,
    [canal]         NVARCHAR(30)  NULL,
    [region]        NVARCHAR(30)  NULL,
    [gerente_id]    NVARCHAR(20)  NULL,
    [antiguedad]    NVARCHAR(20)  NULL,
    [cuota_anual]   NVARCHAR(20)  NULL,
    [fecha_ingreso] NVARCHAR(20)  NULL
);

/* ========================== TRANSACCIONES ========================== */
DROP TABLE IF EXISTS [GCA].[StageVenta];
CREATE TABLE [GCA].[StageVenta](
    [FilaOrigen]           INT IDENTITY(1,1) NOT NULL,
    [venta_id]             NVARCHAR(20) NULL,
    [oportunidad_id]       NVARCHAR(20) NULL,
    [cliente_id]           NVARCHAR(20) NULL,
    [vendedor_id]          NVARCHAR(20) NULL,
    [producto_id]          NVARCHAR(20) NULL,
    [categoria]            NVARCHAR(40) NULL,
    [fecha_venta]          NVARCHAR(20) NULL,
    [cantidad]             NVARCHAR(10) NULL,
    [precio_lista]         NVARCHAR(20) NULL,
    [descuento]            NVARCHAR(10) NULL,
    [precio_unitario_neto] NVARCHAR(20) NULL,
    [venta_neta]           NVARCHAR(20) NULL,
    [costo_total]          NVARCHAR(20) NULL,
    [margen_bruto]         NVARCHAR(20) NULL,
    [canal]                NVARCHAR(30) NULL,
    [region]               NVARCHAR(30) NULL,
    [tipo_cliente]         NVARCHAR(10) NULL
);

DROP TABLE IF EXISTS [GCA].[StageOportunidad];
CREATE TABLE [GCA].[StageOportunidad](
    [FilaOrigen]               INT IDENTITY(1,1) NOT NULL,
    [oportunidad_id]           NVARCHAR(20) NULL,
    [cliente_id]               NVARCHAR(20) NULL,
    [vendedor_id]              NVARCHAR(20) NULL,
    [canal]                    NVARCHAR(30) NULL,
    [region]                   NVARCHAR(30) NULL,
    [gerente_id]               NVARCHAR(20) NULL,
    [fecha_creacion]           NVARCHAR(20) NULL,
    [fecha_cierre]             NVARCHAR(20) NULL,
    [etapa]                    NVARCHAR(30) NULL,
    [resultado]                NVARCHAR(30) NULL,
    [facturada]                NVARCHAR(10) NULL,
    [motivo_perdida]           NVARCHAR(40) NULL,
    [monto_oportunidad]        NVARCHAR(20) NULL,
    [descuento_solicitado]     NVARCHAR(10) NULL,
    [descuento_fuera_politica] NVARCHAR(10) NULL,
    [touchpoints]              NVARCHAR(10) NULL,
    [tiene_demo_tecnica]       NVARCHAR(10) NULL,
    [ciclo_venta_dias]         NVARCHAR(10) NULL,
    [dias_sin_actividad]       NVARCHAR(10) NULL,
    [fase]                     NVARCHAR(20) NULL
);

DROP TABLE IF EXISTS [GCA].[StageLlamada];
CREATE TABLE [GCA].[StageLlamada](
    [FilaOrigen]   INT IDENTITY(1,1) NOT NULL,
    [llamada_id]   NVARCHAR(20) NULL,
    [fecha]        NVARCHAR(20) NULL,
    [vendedor_id]  NVARCHAR(20) NULL,
    [cliente_id]   NVARCHAR(20) NULL,
    [duracion_seg] NVARCHAR(10) NULL,
    [disposicion]  NVARCHAR(40) NULL,
    [es_venta]     NVARCHAR(10) NULL
);

DROP TABLE IF EXISTS [GCA].[StageCarrito];
CREATE TABLE [GCA].[StageCarrito](
    [FilaOrigen]    INT IDENTITY(1,1) NOT NULL,
    [carrito_id]    NVARCHAR(20) NULL,
    [fecha]         NVARCHAR(20) NULL,
    [cliente_id]    NVARCHAR(20) NULL,
    [monto]         NVARCHAR(20) NULL,
    [paso_abandono] NVARCHAR(30) NULL,
    [recuperado]    NVARCHAR(10) NULL,
    [fase]          NVARCHAR(20) NULL
);

DROP TABLE IF EXISTS [GCA].[StageSesion];
CREATE TABLE [GCA].[StageSesion](
    [FilaOrigen]        INT IDENTITY(1,1) NOT NULL,
    [fecha]             NVARCHAR(20) NULL,
    [canal]             NVARCHAR(30) NULL,
    [dispositivo]       NVARCHAR(20) NULL,
    [sesiones]          NVARCHAR(10) NULL,
    [add_to_cart]       NVARCHAR(10) NULL,
    [checkout_iniciado] NVARCHAR(10) NULL,
    [ordenes]           NVARCHAR(10) NULL,
    [ticket_promedio]   NVARCHAR(20) NULL,
    [venta_total]       NVARCHAR(20) NULL,
    [fase]              NVARCHAR(20) NULL
);

DROP TABLE IF EXISTS [GCA].[StageEncuesta];
CREATE TABLE [GCA].[StageEncuesta](
    [FilaOrigen]  INT IDENTITY(1,1) NOT NULL,
    [encuesta_id] NVARCHAR(20) NULL,
    [fecha]       NVARCHAR(20) NULL,
    [cliente_id]  NVARCHAR(20) NULL,
    [momento]     NVARCHAR(30) NULL,
    [nps]         NVARCHAR(10) NULL,
    [csat]        NVARCHAR(10) NULL,
    [fase]        NVARCHAR(20) NULL
);

DROP TABLE IF EXISTS [GCA].[StageMarketing];
CREATE TABLE [GCA].[StageMarketing](
    [FilaOrigen]      INT IDENTITY(1,1) NOT NULL,
    [fecha]           NVARCHAR(20) NULL,
    [canal]           NVARCHAR(30) NULL,
    [campana]         NVARCHAR(20) NULL,
    [inversion]       NVARCHAR(20) NULL,
    [leads]           NVARCHAR(10) NULL,
    [nuevos_clientes] NVARCHAR(10) NULL,
    [fase]            NVARCHAR(20) NULL
);

DROP TABLE IF EXISTS [GCA].[StageTicketSoporte];
CREATE TABLE [GCA].[StageTicketSoporte](
    [FilaOrigen]       INT IDENTITY(1,1) NOT NULL,
    [ticket_id]        NVARCHAR(20) NULL,
    [cliente_id]       NVARCHAR(20) NULL,
    [fecha_apertura]   NVARCHAR(20) NULL,
    [fecha_cierre]     NVARCHAR(20) NULL,   -- viene corrupta: "55:34.6"
    [horas_resolucion] NVARCHAR(10) NULL,
    [categoria]        NVARCHAR(30) NULL,
    [sla_cumplido]     NVARCHAR(10) NULL,
    [fase]             NVARCHAR(20) NULL
);
GO
