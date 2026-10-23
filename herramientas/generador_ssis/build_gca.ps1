# Genera stage_GCA.ispac y DWH_GCA.ispac con la API de SSIS 2025 (mismas DLL del GAC que H&M)
param([string]$Datos = 'C:\Users\Juan\Repositorios\inteligenciaNegocios\Lab Integrador Grupo Comercial Andino\Lab Integrador Grupo Comercial Andino\data_ventas')
$ErrorActionPreference = 'Stop'
$sp  = Split-Path -Parent $MyInvocation.MyCommand.Path
$gac = 'C:\WINDOWS\Microsoft.Net\assembly'
$v   = 'v4.0_17.0.0.0__89845dcd8080cc91'
$refs = @(
  "$gac\GAC_MSIL\Microsoft.SqlServer.ManagedDTS\$v\Microsoft.SqlServer.ManagedDTS.dll",
  "$gac\GAC_64\Microsoft.SqlServer.DTSRuntimeWrap\$v\Microsoft.SqlServer.DTSRuntimeWrap.dll",
  "$gac\GAC_MSIL\Microsoft.SqlServer.DTSPipelineWrap\$v\Microsoft.SqlServer.DTSPipelineWrap.dll",
  "$gac\GAC_64\Microsoft.SqlServer.SQLTask\$v\Microsoft.SqlServer.SQLTask.dll",
  "$gac\GAC_MSIL\Microsoft.SqlServer.SQLTaskConnectionsWrap\$v\Microsoft.SqlServer.SQLTaskConnectionsWrap.dll",
  'System.Core.dll'
)
Add-Type -Path "$sp\GCABuilder.cs" -ReferencedAssemblies $refs -IgnoreWarnings

$out = "$sp\out"
New-Item -ItemType Directory -Force $out | Out-Null
function Run([scriptblock]$b) {
  try { & $b } catch { $e = $_.Exception; while ($e.InnerException) { $e = $e.InnerException }; $e.Message; $e.StackTrace; throw }
}
Run { (New-Object GCABuilder).BuildStage("$out\stage_GCA.ispac", $Datos) }
'stage_GCA.ispac OK'
Run { (New-Object GCABuilder).BuildDwh("$out\DWH_GCA.ispac") }
'DWH_GCA.ispac OK'
