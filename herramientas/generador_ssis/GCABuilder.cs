using System;
using System.Collections.Generic;
using System.Linq;
using Microsoft.SqlServer.Dts.Runtime;
using Microsoft.SqlServer.Dts.Pipeline.Wrapper;
using Microsoft.SqlServer.Dts.Tasks.ExecuteSQLTask;
using Wrap = Microsoft.SqlServer.Dts.Runtime.Wrapper;

// Generador de los proyectos SSIS stage_GCA y DWH_GCA (plantilla del laboratorio, igual que H&M).
public class GCABuilder
{
    public const string Server = @"LAPTOP-IO596P6A\DEV";
    const string AdoType = "ADO.NET:System.Data.SqlClient.SqlConnection, System.Data, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089";
    const int DbGuid = 9, DbInt32 = 11, DbString = 16, DbDateTime2 = 26;
    const string AuditConn = "AdoNet DWH_GCA";

    const string GetAuditSql =
@"INSERT INTO [DIM_AUDIT]
           ([TableName]
           ,[PkgName]
           ,[PkgGUID]
           ,[ExecStartDT]
           ,[ExecStopDT]
           ,[ExecutionInstanceGUID]
           ,[ExtractRowCnt]
           ,[TableInitialRowCnt]
           ,[TableFinalRowCnt]
           ,[SuccessfulProcessingInd])
     VALUES
           (@TableName
           ,@PkgName
           ,@PkgGUID
           ,@StartTime
           ,NULL
           ,@PkgExecGUID
           ,NULL
           ,@RowCount
           ,NULL
           ,'N')
SELECT CAST(SCOPE_IDENTITY() AS INT) AS AuditKey";

    const string UpdateAuditSql =
@"UPDATE [DIM_AUDIT]
SET ExecStopDT = SYSDATETIME()
 , ExtractRowCnt = @RowCount
 ,TableFinalRowCnt = @RowCount
 ,SuccessfulProcessingInd='Y'
WHERE AuditKey = @AuditKey;";

    const string MasterGetAuditSql =
@"INSERT INTO [DIM_AUDIT]
           ([TableName]
           ,[PkgName]
           ,[PkgGUID]
           ,[ExecStartDT]
           ,[ExecStopDT]
           ,[ExecutionInstanceGUID]
           ,[ExtractRowCnt]
           ,[TableInitialRowCnt]
           ,[TableFinalRowCnt]
           ,[SuccessfulProcessingInd])
     VALUES
           (@TableName
           ,@PkgName
           ,@PkgGUID
           ,@StartTime
           ,NULL
           ,@PkgExecGUID
           ,NULL
           ,NULL
           ,NULL
           ,'N')
SELECT CAST(SCOPE_IDENTITY() AS INT) AS AuditKey";

    const string MasterUpdateAuditSql =
@"UPDATE [DIM_AUDIT]
SET ExecStopDT = SYSDATETIME()
 ,SuccessfulProcessingInd='Y'
WHERE AuditKey = @AuditKey;";

    Project P;

    // ------------------------------------------------------------------ conexiones
    static string OleDbCs(string db) { return
        "Data Source=" + Server + ";Initial Catalog=" + db + ";Provider=MSOLEDBSQL19;Integrated Security=SSPI;Use Encryption for Data=Optional;Trust Server Certificate=True;Application Name=SSIS-GCA;Auto Translate=False;"; }
    static string AdoCs(string db) { return
        "Data Source=" + Server + ";Initial Catalog=" + db + ";Integrated Security=True;TrustServerCertificate=True;Application Name=SSIS-GCA;"; }

    ConnectionManager AddConn(string type, string name, string cs)
    {
        ConnectionManagerItem it = P.ConnectionManagerItems.Add(type, name + ".conmgr");
        ConnectionManager cm = it.ConnectionManager;
        cm.Name = name;
        cm.ConnectionString = cs;
        return cm;
    }

    // Todas las columnas como texto Unicode: el STAGE es copia fiel del archivo (UTF-8, CRLF)
    ConnectionManager AddFlatFile(string name, string subFolder, string file, string dataFolder, string[] cols, int[] widths)
    {
        ConnectionManagerItem it = P.ConnectionManagerItems.Add("FLATFILE", name + ".conmgr");
        ConnectionManager cm = it.ConnectionManager;
        cm.Name = name;
        cm.ConnectionString = dataFolder + "\\" + subFolder + "\\" + file;
        cm.Properties["Format"].SetValue(cm, "Delimited");
        cm.Properties["ColumnNamesInFirstDataRow"].SetValue(cm, true);
        cm.Properties["CodePage"].SetValue(cm, 65001);
        cm.Properties["Unicode"].SetValue(cm, false);
        cm.Properties["LocaleID"].SetValue(cm, 1033);
        cm.Properties["TextQualifier"].SetValue(cm, "\"");
        cm.Properties["HeaderRowDelimiter"].SetValue(cm, "\r\n");
        Wrap.IDTSConnectionManagerFlatFile100 ff = (Wrap.IDTSConnectionManagerFlatFile100)cm.InnerObject;
        for (int i = 0; i < cols.Length; i++)
        {
            Wrap.IDTSConnectionManagerFlatFileColumn100 c = ff.Columns.Add();
            c.ColumnType = "Delimited";
            c.ColumnDelimiter = i == cols.Length - 1 ? "\r\n" : ",";
            c.TextQualified = true;
            c.DataType = Wrap.DataType.DT_WSTR;
            c.MaximumWidth = widths[i];
            c.ColumnWidth = 0;
            ((Wrap.IDTSName100)c).Name = cols[i];
        }
        cm.SetExpression("ConnectionString", "@[$Project::RutaDatos] + \"\\\\" + subFolder + "\\\\" + file + "\"");
        return cm;
    }

    // ------------------------------------------------------------------ paquetes y tareas
    Package NewPackage(string name, string tableName, bool master = false)
    {
        Package pkg = new Package();
        pkg.Name = name;
        pkg.ProtectionLevel = DTSProtectionLevel.DontSaveSensitive;
        pkg.Variables.Add("AuditKey", false, "User", 0);
        if (!master) pkg.Variables.Add("RowCount", false, "User", 0);
        pkg.Variables.Add("TableName", false, "User", tableName);
        P.PackageItems.Add(pkg, name + ".dtsx");
        return pkg;
    }

    static ConnectionManager C(Package pkg, string name)
    {
        foreach (ConnectionManager cm in pkg.Connections) if (cm.Name == name) return cm;
        throw new Exception("Conexion no encontrada en " + pkg.Name + ": " + name);
    }

    static void Param(ExecuteSQLTask t, string name, string variable, int dbType)
    {
        IDTSParameterBinding p = (IDTSParameterBinding)t.ParameterBindings.Add();
        p.ParameterName = name;
        p.DtsVariableName = variable;
        p.ParameterDirection = ParameterDirections.Input;
        p.DataType = dbType;
        p.ParameterSize = -1;
    }

    static TaskHost Sql(IDTSSequence parent, string name, ConnectionManager cm, string sql)
    {
        TaskHost th = (TaskHost)parent.Executables.Add("Microsoft.ExecuteSQLTask");
        th.Name = name;
        th.Description = "Tarea Ejecutar SQL";
        ExecuteSQLTask t = (ExecuteSQLTask)th.InnerObject;
        t.Connection = cm.ID;
        t.SqlStatementSource = sql;
        t.TimeOut = 0;
        return th;
    }

