param([string]$BimPath, [string]$Server = "localhost\TABULAR", [string]$Db = "Tabular_GCA")
$ErrorActionPreference = "Stop"
$gac = "C:\Windows\Microsoft.NET\assembly\GAC_MSIL"
foreach ($n in "Microsoft.AnalysisServices.Core", "Microsoft.AnalysisServices") {
    $dll = Get-ChildItem "$gac\$n" -Recurse -Filter "$n.dll" | Sort-Object FullName -Descending | Select-Object -First 1
    Add-Type -Path $dll.FullName
}
$bim = Get-Content $BimPath -Raw -Encoding UTF8 | ConvertFrom-Json
$bim.name = $Db; $bim.id = $Db
$bim.model | Add-Member -NotePropertyName name -NotePropertyValue "Modelo" -Force
$tmsl = @{ createOrReplace = @{ object = @{ database = $Db }; database = $bim } } | ConvertTo-Json -Depth 50 -Compress
# procesamiento de a una tabla (maxParallelism = 1): en una PC con poca RAM, procesar en paralelo
# deja a SQL Server sin memoria y el cubo nunca termina
$refresh = @{ sequence = @{ maxParallelism = 1; operations = @(@{ refresh = @{ type = "full"; objects = @(@{ database = $Db }) } }) } } |
           ConvertTo-Json -Depth 10 -Compress

$s = New-Object Microsoft.AnalysisServices.Server
$s.Connect($Server)
foreach ($cmd in @(@("DEPLOY", $tmsl), @("PROCESS", $refresh))) {
    $res = $s.Execute($cmd[1])
    $errs = foreach ($r in $res) { foreach ($m in $r.Messages) { $m.Description } }
    if ($errs) { "$($cmd[0]) ERRORES:"; $errs; $s.Disconnect(); exit 1 } else { "$($cmd[0]) OK" }
}
$s.Disconnect()
