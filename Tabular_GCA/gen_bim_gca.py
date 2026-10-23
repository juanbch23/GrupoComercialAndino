"""Genera Model.bim (compatibilidad 1200, como pide 'Cubos Tabulares y Pbi.pdf') del cubo Grupo Comercial Andino.

Origen : LAPTOP-IO596P6A\\DEV -> DWH_GCA (modelo estrella cargado y limpiado por SSIS)
Uso    : python gen_bim_gca.py Model.bim
Medidas: una carpeta por indicador crítico del caso (Indicadores_Criticos_GCA.docx) + calidad de datos.
"""
import json, sys

OUT = sys.argv[1] if len(sys.argv) > 1 else "Model.bim"
SERVER = r"LAPTOP-IO596P6A\DEV"
DS = "DWH_GCA"

MONEY = "#,0.00"
INT = "#,0"
DEC = "#,0.00"
PCT = "0.0 %;-0.0 %;0.0 %"
X = '0.0"x"'

def col(name, dtype, **o):
    c = {"name": name, "dataType": dtype, "sourceColumn": o.get("src", name)}
    if o.get("hidden"): c["isHidden"] = True
    if o.get("sort"): c["sortByColumn"] = o["sort"]
    if o.get("fmt"): c["formatString"] = o["fmt"]
    if o.get("key"): c["isKey"] = True
    if o.get("desc"): c["description"] = o["desc"]
    return c

K = lambda n: col(n, "int64", hidden=True)        # llaves ocultas