    static TaskHost RowCnt(Package pkg, string name, ConnectionManager cm, string table)
    {
        TaskHost th = Sql(pkg, name, cm, "SELECT COUNT(1) AS RowCnt FROM " + table);
        ExecuteSQLTask t = (ExecuteSQLTask)th.InnerObject;
        t.ResultSetType = ResultSetType.ResultSetType_SingleRow;
        IDTSResultBinding rb = (IDTSResultBinding)t.ResultSetBindings.Add();
        rb.ResultName = "0";
        rb.DtsVariableName = "User::RowCount";
        return th;
    }

    static TaskHost GetAuditKey(Package pkg, ConnectionManager adoDwh, bool master)
    {
        TaskHost th = Sql(pkg, "Task Get AuditKey", adoDwh, master ? MasterGetAuditSql : GetAuditSql);
        ExecuteSQLTask t = (ExecuteSQLTask)th.InnerObject;
        t.ResultSetType = ResultSetType.ResultSetType_SingleRow;
        IDTSResultBinding rb = (IDTSResultBinding)t.ResultSetBindings.Add();
        rb.ResultName = "0";
        rb.DtsVariableName = "User::AuditKey";
        Param(t, "StartTime", "System::StartTime", DbDateTime2);
        Param(t, "PkgName", "System::PackageName", DbString);
        Param(t, "PkgGUID", "System::PackageID", DbGuid);
        Param(t, "PkgExecGUID", "System::ExecutionInstanceGUID", DbGuid);
        Param(t, "TableName", "User::TableName", DbString);
        if (!master) Param(t, "RowCount", "User::RowCount", DbInt32);
        return th;
    }

    static TaskHost UpdateAudit(Package pkg, ConnectionManager adoDwh, bool master)
    {
        TaskHost th = Sql(pkg, "Update AuditDim", adoDwh, master ? MasterUpdateAuditSql : UpdateAuditSql);
        ExecuteSQLTask t = (ExecuteSQLTask)th.InnerObject;
        if (!master) Param(t, "RowCount", "User::RowCount", DbInt32);
        Param(t, "AuditKey", "User::AuditKey", DbInt32);
        return th;
    }

    static void Chain(Package pkg, params Executable[] steps)
    {
        for (int i = 1; i < steps.Length; i++) pkg.PrecedenceConstraints.Add(steps[i - 1], steps[i]);
    }

    // Plantilla del laboratorio: Prior RowCnt -> Get AuditKey -> [TRUNCATE] -> trabajo -> Post RowCnt -> Update AuditDim
    void Template(Package pkg, string targetConn, string countTable, string truncateSql, Executable work)
    {
        ConnectionManager adoDwh = C(pkg, AuditConn);
        ConnectionManager target = C(pkg, targetConn);
        TaskHost prior = RowCnt(pkg, "Task Prior RowCnt", target, countTable);
        TaskHost key = GetAuditKey(pkg, adoDwh, false);
        TaskHost post = RowCnt(pkg, "Task Post RowCnt", target, countTable);
        TaskHost upd = UpdateAudit(pkg, adoDwh, false);
        if (truncateSql != null)
            Chain(pkg, prior, key, Sql(pkg, "TRUNCATE", target, truncateSql), work, post, upd);
        else
            Chain(pkg, prior, key, work, post, upd);
    }

    static MainPipe DataFlow(Package pkg, string name, out TaskHost th)
    {
        th = (TaskHost)pkg.Executables.Add("Microsoft.Pipeline");
        th.Name = name;
        th.Description = "Tarea Flujo de datos";
        try { th.Properties["AutoAdjustBufferSize"].SetValue(th, true); } catch { }
        return (MainPipe)th.InnerObject;
    }

    // ------------------------------------------------------------------ componentes del flujo de datos
    static IDTSComponentMetaData100 Comp(MainPipe mp, string classId, string name, out CManagedComponentWrapper d)
    {
        IDTSComponentMetaData100 c = mp.ComponentMetaDataCollection.New();
        c.ComponentClassID = classId;
        d = c.Instantiate();
        d.ProvideComponentProperties();
        c.Name = name;
        return c;
    }

    static void SetConn(IDTSComponentMetaData100 c, ConnectionManager cm)
    {
        c.RuntimeConnectionCollection[0].ConnectionManager = DtsConvert.GetExtendedInterface(cm);
        c.RuntimeConnectionCollection[0].ConnectionManagerID = cm.ID;
    }

    static void Refresh(CManagedComponentWrapper d)
    {
        d.AcquireConnections(null);
        d.ReinitializeMetaData();
        d.ReleaseConnections();
    }

    static void Connect(MainPipe mp, IDTSOutput100 from, IDTSComponentMetaData100 to)
    {
        IDTSPath100 path = mp.PathCollection.New();
        path.AttachPathAndPropagateNotifications(from, to.InputCollection[0]);
    }

    static IDTSOutput100 Out(IDTSComponentMetaData100 c, string name)
    {
        foreach (IDTSOutput100 o in c.OutputCollection) if (o.Name == name) return o;
        throw new Exception("Salida no encontrada: " + c.Name + "." + name);
    }

    static IDTSOutput100 DefaultOut(IDTSComponentMetaData100 c)
    {
        foreach (IDTSOutput100 o in c.OutputCollection) if (!o.IsErrorOut && o.Name != "bad") return o;
        throw new Exception("Sin salida predeterminada: " + c.Name);
    }

    static IDTSVirtualInputColumn100 VCol(IDTSVirtualInput100 vi, string name)
    {
        foreach (IDTSVirtualInputColumn100 v in vi.VirtualInputColumnCollection)
            if (string.Equals(v.Name, name, StringComparison.OrdinalIgnoreCase)) return v;
        throw new Exception("Columna no encontrada en la entrada: " + name);
    }

    static string Lin(IDTSVirtualInput100 vi, string col) { return "#" + VCol(vi, col).LineageID; }

    static IDTSComponentMetaData100 OleSource(MainPipe mp, string name, ConnectionManager cm, string sql)
    {
        CManagedComponentWrapper d;
        IDTSComponentMetaData100 c = Comp(mp, "Microsoft.OLEDBSource", name, out d);
        SetConn(c, cm);
        d.SetComponentProperty("AccessMode", 2);
        d.SetComponentProperty("SqlCommand", sql);
        Refresh(d);
        return c;
    }

    static IDTSComponentMetaData100 FlatSource(MainPipe mp, string name, ConnectionManager cm)
    {
        CManagedComponentWrapper d;
        IDTSComponentMetaData100 c = Comp(mp, "Microsoft.FlatFileSource", name, out d);
        SetConn(c, cm);
        d.SetComponentProperty("RetainNulls", true);   // campos vacíos -> NULL
        Refresh(d);
        return c;
    }

