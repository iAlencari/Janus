#requires -Version 5.1
# Monta o Janus-Setup-<versão>.exe: um executável pequeno que pede administrador UMA vez
# e abre a janela de instalação (install.ps1). Usa o compilador C# que já vem no Windows (.NET Framework 4).
# Qualquer pessoa pode rodar este script a partir do código-fonte e gerar o próprio instalador.
# Uso: powershell -ExecutionPolicy Bypass -File instalador\montar-instalador.ps1
# Edição especial: -Edicao caminho\edicao.json (vai junto no instalador) e -Saida pasta onde gravar o .exe
param([string]$Edicao, [string]$Saida)
$ErrorActionPreference = 'Stop'
$Base = Split-Path -Parent $PSCommandPath          # ...\janus\instalador
$App  = Split-Path -Parent $Base                   # ...\janus
$ver  = [regex]::Match([IO.File]::ReadAllText((Join-Path $App 'Janus.ps1')), "\`$AppVersion = '([^']+)'").Groups[1].Value
if (-not $ver) { throw 'Não achei $AppVersion no Janus.ps1' }
$csc = Join-Path $env:windir 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $csc)) { $csc = Join-Path $env:windir 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (-not (Test-Path -LiteralPath $csc)) { throw 'Compilador C# do .NET Framework 4 não encontrado.' }

$stage = Join-Path $env:TEMP ('janus-build-' + [guid]::NewGuid().ToString('N'))
$pay = Join-Path $stage 'payload'
New-Item -ItemType Directory -Path $pay -Force | Out-Null
try {
    foreach ($f in 'install.ps1', 'Janus.ps1', 'idiomas.json', 'Janus.ico', 'uninstall.ps1', 'LICENSE', 'LEIA-ME.txt', 'janus-icone.png') {
        $src = $(if (Test-Path -LiteralPath (Join-Path $Base $f)) { Join-Path $Base $f } else { Join-Path $App $f })
        if (-not (Test-Path -LiteralPath $src)) { throw "Arquivo faltando: $f" }
        Copy-Item -LiteralPath $src -Destination $pay
    }
    $nomeApp = 'Janus'
    if ($Edicao) { Copy-Item -LiteralPath $Edicao -Destination (Join-Path $pay 'edicao.json'); $ed = Get-Content -LiteralPath $Edicao -Raw -Encoding UTF8 | ConvertFrom-Json; if ($ed.Nome) { $nomeApp = [string]$ed.Nome } }
    $zip = Join-Path $stage 'payload.zip'
    Compress-Archive -Path (Join-Path $pay '*') -DestinationPath $zip -CompressionLevel Optimal

    # versão numérica para o arquivo (0.1.0-beta.3 -> 0.1.0.3)
    $m = [regex]::Match($ver, '^(\d+)\.(\d+)\.(\d+)(?:-beta\.(\d+))?$')
    $v4 = '{0}.{1}.{2}.{3}' -f $m.Groups[1].Value, $m.Groups[2].Value, $m.Groups[3].Value, $(if ($m.Groups[4].Success) { $m.Groups[4].Value } else { '0' })
    $cs = [IO.File]::ReadAllText((Join-Path $Base 'setup.cs'), [Text.Encoding]::UTF8).Replace('__NOME__', $nomeApp.Replace('"', '')).Replace('__VERSAO4__', $v4).Replace('__VERSAO__', $ver)
    $csFile = Join-Path $stage 'setup.cs'; [IO.File]::WriteAllText($csFile, $cs, (New-Object Text.UTF8Encoding($true)))

    $outDir = $(if ($Saida) { $Saida } else { Join-Path $App 'saida' })
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $exe = Join-Path $outDir ((($nomeApp -replace '\s+', '-') + "-Setup-$ver.exe"))
    if (Test-Path -LiteralPath $exe) { Remove-Item -LiteralPath $exe -Force }
    $fw = Split-Path -Parent $csc
    $out = & $csc /nologo /target:winexe /platform:anycpu /optimize+ "/out:$exe" "/win32manifest:$(Join-Path $Base 'setup.manifest')" "/win32icon:$(Join-Path $App 'Janus.ico')" "/resource:$zip,payload.zip" `
        "/r:$fw\System.IO.Compression.dll" "/r:$fw\System.IO.Compression.FileSystem.dll" '/r:System.Windows.Forms.dll' $csFile
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $exe)) { throw ("O compilador falhou:`n" + ($out -join "`n")) }
} finally { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
Write-Output ("Instalador: {0} ({1} KB)" -f $exe, [math]::Round((Get-Item -LiteralPath $exe).Length / 1KB))
Write-Output ("SHA-256: " + (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash)