# ------------------------------------------------------------------ tablas (nombre, consulta, columnas)
TABLES = [
    ("DimFecha",
     """SELECT [FechaKey], CAST([Fecha] AS DATETIME) AS [Fecha], [Anio], [Mes], [NombreMes], [Trimestre], [DiaSemana],
       [NombreDia], CAST([EsFinSemana] AS INT) AS [EsFinSemana], [Periodo], [Fase], [AnioMes],
       LEFT([NombreMes], 3) + '-' + CAST([Anio] AS VARCHAR(4)) AS [MesAnio]
  FROM [GENERICO].[DimFecha] WHERE [FechaKey] > 0""",
     [K("FechaKey"), col("Fecha", "dateTime", key=True, fmt="dd/MM/yyyy"), col("Anio", "int64", fmt="0"),
      col("Mes", "int64", hidden=True), col("NombreMes", "string", sort="Mes"), col("Trimestre", "int64"),
      col("DiaSemana", "int64", hidden=True), col("NombreDia", "string", sort="DiaSemana"),
      col("EsFinSemana", "int64", desc="1 = sábado o domingo"), col("Periodo", "string"),
      col("Fase", "string", desc="antes = ene-jun 2023 (situación anterior); despues = jul-2023 a dic-2024 (situación actual del caso)"),
      col("AnioMes", "int64", hidden=True), col("MesAnio", "string", sort="AnioMes")]),
    ("DimCliente",
     """SELECT [ClienteKey], [ClienteID], [Nombre], [Tipo], [Segmento], [Pais], CAST([FechaAlta] AS DATETIME) AS [FechaAlta],
       [Contrato], [Ejecutivo], [CanalOrigen], CAST([PosibleDuplicado] AS INT) AS [PosibleDuplicado],
       CAST([FechaAltaFutura] AS INT) AS [FechaAltaFutura], CAST([AltaPosteriorACompra] AS INT) AS [AltaPosteriorACompra],
       CAST([FechaPrimeraCompra] AS DATETIME) AS [FechaPrimeraCompra], CAST([FechaUltimaCompra] AS DATETIME) AS [FechaUltimaCompra],
       CAST([Compra2023] AS INT) AS [Compra2023], CAST([Compra2024] AS INT) AS [Compra2024], CAST([Churn2024] AS INT) AS [Churn2024]
  FROM [Comercial].[vw_DimCliente]""",
     [K("ClienteKey"), col("ClienteID", "string"), col("Nombre", "string"), col("Tipo", "string", desc="B2B / B2C"),
      col("Segmento", "string"), col("Pais", "string"), col("FechaAlta", "dateTime", fmt="dd/MM/yyyy", desc="Fecha del archivo (no confiable)"),
      col("Contrato", "string"), col("Ejecutivo", "string"), col("CanalOrigen", "string"),
      col("PosibleDuplicado", "int64", desc="1 = mismo nombre y país que otro cliente_id"),
      col("FechaAltaFutura", "int64", hidden=True), col("AltaPosteriorACompra", "int64", hidden=True),
      col("FechaPrimeraCompra", "dateTime", fmt="dd/MM/yyyy"), col("FechaUltimaCompra", "dateTime", fmt="dd/MM/yyyy"),
      col("Compra2023", "int64", hidden=True), col("Compra2024", "int64", hidden=True), col("Churn2024", "int64", hidden=True)]),
    ("DimProducto",
     """SELECT [ProductoKey], [ProductoID], [Categoria], [CostoUnitario], [PrecioLista], [MargenObjetivo]
  FROM [Comercial].[DimProducto] WHERE [ProductoKey] > 0""",
     [K("ProductoKey"), col("ProductoID", "string"), col("Categoria", "string"),
      col("CostoUnitario", "decimal", fmt=MONEY, hidden=True), col("PrecioLista", "decimal", fmt=MONEY, hidden=True),
      col("MargenObjetivo", "decimal", fmt=PCT, hidden=True)]),
    ("DimVendedor",
     """SELECT [VendedorKey], [VendedorID], [Nombre], [Canal] AS [CanalVendedor], [Region] AS [RegionVendedor], [GerenteID],
       [Antiguedad], [CuotaAnual], CAST([FechaIngreso] AS DATETIME) AS [FechaIngreso],
       CAST([IngresoPosteriorAVenta] AS INT) AS [IngresoPosteriorAVenta]
  FROM [Comercial].[vw_DimVendedor]""",
     [K("VendedorKey"), col("VendedorID", "string"), col("Nombre", "string"), col("CanalVendedor", "string"),
      col("RegionVendedor", "string"), col("GerenteID", "string"), col("Antiguedad", "string"),
      col("CuotaAnual", "decimal", fmt=MONEY, hidden=True), col("FechaIngreso", "dateTime", fmt="dd/MM/yyyy"),
      col("IngresoPosteriorAVenta", "int64", hidden=True)]),
    ("DimCanal",
     "SELECT [CanalKey], [Canal] FROM [Comercial].[DimCanal] WHERE [CanalKey] > 0",
     [K("CanalKey"), col("Canal", "string")]),
    ("DimRegion",
     "SELECT [RegionKey], [Region], [Pais] FROM [Comercial].[DimRegion] WHERE [RegionKey] > 0",
     [K("RegionKey"), col("Region", "string"), col("Pais", "string")]),
    ("FactVenta",
     """SELECT [VentaID], [OportunidadID], [FechaKey], [ClienteKey], [VendedorKey], [ProductoKey], [CanalKey], [RegionKey],
       [Cantidad], [PrecioLista], [Descuento], [PrecioUnitarioNeto], [VentaNeta], [CostoTotal], [MargenBruto], [MargenPct],
       CAST([Cantidad] * [PrecioLista] AS DECIMAL(18,2)) AS [ImporteLista],
       CAST([VentaNetaRecalculada] AS INT) AS [VentaNetaRecalculada], CAST([MargenRecalculado] AS INT) AS [MargenRecalculado]
  FROM [Comercial].[FactVenta]""",
     [col("VentaID", "string"), col("OportunidadID", "string", hidden=True)] +
     [K(k) for k in ("FechaKey", "ClienteKey", "VendedorKey", "ProductoKey", "CanalKey", "RegionKey")] +
     [col(c, "decimal", fmt=MONEY, hidden=True) for c in ("PrecioLista", "PrecioUnitarioNeto", "VentaNeta", "CostoTotal",
                                                          "MargenBruto", "ImporteLista")] +
     [col("Cantidad", "int64", hidden=True), col("Descuento", "decimal", fmt=PCT, hidden=True),
      col("MargenPct", "decimal", fmt=PCT, hidden=True),
      col("VentaNetaRecalculada", "int64", hidden=True), col("MargenRecalculado", "int64", hidden=True)]),
    ("FactOportunidad",
     """SELECT [OportunidadID], [FechaCreacionKey], [FechaCierreKey], [ClienteKey], [VendedorKey], [CanalKey], [RegionKey],
       [GerenteID], [Etapa], [Resultado], CAST([Facturada] AS INT) AS [Facturada], [MotivoPerdida], [Monto],
       [DescuentoSolicitado], CAST([FueraPolitica] AS INT) AS [FueraPolitica], [Touchpoints],
       CAST([TieneDemoTecnica] AS INT) AS [TieneDemoTecnica],
       CASE WHEN [TieneDemoTecnica] = 1 THEN 'Con demo' ELSE 'Sin demo' END AS [DemoTecnica],
       CASE WHEN [Touchpoints] > 3 THEN 'Más de 3' WHEN [Touchpoints] = 1 THEN '1' ELSE '2 a 3' END AS [GrupoTouchpoints],
       [CicloVentaDias], [CicloVentaOrigen], CAST([CicloCorregido] AS INT) AS [CicloCorregido],
       [DiasSinActividad], CAST([Zombie] AS INT) AS [Zombie]
  FROM [Comercial].[FactOportunidad]""",
     [col("OportunidadID", "string")] +
     [K(k) for k in ("FechaCreacionKey", "FechaCierreKey", "ClienteKey", "VendedorKey", "CanalKey", "RegionKey")] +
     [col("GerenteID", "string"), col("Etapa", "string"), col("Resultado", "string"), col("Facturada", "int64", hidden=True),
      col("MotivoPerdida", "string"), col("Monto", "decimal", fmt=MONEY, hidden=True),
      col("DescuentoSolicitado", "decimal", fmt=PCT, hidden=True), col("FueraPolitica", "int64", hidden=True),
      col("Touchpoints", "int64"), col("TieneDemoTecnica", "int64", hidden=True), col("DemoTecnica", "string"),
      col("GrupoTouchpoints", "string"), col("CicloVentaDias", "int64", hidden=True),
      col("CicloVentaOrigen", "int64", hidden=True), col("CicloCorregido", "int64", hidden=True),
      col("DiasSinActividad", "int64", hidden=True), col("Zombie", "int64", hidden=True)]),
    ("FactLlamada",
     """SELECT [LlamadaID], [FechaKey], [VendedorKey], [ClienteKey], [DuracionSeg], [Disposicion],
       CAST([EsVenta] AS INT) AS [EsVenta], CAST([EsVentaInconsistente] AS INT) AS [EsVentaInconsistente]
  FROM [Comercial].[FactLlamada]""",
     [col("LlamadaID", "string", hidden=True), K("FechaKey"), K("VendedorKey"), K("ClienteKey"),
      col("DuracionSeg", "int64", hidden=True), col("Disposicion", "string"), col("EsVenta", "int64", hidden=True),
      col("EsVentaInconsistente", "int64", hidden=True)]),
    ("FactCarrito",
     """SELECT [CarritoID], [FechaKey], [ClienteKey], [Monto], [PasoAbandono], CAST([Recuperado] AS INT) AS [Recuperado]
  FROM [Comercial].[FactCarrito]""",
     [col("CarritoID", "string", hidden=True), K("FechaKey"), K("ClienteKey"), col("Monto", "decimal", fmt=MONEY, hidden=True),
      col("PasoAbandono", "string"), col("Recuperado", "int64", hidden=True)]),
    ("FactSesion",
     """SELECT [FechaKey], [CanalDigital], [Dispositivo], [Sesiones], [AddToCart], [CheckoutIniciado], [Ordenes],
       [TicketPromedio], [VentaTotal]
  FROM [Comercial].[FactSesion]""",
     [K("FechaKey"), col("CanalDigital", "string"), col("Dispositivo", "string")] +
     [col(c, "int64", hidden=True) for c in ("Sesiones", "AddToCart", "CheckoutIniciado", "Ordenes")] +
     [col("TicketPromedio", "decimal", fmt=MONEY, hidden=True), col("VentaTotal", "decimal", fmt=MONEY, hidden=True)]),
    ("FactEncuesta",
     """SELECT [EncuestaID], [FechaKey], [ClienteKey], [Momento], [NPS], [CSAT] FROM [Comercial].[FactEncuesta]""",
     [col("EncuestaID", "string", hidden=True), K("FechaKey"), K("ClienteKey"), col("Momento", "string"),
      col("NPS", "int64", hidden=True), col("CSAT", "decimal", fmt=DEC, hidden=True)]),
    ("FactMarketing",
     """SELECT [FechaKey], [CanalDigital], [Campana], [Inversion], [Leads], [NuevosClientes] FROM [Comercial].[FactMarketing]""",
     [K("FechaKey"), col("CanalDigital", "string"), col("Campana", "string"), col("Inversion", "decimal", fmt=MONEY, hidden=True),
      col("Leads", "int64", hidden=True), col("NuevosClientes", "int64", hidden=True)]),
    ("FactTicketSoporte",
     """SELECT [TicketID], [ClienteKey], [FechaAperturaKey], [FechaCierre], [HorasResolucion], [Categoria],
       CAST([SlaCumplido] AS INT) AS [SlaCumplido], CAST([SlaRecalculado] AS INT) AS [SlaRecalculado]
  FROM [Comercial].[FactTicketSoporte]""",
     [col("TicketID", "string", hidden=True), K("ClienteKey"), K("FechaAperturaKey"),
      col("FechaCierre", "dateTime", fmt="dd/MM/yyyy HH:mm", desc="Reconstruida: apertura + horas de resolución"),
      col("HorasResolucion", "decimal", fmt=DEC, hidden=True), col("Categoria", "string"),
      col("SlaCumplido", "int64", hidden=True), col("SlaRecalculado", "int64", hidden=True)]),
    ("FactCuota",
     "SELECT [VendedorKey], [FechaKey], [CuotaMensual] FROM [Comercial].[vw_FactCuota]",
     [K("VendedorKey"), K("FechaKey"), col("CuotaMensual", "decimal", fmt=MONEY, hidden=True)]),
]