    // destino OLE DB en carga rápida; map = columna entrada -> columna destino (null = por nombre)
    static IDTSComponentMetaData100 OleDest(MainPipe mp, string name, ConnectionManager cm, string table,
                                            IDTSOutput100 from, Dictionary<string, string> map)
    {
        CManagedComponentWrapper d;
        IDTSComponentMetaData100 c = Comp(mp, "Microsoft.OLEDBDestination", name, out d);
        SetConn(c, cm);
        d.SetComponentProperty("AccessMode", 3);
        d.SetComponentProperty("OpenRowset", table);
        d.SetComponentProperty("FastLoadKeepIdentity", false);
        d.SetComponentProperty("FastLoadKeepNulls", false);
        d.SetComponentProperty("FastLoadOptions", "TABLOCK,CHECK_CONSTRAINTS");
        d.SetComponentProperty("FastLoadMaxInsertCommitSize", 2147483647);
        Refresh(d);
        Connect(mp, from, c);

        IDTSInput100 inp = c.InputCollection[0];
        IDTSVirtualInput100 vi = inp.GetVirtualInput();
        var ext = new Dictionary<string, IDTSExternalMetadataColumn100>(StringComparer.OrdinalIgnoreCase);
        foreach (IDTSExternalMetadataColumn100 e in inp.ExternalMetadataColumnCollection) ext[e.Name] = e;
        int mapped = 0;
        foreach (IDTSVirtualInputColumn100 v in vi.VirtualInputColumnCollection)
        {
            string target;
            if (map != null) { if (!map.TryGetValue(v.Name, out target)) continue; }
            else target = v.Name;
            IDTSExternalMetadataColumn100 e;
            if (!ext.TryGetValue(target, out e)) continue;
            IDTSInputColumn100 ic = d.SetUsageType(inp.ID, vi, v.LineageID, DTSUsageType.UT_READONLY);
            d.MapInputColumn(inp.ID, ic.ID, e.ID);
            mapped++;
        }
        if (map != null && mapped != map.Count)
            throw new Exception(name + ": se mapearon " + mapped + " de " + map.Count + " columnas");
        return c;
    }

    // Búsqueda (full cache). joins: (columna de entrada, columna de referencia); outs: (columna de referencia, nombre de salida)
    static IDTSComponentMetaData100 Lookup(MainPipe mp, string name, ConnectionManager cm, string sql,
                                           IDTSOutput100 from, string[][] joins, string[][] outs)
    {
        CManagedComponentWrapper d;
        IDTSComponentMetaData100 c = Comp(mp, "Microsoft.Lookup", name, out d);
        SetConn(c, cm);
        d.SetComponentProperty("SqlCommand", sql);
        d.SetComponentProperty("CacheType", 0);
        d.SetComponentProperty("NoMatchBehavior", 0);
        Connect(mp, from, c);
        Refresh(d);

        IDTSInput100 inp = c.InputCollection[0];
        IDTSVirtualInput100 vi = inp.GetVirtualInput();
        foreach (string[] j in joins)
        {
            IDTSInputColumn100 ic = d.SetUsageType(inp.ID, vi, VCol(vi, j[0]).LineageID, DTSUsageType.UT_READONLY);
            d.SetInputColumnProperty(inp.ID, ic.ID, "JoinToReferenceColumn", j[1]);
        }
        IDTSOutput100 match = c.OutputCollection[0];
        foreach (string[] o in outs)
        {
            IDTSOutputColumn100 oc = d.InsertOutputColumnAt(match.ID, match.OutputColumnCollection.Count, o[1], "");
            d.SetOutputColumnProperty(match.ID, oc.ID, "CopyFromReferenceColumn", o[0]);
        }
        // igual que el lab: "omitir error" -> la llave queda NULL y la división condicional la separa
        match.ErrorRowDisposition = DTSRowDisposition.RD_IgnoreFailure;
        return c;
    }

    // División condicional "bad": fila descartada por la consulta (MotivoDescarte) o con alguna llave NULL
    static IDTSComponentMetaData100 BadSplit(MainPipe mp, IDTSOutput100 from, string[] keys)
    {
        CManagedComponentWrapper d;
        IDTSComponentMetaData100 c = Comp(mp, "Microsoft.ConditionalSplit", "División condicional", out d);
        Connect(mp, from, c);
        IDTSInput100 inp = c.InputCollection[0];
        IDTSVirtualInput100 vi = inp.GetVirtualInput();
        d.SetUsageType(inp.ID, vi, VCol(vi, "MotivoDescarte").LineageID, DTSUsageType.UT_READONLY);
        foreach (string k in keys) d.SetUsageType(inp.ID, vi, VCol(vi, k).LineageID, DTSUsageType.UT_READONLY);
        IDTSOutput100 bad = d.InsertOutput(DTSInsertPlacement.IP_BEFORE, c.OutputCollection[0].ID);
        bad.Name = "bad";
        bad.Description = "Filas descartadas por limpieza o con alguna llave sin coincidencia";
        bad.IsErrorOut = false;
        string expr = "!ISNULL(" + Lin(vi, "MotivoDescarte") + ") || " + string.Join(" || ", keys.Select(k => "ISNULL(" + Lin(vi, k) + ")"));
        string friendly = "!ISNULL(MotivoDescarte) || " + string.Join(" || ", keys.Select(k => "ISNULL(" + k + ")"));
        d.SetOutputProperty(bad.ID, "Expression", expr);
        d.SetOutputProperty(bad.ID, "FriendlyExpression", friendly);
        d.SetOutputProperty(bad.ID, "EvaluationOrder", 0);
        return c;
    }

    // Columna derivada "Motivo" en la salida bad: el motivo de la consulta o "llave sin coincidencia"
    static IDTSComponentMetaData100 MotivoColumn(MainPipe mp, IDTSOutput100 from)
    {
        CManagedComponentWrapper d;
        IDTSComponentMetaData100 c = Comp(mp, "Microsoft.DerivedColumn", "Columna derivada Motivo", out d);
        Connect(mp, from, c);
        IDTSInput100 inp = c.InputCollection[0];
        IDTSVirtualInput100 vi = inp.GetVirtualInput();
        d.SetUsageType(inp.ID, vi, VCol(vi, "MotivoDescarte").LineageID, DTSUsageType.UT_READONLY);
        IDTSOutput100 o = c.OutputCollection[0];
        IDTSOutputColumn100 oc = d.InsertOutputColumnAt(o.ID, 0, "Motivo", "Motivo del descarte");
        d.SetOutputColumnDataTypeProperties(o.ID, oc.ID, Wrap.DataType.DT_WSTR, 200, 0, 0, 0);
        string lin = Lin(vi, "MotivoDescarte");
        d.SetOutputColumnProperty(o.ID, oc.ID, "Expression",
            "ISNULL(" + lin + ") ? (DT_WSTR,200)\"Llave sin coincidencia en una dimensión\" : " + lin);
        d.SetOutputColumnProperty(o.ID, oc.ID, "FriendlyExpression",
            "ISNULL(MotivoDescarte) ? (DT_WSTR,200)\"Llave sin coincidencia en una dimensión\" : MotivoDescarte");
        return c;
    }

