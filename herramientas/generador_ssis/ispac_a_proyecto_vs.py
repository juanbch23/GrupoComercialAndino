"""Crea (o actualiza) un proyecto SSIS de Visual Studio a partir de un .ispac generado por GCABuilder.
Uso: python ispac_a_proyecto_vs.py <archivo.ispac> <carpeta_solucion> <nombre_proyecto>
Genera <carpeta_solucion>/<nombre>/<nombre>.dtproj (+ .database, .dtproj.user) con el <Manifest> del .ispac."""
import sys, os, re, zipfile, urllib.parse
from xml.sax.saxutils import escape

ispac, soldir, name = sys.argv[1], sys.argv[2], sys.argv[3]
projdir = os.path.join(soldir, name)
os.makedirs(projdir, exist_ok=True)
for f in os.listdir(projdir):                      # se reemplazan los paquetes y conexiones anteriores
    if f.endswith((".dtsx", ".conmgr")):
        os.remove(os.path.join(projdir, f))

manifest = None
with zipfile.ZipFile(ispac) as z:
    for n in z.namelist():
        fn = urllib.parse.unquote(n)
        if fn == "@Project.manifest":
            manifest = z.read(n).decode("utf-8-sig")
        elif fn.endswith((".dtsx", ".conmgr")) or fn == "Project.params":
            with open(os.path.join(projdir, fn), "wb") as o:
                o.write(z.read(n))
manifest = re.sub(r"<\?xml[^>]*\?>\s*", "", manifest).strip()
manifest = re.sub(r'\s*<SSIS:Property SSIS:Name="TargetServerVersion">\d+</SSIS:Property>', "", manifest)
manifest = "\n".join("      " + l for l in manifest.splitlines())
n = escape(name)

dtproj = f"""<?xml version="1.0" encoding="utf-8"?>
<Project xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <DeploymentModel>Project</DeploymentModel>
  <ProductVersion>17.0.1016.0</ProductVersion>
  <SchemaVersion>9.0.1.0</SchemaVersion>
  <Database>
    <Name>{n}.database</Name>
    <FullPath>{n}.database</FullPath>
  </Database>
  <DataSources />
  <DataSourceViews />
  <DeploymentModelSpecificContent>
    <Manifest>
{manifest}
    </Manifest>
  </DeploymentModelSpecificContent>
  <ControlFlowParts />
  <Miscellaneous />
  <Configurations>
    <Configuration>
      <Name>Development</Name>
      <Options>
        <OutputPath>bin</OutputPath>
        <ConnectionMappings />
        <ConnectionProviderMappings />
        <ConnectionSecurityMappings />
        <DatabaseStorageLocations />
        <TargetServerVersion>SQLServer2025</TargetServerVersion>
        <AzureMode>false</AzureMode>
        <LinkedAzureTenantId />
        <LinkedAzureAccountId />
        <LinkedAzureSSISIR />
        <LinkedAzureStorage />
        <RemoteExecutionFolder />
        <ParameterConfigurationValues />
      </Options>
    </Configuration>
  </Configurations>
</Project>
"""
database = f"""<Database xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://schemas.microsoft.com/analysisservices/2003/engine">
  <ID>{n}</ID>
  <Name>{n}</Name>
  <CreatedTimestamp>0001-01-01T00:00:00Z</CreatedTimestamp>
  <LastSchemaUpdate>0001-01-01T00:00:00Z</LastSchemaUpdate>
  <LastProcessed>0001-01-01T00:00:00Z</LastProcessed>
  <State>Unprocessed</State>
  <LastUpdate>0001-01-01T00:00:00Z</LastUpdate>
  <DataSourceImpersonationInfo>
    <ImpersonationMode>Default</ImpersonationMode>
    <ImpersonationInfoSecurity>Unchanged</ImpersonationInfoSecurity>
  </DataSourceImpersonationInfo>
</Database>
"""
user = """<?xml version="1.0" encoding="utf-8"?>
<DataTransformationsUserConfiguration xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <Configurations>
    <Configuration>
      <Name>Development</Name>
      <Options>
        <UseWinAuth>false</UseWinAuth>
        <OfflineMode>false</OfflineMode>
        <ProgressReporting>true</ProgressReporting>
        <ParameterConfigurationSensitiveValues />
      </Options>
    </Configuration>
  </Configurations>
</DataTransformationsUserConfiguration>
"""
for fn, txt in [(name + ".dtproj", dtproj), (name + ".database", database), (name + ".dtproj.user", user)]:
    with open(os.path.join(projdir, fn), "w", encoding="utf-8-sig", newline="\r\n") as o:
        o.write(txt)
print(name, "OK:", sorted(f for f in os.listdir(projdir) if f.endswith((".dtsx", ".conmgr", ".params"))))