# ------------------------------------------------------------------ medidas
M = []
def m(table, name, expr, fmt=None, folder=None, desc=None):
    d = {"name": name, "expression": expr.strip()}
    if fmt: d["formatString"] = fmt
    if folder: d["displayFolder"] = folder
    if desc: d["description"] = desc
    M.append((table, d))

ANTES = 'DimFecha[Fase] = "antes"'
DESPUES = 'DimFecha[Fase] = "despues"'
def fases(table, base, fmt, folder):
    """Versión 'Antes' y 'Después' de un indicador (el caso compara situación anterior vs actual)."""
    m(table, base + "_Antes", f"CALCULATE([{base}], {ANTES})", fmt, folder)
    m(table, base + "_Despues", f"CALCULATE([{base}], {DESPUES})", fmt, folder)

# 0. Base de ventas
F = "00. Ventas base"
m("FactVenta", ".Ventas_Netas", "SUM(FactVenta[VentaNeta])", MONEY, F, "Venta neta recalculada (cantidad x precio unitario neto)")
m("FactVenta", ".Costo_Total", "SUM(FactVenta[CostoTotal])", MONEY, F)
m("FactVenta", ".Margen_Bruto", "SUM(FactVenta[MargenBruto])", MONEY, F, "Ventas netas - costo")
m("FactVenta", ".Transacciones", "COUNTROWS(FactVenta)", INT, F)
m("FactVenta", ".Unidades", "SUM(FactVenta[Cantidad])", INT, F)
m("FactVenta", ".Clientes_Activos", "DISTINCTCOUNT(FactVenta[ClienteKey])", INT, F)
m("FactVenta", ".Vendedores_Activos", "DISTINCTCOUNT(FactVenta[VendedorKey])", INT, F)
m("FactVenta", ".Meses", "DISTINCTCOUNT(DimFecha[AnioMes])", INT, F)