    // ================================================================== STAGE
    public void BuildStage(string ispac, string dataFolder)
    {
        P = Project.CreateProject();
        P.Name = "stage_GCA";
        P.ProtectionLevel = DTSProtectionLevel.DontSaveSensitive;
        Parameter rp = P.Parameters.Add("RutaDatos", TypeCode.String);
        rp.Value = dataFolder;
        rp.Description = "Carpeta data_ventas (contiene Maestros y Transacciones)";

        AddConn("OLEDB", "OleDB STAGE_GCA", OleDbCs("STAGE_GCA"));
        AddConn(AdoType, "AdoNet STAGE_GCA", AdoCs("STAGE_GCA"));
        AddConn(AdoType, AuditConn, AdoCs("DWH_GCA"));

        var files = new[] {
            new { Pkg = "StageCalendario", Ff = "FF Calendario", Sub = "Maestros", File = "Calendario.csv", Table = "[GCA].[StageCalendario]",
                  Cols = new[] { "fecha","anio","mes","trimestre","dia_semana","es_fin_semana","periodo","fase" },
                  W = new[] { 20,10,10,10,10,10,10,20 } },
            new { Pkg = "StageCliente", Ff = "FF Cliente", Sub = "Maestros", File = "Cliente.csv", Table = "[GCA].[StageCliente]",
                  Cols = new[] { "cliente_id","nombre","tipo","segmento","pais","fecha_alta","tiene_contrato","tiene_ejecutivo","canal_origen" },
                  W = new[] { 20,100,10,30,30,20,10,10,40 } },
            new { Pkg = "StageProducto", Ff = "FF Producto", Sub = "Maestros", File = "Producto.csv", Table = "[GCA].[StageProducto]",
                  Cols = new[] { "producto_id","categoria","costo_unitario","precio_lista","margen_objetivo" },
                  W = new[] { 20,40,20,20,20 } },
            new { Pkg = "StageVendedor", Ff = "FF Vendedor", Sub = "Maestros", File = "Vendedor.csv", Table = "[GCA].[StageVendedor]",
                  Cols = new[] { "vendedor_id","nombre","canal","region","gerente_id","antiguedad","cuota_anual","fecha_ingreso" },
                  W = new[] { 20,100,30,30,20,20,20,20 } },
            new { Pkg = "StageVenta", Ff = "FF Venta", Sub = "Transacciones", File = "Transacciones_venta.csv", Table = "[GCA].[StageVenta]",
                  Cols = new[] { "venta_id","oportunidad_id","cliente_id","vendedor_id","producto_id","categoria","fecha_venta","cantidad",
                                 "precio_lista","descuento","precio_unitario_neto","venta_neta","costo_total","margen_bruto","canal","region","tipo_cliente" },
                  W = new[] { 20,20,20,20,20,40,20,10,20,10,20,20,20,20,30,30,10 } },
            new { Pkg = "StageOportunidad", Ff = "FF Oportunidad", Sub = "Transacciones", File = "Transacciones_oportunidad.csv", Table = "[GCA].[StageOportunidad]",
                  Cols = new[] { "oportunidad_id","cliente_id","vendedor_id","canal","region","gerente_id","fecha_creacion","fecha_cierre","etapa",
                                 "resultado","facturada","motivo_perdida","monto_oportunidad","descuento_solicitado","descuento_fuera_politica",
                                 "touchpoints","tiene_demo_tecnica","ciclo_venta_dias","dias_sin_actividad","fase" },
                  W = new[] { 20,20,20,30,30,20,20,20,30,30,10,40,20,10,10,10,10,10,10,20 } },
            new { Pkg = "StageLlamada", Ff = "FF Llamada", Sub = "Transacciones", File = "Transacciones_call_center.csv", Table = "[GCA].[StageLlamada]",
                  Cols = new[] { "llamada_id","fecha","vendedor_id","cliente_id","duracion_seg","disposicion","es_venta" },
                  W = new[] { 20,20,20,20,10,40,10 } },
            new { Pkg = "StageCarrito", Ff = "FF Carrito", Sub = "Transacciones", File = "Transacciones_carrito_abandonado.csv", Table = "[GCA].[StageCarrito]",
                  Cols = new[] { "carrito_id","fecha","cliente_id","monto","paso_abandono","recuperado","fase" },
                  W = new[] { 20,20,20,20,30,10,20 } },
            new { Pkg = "StageSesion", Ff = "FF Sesion", Sub = "Transacciones", File = "Transacciones_ecommerce_sessions.csv", Table = "[GCA].[StageSesion]",
                  Cols = new[] { "fecha","canal","dispositivo","sesiones","add_to_cart","checkout_iniciado","ordenes","ticket_promedio","venta_total","fase" },
                  W = new[] { 20,30,20,10,10,10,10,20,20,20 } },
            new { Pkg = "StageEncuesta", Ff = "FF Encuesta", Sub = "Transacciones", File = "Transacciones_encuesta.csv", Table = "[GCA].[StageEncuesta]",
                  Cols = new[] { "encuesta_id","fecha","cliente_id","momento","nps","csat","fase" },
                  W = new[] { 20,20,20,30,10,10,20 } },
            new { Pkg = "StageMarketing", Ff = "FF Marketing", Sub = "Transacciones", File = "Transacciones_marketing.csv", Table = "[GCA].[StageMarketing]",
                  Cols = new[] { "fecha","canal","campana","inversion","leads","nuevos_clientes","fase" },
                  W = new[] { 20,30,20,20,10,10,20 } },
            new { Pkg = "StageTicketSoporte", Ff = "FF TicketSoporte", Sub = "Transacciones", File = "Transacciones_ticket_soporte.csv", Table = "[GCA].[StageTicketSoporte]",
                  Cols = new[] { "ticket_id","cliente_id","fecha_apertura","fecha_cierre","horas_resolucion","categoria","sla_cumplido","fase" },
                  W = new[] { 20,20,20,20,10,30,10,20 } },
        };

        foreach (var f in files) AddFlatFile(f.Ff, f.Sub, f.File, dataFolder, f.Cols, f.W);
        foreach (var f in files)
        {
            Package pkg = NewPackage(f.Pkg, f.Table);
            TaskHost th; MainPipe mp = DataFlow(pkg, "DF " + f.Pkg, out th);
            var src = FlatSource(mp, "Origen de archivo plano", C(pkg, f.Ff));
            OleDest(mp, f.Pkg, C(pkg, "OleDB STAGE_GCA"), f.Table, src.OutputCollection[0], null);
            // TRUNCATE reinicia también el IDENTITY de FilaOrigen
            Template(pkg, "AdoNet STAGE_GCA", f.Table, "TRUNCATE TABLE " + f.Table + ";", th);
        }

        Master("MasterExecuteStage", "Master_Stage_GCA", new[] { "Maestros", "Transacciones" },
            new[] { files.Where(f => f.Sub == "Maestros").Select(f => f.Pkg).ToArray(),
                    files.Where(f => f.Sub == "Transacciones").Select(f => f.Pkg).ToArray() });
        P.SaveTo(ispac);
        P.Dispose();
    }

