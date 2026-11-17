#requires -Version 5.1
# Publica uma versão do Janus: monta o instalador, gera o manifesto (SHA-256 de cada arquivo),
# assina com a sua chave privada (pede a senha) e cria o Release no GitHub com o "gh".
# Uso: powershell -ExecutionPolicy Bypass -File ferramentas\publicar.ps1 -Notas "O que mudou"
#      -SemEnviar   só prepara e assina em saida\release-<versão>, sem enviar ao GitHub
param([string]$Notas = '', [string]$NotasArquivo = '', [switch]$SemEnviar,
      [string]$Chave = (Join-Path (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Janus-chave') 'janus-assinatura.pfx'))
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$App  = Join-Path $Repo 'Janus.ps1'
$src  = [IO.File]::ReadAllText($App, [Text.Encoding]::UTF8)
$ver  = [regex]::Match($src, "\`$AppVersion = '([^']+)'").Groups[1].Value
$pub  = [regex]::Match($src, "(?m)^\`$PublicKeyXml = '(.*)'").Groups[1].Value
$owner = [regex]::Match($src, "\`$RepoOwner = '([^']+)'").Groups[1].Value
$name  = [regex]::Match($src, "\`$RepoName = '([^']+)'").Groups[1].Value
if (-not $pub) { throw 'O Janus.ps1 ainda não tem chave pública. Rode antes: ferramentas\criar-chave.ps1' }
if (-not (Test-Path -LiteralPath $Chave)) { throw "Chave privada não encontrada: $Chave" }
Write-Host "Janus $ver -> $owner/$name" -ForegroundColor Cyan

# 1) instalador
& (Join-Path $Repo 'instalador\montar-instalador.ps1')
$out = Join-Path $Repo ("saida\release-$ver")
if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force }
New-Item -ItemType Directory -Path $out | Out-Null
foreach ($f in 'Janus.ps1', 'idiomas.json', 'Janus.ico') { Copy-Item -LiteralPath (Join-Path $Repo $f) -Destination $out }
Move-Item -LiteralPath (Join-Path $Repo "saida\Janus-Setup-$ver.exe") -Destination $out

# 2) manifesto
$files = @(Get-ChildItem -LiteralPath $out -File | Sort-Object Name | ForEach-Object { [ordered]@{ name = $_.Name; sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLower(); size = $_.Length } })
$avisosFile = Join-Path $PSScriptRoot 'avisos.json'
$avisos = $(if (Test-Path -LiteralPath $avisosFile) { @((Get-Content -LiteralPath $avisosFile -Raw -Encoding UTF8 | ConvertFrom-Json)) } else { @() })
$man = [ordered]@{ app = 'Janus'; version = $ver; date = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); repo = "$owner/$name"; files = $files; avisos = $avisos }
$manBytes = [Text.Encoding]::UTF8.GetBytes(($man | ConvertTo-Json -Depth 6))
[IO.File]::WriteAllBytes((Join-Path $out 'manifesto.json'), $manBytes)

# 3) assinatura (a senha é digitada por você)
$pw = Read-Host 'Senha da chave de assinatura' -AsSecureString
$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($Chave, $pw, 'EphemeralKeySet')
$rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
$sig = $rsa.SignData($manBytes, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
$sigB64 = [Convert]::ToBase64String($sig)
Set-Content -LiteralPath (Join-Path $out 'manifesto.sig') -Value $sigB64 -Encoding ASCII -NoNewline
$cert.Dispose()
# confere com a chave pública que está dentro do app, do mesmo jeito que o app vai conferir
$chk = New-Object System.Security.Cryptography.RSACryptoServiceProvider; $chk.PersistKeyInCsp = $false; $chk.FromXmlString($pub)
if (-not $chk.VerifyData($manBytes, 'SHA256', $sig)) { throw 'A assinatura não bate com a chave pública do Janus.ps1. Nada foi publicado.' }
Write-Host "Assinado e conferido: $out" -ForegroundColor Green
Get-ChildItem -LiteralPath $out | ForEach-Object { Write-Host ('  ' + $_.Name) }
if ($SemEnviar) { return }

# 4) GitHub
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'O GitHub CLI (gh) não está instalado.' }
if ($NotasArquivo) { $Notas = [IO.File]::ReadAllText($NotasArquivo) }
if (-not $Notas) { $Notas = "Janus $ver" }
$fv = $ver -replace '^(\d+\.\d+)\.0', '$1' -replace '-beta\.(\d+)$', ' beta $1'
$args1 = @('release', 'create', "v$ver", '--repo', "$owner/$name", '--title', "Janus $fv", '--notes', $Notas)
if ($ver -match '-beta') { $args1 += '--prerelease' }
$args1 += @(Get-ChildItem -LiteralPath $out -File | ForEach-Object { $_.FullName })
& gh @args1
if ($LASTEXITCODE) { throw "gh falhou (código $LASTEXITCODE)" }
Write-Host "Publicado: https://github.com/$owner/$name/releases/tag/v$ver" -ForegroundColor Green