# 3.1 Cumplimiento de cuota
F = "01. Cumplimiento de cuota"
m("FactCuota", ".Cuota", """
IF(ISFILTERED(DimCanal[Canal]),
   -- la cuota es del vendedor: al filtrar por canal se toman los vendedores de ese canal
   CALCULATE(SUM(FactCuota[CuotaMensual]), TREATAS(VALUES(DimCanal[Canal]), DimVendedor[CanalVendedor])),
   SUM(FactCuota[CuotaMensual]))""", MONEY, F, "Cuota anual del vendedor repartida en 12 meses")
m("FactVenta", ".%Cumplimiento_Cuota", "DIVIDE([.Ventas_Netas], [.Cuota])", PCT, F, "Meta >= 95 %")
fases("FactVenta", ".%Cumplimiento_Cuota", PCT, F)

# 3.2 Ticket promedio
F = "02. Ticket promedio"
m("FactVenta", ".Ticket_Promedio", "DIVIDE([.Ventas_Netas], [.Transacciones])", MONEY, F)
m("FactVenta", ".Ticket_B2B", 'CALCULATE([.Ticket_Promedio], DimCliente[Tipo] = "B2B")', MONEY, F, "Meta >= USD 4.000")
m("FactVenta", ".Ticket_B2C", 'CALCULATE([.Ticket_Promedio], DimCliente[Tipo] = "B2C")', MONEY, F, "Meta >= USD 85")
fases("FactVenta", ".Ticket_B2B", MONEY, F)