    // ================================================================== DWH
    public void BuildDwh(string ispac)
    {
        P = Project.CreateProject();
        P.Name = "DWH_GCA";
        P.ProtectionLevel = DTSProtectionLevel.DontSaveSensitive;

        AddConn("OLEDB", "OleDB DWH_GCA", OleDbCs("DWH_GCA"));
        AddConn("OLEDB", "OleDB STAGE_GCA", OleDbCs("STAGE_GCA"));
        AddConn(AdoType, AuditConn, AdoCs("DWH_GCA"));

        // ---------- dimensiones: procedimientos MERGE (la limpieza de maestros está en el SP)
        var dims = new[] {
            new[] { "DimFecha", "[GENERICO].[DimFecha]", "[GENERICO].[sp_DimFecha]" },
            new[] { "DimCanal", "[Comercial].[DimCanal]", "[Comercial].[sp_DimCanal]" },
            new[] { "DimRegion", "[Comercial].[DimRegion]", "[Comercial].[sp_DimRegion]" },
            new[] { "DimCliente", "[Comercial].[DimCliente]", "[Comercial].[sp_DimCliente]" },
            new[] { "DimProducto", "[Comercial].[DimProducto]", "[Comercial].[sp_DimProducto]" },
            new[] { "DimVendedor", "[Comercial].[DimVendedor]", "[Comercial].[sp_DimVendedor]" } };
        foreach (string[] dm in dims)
        {
            Package pkg = NewPackage(dm[0], dm[1]);
            TaskHost sp = Sql(pkg, "Execute sp_" + dm[0], C(pkg, AuditConn), "EXEC " + dm[2] + ";");
            Template(pkg, AuditConn, dm[1], null, sp);
        }

        string F = "SELECT [FechaKey] FROM [GENERICO].[DimFecha] WHERE [FechaKey] > 0";
        string[] LkFecha = { "DimFecha", F };
        string[] LkCliente = { "DimCliente", "SELECT [ClienteKey], [ClienteID] FROM [Comercial].[DimCliente] WHERE [ClienteKey] > 0" };
        string[] LkVendedor = { "DimVendedor", "SELECT [VendedorKey], [VendedorID] FROM [Comercial].[DimVendedor] WHERE [VendedorKey] > 0" };
        string[] LkProducto = { "DimProducto", "SELECT [ProductoKey], [ProductoID] FROM [Comercial].[DimProducto] WHERE [ProductoKey] > 0" };
        string[] LkCanal = { "DimCanal", "SELECT [CanalKey], [Canal] FROM [Comercial].[DimCanal] WHERE [CanalKey] > 0" };
        string[] LkRegion = { "DimRegion", "SELECT [RegionKey], [Region] FROM [Comercial].[DimRegion] WHERE [RegionKey] > 0" };

        Fact("FactVenta", "FACT VENTA", Sql_Venta, new[] {
                Lk(LkFecha, "FechaNum", "FechaKey", "FechaKey", "FechaKey"),
                Lk(LkCliente, "cliente_id", "ClienteID", "ClienteKey", "ClienteKey"),
                Lk(LkVendedor, "vendedor_id", "VendedorID", "VendedorKey", "VendedorKey"),
                Lk(LkProducto, "producto_id", "ProductoID", "ProductoKey", "ProductoKey"),
                Lk(LkCanal, "canal", "Canal", "CanalKey", "CanalKey"),
                Lk(LkRegion, "region", "Region", "RegionKey", "RegionKey") },
            new[] { "VentaID", "OportunidadID", "Cantidad", "PrecioLista", "Descuento", "PrecioUnitarioNeto", "VentaNeta",
                    "CostoTotal", "MargenBruto", "MargenPct", "VentaNetaRecalculada", "MargenRecalculado" });

        Fact("FactOportunidad", "FACT OPORTUNIDAD", Sql_Oportunidad, new[] {
                Lk(new[] { "DimFecha (creación)", F }, "FechaCreaNum", "FechaKey", "FechaKey", "FechaCreacionKey"),
                Lk(new[] { "DimFecha (cierre)", F }, "FechaCierreNum", "FechaKey", "FechaKey", "FechaCierreKey"),
                Lk(LkCliente, "cliente_id", "ClienteID", "ClienteKey", "ClienteKey"),
                Lk(LkVendedor, "vendedor_id", "VendedorID", "VendedorKey", "VendedorKey"),
                Lk(LkCanal, "canal", "Canal", "CanalKey", "CanalKey"),
                Lk(LkRegion, "region", "Region", "RegionKey", "RegionKey") },
            new[] { "OportunidadID", "GerenteID", "Etapa", "Resultado", "Facturada", "MotivoPerdida", "Monto", "DescuentoSolicitado",
                    "FueraPolitica", "Touchpoints", "TieneDemoTecnica", "CicloVentaDias", "CicloVentaOrigen", "CicloCorregido",
                    "DiasSinActividad", "Zombie" });

        Fact("FactLlamada", "FACT LLAMADA", Sql_Llamada, new[] {
                Lk(LkFecha, "FechaNum", "FechaKey", "FechaKey", "FechaKey"),
                Lk(LkVendedor, "vendedor_id", "VendedorID", "VendedorKey", "VendedorKey"),
                Lk(LkCliente, "cliente_id", "ClienteID", "ClienteKey", "ClienteKey") },
            new[] { "LlamadaID", "DuracionSeg", "Disposicion", "EsVenta", "EsVentaInconsistente" });

        Fact("FactCarrito", "FACT CARRITO", Sql_Carrito, new[] {
                Lk(LkFecha, "FechaNum", "FechaKey", "FechaKey", "FechaKey"),
                Lk(LkCliente, "cliente_id", "ClienteID", "ClienteKey", "ClienteKey") },
            new[] { "CarritoID", "Monto", "PasoAbandono", "Recuperado" });

        Fact("FactSesion", "FACT SESION", Sql_Sesion, new[] {
                Lk(LkFecha, "FechaNum", "FechaKey", "FechaKey", "FechaKey") },
            new[] { "CanalDigital", "Dispositivo", "Sesiones", "AddToCart", "CheckoutIniciado", "Ordenes", "TicketPromedio", "VentaTotal" });

        Fact("FactEncuesta", "FACT ENCUESTA", Sql_Encuesta, new[] {
                Lk(LkFecha, "FechaNum", "FechaKey", "FechaKey", "FechaKey"),
                Lk(LkCliente, "cliente_id", "ClienteID", "ClienteKey", "ClienteKey") },
            new[] { "EncuestaID", "Momento", "NPS", "CSAT" });

        Fact("FactMarketing", "FACT MARKETING", Sql_Marketing, new[] {
                Lk(LkFecha, "FechaNum", "FechaKey", "FechaKey", "FechaKey") },
            new[] { "CanalDigital", "Campana", "Inversion", "Leads", "NuevosClientes" });

        Fact("FactTicketSoporte", "FACT TICKET SOPORTE", Sql_Soporte, new[] {
                Lk(new[] { "DimFecha (apertura)", F }, "FechaNum", "FechaKey", "FechaKey", "FechaAperturaKey"),
                Lk(LkCliente, "cliente_id", "ClienteID", "ClienteKey", "ClienteKey") },
            new[] { "TicketID", "FechaCierre", "HorasResolucion", "Categoria", "SlaCumplido", "SlaRecalculado" });

        Master("MasterExecuteDWH", "Master_DWH_GCA", new[] { "Dimensiones", "Hechos" },
            new[] { dims.Select(x => x[0]).ToArray(),
                    new[] { "FactVenta", "FactOportunidad", "FactLlamada", "FactCarrito", "FactSesion", "FactEncuesta", "FactMarketing", "FactTicketSoporte" } });
        P.SaveTo(ispac);
        P.Dispose();
    }

    // definición de una búsqueda: nombre, sql, columna de entrada, columna de referencia, columna a copiar, nombre de salida
    static string[] Lk(string[] dim, string inCol, string refCol, string copyCol, string outName)
    { return new[] { dim[0], dim[1], inCol, refCol, copyCol, outName }; }

    // Flujo de hechos: Origen (consulta con limpieza) -> Búsquedas -> División condicional bad -> Error (con Motivo) / Fact
    void Fact(string name, string dfName, string sql, string[][] lookups, string[] measures)
    {
        string table = "[Comercial].[" + name + "]", err = "[Comercial].[Error" + name + "]";
        Package pkg = NewPackage(name, table);
        TaskHost th; MainPipe mp = DataFlow(pkg, dfName, out th);
        ConnectionManager dwh = C(pkg, "OleDB DWH_GCA");
        IDTSComponentMetaData100 prev = OleSource(mp, "Origen de OLE DB (limpieza)", C(pkg, "OleDB STAGE_GCA"), sql);
        var keys = new List<string>();
        foreach (string[] l in lookups)
        {
            prev = Lookup(mp, l[0], dwh, l[1], prev.OutputCollection[0], new[] { new[] { l[2], l[3] } }, new[] { new[] { l[4], l[5] } });
            keys.Add(l[5]);
        }
        var cs = BadSplit(mp, prev.OutputCollection[0], keys.ToArray());
        var mot = MotivoColumn(mp, Out(cs, "bad"));
        OleDest(mp, "Error" + name, dwh, err, mot.OutputCollection[0], null);
        var map = keys.Concat(measures).ToDictionary(k => k, k => k);
        OleDest(mp, name, dwh, table, DefaultOut(cs), map);
        Template(pkg, AuditConn, table, "TRUNCATE TABLE " + table + ";\r\nTRUNCATE TABLE " + err + ";", th);
    }

