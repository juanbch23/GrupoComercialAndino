# Medidas DAX del cubo Tabular_GCA

Generado desde `Model.bim` (fuente: `gen_bim_gca.py`). Cubo `Tabular_GCA` en `localhost\TABULAR`, compatibilidad 1200.
Cada carpeta corresponde a un indicador crítico del caso (`Indicadores_Criticos_GCA.docx`).
Las medidas `_Antes` / `_Despues` comparan la situación anterior (ene–jun 2023) con la actual (jul 2023–dic 2024), según la columna `DimFecha[Fase]` del calendario del caso.

## Modelo

| Tabla | Tipo | Origen en DWH_GCA |
|---|---|---|
| DimFecha | Dimensión | `[GENERICO].[DimFecha]` |
| DimCliente | Dimensión | `[Comercial].[vw_DimCliente]` |
| DimProducto | Dimensión | `[Comercial].[DimProducto]` |
| DimVendedor | Dimensión | `[Comercial].[vw_DimVendedor]` |
| DimCanal | Dimensión | `[Comercial].[DimCanal]` |
| DimRegion | Dimensión | `[Comercial].[DimRegion]` |
| FactVenta | Hecho | `[Comercial].[FactVenta]` |
| FactOportunidad | Hecho | `[Comercial].[FactOportunidad]` |
| FactLlamada | Hecho | `[Comercial].[FactLlamada]` |
| FactCarrito | Hecho | `[Comercial].[FactCarrito]` |
| FactSesion | Hecho | `[Comercial].[FactSesion]` |
| FactEncuesta | Hecho | `[Comercial].[FactEncuesta]` |
| FactMarketing | Hecho | `[Comercial].[FactMarketing]` |
| FactTicketSoporte | Hecho | `[Comercial].[FactTicketSoporte]` |
| FactCuota | Hecho | `[Comercial].[vw_FactCuota]` |

Relaciones: 25 (la de `FactOportunidad[FechaCreacionKey]` está inactiva; se usa con `USERELATIONSHIP`).

## 00. Ventas base

| Medida | Tabla | Fórmula DAX | Descripción |
|---|---|---|---|
| `.Ventas_Netas` | FactVenta | `SUM(FactVenta[VentaNeta])` | Venta neta recalculada (cantidad x precio unitario neto) |
| `.Costo_Total` | FactVenta | `SUM(FactVenta[CostoTotal])` |  |
| `.Margen_Bruto` | FactVenta | `SUM(FactVenta[MargenBruto])` | Ventas netas - costo |
| `.Transacciones` | FactVenta | `COUNTROWS(FactVenta)` |  |
| `.Unidades` | FactVenta | `SUM(FactVenta[Cantidad])` |  |
| `.Clientes_Activos` | FactVenta | `DISTINCTCOUNT(FactVenta[ClienteKey])` |  |
| `.Vendedores_Activos` | FactVenta | `DISTINCTCOUNT(FactVenta[VendedorKey])` |  |
| `.Meses` | FactVenta | `DISTINCTCOUNT(DimFecha[AnioMes])` |  |

## 01. Cumplimiento de cuota

| Medida | Tabla | Fórmula DAX | Descripción |
|---|---|---|---|
| `.%Cumplimiento_Cuota` | FactVenta | `DIVIDE([.Ventas_Netas], [.Cuota])` | Meta >= 95 % |
| `.%Cumplimiento_Cuota_Antes` | FactVenta | `CALCULATE([.%Cumplimiento_Cuota], DimFecha[Fase] = "antes")` |  |
| `.%Cumplimiento_Cuota_Despues` | FactVenta | `CALCULATE([.%Cumplimiento_Cuota], DimFecha[Fase] = "despues")` |  |
| `.Cuota` | FactCuota | `SUM(FactCuota[CuotaMensual])` | Cuota anual del vendedor repartida en 12 meses |

## 02. Ticket promedio

