# Ejecuta una consulta DAX contra el cubo y muestra el resultado (validaciones).
param([Parameter(Mandatory)][string]$Dax, [string]$Server = "localhost\TABULAR", [string]$Catalogo = "Tabular_GCA")
$ErrorActionPreference = "Stop"
$dll = Get-ChildItem "C:\Windows\Microsoft.NET\assembly\GAC_MSIL\Microsoft.AnalysisServices.AdomdClient" -Recurse -Filter "*.dll" |
       Sort-Object FullName -Descending | Select-Object -First 1
Add-Type -Path $dll.FullName
$cn = New-Object Microsoft.AnalysisServices.AdomdClient.AdomdConnection "Data Source=$Server;Catalog=$Catalogo"
$cn.Open()
$cmd = $cn.CreateCommand(); $cmd.CommandText = $Dax
$r = $cmd.ExecuteReader()
$cols = 0..($r.FieldCount - 1) | ForEach-Object { $r.GetName($_) -replace '^.*\[(.*)\]$', '$1' }
$rows = while ($r.Read()) {
    $o = [ordered]@{}; for ($i = 0; $i -lt $r.FieldCount; $i++) { $o[$cols[$i]] = $r.GetValue($i) }; [pscustomobject]$o
}
$cn.Close()
$rows | Format-Table -AutoSize | Out-String -Width 250