    // ================================================================== consultas de origen con limpieza
    // Rango válido = calendario del caso (DimFecha). Regla de duplicados en hechos:
    //   rnId > 1                       -> mismo ID repetido: se queda la primera aparición (FilaOrigen)
    //   fecha fuera de rango + "gemelo" -> copia de otro registro (mismo contenido, otro ID) con fecha alterada
    const string Rango = "CROSS JOIN (SELECT MIN([Fecha]) AS [FMin], MAX([Fecha]) AS [FMax] FROM [DWH_GCA].[GENERICO].[DimFecha] WHERE [FechaKey] > 0) c";

    const string Sql_Venta =
@"WITH S AS (
    SELECT v.*, COALESCE(TRY_CONVERT(DATE, v.[fecha_venta], 103), TRY_CONVERT(DATE, v.[fecha_venta], 23)) AS [FechaD],
           TRY_CONVERT(INT, v.[cantidad]) AS [Cant], TRY_CONVERT(DECIMAL(18,2), v.[precio_lista]) AS [PL],
           TRY_CONVERT(DECIMAL(9,4), v.[descuento]) AS [Dto], TRY_CONVERT(DECIMAL(18,2), v.[precio_unitario_neto]) AS [PUN0],
           TRY_CONVERT(DECIMAL(18,2), v.[venta_neta]) AS [VN], TRY_CONVERT(DECIMAL(18,2), v.[costo_total]) AS [CT],
           TRY_CONVERT(DECIMAL(9,4), v.[margen_bruto]) AS [MB]
      FROM [GCA].[StageVenta] v),
R AS (
    SELECT S.*, COALESCE(S.[PUN0], ROUND(S.[PL] * (1 - S.[Dto]), 2)) AS [PUN],
           CASE WHEN S.[FechaD] BETWEEN c.[FMin] AND c.[FMax] THEN 1 ELSE 0 END AS [EnRango],
           ROW_NUMBER() OVER (PARTITION BY S.[venta_id] ORDER BY S.[FilaOrigen]) AS [rnId],
           MIN(CASE WHEN S.[FechaD] BETWEEN c.[FMin] AND c.[FMax] THEN S.[venta_id] END)
               OVER (PARTITION BY S.[oportunidad_id], S.[cliente_id], S.[vendedor_id], S.[producto_id], S.[categoria], S.[cantidad],
                                  S.[precio_lista], S.[descuento], S.[precio_unitario_neto], S.[venta_neta], S.[costo_total],
                                  S.[margen_bruto], S.[canal], S.[region], S.[tipo_cliente]) AS [Gemelo]
      FROM S " + Rango + @"),
X AS (SELECT R.*, CAST(ROUND(R.[Cant] * R.[PUN], 2) AS DECIMAL(18,2)) AS [VNCalc] FROM R)
SELECT [FilaOrigen], [venta_id], [oportunidad_id], [cliente_id], [vendedor_id], [producto_id], [fecha_venta], [cantidad] AS [cantidad_origen],
       [venta_neta], [canal], [region],
       [venta_id] AS [VentaID],
       NULLIF(LTRIM(RTRIM([oportunidad_id])), N'') AS [OportunidadID],
       CONVERT(INT, CONVERT(CHAR(8), [FechaD], 112)) AS [FechaNum],
       [Cant] AS [Cantidad], [PL] AS [PrecioLista], [Dto] AS [Descuento], [PUN] AS [PrecioUnitarioNeto],
       [VNCalc] AS [VentaNeta], [CT] AS [CostoTotal],
       CAST([VNCalc] - [CT] AS DECIMAL(18,2)) AS [MargenBruto],
       CAST(CASE WHEN [VNCalc] = 0 THEN 0 ELSE ROUND(([VNCalc] - [CT]) / [VNCalc], 4) END AS DECIMAL(9,4)) AS [MargenPct],
       CAST(CASE WHEN [VN] IS NULL OR ABS([VN] - [VNCalc]) > 1 THEN 1 ELSE 0 END AS BIT) AS [VentaNetaRecalculada],
       CAST(CASE WHEN [MB] IS NULL THEN 1 ELSE 0 END AS BIT) AS [MargenRecalculado],
       CAST(CASE WHEN [rnId] > 1 THEN N'Duplicado exacto: venta_id repetido (se conservó la primera aparición)'
                 WHEN [FechaD] IS NULL THEN N'Fecha de venta inválida: ' + ISNULL([fecha_venta], N'(vacía)')
                 WHEN [EnRango] = 0 AND [Gemelo] IS NOT NULL THEN N'Duplicado de ' + [Gemelo] + N' con fecha alterada (' + [fecha_venta] + N')'
                 WHEN [EnRango] = 0 THEN N'Fecha fuera del calendario (' + [fecha_venta] + N')'
                 WHEN [Cant] IS NULL OR [Cant] <= 0 OR [PUN] IS NULL OR [CT] IS NULL THEN N'Cantidad, precio o costo inválido'
            END AS NVARCHAR(200)) AS [MotivoDescarte]
  FROM X";

    const string Sql_Oportunidad =
@"WITH S AS (
    SELECT o.*, COALESCE(TRY_CONVERT(DATE, o.[fecha_creacion], 23), TRY_CONVERT(DATE, o.[fecha_creacion], 103)) AS [FCrea],
           COALESCE(TRY_CONVERT(DATE, o.[fecha_cierre], 23), TRY_CONVERT(DATE, o.[fecha_cierre], 103)) AS [FCierre],
           ROW_NUMBER() OVER (PARTITION BY o.[oportunidad_id] ORDER BY o.[FilaOrigen]) AS [rnId]
      FROM [GCA].[StageOportunidad] o)
SELECT [FilaOrigen], [oportunidad_id], [cliente_id], [vendedor_id], [fecha_creacion], [fecha_cierre], [canal], [region],
       [oportunidad_id] AS [OportunidadID],
       CONVERT(INT, CONVERT(CHAR(8), [FCrea], 112)) AS [FechaCreaNum],
       CONVERT(INT, CONVERT(CHAR(8), [FCierre], 112)) AS [FechaCierreNum],
       CAST(ISNULL(NULLIF(LTRIM(RTRIM([gerente_id])), N''), N'Sin Datos') AS NVARCHAR(20)) AS [GerenteID],
       CAST(LTRIM(RTRIM([etapa])) AS NVARCHAR(30)) AS [Etapa],
       CAST(LTRIM(RTRIM([resultado])) AS NVARCHAR(30)) AS [Resultado],
       CAST(CASE WHEN [facturada] = N'1' THEN 1 ELSE 0 END AS BIT) AS [Facturada],
       CAST(ISNULL(NULLIF(LTRIM(RTRIM([motivo_perdida])), N''), N'No aplica') AS NVARCHAR(40)) AS [MotivoPerdida],
       TRY_CONVERT(DECIMAL(18,2), [monto_oportunidad]) AS [Monto],
       TRY_CONVERT(DECIMAL(9,4), [descuento_solicitado]) AS [DescuentoSolicitado],
       CAST(CASE WHEN [descuento_fuera_politica] = N'1' THEN 1 ELSE 0 END AS BIT) AS [FueraPolitica],
       TRY_CONVERT(TINYINT, [touchpoints]) AS [Touchpoints],
       CAST(CASE WHEN [tiene_demo_tecnica] = N'1' THEN 1 ELSE 0 END AS BIT) AS [TieneDemoTecnica],
       DATEDIFF(DAY, [FCrea], [FCierre]) AS [CicloVentaDias],
       TRY_CONVERT(INT, [ciclo_venta_dias]) AS [CicloVentaOrigen],
       CAST(CASE WHEN ISNULL(TRY_CONVERT(INT, [ciclo_venta_dias]), -1) <> DATEDIFF(DAY, [FCrea], [FCierre]) THEN 1 ELSE 0 END AS BIT) AS [CicloCorregido],
       TRY_CONVERT(INT, [dias_sin_actividad]) AS [DiasSinActividad],
       CAST(CASE WHEN TRY_CONVERT(INT, [dias_sin_actividad]) > 180 THEN 1 ELSE 0 END AS BIT) AS [Zombie],
       CAST(CASE WHEN [rnId] > 1 THEN N'Duplicado exacto: oportunidad_id repetido (se conservó la primera aparición)'
                 WHEN [FCrea] IS NULL OR [FCierre] IS NULL THEN N'Fecha de creación o cierre inválida'
                 WHEN [FCierre] < [FCrea] THEN N'Fecha de cierre anterior a la creación'
                 WHEN TRY_CONVERT(DECIMAL(18,2), [monto_oportunidad]) IS NULL THEN N'Monto inválido'
            END AS NVARCHAR(200)) AS [MotivoDescarte]
  FROM S";

    const string Sql_Llamada =