# 3.3 Conversión e-commerce
F = "03. Conversión e-commerce"
m("FactSesion", ".Sesiones", "SUM(FactSesion[Sesiones])", INT, F)
m("FactSesion", ".Ordenes", "SUM(FactSesion[Ordenes])", INT, F)
m("FactSesion", ".%Conversion_Ecommerce", "DIVIDE([.Ordenes], [.Sesiones])", "0.00 %", F, "Meta >= 3,0 %")
m("FactSesion", ".%Add_to_Cart", "DIVIDE(SUM(FactSesion[AddToCart]), [.Sesiones])", "0.00 %", F)
m("FactSesion", ".%Checkout_Iniciado", "DIVIDE(SUM(FactSesion[CheckoutIniciado]), [.Sesiones])", "0.00 %", F)
m("FactSesion", ".Venta_Ecommerce", "SUM(FactSesion[VentaTotal])", MONEY, F)
fases("FactSesion", ".%Conversion_Ecommerce", "0.00 %", F)
m("FactCarrito", ".Carritos_Abandonados", "COUNTROWS(FactCarrito)", INT, F)
m("FactCarrito", ".Monto_Abandonado", "SUM(FactCarrito[Monto])", MONEY, F)
m("FactCarrito", ".%Carritos_Recuperados", "DIVIDE(SUM(FactCarrito[Recuperado]), [.Carritos_Abandonados])", PCT, F)

# 3.4 Ciclo de venta
F = "04. Ciclo de venta"
m("FactOportunidad", ".Ciclo_Venta_Dias", 'CALCULATE(AVERAGE(FactOportunidad[CicloVentaDias]), FactOportunidad[Facturada] = 1)',
  "#,0.0", F, "Días de creación a cierre de las oportunidades ganadas (facturadas). Meta <= 50")
fases("FactOportunidad", ".Ciclo_Venta_Dias", "#,0.0", F)

# 3.5 Win rate  /  3.16 Ventas perdidas
F = "05. Win rate y pérdidas"
m("FactOportunidad", ".Oportunidades_Cerradas", "COUNTROWS(FactOportunidad)", INT, F)
m("FactOportunidad", ".Oportunidades_Ganadas", "CALCULATE(COUNTROWS(FactOportunidad), FactOportunidad[Facturada] = 1)", INT, F,
  "Regla del caso: ganada solo si está facturada")
m("FactOportunidad", ".Oportunidades_Perdidas", "[.Oportunidades_Cerradas] - [.Oportunidades_Ganadas]", INT, F)
m("FactOportunidad", ".%Win_Rate", "DIVIDE([.Oportunidades_Ganadas], [.Oportunidades_Cerradas])", PCT, F, "Meta >= 35 %")
m("FactOportunidad", ".%Perdidas", "DIVIDE([.Oportunidades_Perdidas], [.Oportunidades_Cerradas])", PCT, F, "Meta <= 65 %")
m("FactOportunidad", ".%Motivo_Perdida", """
DIVIDE([.Oportunidades_Perdidas],
       CALCULATE([.Oportunidades_Perdidas], ALLSELECTED(FactOportunidad[MotivoPerdida])))""", PCT, F,
  "Participación de cada motivo sobre las oportunidades perdidas")
