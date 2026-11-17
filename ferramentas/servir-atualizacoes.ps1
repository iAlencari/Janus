#requires -Version 5.1
# Serve a pasta de atualizações do Janus na internet, de graça, pelo túnel rápido da Cloudflare.
# Sobe um servidor local que só entrega arquivos DENTRO da pasta (só leitura) e abre o túnel.
# O endereço https://....trycloudflare.com aparece na tela e MUDA a cada vez que você roda.
# Feche a janela (ou Ctrl+C) para tirar tudo do ar.
# Uso:  powershell -ExecutionPolicy Bypass -File ferramentas\servir-atualizacoes.ps1
#       -Pasta <pasta>   outra pasta (padrão: janus\atualizacoes-servidor)
#       -Porta 8080      porta local
#       -SemTunel        só o servidor local (para testar sem expor nada)
param([string]$Pasta, [int]$Porta = 8080, [switch]$SemTunel)
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
if (-not $Pasta) { $Pasta = Join-Path $Repo 'atualizacoes-servidor' }
New-Item -ItemType Directory -Force -Path $Pasta | Out-Null
$Raiz = [IO.Path]::GetFullPath($Pasta).TrimEnd('\') + '\'

$tipos = @{ '.json' = 'application/json'; '.ps1' = 'text/plain; charset=utf-8'; '.txt' = 'text/plain; charset=utf-8'; '.md' = 'text/plain; charset=utf-8'
            '.exe' = 'application/octet-stream'; '.zip' = 'application/zip'; '.ico' = 'image/x-icon'; '.png' = 'image/png'; '.sig' = 'text/plain'; '.xml' = 'application/xml' }

Write-Host ''
Write-Host 'Janus: servidor de atualizações' -ForegroundColor Cyan
Write-Host "Pasta servida: $Raiz"
$arqs = @(Get-ChildItem -LiteralPath $Raiz -File -Recurse -ErrorAction SilentlyContinue)
if ($arqs.Count) { foreach ($a in $arqs) { Write-Host ('  - {0}  ({1} KB)' -f $a.FullName.Substring($Raiz.Length), [math]::Round($a.Length / 1KB, 1)) } }
else { Write-Host '  (a pasta está vazia: coloque nela os arquivos da versão, por exemplo Janus.ps1, idiomas.json e o manifesto assinado)' -ForegroundColor Yellow }

$http = New-Object System.Net.HttpListener
$http.Prefixes.Add("http://localhost:$Porta/")
try { $http.Start() } catch { Write-Host "Não consegui abrir a porta $Porta (já está em uso?). Use -Porta 8081, por exemplo." -ForegroundColor Red; exit 1 }

$cf = $null; $url = ''
if (-not $SemTunel) {
    $exe = $(if (Get-Command cloudflared -ErrorAction SilentlyContinue) { (Get-Command cloudflared).Source } else { 'C:\Program Files (x86)\cloudflared\cloudflared.exe' })
    if (-not (Test-Path -LiteralPath $exe)) {
        Write-Host 'Não achei o cloudflared. Instale com:  winget install Cloudflare.cloudflared  e abra um terminal novo.' -ForegroundColor Red
        $http.Stop(); exit 1
    }
    $log = Join-Path $env:TEMP 'janus-tunel.log'; Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
    # --http-host-header: o servidor local só aceita "localhost"
    $cf = Start-Process -FilePath $exe -ArgumentList @('tunnel', '--no-autoupdate', '--http-host-header', "localhost:$Porta", '--url', "http://localhost:$Porta") -PassThru -WindowStyle Hidden -RedirectStandardError $log -RedirectStandardOutput (Join-Path $env:TEMP 'janus-tunel-out.log')
    Write-Host 'Abrindo o túnel...' -ForegroundColor DarkGray
    for ($i = 0; $i -lt 60 -and -not $url; $i++) {
        Start-Sleep -Milliseconds 500
        if ($cf.HasExited) { break }
        if (Test-Path -LiteralPath $log) { $m = [regex]::Match((Get-Content -LiteralPath $log -Raw -ErrorAction SilentlyContinue), 'https://[a-z0-9\-]+\.trycloudflare\.com'); if ($m.Success) { $url = $m.Value } }
    }
    if (-not $url) {
        Write-Host 'O túnel não abriu. Últimas linhas do registro:' -ForegroundColor Red
        if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Tail 8 }
        try { if (-not $cf.HasExited) { $cf.Kill() } } catch {}; $http.Stop(); exit 1
    }
}
Write-Host ''
if ($url) {
    Write-Host 'No ar! Endereço para passar aos testadores:' -ForegroundColor Green
    Write-Host "  $url" -ForegroundColor White
} else { Write-Host "Servidor local (sem túnel): http://localhost:$Porta/" -ForegroundColor Green }
Write-Host 'Só arquivos desta pasta são entregues. Feche esta janela (ou Ctrl+C) para tirar do ar.' -ForegroundColor DarkGray
Write-Host ''

try {
    while ($http.IsListening) {
        $ar = $http.BeginGetContext($null, $null)
        while (-not $ar.AsyncWaitHandle.WaitOne(400)) { if ($cf -and $cf.HasExited) { Write-Host 'O túnel caiu. Rode o script de novo.' -ForegroundColor Red; return } }
        $ctx = $http.EndGetContext($ar); $rq = $ctx.Request; $rs = $ctx.Response
        $status = 200; $bytes = $null
        try {
            if ($rq.HttpMethod -notin 'GET', 'HEAD') { $status = 405 }
            else {
                $rel = [Uri]::UnescapeDataString($rq.Url.AbsolutePath).TrimStart('/') -replace '/', '\'
                $alvo = [IO.Path]::GetFullPath((Join-Path $Raiz $rel))
                # nunca sai da pasta (bloqueia "..\" e caminhos absolutos)
                if (-not $alvo.StartsWith($Raiz, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $alvo -PathType Leaf)) { $status = 404 }
                else {
                    $bytes = [IO.File]::ReadAllBytes($alvo)
                    $ext = [IO.Path]::GetExtension($alvo).ToLower()
                    $rs.ContentType = $(if ($tipos.ContainsKey($ext)) { $tipos[$ext] } else { 'application/octet-stream' })
                    $rs.Headers.Add('Cache-Control', 'no-store')
                }
            }
        } catch { $status = 400 }
        $rs.StatusCode = $status
        if ($status -eq 200 -and $rq.HttpMethod -eq 'GET') { $rs.ContentLength64 = $bytes.Length; $rs.OutputStream.Write($bytes, 0, $bytes.Length) }
        elseif ($status -ne 200) { $msg = [Text.Encoding]::UTF8.GetBytes([string]$status); $rs.ContentLength64 = $msg.Length; $rs.OutputStream.Write($msg, 0, $msg.Length) }
        $rs.OutputStream.Close()
        Write-Host ('{0}  {1}  {2}  {3}' -f (Get-Date -Format 'HH:mm:ss'), $status, $rq.HttpMethod, $rq.Url.AbsolutePath)
    }
} finally {
    try { $http.Stop(); $http.Close() } catch {}
    try { if ($cf -and -not $cf.HasExited) { $cf.Kill() } } catch {}
    Write-Host 'Servidor e túnel encerrados.' -ForegroundColor DarkGray
}