@"WITH S AS (
    SELECT l.*, COALESCE(TRY_CONVERT(DATE, l.[fecha], 103), TRY_CONVERT(DATE, l.[fecha], 23)) AS [FechaD],
           ROW_NUMBER() OVER (PARTITION BY l.[llamada_id] ORDER BY l.[FilaOrigen]) AS [rnId],
           CASE WHEN EXISTS (SELECT 1 FROM [GCA].[StageCliente] k WHERE k.[cliente_id] = l.[cliente_id]) THEN 1 ELSE 0 END AS [ClienteExiste]
      FROM [GCA].[StageLlamada] l)
SELECT [FilaOrigen], [llamada_id], [fecha], [vendedor_id], [cliente_id], [disposicion] AS [disposicion_origen],
       [llamada_id] AS [LlamadaID],
       CONVERT(INT, CONVERT(CHAR(8), [FechaD], 112)) AS [FechaNum],
       TRY_CONVERT(INT, [duracion_seg]) AS [DuracionSeg],
       CAST(LTRIM(RTRIM([disposicion])) AS NVARCHAR(40)) AS [Disposicion],
       CAST(CASE WHEN [es_venta] = N'1' THEN 1 ELSE 0 END AS BIT) AS [EsVenta],
       CAST(CASE WHEN [es_venta] = N'1' AND [disposicion] IN (N'No contactado', N'Rechazo') THEN 1 ELSE 0 END AS BIT) AS [EsVentaInconsistente],
       CAST(CASE WHEN [rnId] > 1 THEN N'Duplicado exacto: llamada_id repetido (se conservó la primera aparición)'
                 WHEN [FechaD] IS NULL THEN N'Fecha inválida'
                 WHEN [ClienteExiste] = 0 THEN N'Cliente inexistente en el maestro (' + [cliente_id] + N')'
                 WHEN TRY_CONVERT(INT, [duracion_seg]) IS NULL OR TRY_CONVERT(INT, [duracion_seg]) < 0 THEN N'Duración inválida'
            END AS NVARCHAR(200)) AS [MotivoDescarte]
  FROM S";

    const string Sql_Carrito =
@"WITH S AS (
    SELECT k.*, COALESCE(TRY_CONVERT(DATE, k.[fecha], 103), TRY_CONVERT(DATE, k.[fecha], 23)) AS [FechaD]
      FROM [GCA].[StageCarrito] k),
R AS (
    SELECT S.*, CASE WHEN S.[FechaD] BETWEEN c.[FMin] AND c.[FMax] THEN 1 ELSE 0 END AS [EnRango],
           ROW_NUMBER() OVER (PARTITION BY S.[carrito_id] ORDER BY S.[FilaOrigen]) AS [rnId],
           MIN(CASE WHEN S.[FechaD] BETWEEN c.[FMin] AND c.[FMax] THEN S.[carrito_id] END)
               OVER (PARTITION BY S.[cliente_id], S.[monto], S.[paso_abandono], S.[recuperado], S.[fase]) AS [Gemelo]
      FROM S " + Rango + @")
SELECT [FilaOrigen], [carrito_id], [fecha], [cliente_id], [monto] AS [monto_origen], [paso_abandono],
       [carrito_id] AS [CarritoID],
       CONVERT(INT, CONVERT(CHAR(8), [FechaD], 112)) AS [FechaNum],
       TRY_CONVERT(DECIMAL(18,2), [monto]) AS [Monto],
       CAST(LTRIM(RTRIM([paso_abandono])) AS NVARCHAR(30)) AS [PasoAbandono],
       CAST(CASE WHEN [recuperado] = N'1' THEN 1 ELSE 0 END AS BIT) AS [Recuperado],
       CAST(CASE WHEN [rnId] > 1 THEN N'Duplicado exacto: carrito_id repetido (se conservó la primera aparición)'
                 WHEN [FechaD] IS NULL THEN N'Fecha inválida'
                 WHEN [EnRango] = 0 AND [Gemelo] IS NOT NULL THEN N'Duplicado de ' + [Gemelo] + N' con fecha alterada (' + [fecha] + N')'
                 WHEN [EnRango] = 0 THEN N'Fecha fuera del calendario (' + [fecha] + N')'
                 WHEN TRY_CONVERT(DECIMAL(18,2), [monto]) IS NULL THEN N'Monto inválido'
            END AS NVARCHAR(200)) AS [MotivoDescarte]
  FROM R";

    const string Sql_Sesion =
@"WITH S AS (
    SELECT s.*, COALESCE(TRY_CONVERT(DATE, s.[fecha], 23), TRY_CONVERT(DATE, s.[fecha], 103)) AS [FechaD],
           ROW_NUMBER() OVER (PARTITION BY s.[fecha], s.[canal], s.[dispositivo] ORDER BY s.[FilaOrigen]) AS [rnId]
      FROM [GCA].[StageSesion] s)
SELECT [FilaOrigen], [fecha], [canal], [dispositivo] AS [dispositivo_origen],
       CONVERT(INT, CONVERT(CHAR(8), [FechaD], 112)) AS [FechaNum],
       CAST(LTRIM(RTRIM([canal])) AS NVARCHAR(30)) AS [CanalDigital],
       CAST(LTRIM(RTRIM([dispositivo])) AS NVARCHAR(20)) AS [Dispositivo],
       TRY_CONVERT(INT, [sesiones]) AS [Sesiones], TRY_CONVERT(INT, [add_to_cart]) AS [AddToCart],
       TRY_CONVERT(INT, [checkout_iniciado]) AS [CheckoutIniciado], TRY_CONVERT(INT, [ordenes]) AS [Ordenes],
       TRY_CONVERT(DECIMAL(18,2), [ticket_promedio]) AS [TicketPromedio], TRY_CONVERT(DECIMAL(18,2), [venta_total]) AS [VentaTotal],
       CAST(CASE WHEN [rnId] > 1 THEN N'Duplicado exacto: misma fecha, canal y dispositivo (se conservó la primera aparición)'
                 WHEN [FechaD] IS NULL THEN N'Fecha inválida'
                 WHEN TRY_CONVERT(INT, [ordenes]) > TRY_CONVERT(INT, [checkout_iniciado])
                   OR TRY_CONVERT(INT, [checkout_iniciado]) > TRY_CONVERT(INT, [add_to_cart])
                   OR TRY_CONVERT(INT, [add_to_cart]) > TRY_CONVERT(INT, [sesiones]) THEN N'Embudo incoherente'
            END AS NVARCHAR(200)) AS [MotivoDescarte]
  FROM S";

    const string Sql_Encuesta =