fases("FactOportunidad", ".%Win_Rate", PCT, F)

# 3.6 Pipeline
F = "06. Pipeline"
m("FactOportunidad", ".Monto_Pipeline", "SUM(FactOportunidad[Monto])", MONEY, F)
m("FactOportunidad", ".Pipeline_Coverage", "DIVIDE([.Monto_Pipeline], [.Cuota])", X, F,
  "Monto de oportunidades / cuota. Todas las oportunidades del archivo están cerradas: es una aproximación")
m("FactOportunidad", ".%Zombie", "DIVIDE(CALCULATE(COUNTROWS(FactOportunidad), FactOportunidad[Zombie] = 1), [.Oportunidades_Cerradas])",
  PCT, F, "Oportunidades con más de 180 días sin actividad")

# 3.7 Churn  /  3.15 Cross-sell
F = "07. Churn y cross-sell"
m("DimCliente", ".Clientes_Activos_2023", "CALCULATE(COUNTROWS(DimCliente), DimCliente[Compra2023] = 1)", INT, F)
m("DimCliente", ".Clientes_Churn_2024", "CALCULATE(COUNTROWS(DimCliente), DimCliente[Churn2024] = 1)", INT, F)
m("DimCliente", ".%Churn", "DIVIDE([.Clientes_Churn_2024], [.Clientes_Activos_2023])", PCT, F,
  "Clientes que compraron en 2023 y no compraron en 2024 / clientes activos en 2023. Meta <= 8 %")
m("FactVenta", ".Clientes_Multicategoria", """
COUNTROWS(FILTER(VALUES(FactVenta[ClienteKey]), CALCULATE(DISTINCTCOUNT(DimProducto[Categoria])) > 1))""", INT, F)
m("FactVenta", ".%Cross_Sell", "DIVIDE([.Clientes_Multicategoria], [.Clientes_Activos])", PCT, F,
  "Clientes que compran más de una categoría / clientes activos. Meta >= 35 %")

# 3.8 Margen
F = "08. Margen bruto"
m("FactVenta", ".%Margen_Bruto", "DIVIDE([.Margen_Bruto], [.Ventas_Netas])", PCT, F, "Meta >= 26 %")
m("FactVenta", ".Ventas_Margen_Negativo", "CALCULATE([.Transacciones], FactVenta[MargenBruto] < 0)", INT, F,
  "Ventas por debajo del costo")
fases("FactVenta", ".%Margen_Bruto", PCT, F)

# 3.9 Descuentos
F = "09. Descuentos"
m("FactVenta", ".%Descuento_Promedio", "1 - DIVIDE([.Ventas_Netas], SUM(FactVenta[ImporteLista]))", PCT, F,
  "Descuento otorgado / precio de lista (ponderado por importe). Meta <= 9 %")
m("FactOportunidad", ".%Descuento_Solicitado", "AVERAGE(FactOportunidad[DescuentoSolicitado])", PCT, F)
m("FactOportunidad", ".%Fuera_Politica", "DIVIDE(SUM(FactOportunidad[FueraPolitica]), [.Oportunidades_Cerradas])", PCT, F)
fases("FactVenta", ".%Descuento_Promedio", PCT, F)

# 3.10 Productividad
F = "10. Productividad"
m("FactVenta", ".Productividad_Vendedor", "DIVIDE([.Ventas_Netas], [.Vendedores_Activos])", MONEY, F, "Ventas netas / vendedores")
m("FactVenta", ".Productividad_Anual", "DIVIDE([.Productividad_Vendedor] * 12, [.Meses])", MONEY, F,
  "Ventas por vendedor llevadas a 12 meses. Meta >= USD 1,6M")

# 3.11 CAC  /  3.12 LTV/CAC
F = "11. CAC y LTV"
m("FactMarketing", ".Inversion_Marketing", "SUM(FactMarketing[Inversion])", MONEY, F)
m("FactMarketing", ".Leads", "SUM(FactMarketing[Leads])", INT, F)
m("FactMarketing", ".Nuevos_Clientes", "SUM(FactMarketing[NuevosClientes])", INT, F)
m("FactMarketing", ".CAC_Marketing", "DIVIDE([.Inversion_Marketing], [.Nuevos_Clientes])", MONEY, F,
  "Solo inversión de marketing (el archivo no trae comisiones ni costo de venta directa). Meta <= USD 380")