| Medida | Tabla | Fórmula DAX | Descripción |
|---|---|---|---|
| `.Ticket_Promedio` | FactVenta | `DIVIDE([.Ventas_Netas], [.Transacciones])` |  |
| `.Ticket_B2B` | FactVenta | `CALCULATE([.Ticket_Promedio], DimCliente[Tipo] = "B2B")` | Meta >= USD 4.000 |
| `.Ticket_B2C` | FactVenta | `CALCULATE([.Ticket_Promedio], DimCliente[Tipo] = "B2C")` | Meta >= USD 85 |
| `.Ticket_B2B_Antes` | FactVenta | `CALCULATE([.Ticket_B2B], DimFecha[Fase] = "antes")` |  |
| `.Ticket_B2B_Despues` | FactVenta | `CALCULATE([.Ticket_B2B], DimFecha[Fase] = "despues")` |  |

## 03. Conversión e-commerce

| Medida | Tabla | Fórmula DAX | Descripción |
|---|---|---|---|
| `.Carritos_Abandonados` | FactCarrito | `COUNTROWS(FactCarrito)` |  |
| `.Monto_Abandonado` | FactCarrito | `SUM(FactCarrito[Monto])` |  |
| `.%Carritos_Recuperados` | FactCarrito | `DIVIDE(SUM(FactCarrito[Recuperado]), [.Carritos_Abandonados])` |  |
| `.Sesiones` | FactSesion | `SUM(FactSesion[Sesiones])` |  |
| `.Ordenes` | FactSesion | `SUM(FactSesion[Ordenes])` |  |
| `.%Conversion_Ecommerce` | FactSesion | `DIVIDE([.Ordenes], [.Sesiones])` | Meta >= 3,0 % |
| `.%Add_to_Cart` | FactSesion | `DIVIDE(SUM(FactSesion[AddToCart]), [.Sesiones])` |  |
| `.%Checkout_Iniciado` | FactSesion | `DIVIDE(SUM(FactSesion[CheckoutIniciado]), [.Sesiones])` |  |
| `.Venta_Ecommerce` | FactSesion | `SUM(FactSesion[VentaTotal])` |  |
| `.%Conversion_Ecommerce_Antes` | FactSesion | `CALCULATE([.%Conversion_Ecommerce], DimFecha[Fase] = "antes")` |  |
| `.%Conversion_Ecommerce_Despues` | FactSesion | `CALCULATE([.%Conversion_Ecommerce], DimFecha[Fase] = "despues")` |  |

## 04. Ciclo de venta

| Medida | Tabla | Fórmula DAX | Descripción |
|---|---|---|---|
| `.Ciclo_Venta_Dias` | FactOportunidad | `CALCULATE(AVERAGE(FactOportunidad[CicloVentaDias]), FactOportunidad[Facturada] = 1)` | Días de creación a cierre de las oportunidades ganadas (facturadas). Meta <= 50 |
| `.Ciclo_Venta_Dias_Antes` | FactOportunidad | `CALCULATE([.Ciclo_Venta_Dias], DimFecha[Fase] = "antes")` |  |
| `.Ciclo_Venta_Dias_Despues` | FactOportunidad | `CALCULATE([.Ciclo_Venta_Dias], DimFecha[Fase] = "despues")` |  |

## 05. Win rate y pérdidas

| Medida | Tabla | Fórmula DAX | Descripción |
|---|---|---|---|
| `.Oportunidades_Cerradas` | FactOportunidad | `COUNTROWS(FactOportunidad)` |  |
| `.Oportunidades_Ganadas` | FactOportunidad | `CALCULATE(COUNTROWS(FactOportunidad), FactOportunidad[Facturada] = 1)` | Regla del caso: ganada solo si está facturada |
| `.Oportunidades_Perdidas` | FactOportunidad | `[.Oportunidades_Cerradas] - [.Oportunidades_Ganadas]` |  |
| `.%Win_Rate` | FactOportunidad | `DIVIDE([.Oportunidades_Ganadas], [.Oportunidades_Cerradas])` | Meta >= 35 % |
| `.%Perdidas` | FactOportunidad | `DIVIDE([.Oportunidades_Perdidas], [.Oportunidades_Cerradas])` | Meta <= 65 % |
| `.%Motivo_Perdida` | FactOportunidad | `DIVIDE([.Oportunidades_Perdidas], CALCULATE([.Oportunidades_Perdidas], ALLSELECTED(FactOportunidad[MotivoPerdida])))` | Participación de cada motivo sobre las oportunidades perdidas |
| `.%Win_Rate_Antes` | FactOportunidad | `CALCULATE([.%Win_Rate], DimFecha[Fase] = "antes")` |  |
| `.%Win_Rate_Despues` | FactOportunidad | `CALCULATE([.%Win_Rate], DimFecha[Fase] = "despues")` |  |