@"WITH S AS (
    SELECT e.*, COALESCE(TRY_CONVERT(DATE, e.[fecha], 23), TRY_CONVERT(DATE, e.[fecha], 103)) AS [FechaD],
           ROW_NUMBER() OVER (PARTITION BY e.[encuesta_id] ORDER BY e.[FilaOrigen]) AS [rnId]
      FROM [GCA].[StageEncuesta] e)
SELECT [FilaOrigen], [encuesta_id], [fecha], [cliente_id],
       [encuesta_id] AS [EncuestaID],
       CONVERT(INT, CONVERT(CHAR(8), [FechaD], 112)) AS [FechaNum],
       CAST(LTRIM(RTRIM([momento])) AS NVARCHAR(30)) AS [Momento],
       TRY_CONVERT(INT, [nps]) AS [NPS], TRY_CONVERT(DECIMAL(5,2), [csat]) AS [CSAT],
       CAST(CASE WHEN [rnId] > 1 THEN N'Duplicado exacto: encuesta_id repetido (se conservó la primera aparición)'
                 WHEN [FechaD] IS NULL THEN N'Fecha inválida'
                 WHEN TRY_CONVERT(INT, [nps]) NOT BETWEEN -100 AND 100 THEN N'NPS fuera de rango (-100..100)'
                 WHEN TRY_CONVERT(DECIMAL(5,2), [csat]) NOT BETWEEN 1 AND 5 THEN N'CSAT fuera de rango (1..5)'
            END AS NVARCHAR(200)) AS [MotivoDescarte]
  FROM S";

    const string Sql_Marketing =
@"WITH S AS (
    SELECT m.*, COALESCE(TRY_CONVERT(DATE, m.[fecha], 23), TRY_CONVERT(DATE, m.[fecha], 103)) AS [FechaD],
           ROW_NUMBER() OVER (PARTITION BY m.[fecha], m.[canal], m.[campana] ORDER BY m.[FilaOrigen]) AS [rnId]
      FROM [GCA].[StageMarketing] m)
SELECT [FilaOrigen], [fecha], [canal], [campana] AS [campana_origen],
       CONVERT(INT, CONVERT(CHAR(8), [FechaD], 112)) AS [FechaNum],
       CAST(LTRIM(RTRIM([canal])) AS NVARCHAR(30)) AS [CanalDigital],
       CAST(LTRIM(RTRIM([campana])) AS NVARCHAR(20)) AS [Campana],
       TRY_CONVERT(DECIMAL(18,2), [inversion]) AS [Inversion], TRY_CONVERT(INT, [leads]) AS [Leads],
       TRY_CONVERT(INT, [nuevos_clientes]) AS [NuevosClientes],
       CAST(CASE WHEN [rnId] > 1 THEN N'Duplicado exacto: misma fecha, canal y campaña (se conservó la primera aparición)'
                 WHEN [FechaD] IS NULL THEN N'Fecha inválida'
                 WHEN TRY_CONVERT(INT, [nuevos_clientes]) > TRY_CONVERT(INT, [leads]) THEN N'Nuevos clientes mayor que leads'
            END AS NVARCHAR(200)) AS [MotivoDescarte]
  FROM S";

    const string Sql_Soporte =
@"WITH S AS (
    SELECT t.*, COALESCE(TRY_CONVERT(DATE, t.[fecha_apertura], 103), TRY_CONVERT(DATE, t.[fecha_apertura], 23)) AS [FechaD],
           TRY_CONVERT(DECIMAL(9,2), t.[horas_resolucion]) AS [Horas]
      FROM [GCA].[StageTicketSoporte] t),
R AS (
    SELECT S.*, CASE WHEN S.[FechaD] BETWEEN c.[FMin] AND c.[FMax] THEN 1 ELSE 0 END AS [EnRango],
           ROW_NUMBER() OVER (PARTITION BY S.[ticket_id] ORDER BY S.[FilaOrigen]) AS [rnId],
           MIN(CASE WHEN S.[FechaD] BETWEEN c.[FMin] AND c.[FMax] THEN S.[ticket_id] END)
               OVER (PARTITION BY S.[cliente_id], S.[horas_resolucion], S.[categoria], S.[sla_cumplido], S.[fase]) AS [Gemelo]
      FROM S " + Rango + @")
SELECT [FilaOrigen], [ticket_id], [cliente_id], [fecha_apertura], [fecha_cierre], [horas_resolucion],
       [ticket_id] AS [TicketID],
       CONVERT(INT, CONVERT(CHAR(8), [FechaD], 112)) AS [FechaNum],
       -- fecha_cierre viene corrupta (""55:34.6""): se reconstruye con apertura + horas de resolución
       DATEADD(SECOND, CAST(ROUND([Horas] * 3600, 0) AS INT), CAST([FechaD] AS DATETIME2(0))) AS [FechaCierre],
       [Horas] AS [HorasResolucion],
       CAST(LTRIM(RTRIM([categoria])) AS NVARCHAR(30)) AS [Categoria],
       CAST(CASE WHEN [sla_cumplido] = N'1' THEN 1 ELSE 0 END AS BIT) AS [SlaCumplido],
       CAST(CASE WHEN [Horas] <= 24 THEN 1 ELSE 0 END AS BIT) AS [SlaRecalculado],
       CAST(CASE WHEN [rnId] > 1 THEN N'Duplicado exacto: ticket_id repetido (se conservó la primera aparición)'
                 WHEN [FechaD] IS NULL THEN N'Fecha de apertura inválida'
                 WHEN [EnRango] = 0 AND [Gemelo] IS NOT NULL THEN N'Duplicado de ' + [Gemelo] + N' con fecha alterada (' + [fecha_apertura] + N')'
                 WHEN [EnRango] = 0 THEN N'Fecha fuera del calendario (' + [fecha_apertura] + N')'
                 WHEN [Horas] IS NULL OR [Horas] < 0 THEN N'Horas de resolución inválidas'
            END AS NVARCHAR(200)) AS [MotivoDescarte]
  FROM R";

    // ================================================================== MAESTROS (proceso_bi parte 2)
    void Master(string name, string tableName, string[] containers, string[][] packages)
    {
        Package pkg = NewPackage(name, tableName, true);
        ConnectionManager adoDwh = C(pkg, AuditConn);
        Executable prev = GetAuditKey(pkg, adoDwh, true);
        for (int i = 0; i < containers.Length; i++)
        {
            Sequence seq = (Sequence)pkg.Executables.Add("STOCK:SEQUENCE");
            seq.Name = containers[i];
            foreach (string p in packages[i])
            {
                TaskHost th = (TaskHost)seq.Executables.Add("Microsoft.ExecutePackageTask");
                th.Name = p;
                th.Description = "Tarea Ejecutar paquete";
                th.Properties["UseProjectReference"].SetValue(th, true);
                th.Properties["PackageName"].SetValue(th, p + ".dtsx");
            }
            pkg.PrecedenceConstraints.Add(prev, seq);
            prev = seq;
        }
        pkg.PrecedenceConstraints.Add(prev, UpdateAudit(pkg, adoDwh, true));
    }
}