m("FactMarketing", ".Costo_por_Lead", "DIVIDE([.Inversion_Marketing], [.Leads])", MONEY, F)
m("FactVenta", ".LTV_Margen_por_Cliente", "DIVIDE([.Margen_Bruto], [.Clientes_Activos])", MONEY, F,
  "Margen bruto acumulado por cliente activo (aproximación de LTV)")
m("FactVenta", ".LTV_CAC", "DIVIDE([.LTV_Margen_por_Cliente], CALCULATE([.CAC_Marketing], ALL(FactMarketing[CanalDigital])))", X, F,
  "Aproximación: margen por cliente / CAC de marketing. Meta >= 3,0x")

# 3.14 NPS / CSAT
F = "12. NPS y soporte"
m("FactEncuesta", ".Encuestas", "COUNTROWS(FactEncuesta)", INT, F)
m("FactEncuesta", ".NPS", "AVERAGE(FactEncuesta[NPS])", "0.0", F, "Promedio del puntaje NPS de cada medición. Meta >= 50")
m("FactEncuesta", ".CSAT", "AVERAGE(FactEncuesta[CSAT])", "0.00", F)
fases("FactEncuesta", ".NPS", "0.0", F)
m("FactTicketSoporte", ".Tickets_Soporte", "COUNTROWS(FactTicketSoporte)", INT, F)
m("FactTicketSoporte", ".Horas_Resolucion", "AVERAGE(FactTicketSoporte[HorasResolucion])", "0.0", F)
m("FactTicketSoporte", ".%SLA_Cumplido", "DIVIDE(SUM(FactTicketSoporte[SlaRecalculado]), [.Tickets_Soporte])", PCT, F,
  "Tickets resueltos en 24 horas o menos")

# Call center
F = "13. Inside sales (call center)"
m("FactLlamada", ".Llamadas", "COUNTROWS(FactLlamada)", INT, F)
m("FactLlamada", ".%Llamadas_con_Venta", "DIVIDE(SUM(FactLlamada[EsVenta]), [.Llamadas])", PCT, F)
m("FactLlamada", ".%Contactadas", 'DIVIDE(CALCULATE([.Llamadas], FactLlamada[Disposicion] <> "No contactado"), [.Llamadas])', PCT, F)

# Calidad de datos (para mostrar "cómo quedó" la limpieza)
F = "99. Calidad de datos"
m("FactVenta", ".Ventas_Neta_Recalculada", "SUM(FactVenta[VentaNetaRecalculada])", INT, F,
  "Ventas cuyo importe venía vacío en el archivo y se recalculó")
m("FactVenta", ".Ventas_Margen_Recalculado", "SUM(FactVenta[MargenRecalculado])", INT, F)
m("FactOportunidad", ".Ciclos_Corregidos", "SUM(FactOportunidad[CicloCorregido])", INT, F,
  "ciclo_venta_dias del archivo no coincidía con cierre - creación")
m("FactLlamada", ".Llamadas_Inconsistentes", "SUM(FactLlamada[EsVentaInconsistente])", INT, F,
  "es_venta = 1 con disposición 'No contactado' o 'Rechazo'")
m("DimCliente", ".Clientes_Posible_Duplicado", "SUM(DimCliente[PosibleDuplicado])", INT, F)
m("DimCliente", ".Clientes_Alta_Posterior_Compra", "SUM(DimCliente[AltaPosteriorACompra])", INT, F)
m("DimVendedor", ".Vendedores_Ingreso_Posterior_Venta", "SUM(DimVendedor[IngresoPosteriorAVenta])", INT, F)

# ------------------------------------------------------------------ ensamblado
tables = []
for name, query, cols in TABLES:
    t = {"name": name, "columns": cols,
         "partitions": [{"name": name, "dataView": "full", "source": {"query": query, "dataSource": DS}}]}
    if name == "DimFecha":
        t["dataCategory"] = "Time"
    ms = [d for tb, d in M if tb == name]
    if ms:
        t["measures"] = ms
    tables.append(t)