## 06. Pipeline

| Medida | Tabla | Fórmula DAX | Descripción |
|---|---|---|---|
| `.Monto_Pipeline` | FactOportunidad | `SUM(FactOportunidad[Monto])` |  |
| `.Pipeline_Coverage` | FactOportunidad | `DIVIDE([.Monto_Pipeline], [.Cuota])` | Monto de oportunidades / cuota. Todas las oportunidades del archivo están cerradas: es una aproximación |
| `.%Zombie` | FactOportunidad | `DIVIDE(CALCULATE(COUNTROWS(FactOportunidad), FactOportunidad[Zombie] = 1), [.Oportunidades_Cerradas])` | Oportunidades con más de 180 días sin actividad |

## 07. Churn y cross-sell

| Medida | Tabla | Fórmula DAX | Descripción |
|---|---|---|---|
| `.Clientes_Activos_2023` | DimCliente | `CALCULATE(COUNTROWS(DimCliente), DimCliente[Compra2023] = 1)` |  |
| `.Clientes_Churn_2024` | DimCliente | `CALCULATE(COUNTROWS(DimCliente), DimCliente[Churn2024] = 1)` |  |
| `.%Churn` | DimCliente | `DIVIDE([.Clientes_Churn_2024], [.Clientes_Activos_2023])` | Clientes que compraron en 2023 y no compraron en 2024 / clientes activos en 2023. Meta <= 8 % |
| `.Clientes_Multicategoria` | FactVenta | `COUNTROWS(FILTER(VALUES(FactVenta[ClienteKey]), CALCULATE(DISTINCTCOUNT(DimProducto[Categoria])) > 1))` |  |
| `.%Cross_Sell` | FactVenta | `DIVIDE([.Clientes_Multicategoria], [.Clientes_Activos])` | Clientes que compran más de una categoría / clientes activos. Meta >= 35 % |

## 08. Margen bruto

| Medida | Tabla | Fórmula DAX | Descripción |
|---|---|---|---|
| `.%Margen_Bruto` | FactVenta | `DIVIDE([.Margen_Bruto], [.Ventas_Netas])` | Meta >= 26 % |
| `.Ventas_Margen_Negativo` | FactVenta | `CALCULATE([.Transacciones], FactVenta[MargenBruto] < 0)` | Ventas por debajo del costo |
| `.%Margen_Bruto_Antes` | FactVenta | `CALCULATE([.%Margen_Bruto], DimFecha[Fase] = "antes")` |  |
| `.%Margen_Bruto_Despues` | FactVenta | `CALCULATE([.%Margen_Bruto], DimFecha[Fase] = "despues")` |  |

## 09. Descuentos

| Medida | Tabla | Fórmula DAX | Descripción |
|---|---|---|---|
| `.%Descuento_Promedio` | FactVenta | `1 - DIVIDE([.Ventas_Netas], SUM(FactVenta[ImporteLista]))` | Descuento otorgado / precio de lista (ponderado por importe). Meta <= 9 % |
| `.%Descuento_Promedio_Antes` | FactVenta | `CALCULATE([.%Descuento_Promedio], DimFecha[Fase] = "antes")` |  |
| `.%Descuento_Promedio_Despues` | FactVenta | `CALCULATE([.%Descuento_Promedio], DimFecha[Fase] = "despues")` |  |
| `.%Descuento_Solicitado` | FactOportunidad | `AVERAGE(FactOportunidad[DescuentoSolicitado])` |  |
| `.%Fuera_Politica` | FactOportunidad | `DIVIDE(SUM(FactOportunidad[FueraPolitica]), [.Oportunidades_Cerradas])` |  |

## 10. Productividad

| Medida | Tabla | Fórmula DAX | Descripción |
|---|---|---|---|
| `.Productividad_Vendedor` | FactVenta | `DIVIDE([.Ventas_Netas], [.Vendedores_Activos])` | Ventas netas / vendedores |
| `.Productividad_Anual` | FactVenta | `DIVIDE([.Productividad_Vendedor] * 12, [.Meses])` | Ventas por vendedor llevadas a 12 meses. Meta >= USD 1,6M |

## 11. CAC y LTV

