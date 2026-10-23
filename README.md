# Grupo Comercial Andino — BI de ventas (Lab Integrador)

Solución BI del caso **"Grupo Comercial Andino: recuperar el crecimiento rentable sin quemar el pipeline"**:
**CSV → STAGE → Data Warehouse (SSIS, con limpieza de datos) → Cubo tabular (SSAS) → Power BI**.

> **¿Quieres replicarlo en tu PC?** Sigue [INSTALACION.md](INSTALACION.md): software, bases de datos, usuarios,
> carga con SSIS, validaciones y cubo.

## Estructura

| Carpeta | Contenido |
|---|---|
| `caso/` | Enunciado del caso (PDF) e indicadores críticos con lectura y acción (`Indicadores_Criticos_GCA.docx`) |
| `data_ventas/` | Datos de origen: `Maestros/` (calendario, cliente, producto, vendedor) y `Transacciones/` (8 archivos) |
| `sql/` | Creación de `STAGE_GCA` y `DWH_GCA`, validaciones, hallazgos **antes/después** y vistas del cubo |
| `GCA/` | Solución de Visual Studio `GCA.sln`: proyectos SSIS `stage_GCA` y `DWH_GCA` + proyecto tabular |
| `Tabular_GCA/` | Cubo tabular (compatibilidad 1200): `Model.bim`, generador, despliegue y `MEDIDAS_DAX.md` (83 medidas) |
| `herramientas/` | Generador de los paquetes SSIS (API de SSIS 2025) y `configurar_entorno.ps1` para otra PC |
| `docs/` | **`Hallazgos_Calidad_Datos.md`**: datos sucios encontrados y cómo los resolvió el ETL |

## Modelo (DWH_GCA)

- **Dimensiones:** `GENERICO.DimFecha`, `Comercial.DimCliente`, `DimProducto`, `DimVendedor`, `DimCanal`, `DimRegion`
  (comodín `-1`, cargadas por procedimientos `MERGE` con `ROW_NUMBER` para quitar duplicados).
- **Hechos:** `FactVenta`, `FactOportunidad`, `FactLlamada`, `FactCarrito`, `FactSesion`, `FactEncuesta`,
  `FactMarketing`, `FactTicketSoporte` (Búsquedas + División condicional → tablas `Error...` con **motivo**).
- **Auditoría:** `dbo.DIM_AUDIT` (plantilla del laboratorio en cada paquete). Descartes de maestros: `Comercial.ErrorMaestro`.

## Limpieza de datos (resumen)

La data viene sucia a propósito. Principales hallazgos ([detalle](docs/Hallazgos_Calidad_Datos.md)):

| Problema | Cantidad | Solución en el ETL |
|---|---|---|
| Copias de registros reales con otro ID y fecha alterada (ventas, carritos, soporte) | 609 + 26,550 + 636 | Se detectan por contenido idéntico; se conserva el original y la copia va a `Error...` |
| Maestros con filas repetidas (calendario, producto, vendedor, cliente) | 36 + 210 + 17 + 28 | `ROW_NUMBER()` por ID → se queda la primera aparición |
| Ventas con `venta_neta` / `margen_bruto` vacíos (ej. `VTA-00000216` sale en 0) | 103 / 488 | Recalculados: cantidad × precio neto; (venta − costo) / venta |
| `fecha_cierre` de soporte corrupta (`55:34.6`) | todos | Reconstruida: apertura + horas de resolución |
| Dos formatos de fecha | 4 + 4 archivos | `TRY_CONVERT(DATE, x, 103)` / `(…, 23)` |
| Llamadas de clientes inexistentes | 150 | `ErrorFactLlamada` |
| `ciclo_venta_dias` incoherente con las fechas | 2,391 | Recalculado con las fechas |

**Cuadre final:** archivo = DWH + errores en las 12 tablas (`sql/03_validaciones.sql`).

## Indicadores

El cubo implementa los indicadores críticos del caso con los datos disponibles (cumplimiento de cuota, ticket B2B/B2C,
conversión e-commerce, ciclo de venta, win rate, pérdidas por motivo, churn, cross-sell, margen, descuentos,
productividad, CAC, LTV/CAC, NPS, SLA de soporte) y su comparación **antes / después** según la fase del calendario.
Limitaciones de los datos (churn, pipeline, forecast, CAC) en `docs/Hallazgos_Calidad_Datos.md`, sección 8.

## Entorno del autor

SQL Server 2025 Developer `LAPTOP-IO596P6A\DEV` (motor + Integration Services) · Analysis Services tabular
`localhost\TABULAR` · Visual Studio 2022 con extensiones SSIS y Analysis Services.