def rel(name, ft, fc, tt, tc, active=True):
    r = {"name": name, "fromTable": ft, "fromColumn": fc, "toTable": tt, "toColumn": tc}
    if not active:
        r["isActive"] = False
    return r

relationships = [
    rel("FV_Fecha", "FactVenta", "FechaKey", "DimFecha", "FechaKey"),
    rel("FV_Cliente", "FactVenta", "ClienteKey", "DimCliente", "ClienteKey"),
    rel("FV_Vendedor", "FactVenta", "VendedorKey", "DimVendedor", "VendedorKey"),
    rel("FV_Producto", "FactVenta", "ProductoKey", "DimProducto", "ProductoKey"),
    rel("FV_Canal", "FactVenta", "CanalKey", "DimCanal", "CanalKey"),
    rel("FV_Region", "FactVenta", "RegionKey", "DimRegion", "RegionKey"),
    rel("FO_FechaCierre", "FactOportunidad", "FechaCierreKey", "DimFecha", "FechaKey"),
    rel("FO_FechaCreacion", "FactOportunidad", "FechaCreacionKey", "DimFecha", "FechaKey", active=False),
    rel("FO_Cliente", "FactOportunidad", "ClienteKey", "DimCliente", "ClienteKey"),
    rel("FO_Vendedor", "FactOportunidad", "VendedorKey", "DimVendedor", "VendedorKey"),
    rel("FO_Canal", "FactOportunidad", "CanalKey", "DimCanal", "CanalKey"),
    rel("FO_Region", "FactOportunidad", "RegionKey", "DimRegion", "RegionKey"),
    rel("FL_Fecha", "FactLlamada", "FechaKey", "DimFecha", "FechaKey"),
    rel("FL_Vendedor", "FactLlamada", "VendedorKey", "DimVendedor", "VendedorKey"),
    rel("FL_Cliente", "FactLlamada", "ClienteKey", "DimCliente", "ClienteKey"),
    rel("FC_Fecha", "FactCarrito", "FechaKey", "DimFecha", "FechaKey"),
    rel("FC_Cliente", "FactCarrito", "ClienteKey", "DimCliente", "ClienteKey"),
    rel("FS_Fecha", "FactSesion", "FechaKey", "DimFecha", "FechaKey"),
    rel("FE_Fecha", "FactEncuesta", "FechaKey", "DimFecha", "FechaKey"),
    rel("FE_Cliente", "FactEncuesta", "ClienteKey", "DimCliente", "ClienteKey"),
    rel("FM_Fecha", "FactMarketing", "FechaKey", "DimFecha", "FechaKey"),
    rel("FT_Fecha", "FactTicketSoporte", "FechaAperturaKey", "DimFecha", "FechaKey"),
    rel("FT_Cliente", "FactTicketSoporte", "ClienteKey", "DimCliente", "ClienteKey"),
    rel("FQ_Fecha", "FactCuota", "FechaKey", "DimFecha", "FechaKey"),
    rel("FQ_Vendedor", "FactCuota", "VendedorKey", "DimVendedor", "VendedorKey"),
]

bim = {
    "name": "SemanticModel",
    "compatibilityLevel": 1200,
    "model": {
        "culture": "es-ES",
        "dataSources": [{
            "name": DS,
            "connectionString": f"Provider=MSOLEDBSQL.1;Data Source={SERVER};Initial Catalog={DS};"
                                "Integrated Security=SSPI;Persist Security Info=false",
            "impersonationMode": "impersonateServiceAccount",
            "annotations": [{"name": "ConnectionEditUISource", "value": "SqlServer"}],
        }],
        "tables": tables,
        "relationships": relationships,
        "annotations": [{"name": "ClientCompatibilityLevel", "value": "400"}],
    },
    "id": "SemanticModel",
}
with open(OUT, "w", encoding="utf-8") as f:
    json.dump(bim, f, ensure_ascii=False, indent=2)
print("OK", OUT, "tablas:", len(tables), "medidas:", len(M), "relaciones:", len(relationships))