| Medida | Tabla | Fórmula DAX | Descripción |
|---|---|---|---|
| `.LTV_Margen_por_Cliente` | FactVenta | `DIVIDE([.Margen_Bruto], [.Clientes_Activos])` | Margen bruto acumulado por cliente activo (aproximación de LTV) |
| `.LTV_CAC` | FactVenta | `DIVIDE([.LTV_Margen_por_Cliente], CALCULATE([.CAC_Marketing], ALL(FactMarketing[CanalDigital])))` | Aproximación: margen por cliente / CAC de marketing. Meta >= 3,0x |
| `.Inversion_Marketing` | FactMarketing | `SUM(FactMarketing[Inversion])` |  |
| `.Leads` | FactMarketing | `SUM(FactMarketing[Leads])` |  |
| `.Nuevos_Clientes` | FactMarketing | `SUM(FactMarketing[NuevosClientes])` |  |
| `.CAC_Marketing` | FactMarketing | `DIVIDE([.Inversion_Marketing], [.Nuevos_Clientes])` | Solo inversión de marketing (el archivo no trae comisiones ni costo de venta directa). Meta <= USD 380 |
| `.Costo_por_Lead` | FactMarketing | `DIVIDE([.Inversion_Marketing], [.Leads])` |  |

## 12. NPS y soporte

| Medida | Tabla | Fórmula DAX | Descripción |
|---|---|---|---|
| `.Encuestas` | FactEncuesta | `COUNTROWS(FactEncuesta)` |  |
| `.NPS` | FactEncuesta | `AVERAGE(FactEncuesta[NPS])` | Promedio del puntaje NPS de cada medición. Meta >= 50 |
| `.CSAT` | FactEncuesta | `AVERAGE(FactEncuesta[CSAT])` |  |
| `.NPS_Antes` | FactEncuesta | `CALCULATE([.NPS], DimFecha[Fase] = "antes")` |  |
| `.NPS_Despues` | FactEncuesta | `CALCULATE([.NPS], DimFecha[Fase] = "despues")` |  |
| `.Tickets_Soporte` | FactTicketSoporte | `COUNTROWS(FactTicketSoporte)` |  |
| `.Horas_Resolucion` | FactTicketSoporte | `AVERAGE(FactTicketSoporte[HorasResolucion])` |  |
| `.%SLA_Cumplido` | FactTicketSoporte | `DIVIDE(SUM(FactTicketSoporte[SlaRecalculado]), [.Tickets_Soporte])` | Tickets resueltos en 24 horas o menos |

## 13. Inside sales (call center)

| Medida | Tabla | Fórmula DAX | Descripción |
|---|---|---|---|
| `.Llamadas` | FactLlamada | `COUNTROWS(FactLlamada)` |  |
| `.%Llamadas_con_Venta` | FactLlamada | `DIVIDE(SUM(FactLlamada[EsVenta]), [.Llamadas])` |  |
| `.%Contactadas` | FactLlamada | `DIVIDE(CALCULATE([.Llamadas], FactLlamada[Disposicion] <> "No contactado"), [.Llamadas])` |  |

## 99. Calidad de datos

| Medida | Tabla | Fórmula DAX | Descripción |
|---|---|---|---|
| `.Clientes_Posible_Duplicado` | DimCliente | `SUM(DimCliente[PosibleDuplicado])` |  |
| `.Clientes_Alta_Posterior_Compra` | DimCliente | `SUM(DimCliente[AltaPosteriorACompra])` |  |
| `.Vendedores_Ingreso_Posterior_Venta` | DimVendedor | `SUM(DimVendedor[IngresoPosteriorAVenta])` |  |
| `.Ventas_Neta_Recalculada` | FactVenta | `SUM(FactVenta[VentaNetaRecalculada])` | Ventas cuyo importe venía vacío en el archivo y se recalculó |
| `.Ventas_Margen_Recalculado` | FactVenta | `SUM(FactVenta[MargenRecalculado])` |  |
| `.Ciclos_Corregidos` | FactOportunidad | `SUM(FactOportunidad[CicloCorregido])` | ciclo_venta_dias del archivo no coincidía con cierre - creación |
| `.Llamadas_Inconsistentes` | FactLlamada | `SUM(FactLlamada[EsVentaInconsistente])` | es_venta = 1 con disposición 'No contactado' o 'Rechazo' |
