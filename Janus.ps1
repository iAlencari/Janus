#requires -Version 5.1
<#
  Janus - ajustes do Windows explicados e reversíveis (beta)
  Ideia e pedido: iAlencari | Criado com Claude Code (claude.ai/code): escrito com Claude Opus 5.5, revisado com Claude Fable 5.2
  Licença: GPL-3.0 (veja LICENSE). O nome "Janus" e o ícone são do projeto original: versões modificadas usam outro nome.
  Janus é o deus romano das portas, com duas faces: uma olha para frente, outra para trás. Aqui: aplicar e desfazer.
  - Todo ajuste vem DESLIGADO quando o Windows está no padrão. Ligar = aplicar. Desligar = voltar ao padrão.
  - O botão lê o estado REAL do Windows (registro, energia, dispositivo), não uma memória do app.
  - As leituras rodam em segundo plano (outra thread): a janela nunca trava esperando o Windows.
  - Abas em destaque: Sugestões (no topo) e Ativos (no fim). Automação lê o PC e decide sozinha.
  - Antes da primeira mudança da sessão: ponto de restauração. Antes de cada mudança: backup .reg.
  - Dados (log, backups, ajuda, relatórios, config.json): ao lado do script, ou em %LOCALAPPDATA%\Janus se instalado.
  - Atualizações e selo de autenticidade: Releases do GitHub, conferidos por assinatura digital (RSA + SHA-256).
  Teste sem abrir janela: powershell -STA -File Janus.ps1 -Teste
#>
param([switch]$Teste, [switch]$Bandeja, [switch]$SoRelatorio, [string]$Idioma, [string]$Pagina, [string]$Descartadas)

$ErrorActionPreference = 'Stop'
$Pasta      = Split-Path -Parent $PSCommandPath
$Instalado  = ($Pasta -like ($env:ProgramFiles + '*')) -or ($env:ProgramW6432 -and ($Pasta -like ($env:ProgramW6432 + '*'))) -or (Test-Path -LiteralPath (Join-Path $Pasta 'instalado.txt'))   # instalado.txt: o instalador permite escolher outra pasta
$DataDir    = $(if ($Instalado) { Join-Path $env:LOCALAPPDATA 'Janus' } else { $Pasta })
$LogFile    = Join-Path $DataDir 'log.txt'
$BackupDir  = Join-Path $DataDir 'backups'
$IconPath   = $(if (Test-Path -LiteralPath (Join-Path $Pasta 'Janus.ico')) { Join-Path $Pasta 'Janus.ico' } else { Join-Path $DataDir 'Janus.ico' })
$HelpDir    = Join-Path $DataDir 'ajuda'
$ConfigFile = Join-Path $DataDir 'config.json'
$ReportDir  = Join-Path $DataDir 'relatorios'
$LockFile   = Join-Path $DataDir 'sessao.lock'
$ShowReq    = Join-Path $DataDir 'mostrar.pedido'   # outra cópia do Janus pede para esta aparecer
$CloseReq   = Join-Path $DataDir 'fechar.pedido'    # pedido para fechar de vez (mesmo nos ícones ocultos)
$CrashFile  = Join-Path $DataDir 'ultimo-erro.txt'
$LangFile   = Join-Path $Pasta 'idiomas.json'
# Edição especial (opcional): edicao.json ao lado do Janus.ps1. Ex.: { "Nome": "Janus Beta", "Selo": "Amigo Exclusive Edition", "Idioma": "en" }
$Edition = @{}
$EdFile = Join-Path $Pasta 'edicao.json'
if (Test-Path -LiteralPath $EdFile) { try { $ej = Get-Content -LiteralPath $EdFile -Raw -Encoding UTF8 | ConvertFrom-Json; foreach ($p in $ej.PSObject.Properties) { $Edition[$p.Name] = $p.Value } } catch {} }
$AppName = $(if ($Edition.Nome) { [string]$Edition.Nome } else { 'Janus' })
$AppVersion = '0.1.0-beta.3'       # beta enquanto o app está sendo construído; a primeira versão "de verdade" será 0.1.0 ou 1.0.0
$RepoOwner  = 'iAlencari'
$RepoName   = 'Janus'
$RepoUrl    = "https://github.com/$RepoOwner/$RepoName"
# Chave PÚBLICA de assinatura (só confere; não assina). Preenchida por ferramentas\criar-chave.ps1.
$PublicKeyXml = '<RSAKeyValue><Modulus>v2PkPZ/VTBkRIjn41W5wf+A11yCzMZdkUStkST/cJN8i1qW8jn4hAzvb5kTiG7dU8uI/en5Qlybv7A+XPyIgTavJ0gkqBDoprNpE9nK01JNFfvgMDxMS/EYXFZsjEh74trpNYrH/0RMiOJ/ACjgqC40eCQzrkPRqzkSIg3mGoZQBLp6EMr7s2eJsKwQG4cbbvNaRlQCMkwq5ybs46wIdl+9Q2GriVCCh6ZpJ0VvoHqVdx1qrN24UHj/yLBwADpW06sy9bnXRVlzFKQKl79LRzc7mIz1xqoW6y7eSeMEyHwnInCDfT9j4X/JTbOTbGzWaLwI1N4qe8kn32CH9tpT0HtleExcd/3jHwkVnJWOKqtCrK4ZCqXm2FPzJP1NfGOS5acCY/lxI13SyoUnwptwOsHZe5+jT22q7yynxZQkMa6yMJJ6ze/BvrAd19E+8gRMoMaluPWRsLfGm34g6m0LEPCe/xwKq7ZhQd8mKCPw/kd1QD6iIiKbslXMCVgmO05Lp</Modulus><Exponent>AQAB</Exponent></RSAKeyValue>'
New-Item -ItemType Directory -Force -Path $DataDir, $BackupDir, $HelpDir, $ReportDir | Out-Null
function Format-Version([string]$v) {
    # "0.1.0-beta.2" -> "0.1.0 - beta 2"
    $m = [regex]::Match($v, '^(\d+\.\d+\.\d+)(?:-beta\.(\d+))?$')
    if (-not $m.Success) { return $v }
    if ($m.Groups[2].Success) { return ('{0} - beta {1}' -f $m.Groups[1].Value, $m.Groups[2].Value) }
    return $m.Groups[1].Value
}
# compara versões: 1 se a > b, -1 se a < b, 0 se iguais (beta vem antes da versão final)
function Compare-AppVersion([string]$a, [string]$b) {
    function P($v) { $m = [regex]::Match(($v -replace '^v', ''), '^(\d+)\.(\d+)\.(\d+)(?:-beta\.(\d+))?$'); if (-not $m.Success) { return $null }
        return @([int]$m.Groups[1].Value, [int]$m.Groups[2].Value, [int]$m.Groups[3].Value, $(if ($m.Groups[4].Success) { [int]$m.Groups[4].Value } else { [int]::MaxValue })) }
    $x = P $a; $y = P $b; if (-not $x -or -not $y) { return 0 }
    for ($i = 0; $i -lt 4; $i++) { if ($x[$i] -gt $y[$i]) { return 1 }; if ($x[$i] -lt $y[$i]) { return -1 } }
    return 0
}

# ---------- administrador ----------
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    if ($Teste) { Write-Output 'AVISO: teste sem administrador; leituras de sistema podem falhar.' }
    else {
        # opção "abrir sem a tela de administrador": uma tarefa agendada (criada com permissão) abre o Janus já como administrador
        if (-not $SoRelatorio) {
            $tn = '\Janus\Abrir o Janus'
            $tx = & schtasks.exe /query /tn $tn /xml 2>$null
            if ($LASTEXITCODE -eq 0 -and (($tx -join '') -like ('*' + $PSCommandPath + '*'))) { $null = & schtasks.exe /run /tn $tn 2>$null; if ($LASTEXITCODE -eq 0) { exit } }
        }
        $fwd = @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-WindowStyle','Hidden','-File',"`"$PSCommandPath`"")
        if ($SoRelatorio) { $fwd += '-SoRelatorio' }
        Start-Process powershell.exe -Verb RunAs -ArgumentList $fwd
        exit
    }
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing
if (-not ('PANative' -as [type])) {
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class PANative {
  [DllImport("user32.dll", SetLastError=true)] public static extern bool SystemParametersInfo(uint a, uint b, int[] c, uint d);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool SystemParametersInfo(uint a, uint b, IntPtr c, uint d);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool SystemParametersInfo(uint a, uint b, ref bool c, uint d);
  [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, UIntPtr w, string l, uint f, uint t, out UIntPtr r);
  [DllImport("shell32.dll", SetLastError=true)] public static extern int SetCurrentProcessExplicitAppUserModelID([MarshalAs(UnmanagedType.LPWStr)] string id);
  public static void Broadcast(string area){ UIntPtr r; SendMessageTimeout((IntPtr)0xffff, 0x1A, UIntPtr.Zero, area, 2, 3000, out r); }
}
"@
}
# ID próprio na barra de tarefas: assim ela mostra o ícone do Janus, e não o do PowerShell
try { [void][PANative]::SetCurrentProcessExplicitAppUserModelID('iAlencari.Janus') } catch {}

# ---------- leituras (usadas na janela E na thread de segundo plano) ----------
# Este bloco é texto para poder ser carregado também no "runspace" de segundo plano.
$HelperCode = @'
function Get-RegValue([string]$path, [string]$name) {
    try { (Get-ItemProperty -LiteralPath $path -Name $name -ErrorAction Stop).$name } catch { $null }
}
function Get-PowerIndex([string]$sub, [string]$setting) {
    $q = & powercfg /q SCHEME_CURRENT $sub $setting 2>$null
    $hex = @($q | Select-String -Pattern ':\s*0x([0-9a-fA-F]+)\s*$' | ForEach-Object { [Convert]::ToInt32($_.Matches[0].Groups[1].Value, 16) })
    # as duas últimas linhas são sempre o valor atual na tomada (AC) e na bateria (DC); antes delas podem vir mínimo/máximo possíveis
    if ($hex.Count -ge 2) { return $hex[-2] } elseif ($hex.Count -eq 1) { return $hex[0] } else { return $null }
}
function Get-IGpu {
    $all = @(Get-PnpDevice -Class Display -ErrorAction SilentlyContinue | Where-Object { $_.Present })
    # só conta como "integrado que dá para desligar" se existir também uma placa de vídeo dedicada
    if (-not @($all | Where-Object { $_.FriendlyName -match 'NVIDIA|Radeon RX|Radeon Pro|Arc\(TM\) A|Arc A\d' }).Count) { return $null }
    $all | Where-Object { $_.FriendlyName -match 'AMD Radeon\(TM\)|AMD Radeon Graphics|Intel\(R\) (UHD|Iris|HD) Graphics|Intel\(R\) Graphics' -and $_.FriendlyName -notmatch 'RX|Pro|Arc' } | Select-Object -First 1
}
function Read-SecurityStatus {
    $out = New-Object System.Collections.ArrayList
    $mp = $null; try { $mp = Get-MpComputerStatus -ErrorAction Stop } catch {}
    function A($name, $value, $level) { [void]$out.Add(@{ Name = $name; Value = $value; Level = $level; Ok = ($level -eq 'ok') }) }
    if ($mp) {
        A 'Antivírus em tempo real' $(if ($mp.RealTimeProtectionEnabled) { 'Ligado' } else { 'DESLIGADO' }) $(if ($mp.RealTimeProtectionEnabled) { 'ok' } else { 'crit' })
        A 'Proteção contra adulteração' $(if ($mp.IsTamperProtected) { 'Ligada' } else { 'DESLIGADA' }) $(if ($mp.IsTamperProtected) { 'ok' } else { 'crit' })
        $age = ((Get-Date) - $mp.AntivirusSignatureLastUpdated).TotalDays
        A 'Assinaturas do Defender' ($mp.AntivirusSignatureLastUpdated.ToString('dd/MM HH:mm')) $(if ($age -lt 2) { 'ok' } elseif ($age -lt 7) { 'warn' } else { 'crit' })
        $q = $mp.QuickScanEndTime
        if ($q) { $qa = ((Get-Date) - $q).TotalDays; A 'Última verificação rápida' ($q.ToString('dd/MM HH:mm')) $(if ($qa -lt 8) { 'ok' } else { 'warn' }) } else { A 'Última verificação rápida' 'nunca' 'warn' }
    } else { A 'Microsoft Defender' 'não consegui ler' 'crit' }
    try { $sb = Confirm-SecureBootUEFI -ErrorAction Stop; A 'Secure Boot' $(if ($sb) { 'Ativo' } else { 'Desligado' }) $(if ($sb) { 'ok' } else { 'warn' }) } catch { A 'Secure Boot' 'não consegui ler' 'warn' }
    try { $tpm = Get-Tpm -ErrorAction Stop; A 'TPM 2.0' $(if ($tpm.TpmReady) { 'Pronto' } else { 'Não pronto' }) $(if ($tpm.TpmReady) { 'ok' } else { 'warn' }) } catch { A 'TPM 2.0' 'não consegui ler' 'warn' }
    try { $dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction Stop; $h = @($dg.SecurityServicesRunning) -contains 2; A 'Integridade de memória' $(if ($h) { 'Ativa' } else { 'Inativa' }) $(if ($h) { 'ok' } else { 'warn' }) } catch { A 'Integridade de memória' 'não consegui ler' 'warn' }
    $uac = (Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'EnableLUA') -eq 1
    A 'Controle de Conta (UAC)' $(if ($uac) { 'Ligado' } else { 'DESLIGADO' }) $(if ($uac) { 'ok' } else { 'crit' })
    try { $fw = @(Get-NetFirewallProfile -ErrorAction Stop | Where-Object { -not $_.Enabled }).Count -eq 0; A 'Firewall' $(if ($fw) { 'Ligado nos 3 perfis' } else { 'Algum perfil desligado' }) $(if ($fw) { 'ok' } else { 'crit' }) } catch { A 'Firewall' 'não consegui ler' 'warn' }
    $ex = @(); if ($mp) { try { $ex = @((Get-MpPreference -ErrorAction Stop).ExclusionPath | Where-Object { $_ }) } catch {} }
    A 'Exclusões no Defender' $(if ($ex.Count) { "$($ex.Count) pasta(s)" } else { 'Nenhuma' }) $(if ($ex.Count) { 'warn' } else { 'ok' })
    return $out
}
function Read-PcInfo {
    $pc = @{}
    $os = Get-CimInstance Win32_OperatingSystem
    $pc.Windows = '{0} | build {1}.{2}' -f ($os.Caption -replace 'Microsoft ', ''), $os.BuildNumber, (Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' 'UBR')
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $pc.Cpu = '{0} | {1} núcleos, {2} threads' -f $cpu.Name.Trim(), $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors
    $vcs = @(Get-CimInstance Win32_VideoController)
    $disc = @($vcs | Where-Object { $_.Name -match 'NVIDIA|Radeon RX|Arc' })
    $pc.Gpu = (($disc | ForEach-Object { '{0} (driver {1})' -f $_.Name, $_.DriverVersion }) -join '; ')
    if (-not $pc.Gpu) { $pc.Gpu = (($vcs | ForEach-Object { $_.Name }) -join '; ') }
    $active = @($vcs | Where-Object { $_.CurrentHorizontalResolution })
    $pc.Tela = (($active | ForEach-Object { '{0}x{1} a {2} Hz' -f $_.CurrentHorizontalResolution, $_.CurrentVerticalResolution, $_.CurrentRefreshRate } | Select-Object -Unique) -join '; ')
    $pc.DisplayOnDiscrete = (@($active | Where-Object { $_.Name -match 'NVIDIA|Radeon RX|Arc' }).Count -gt 0)
    try {
        $mid = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction Stop | Where-Object Active | Select-Object -First 1
        $mname = -join ($mid.UserFriendlyName | Where-Object { $_ } | ForEach-Object { [char]$_ })
        $con = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorConnectionParams -ErrorAction Stop | Where-Object Active | Select-Object -First 1
        $map = @{ '0'='VGA'; '4'='DVI'; '5'='HDMI'; '10'='DisplayPort'; '11'='DisplayPort'; '2147483648'='interno' }
        $ctype = $map[[string]$con.VideoOutputTechnology]; if (-not $ctype) { $ctype = 'outra' }
        $pc.Monitor = '{0} via {1}' -f $mname, $ctype
    } catch { $pc.Monitor = 'não consegui ler' }
    $ram = @(Get-CimInstance Win32_PhysicalMemory)
    $pc.Ram = '{0} GB | {1} MT/s | {2} pente(s)' -f ([math]::Round((($ram | Measure-Object Capacity -Sum).Sum) / 1GB)), ($ram | Select-Object -First 1).ConfiguredClockSpeed, $ram.Count
    try { $v = Get-Volume -DriveLetter C -ErrorAction Stop; $pc.Disco = 'C: {0} GB livres de {1} GB' -f [math]::Round($v.SizeRemaining / 1GB), [math]::Round($v.Size / 1GB) } catch { $pc.Disco = 'não consegui ler' }
    $nets = @(Get-NetAdapter -ErrorAction SilentlyContinue)
    $up = @($nets | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch 'Hyper-V|Virtual|Loopback' })
    $pc.Rede = (($up | ForEach-Object { '{0} ({1})' -f $_.Name, $_.LinkSpeed }) -join '; ')
    $pc.HasEthernet = (@($up | Where-Object { $_.MediaType -eq '802.3' }).Count -gt 0)
    $pc.HasWifi = (@($nets | Where-Object { $_.Name -match 'Wi-?Fi' -or $_.InterfaceDescription -match 'Wi-?Fi|Wireless|802\.11' }).Count -gt 0)
    $pc.UsbRadios = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like 'USB\*' -and $_.Class -in 'Net', 'Bluetooth' } | ForEach-Object { $_.FriendlyName } | Select-Object -Unique)
    $pc.IGpu = Get-IGpu
    $pc.HasBattery = (@(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue).Count -gt 0)
    $pc.HasExitLag = (Test-Path "$env:ProgramFiles\ExitLag") -or (Test-Path "${env:ProgramFiles(x86)}\ExitLag") -or [bool](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like 'ExitLag*' })
    $pc.Energia = (& powercfg /getactivescheme) -replace '.*\(([^)]+)\).*', '$1'
    $pc.Tipo = $(if ($pc.HasBattery) { 'Notebook' } else { 'PC de mesa' })
    return $pc
}
'@
. ([scriptblock]::Create($HelperCode))

# ---------- utilidades ----------
function Write-Log([string]$msg) {
    if ($Teste) { return }   # o modo de teste não suja o registro de mudanças
    $line = '[{0}] {1}' -f (Get-Date -Format 'dd/MM/yyyy HH:mm:ss'), $msg
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
}
function Set-RegValue([string]$path, [string]$name, $value, [string]$type = 'DWord') {
    if (-not (Test-Path -LiteralPath $path)) { New-Item -Path $path -Force | Out-Null }
    New-ItemProperty -LiteralPath $path -Name $name -Value $value -PropertyType $type -Force | Out-Null
}
function Remove-RegValue([string]$path, [string]$name) {
    if (Test-Path -LiteralPath $path) { Remove-ItemProperty -LiteralPath $path -Name $name -ErrorAction SilentlyContinue }
}
function Backup-Keys([string]$id, [string[]]$keys) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $i = 0
    foreach ($k in $keys) {
        $i++
        $file = Join-Path $BackupDir ("{0}-{1}-{2}.reg" -f $stamp, $id, $i)
        $psPath = $k -replace '^HKCU\\', 'HKCU:\' -replace '^HKLM\\', 'HKLM:\'
        if (-not (Test-Path -LiteralPath $psPath)) { Add-Content -LiteralPath ($file -replace '\.reg$', '.txt') -Value ("Chave não existia antes da mudança: " + $k) -Encoding UTF8; continue }
        $null = cmd.exe /c ("reg export `"{0}`" `"{1}`" /y >nul 2>&1" -f $k, $file)
    }
}
$script:RestorePointDone = $false
function Ensure-RestorePoint {
    if ($script:RestorePointDone) { return }
    $script:RestorePointDone = $true
    try {
        Checkpoint-Computer -Description 'Janus' -RestorePointType MODIFY_SETTINGS -WarningAction SilentlyContinue -WarningVariable avisoRp
        if ($avisoRp) { Write-Log ('Ponto de restauração: ' + ($avisoRp -join ' ')) } else { Write-Log 'Ponto de restauração criado antes das mudanças.' }
    } catch { Write-Log ('Ponto de restauração não criado: ' + $_.Exception.Message) }
}
function Set-PowerIndex([string]$sub, [string]$setting, [int]$v) {
    & powercfg /setacvalueindex SCHEME_CURRENT $sub $setting $v | Out-Null
    & powercfg /setdcvalueindex SCHEME_CURRENT $sub $setting $v | Out-Null
    & powercfg /setactive SCHEME_CURRENT | Out-Null
}
# ---------- tema (escuro / claro / seguir o Windows) ----------
# O app é desenhado no tema escuro; no claro, cada cor escura é trocada pela equivalente clara.
$ThemeMap = @{
    '#0E1117' = '#F3F5F9'; '#121620' = '#FFFFFF'; '#171C26' = '#FFFFFF'; '#1E2532' = '#E3E7EE'; '#232A36' = '#E1E5EC'; '#262E3C' = '#D5DBE5'
    '#232A37' = '#EEF1F6'; '#1F2940' = '#E6ECFA'; '#2A303C' = '#D9DEE7'; '#3A4252' = '#C5CCD8'; '#1C2029' = '#EEF0F4'; '#262B35' = '#E1E4EA'
    '#4A5161' = '#B8BFCB'; '#1A2234' = '#EEF2FB'; '#2C3A57' = '#C9D5EE'; '#3A2026' = '#FDE8EA'
    '#E6E9EF' = '#1A2030'; '#FFFFFF' = '#111827'; '#D6DCE8' = '#2B3445'; '#C9CED6' = '#2B3445'; '#C7CEDB' = '#2B3445'; '#AEB6C4' = '#4A5468'
    '#9AA3B2' = '#5B6578'; '#8B94A5' = '#5B6578'; '#7F8899' = '#6B7588'; '#6F7889' = '#6B7588'; '#6B7486' = '#6B7588'; '#5F6878' = '#8A93A3'
    '#4B5363' = '#8A93A3'; '#8EA3C8' = '#5B6F96'; '#94A3B8' = '#64748B'
    '#FCA5A5' = '#B91C1C'; '#FCD38D' = '#B45309'; '#C7D2FE' = '#3730A3'
    '#7F1D1D' = '#F5B4B4'; '#78350F' = '#F3D19C'; '#5C2A30' = '#F5B4B4'; '#5A4520' = '#F3D19C'; '#1F5C45' = '#9FD8BD'; '#2D4A7C' = '#9DB6E8'
    '#16233D' = '#E3ECFD'; '#12271F' = '#E1F5EA'; '#2A1416' = '#FDECEC'; '#2A2112' = '#FFF6E5'
    '#1C2A4A' = '#E4ECFB'; '#163A2C' = '#E3F4EA'; '#2A1F4A' = '#ECE7FB'; '#23245A' = '#E4E6FB'; '#103A3A' = '#DDF3F1'; '#06080C' = '#FFFFFF'
    '#60A5FA' = '#2563EB'; '#A78BFA' = '#7C3AED'; '#C084FC' = '#9333EA'; '#22C55E' = '#16A34A'; '#F59E0B' = '#B45309'; '#EF4444' = '#DC2626'
    '#818CF8' = '#4F46E5'; '#2DD4BF' = '#0F766E'
}
$script:IsLight = $false
function Map-Color([string]$c) { if ($script:IsLight -and $c -and $ThemeMap.ContainsKey($c.ToUpper())) { return $ThemeMap[$c.ToUpper()] }; return $c }
function Col([string]$c) { [System.Windows.Media.Color]((New-Object System.Windows.Media.ColorConverter).ConvertFrom((Map-Color $c))) }
function Brush([string]$c) { (New-Object System.Windows.Media.BrushConverter).ConvertFromString((Map-Color $c)) }
function Convert-ThemeText([string]$s) { if (-not $script:IsLight) { return $s }; return [regex]::Replace($s, '#[0-9A-Fa-f]{6}\b', { param($m) Map-Color $m.Value }) }
function Set-WindowedOpt([bool]$on) {
    $s = [string](Get-RegValue 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' 'DirectXUserGlobalSettings')
    $parts = @($s -split ';' | Where-Object { $_ -and $_ -notmatch '^SwapEffectUpgradeEnable=' })
    $parts += ('SwapEffectUpgradeEnable=' + [int]$on)
    Set-RegValue 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' 'DirectXUserGlobalSettings' (($parts -join ';') + ';') 'String'
}

# ---------- preferências (config.json) ----------
function Load-Config {
    # padrões; qualquer valor salvo no config.json por cima (opções novas não precisam de código extra aqui)
    $c = @{ WarningSeen = $false; Dismissed = @(); LightMode = $false; Lang = ''; CrashCount = 0; AutoUpdate = $true; Anonimizar = $true
            LangChosen = $false; Theme = 'dark'; NavMode = 'simples'; OptSort = 'prio'; OptView = 'grade'; MonLevel = 'normal'
            SpeedWarnOff = $false; DnsAuto = $true; SecOff = @(); DndUntil = ''; AiChoice = ''; AiAsked = $false; AiGoal = 'fps'; LogView = 'simples'; NotifyItems = @(); NotifyKinds = @('corner'); ManualGames = @(); FoOverride = @()
            NotifyRepeat = 'uma'; NotifyRearm = 30; NotifyEvery = 10; Tray = $false; CloseAsked = $false; LastVersion = '' }
    if ($Edition.Idioma) { $c.Lang = [string]$Edition.Idioma; $c.LangChosen = $true }   # idioma padrão da edição
    if (Test-Path -LiteralPath $ConfigFile) {
        try {
            $j = Get-Content -LiteralPath $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $j.PSObject.Properties) { $c[$p.Name] = $p.Value }
            $c.Dismissed = @($c.Dismissed | Where-Object { $_ }); $c.SecOff = @($c.SecOff | Where-Object { $_ })
            if ($c.Theme -notin 'dark', 'light', 'auto') { $c.Theme = 'dark' }
            if ($c.NavMode -notin 'simples', 'categorias') { $c.NavMode = 'simples' }
            if ($c.MonLevel -notin 'off', 'leve', 'normal', 'real') { $c.MonLevel = 'normal' }
        } catch {}
    }
    return $c
}function Save-Config { ($script:Config | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $ConfigFile -Encoding UTF8 }
$script:Config = Load-Config
$script:DismissedSession = New-Object System.Collections.ArrayList
# ao reabrir sozinho (troca de tema), as sugestões descartadas "só até fechar" continuam descartadas
if ($Descartadas) { foreach ($d in ($Descartadas -split ',')) { if ($d) { [void]$script:DismissedSession.Add($d) } } }
$script:IsLight = ($script:Config.Theme -eq 'light') -or ($script:Config.Theme -eq 'auto' -and (Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme') -eq 1)
if ($Teste -and $env:JANUS_TEMA) { $script:IsLight = ($env:JANUS_TEMA -eq 'light') }

# ---------- idiomas ----------
# O texto-fonte é o português. idiomas.json traz linhas [pt, en, zh, es]. Chaves com {0}, {1} viram padrões:
# "Por quê: {0}. {1}" traduz "Por quê: menos dados. O Windows envia..." traduzindo também cada pedaço.
$Langs = [ordered]@{ pt = 'Português'; en = 'English'; zh = '中文'; es = 'Español' }
$script:I18N = @{}; $script:I18NPat = @{}; $script:I18NMiss = $null
function Load-Languages {
    if (-not (Test-Path -LiteralPath $LangFile)) { return }
    try { $j = [IO.File]::ReadAllText($LangFile, [Text.Encoding]::UTF8) | ConvertFrom-Json } catch { return }
    $col = @{ en = 1; zh = 2; es = 3 }
    foreach ($l in $col.Keys) {
        $d = New-Object 'System.Collections.Generic.Dictionary[string,string]'
        $pats = New-Object System.Collections.ArrayList
        foreach ($row in $j.strings) {
            $k = [string]$row[0]; $v = [string]$row[$col[$l]]
            if (-not $k -or -not $v) { continue }
            $d[$k] = $v
            if ($k -match '\{\d\}') {
                $rx = '^' + ([regex]::Escape($k) -replace '\\\{(\d)}', '(?<a$1>.+?)') + '$'
                [void]$pats.Add(@((New-Object System.Text.RegularExpressions.Regex($rx, 'Singleline')), $v, ($k -replace '\{\d\}', '').Length))
            }
        }
        # padrões mais específicos (mais texto fixo) primeiro: "Versão nova disponível: {0}" antes de "Versão {0}"
        $script:I18N[$l] = $d; $script:I18NPat[$l] = @($pats | Sort-Object { $_[2] } -Descending)
    }
}
function T([string]$s) {
    $lg = $script:Lang
    if (-not $s -or $lg -eq 'pt') { return $s }
    $d = $script:I18N[$lg]; $o = $null
    if ($d -and $d.TryGetValue($s, [ref]$o)) { return $o }
    if ($d) {
        foreach ($p in $script:I18NPat[$lg]) {
            $m = $p[0].Match($s)
            if ($m.Success) {
                $a = New-Object System.Collections.ArrayList
                for ($i = 0; $i -lt 10; $i++) { $g = $m.Groups['a' + $i]; if (-not $g.Success) { break }; [void]$a.Add((T $g.Value)) }
                return ($p[1] -f $a.ToArray())
            }
        }
    }
    if ($null -ne $script:I18NMiss -and $s -match '[A-Za-zÀ-ú]{3}') { [void]$script:I18NMiss.Add($s) }
    return $s
}
Load-Languages
$script:Lang = $(if ($Idioma -and $Langs.Contains($Idioma)) { $Idioma } elseif ($script:Config.Lang -and $Langs.Contains($script:Config.Lang)) { $script:Config.Lang }
                 else { switch -Wildcard ([Globalization.CultureInfo]::CurrentUICulture.Name) { 'pt*' { 'pt' } 'zh*' { 'zh' } 'es*' { 'es' } default { 'en' } } })
if ($script:Lang -ne 'pt' -and -not $script:I18N[$script:Lang]) { $script:Lang = 'pt' }

# ---------- ícone do app ----------
function New-IconPng([int]$size, [string]$mode = 'app') {
    $C = [System.Windows.Media.Color]
    $dv = New-Object System.Windows.Media.DrawingVisual
    $dc = $dv.RenderOpen()
    # Janus: duas faces, duas setas.
    #  -> verde/ciano (velocidade, otimização): aplicar.   <- âmbar (voltar, "rebobinar"): desfazer, padrão do Windows.
    $bg = New-Object System.Windows.Media.LinearGradientBrush ($C::FromRgb(0x1F, 0x29, 0x45)), ($C::FromRgb(0x0B, 0x10, 0x1C)), 90
    $rad = $size * 0.23
    $rect = New-Object System.Windows.Rect 0, 0, $size, $size
    $edge = New-Object System.Windows.Media.Pen ((New-Object System.Windows.Media.SolidColorBrush ($C::FromArgb(70, 0x81, 0x8C, 0xF8)))), ([math]::Max(1, $size * 0.02))
    $dc.DrawRoundedRectangle($bg, $edge, $rect, $rad, $rad)
    $lw = [math]::Max(1.8, $size * 0.09)
    function Pt([double]$x, [double]$y) { New-Object System.Windows.Point ($size * $x), ($size * $y) }
    function Arrow($brush, [double]$y, [bool]$right) {
        $h = 0.12
        $tip = $(if ($right) { 0.78 } else { 0.22 }); $tail = $(if ($right) { 0.22 } else { 0.78 }); $back = $(if ($right) { $tip - $h } else { $tip + $h })
        $sg = New-Object System.Windows.Media.StreamGeometry; $ctx = $sg.Open()
        $ctx.BeginFigure((Pt $tail $y), $false, $false); $ctx.LineTo((Pt $tip $y), $true, $true)
        $ctx.BeginFigure((Pt $back ($y - $h)), $false, $false); $ctx.LineTo((Pt $tip $y), $true, $true); $ctx.LineTo((Pt $back ($y + $h)), $true, $true)
        $ctx.Close()
        $p = New-Object System.Windows.Media.Pen ([System.Windows.Media.Brushes]::White), $lw
        $p.StartLineCap = 'Round'; $p.EndLineCap = 'Round'; $p.LineJoin = 'Round'
        $dc.DrawGeometry($brush, $null, $sg.GetWidenedPathGeometry($p))
    }
    $go = New-Object System.Windows.Media.LinearGradientBrush ($C::FromRgb(0x22, 0xC5, 0x5E)), ($C::FromRgb(0x22, 0xD3, 0xEE)), 0
    $undo = New-Object System.Windows.Media.LinearGradientBrush ($C::FromRgb(0xFB, 0xBF, 0x24)), ($C::FromRgb(0xF5, 0x9E, 0x0B)), 0
    # app/info: as duas setas | do: só a verde (fazer) | undo: só a âmbar (desfazer) | off: cinza (indisponível)
    if ($mode -eq 'off') { $gray = New-Object System.Windows.Media.SolidColorBrush ($C::FromRgb(0x6B, 0x72, 0x80)); Arrow $gray 0.37 $true; Arrow $gray 0.63 $false }
    elseif ($mode -eq 'do') { Arrow $go 0.5 $true }
    elseif ($mode -eq 'undo') { Arrow $undo 0.5 $false }
    else { Arrow $go 0.34 $true; Arrow $undo 0.66 $false }
    $dc.Close()
    $bmp = New-Object System.Windows.Media.Imaging.RenderTargetBitmap $size, $size, 96, 96, ([System.Windows.Media.PixelFormats]::Pbgra32)
    $bmp.Render($dv)
    $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bmp))
    $ms = New-Object System.IO.MemoryStream; $enc.Save($ms)
    return , $ms.ToArray()
}
function New-AppIcon([string]$path) {
    $sizes = @(256, 64, 48, 32, 24, 16)
    $pngs = @($sizes | ForEach-Object { , (New-IconPng $_) })
    $fs = [System.IO.File]::Create($path); $bw = New-Object System.IO.BinaryWriter $fs
    $bw.Write([UInt16]0); $bw.Write([UInt16]1); $bw.Write([UInt16]$sizes.Count)
    $offset = 6 + 16 * $sizes.Count
    for ($i = 0; $i -lt $sizes.Count; $i++) {
        $s = $sizes[$i]; $b = [byte]$(if ($s -ge 256) { 0 } else { $s })
        $bw.Write($b); $bw.Write($b); $bw.Write([byte]0); $bw.Write([byte]0)
        $bw.Write([UInt16]1); $bw.Write([UInt16]32); $bw.Write([UInt32]$pngs[$i].Length); $bw.Write([UInt32]$offset)
        $offset += $pngs[$i].Length
    }
    foreach ($p in $pngs) { $bw.Write($p) }
    $bw.Close(); $fs.Close()
}
function New-PngImage([int]$size, [string]$mode = 'app') {
    $ms = New-Object System.IO.MemoryStream (, (New-IconPng $size $mode))
    $bi = New-Object System.Windows.Media.Imaging.BitmapImage; $bi.BeginInit(); $bi.StreamSource = $ms; $bi.CacheOption = 'OnLoad'; $bi.EndInit()
    return $bi
}
if (-not (Test-Path -LiteralPath $IconPath)) { try { New-AppIcon $IconPath } catch {} }

# ---------- leitura em segundo plano ----------
# A janela nunca lê o Windows direto: ela mostra a última "foto" (Snap) e uma thread separada tira fotos novas.
# Rápida (só ajustes) a cada 5 s; completa (ajustes + verificações + segurança + dados do PC) a cada 1 min.
$WorkerScript = @'
param($inp)
$ErrorActionPreference = 'Stop'
. ([scriptblock]::Create($inp.Helper))
$r = @{ State = @{}; Avail = @{}; Checks = $null; Sec = $null; Pc = $null; Full = $inp.Full; Version = $inp.Version; Errors = New-Object System.Collections.ArrayList; Ms = 0 }
$sw = [Diagnostics.Stopwatch]::StartNew()
foreach ($g in $inp.Gets) {
    $a = $true
    if ($g.Avail) { try { $a = [bool](& ([scriptblock]::Create($g.Avail))) } catch { $a = $false } }
    $r.Avail[$g.Id] = $a
    try { $r.State[$g.Id] = [bool](& ([scriptblock]::Create($g.Get))) } catch { $r.State[$g.Id] = $null }
}
if ($inp.Full) {
    $lst = New-Object System.Collections.ArrayList
    foreach ($c in $inp.Checks) { try { [void]$lst.Add([bool](& ([scriptblock]::Create($c)))) } catch { [void]$lst.Add($null) } }
    $r.Checks = $lst
    try { $r.Sec = @(Read-SecurityStatus) } catch { [void]$r.Errors.Add('segurança: ' + $_.Exception.Message) }
    try { $r.Pc = Read-PcInfo } catch { [void]$r.Errors.Add('dados do PC: ' + $_.Exception.Message) }
}
$r.Ms = $sw.ElapsedMilliseconds
$r
'@
$script:Snap = @{ State = @{}; Avail = @{}; Checks = $null; Sec = $null; Pc = $null; FastAt = [datetime]::MinValue; FullAt = [datetime]::MinValue; FastMs = 0; FullMs = 0 }
$script:SnapVersion = 0
$script:Rs = [runspacefactory]::CreateRunspace(); $script:Rs.Open()
$script:Job = $null; $script:ForceFull = $false; $script:ToastWhenDone = $false; $script:PendingRebuild = $false; $script:FirstLoad = $true; $script:LastErr = ''

function Get-Intervals { if ($script:Config.LightMode) { @{ Fast = 30; Full = 300 } } else { @{ Fast = 5; Full = 60 } } }
function Start-Worker([bool]$full) {
    if ($script:Job) { return }
    $inp = @{ Full = $full; Version = $script:SnapVersion; Helper = $HelperCode
              Gets = @($script:Tweaks | ForEach-Object { @{ Id = $_.Id; Get = $_.Get.ToString(); Avail = $(if ($_.Available) { $_.Available.ToString() } else { '' }) } })
              Checks = @($script:Checks | ForEach-Object { $_.Get.ToString() }) }
    $ps = [powershell]::Create(); $ps.Runspace = $script:Rs
    [void]$ps.AddScript($WorkerScript).AddArgument($inp)
    $script:Job = @{ PS = $ps; Handle = $ps.BeginInvoke(); Full = $full }
    if ($full -and $ui) { Set-LiveState 'busy' }
}
function Receive-Worker([switch]$Wait) {
    $j = $script:Job; if (-not $j) { return $null }
    if (-not $Wait -and -not $j.Handle.IsCompleted) { return $null }
    try { $out = $j.PS.EndInvoke($j.Handle) } finally { $j.PS.Dispose(); $script:Job = $null }
    if (-not $out -or $out.Count -lt 1) { throw 'a leitura em segundo plano não devolveu nada' }
    # em hashtable, ".BaseObject" vira busca de chave; a conversão desembrulha do jeito certo
    $res = [hashtable]$out[0]
    return $res
}
function Merge-Snapshot($res) {
    $now = Get-Date
    if ($res.Pc) { $script:Snap.Pc = $res.Pc }
    foreach ($e in $res.Errors) { if ($e -ne $script:LastErr) { $script:LastErr = $e; Write-Log ('Leitura em segundo plano: ' + $e) } }
    if ($res.Version -ne $script:SnapVersion) {
        # você mudou algo enquanto a foto era tirada: ela já nasceu velha, então descarto e leio de novo
        $script:Snap.FastAt = [datetime]::MinValue; if ($res.Full) { $script:ForceFull = $true }
        return $false
    }
    $script:Snap.State = $res.State; $script:Snap.Avail = $res.Avail; $script:Snap.FastAt = $now
    if ($res.Full) {
        if ($null -ne $res.Checks) { $script:Snap.Checks = $res.Checks }
        if ($null -ne $res.Sec) { $script:Snap.Sec = $res.Sec }
        $script:Snap.FullAt = $now; $script:Snap.FullMs = $res.Ms
    } else { $script:Snap.FastMs = $res.Ms }
    return $true
}
function Invoke-WorkerNow([bool]$full) { Start-Worker $full; $res = Receive-Worker -Wait; [void](Merge-Snapshot $res); return $res }

# Leitura direta (só depois de você mudar algo, para mostrar o resultado na hora)
function Read-State($t) { try { return [bool](& $t.Get) } catch { return $null } }
function Read-CheckOk($c) { try { return [bool](& $c.Get) } catch { return $null } }
# Leitura da foto (instantânea)
function Get-State($t) {
    if ($script:Snap.State.ContainsKey($t.Id)) { return $script:Snap.State[$t.Id] }
    $v = Read-State $t; $script:Snap.State[$t.Id] = $v; return $v
}
function Is-Available($t) {
    if (-not $t.ContainsKey('Available')) { return $true }
    if ($script:Snap.Avail.ContainsKey($t.Id)) { return [bool]$script:Snap.Avail[$t.Id] }
    try { $v = [bool](& $t.Available) } catch { $v = $false }
    $script:Snap.Avail[$t.Id] = $v; return $v
}
function Get-CheckOk($c) { if ($null -ne $script:Snap.Checks) { return $script:Snap.Checks[$c.Idx] }; return Read-CheckOk $c }
function Get-SecurityStatus { if ($null -eq $script:Snap.Sec) { $script:Snap.Sec = @(Read-SecurityStatus) }; return $script:Snap.Sec }
function Get-PcInfo { if ($null -eq $script:Snap.Pc) { $script:Snap.Pc = Read-PcInfo }; return $script:Snap.Pc }

# ---------- os ajustes ----------
# Ligado = ajuste aplicado. Desligado = padrão do Windows.
# Risk: 0 seguro, 1 atenção | Restart: nenhum, explorer, desligar, pc | Rec: $true sugerido, $null a gosto
# Auto: regra da Automação -> @{ Apply = $bool; Why = 'motivo' } a partir da leitura do PC
$script:Tweaks = @(
  @{ Id='mouse-acel'; Page='Entrada'; Prio=2; Scope='usuario'; Glyph=[char]0xE962; Title='Desligar a aceleração do mouse'
     Desc='O cursor passa a andar sempre a mesma distância para o mesmo movimento, rápido ou devagar. A mira fica mais consistente.'
     Caveat='você joga mais com controle, ou acha o ponteiro lento demais na área de trabalho. Leva uns dias para acostumar.'
     Risk=0; Restart='nenhum'; Rec=$true; RecWhy='mira mais consistente'
     Keys=@('HKCU\Control Panel\Mouse')
     Auto={ param($pc) @{ Apply = $pc.DisplayOnDiscrete; Why = $(if ($pc.DisplayOnDiscrete) { 'PC de jogos com placa de vídeo dedicada' } else { 'não parece um PC de jogos' }) } }
     Get={ (Get-RegValue 'HKCU:\Control Panel\Mouse' 'MouseSpeed') -eq '0' }
     Set={ param($on)
           if ($on) {
               $cur = @([string](Get-RegValue 'HKCU:\Control Panel\Mouse' 'MouseSpeed'), [string](Get-RegValue 'HKCU:\Control Panel\Mouse' 'MouseThreshold1'), [string](Get-RegValue 'HKCU:\Control Panel\Mouse' 'MouseThreshold2'))
               if ($cur[0] -and $cur[0] -ne '0') { $script:Config.MouseAntes = $cur; Save-Config }
               $t1 = 0; $t2 = 0; $sp = 0
           } else {
               $prev = @($script:Config.MouseAntes)
               if ($prev.Count -eq 3 -and $prev[0] -ne '0') { $sp = [int]$prev[0]; $t1 = [int]$prev[1]; $t2 = [int]$prev[2] } else { $t1 = 6; $t2 = 10; $sp = 1 }
           }
           Set-RegValue 'HKCU:\Control Panel\Mouse' 'MouseSpeed' "$sp" 'String'
           Set-RegValue 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' "$t1" 'String'
           Set-RegValue 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' "$t2" 'String'
           [void][PANative]::SystemParametersInfo(0x0004, 0, [int[]]@($t1,$t2,$sp), 3) } }

  @{ Id='igpu-off'; Prio=3; Page='Graficos'; Scope='pc'; Glyph=[char]0xE7F4; Title='Desativar o vídeo integrado do processador'
     Desc='O monitor está na placa de vídeo dedicada, então o vídeo do processador não é usado. Desativado, ele não carrega driver nem disputa nada com a placa.'
     Caveat='você liga algum monitor na saída de vídeo da placa-mãe, ou quer o vídeo integrado como reserva se a placa falhar.'
     Risk=1; Restart='nenhum'; Rec=$true; RecWhy='não é usado'
     Keys=@()
     Available={ $null -ne (Get-IGpu) }; UnavailableWhy='Este PC não tem vídeo integrado junto de uma placa de vídeo dedicada (ou ele está desligado na BIOS). Sem placa dedicada, desligar o integrado deixaria o PC sem imagem.'
     Auto={ param($pc) if (-not $pc.IGpu) { @{ Apply=$false; Why='não há vídeo integrado' } } elseif ($pc.DisplayOnDiscrete) { @{ Apply=$true; Why='o monitor está na placa dedicada e o integrado não tem tela' } } else { @{ Apply=$false; Why='a tela usa o vídeo integrado' } } }
     Get={ $g = Get-IGpu; ($null -ne $g) -and ($g.Status -ne 'OK') }
     Set={ param($on) $g = Get-IGpu; if (-not $g) { throw 'vídeo integrado não encontrado' }
           if ($on) {
               $vc = @(Get-CimInstance Win32_VideoController | Where-Object { $_.CurrentHorizontalResolution })
               if (-not @($vc | Where-Object { $_.Name -match 'NVIDIA|Radeon RX|Radeon Pro|Arc' }).Count) { throw 'O monitor não está ligado na placa de vídeo dedicada. Desligar o vídeo integrado agora deixaria a tela sem imagem.' }
               if (@($vc | Where-Object { $_.Name -eq $g.FriendlyName }).Count) { throw 'Há um monitor ligado no vídeo integrado. Mude o cabo para a placa de vídeo dedicada antes.' }
               Disable-PnpDevice -InstanceId $g.InstanceId -Confirm:$false
           } else { Enable-PnpDevice -InstanceId $g.InstanceId -Confirm:$false } } }

  @{ Id='wifi-cabo'; Prio=4; Page='Rede'; Scope='pc'; Glyph=[char]0xE701; Title='Manter o Wi-Fi ligado junto com o cabo'
     Desc='O Windows deixa o Wi-Fi conectado mesmo com o cabo ligado. Assim programas que usam duas internets ao mesmo tempo (como o Multi Internet do ExitLag) já têm a reserva pronta.'
     Caveat='você não usa o Wi-Fi como reserva: ele fica conectado à toa.'
     Risk=0; Restart='pc'; Rec=$true; RecWhy='reserva do ExitLag'
     Keys=@('HKLM\SOFTWARE\Policies\Microsoft\Windows\WcmSvc')
     Auto={ param($pc) if ($pc.HasEthernet -and $pc.HasWifi -and $pc.HasExitLag) { @{ Apply=$true; Why='cabo e Wi-Fi presentes, e o ExitLag usa os dois' } } else { @{ Apply=$false; Why='não há cabo e Wi-Fi juntos com um programa que use os dois' } } }
     Get={ (Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WcmSvc\GroupPolicy' 'fMinimizeConnections') -eq 0 }
     Set={ param($on) if ($on) { Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WcmSvc\GroupPolicy' 'fMinimizeConnections' 0 } else { Remove-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WcmSvc\GroupPolicy' 'fMinimizeConnections' } } }

  @{ Id='usb-suspensao'; Prio=1; Page='Rede'; Scope='pc'; Glyph=[char]0xE88E; Title='Desligar a suspensão seletiva de USB'
     Desc='O Windows para de pausar portas USB paradas. Evita cortes no adaptador Wi-Fi/Bluetooth USB e no receptor do mouse.'
     Caveat='o PC for um notebook usado na bateria: o USB passa a gastar um pouco mais de energia.'
     Risk=0; Restart='nenhum'; Rec=$true; RecWhy='evita cortes no USB'
     Keys=@()
     Auto={ param($pc) if ($pc.UsbRadios.Count) { @{ Apply=$true; Why=('adaptador USB detectado: ' + ($pc.UsbRadios -join ', ')) } } elseif (-not $pc.HasBattery) { @{ Apply=$true; Why='PC de mesa: economia de USB não faz diferença' } } else { @{ Apply=$false; Why='notebook sem adaptador USB de rede' } } }
     Get={ (Get-PowerIndex '2a737441-1930-4402-8d77-b2bebba308a3' '48e6b7a6-50f5-4782-a5d4-53bb8f07e226') -eq 0 }
     Set={ param($on) Set-PowerIndex '2a737441-1930-4402-8d77-b2bebba308a3' '48e6b7a6-50f5-4782-a5d4-53bb8f07e226' $(if ($on) { 0 } else { 1 }) } }

  @{ Id='inic-rapida'; Prio=5; Page='Rede'; Scope='pc'; Glyph=[char]0xE7E8; Title='Desligar a inicialização rápida'
     Desc='Ao desligar, o Windows deixa de hibernar o núcleo. Cada vez que liga, drivers e atualizações começam do zero, como num reinício.'
     Caveat='você prefere que o PC ligue alguns segundos mais rápido e nunca teve problema com drivers ou atualizações.'
     Risk=0; Restart='desligar'; Rec=$null; RecWhy=''
     Keys=@('HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power')
     Auto={ param($pc) if (-not $pc.HasBattery) { @{ Apply=$true; Why='PC de mesa com SSD: o ganho no boot é pequeno e o Windows sempre começa limpo' } } else { @{ Apply=$false; Why='notebook: a inicialização rápida economiza bateria' } } }
     Get={ (Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled') -eq 0 }
     Set={ param($on) Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' $(if ($on) { 0 } else { 1 }) } }

  @{ Id='cpu-minimo'; Prio=20; Page='Rede'; Scope='pc'; Glyph=[char]0xE950; Title='Processador sempre no máximo (estado mínimo 100%)'
     Desc='O plano de energia deixa de baixar o clock do processador quando ele está ocioso. Em jogos o ganho costuma ser muito pequeno ou nenhum, porque o processador já sobe o clock em milissegundos.'
     Caveat='o processador for um Ryzen X3D ou o PC for um notebook: mais calor e consumo podem até reduzir o turbo. A AMD recomenda deixar no padrão.'
     Risk=1; Restart='nenhum'; Rec=$null; RecWhy=''
     Keys=@()
     Auto={ param($pc) @{ Apply=$false; Why='ganho quase nenhum, com mais calor e consumo: não mexo sozinho' } }
     Get={ (Get-PowerIndex 'SUB_PROCESSOR' 'PROCTHROTTLEMIN') -eq 100 }
     Set={ param($on)
           if ($on) {
               # guarda o valor atual para voltar exatamente a ele depois
               $cur = Get-PowerIndex 'SUB_PROCESSOR' 'PROCTHROTTLEMIN'
               if ($null -ne $cur -and $cur -ne 100) { $script:Config.CpuMinAntes = $cur; Save-Config }
               Set-PowerIndex 'SUB_PROCESSOR' 'PROCTHROTTLEMIN' 100
           } else {
               $prev = $(if ($null -ne $script:Config.CpuMinAntes) { [int]$script:Config.CpuMinAntes } else { 5 })
               Set-PowerIndex 'SUB_PROCESSOR' 'PROCTHROTTLEMIN' $prev
           } } }

  @{ Id='telemetria'; Prio=10; Page='Privacidade'; Scope='pc'; Glyph=[char]0xE9D9; Title='Limitar dados de diagnóstico ao obrigatório'
     Desc='O Windows envia à Microsoft só o mínimo obrigatório, sem os dados opcionais de uso.'
     Caveat='você participa do Windows Insider: alguns canais pedem os dados opcionais ligados.'
     Risk=0; Restart='nenhum'; Rec=$true; RecWhy='menos dados enviados'
     Keys=@('HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection')
     Auto={ param($pc) @{ Apply=$true; Why='menos dados enviados, sem efeito no uso' } }
     Get={ $v = Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry'; ($null -ne $v) -and ($v -le 1) }
     Set={ param($on) if ($on) { Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 1 } else { Remove-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' } } }

  @{ Id='id-anuncio'; Prio=13; Page='Privacidade'; Scope='usuario'; Glyph=[char]0xE8EC; Title='Desligar o ID de anúncio'
     Desc='Os apps deixam de ter um identificador seu para mostrar anúncios personalizados.'
     Caveat='praticamente nenhum caso: os anúncios continuam, só não são personalizados.'
     Risk=0; Restart='nenhum'; Rec=$true; RecWhy='não serve para nada útil'
     Keys=@('HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo')
     Auto={ param($pc) @{ Apply=$true; Why='não traz benefício nenhum' } }
     Get={ (Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled') -eq 0 }
     Set={ param($on) Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' $(if ($on) { 0 } else { 1 }) } }

  @{ Id='dicas'; Prio=11; Page='Privacidade'; Scope='usuario'; Glyph=[char]0xEA80; Title='Desligar dicas, sugestões e anúncios'
     Desc='Some com as sugestões no Iniciar e nas Configurações, as dicas na tela e a instalação silenciosa de apps sugeridos.'
     Caveat='você gosta das dicas para conhecer recursos novos do Windows.'
     Risk=0; Restart='nenhum'; Rec=$true; RecWhy='menos propaganda'
     Keys=@('HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager')
     Auto={ param($pc) @{ Apply=$true; Why='menos propaganda e nenhum app instalado sem pedir' } }
     Get={ $k='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; ((Get-RegValue $k 'SystemPaneSuggestionsEnabled') -eq 0) -and ((Get-RegValue $k 'SubscribedContent-338389Enabled') -eq 0) -and ((Get-RegValue $k 'SilentInstalledAppsEnabled') -eq 0) }
     Set={ param($on) $k='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; $d = $(if ($on) { 0 } else { 1 })
           foreach ($n in 'SystemPaneSuggestionsEnabled','SubscribedContent-338388Enabled','SubscribedContent-338389Enabled','SubscribedContent-353694Enabled','SubscribedContent-353696Enabled','SubscribedContent-310093Enabled','SoftLandingEnabled','SilentInstalledAppsEnabled') { Set-RegValue $k $n $d } } }

  @{ Id='bing'; Prio=12; Page='Privacidade'; Scope='usuario'; Glyph=[char]0xE721; Title='Tirar a internet (Bing) da pesquisa do Iniciar'
     Desc='A pesquisa do Iniciar passa a procurar só no PC: resultados mais limpos, sem esperar a internet, e o que você digita não vai para a Microsoft.'
     Caveat='você pesquisa coisas da internet direto pelo Iniciar, como clima ou conversões.'
     Risk=0; Restart='explorer'; Rec=$true; RecWhy='pesquisa mais limpa'
     Keys=@('HKCU\Software\Policies\Microsoft\Windows\Explorer')
     Auto={ param($pc) @{ Apply=$true; Why='pesquisa só no PC, mais rápida e privada' } }
     Get={ (Get-RegValue 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions') -eq 1 }
     Set={ param($on) if ($on) { Set-RegValue 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1 } else { Remove-RegValue 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' } } }

  @{ Id='extensoes'; Prio=14; Page='Interface'; Scope='usuario'; Glyph=[char]0xE8A5; Title='Mostrar extensões de arquivos'
     Desc='Mostra o final do nome dos arquivos (.exe, .pdf, .cmd). Ajuda a perceber arquivos disfarçados, como "foto.jpg.exe".'
     Caveat='quase nenhum: os nomes só ficam um pouco mais longos.'
     Risk=0; Restart='explorer'; Rec=$true; RecWhy='ajuda a ver arquivos disfarçados'
     Keys=@('HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced')
     Auto={ param($pc) @{ Apply=$true; Why='ajuda a perceber arquivos disfarçados' } }
     Get={ (Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'HideFileExt') -eq 0 }
     Set={ param($on) Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'HideFileExt' $(if ($on) { 0 } else { 1 }) } }

  @{ Id='menu-classico'; Prio=15; Page='Interface'; Scope='usuario'; Glyph=[char]0xE712; Title='Usar o menu clássico do botão direito'
     Desc='Volta o menu completo do botão direito, como no Windows 10, sem precisar clicar em "Mostrar mais opções".'
     Caveat='você gosta do menu novo do Windows 11. Alguns programas novos só aparecem no menu novo.'
     Risk=0; Restart='explorer'; Rec=$null; RecWhy=''
     Keys=@('HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}')
     Auto={ param($pc) @{ Apply=$false; Why='questão de gosto: não mexo sozinho' } }
     Get={ Test-Path -LiteralPath 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' }
     Set={ param($on) $k='HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}'
           if ($on) { New-Item -Path "$k\InprocServer32" -Force | Out-Null; Set-Item -LiteralPath "$k\InprocServer32" -Value '' }
           elseif (Test-Path -LiteralPath $k) { Remove-Item -LiteralPath $k -Recurse -Force } } }

  @{ Id='transparencia-off'; Prio=16; Page='Interface'; Scope='usuario'; Glyph=[char]0xE771; Title='Desligar os efeitos de transparência'
     Desc='O Iniciar, a barra de tarefas e algumas janelas ficam com fundo sólido, sem o efeito translúcido.'
     Caveat='você gosta do visual translúcido. Numa placa de vídeo dedicada o ganho de desempenho é praticamente nenhum.'
     Risk=0; Restart='nenhum'; Rec=$null; RecWhy=''
     Keys=@('HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize')
     Auto={ param($pc) @{ Apply=$false; Why='questão de gosto: não mexo sozinho' } }
     Get={ (Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency') -eq 0 }
     Set={ param($on) Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' $(if ($on) { 0 } else { 1 }); [PANative]::Broadcast('ImmersiveColorSet') } }

  @{ Id='animacoes-off'; Prio=17; Page='Interface'; Scope='usuario'; Glyph=[char]0xE916; Title='Desligar as animações do Windows'
     Desc='Abrir, minimizar e trocar de janela fica instantâneo, sem as transições.'
     Caveat='você gosta das transições: elas ajudam a perceber de onde a janela veio.'
     Risk=0; Restart='nenhum'; Rec=$null; RecWhy=''
     Keys=@()
     Auto={ param($pc) @{ Apply=$false; Why='questão de gosto: não mexo sozinho' } }
     Get={ $b = $true; [void][PANative]::SystemParametersInfo(0x1042, 0, [ref]$b, 0); -not $b }
     Set={ param($on) $p = [IntPtr]$(if ($on) { 0 } else { 1 }); [void][PANative]::SystemParametersInfo(0x1043, 0, $p, 3) } }
)

# ---------- ajustes de mouse, teclado e controle ----------
if (-not ('JanusAccess' -as [type])) {
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class JanusAccess {
  [StructLayout(LayoutKind.Sequential)] public struct SK { public uint cbSize; public uint dwFlags; }
  [StructLayout(LayoutKind.Sequential)] public struct FK { public uint cbSize; public uint dwFlags; public uint iWaitMSec; public uint iDelayMSec; public uint iRepeatMSec; public uint iBounceMSec; }
  [DllImport("user32.dll", SetLastError=true)] static extern bool SystemParametersInfo(uint a, uint b, ref SK c, uint d);
  [DllImport("user32.dll", SetLastError=true)] static extern bool SystemParametersInfo(uint a, uint b, ref FK c, uint d);
  // liga/desliga só o ATALHO (Shift 5x, Shift direito 8 s, Num Lock 5 s); os recursos continuam disponíveis
  public static void SetHotkeys(bool on) {
    SK s = new SK(); s.cbSize = (uint)Marshal.SizeOf(typeof(SK));
    SystemParametersInfo(0x003A, s.cbSize, ref s, 0); s.dwFlags = on ? (s.dwFlags | 4u) : (s.dwFlags & ~4u); SystemParametersInfo(0x003B, s.cbSize, ref s, 3);
    SK t = new SK(); t.cbSize = (uint)Marshal.SizeOf(typeof(SK));
    SystemParametersInfo(0x0034, t.cbSize, ref t, 0); t.dwFlags = on ? (t.dwFlags | 4u) : (t.dwFlags & ~4u); SystemParametersInfo(0x0035, t.cbSize, ref t, 3);
    FK f = new FK(); f.cbSize = (uint)Marshal.SizeOf(typeof(FK));
    SystemParametersInfo(0x0032, f.cbSize, ref f, 0); f.dwFlags = on ? (f.dwFlags | 4u) : (f.dwFlags & ~4u); SystemParametersInfo(0x0033, f.cbSize, ref f, 3);
  }
}
"@
}
$script:Tweaks += @(
  @{ Id='atalhos-acessibilidade'; Prio=6; Page='Entrada'; Scope='usuario'; Glyph=[char]0xE765; Title='Desligar os atalhos das Teclas de Aderência e de Filtro'
     Desc='Apertar Shift 5 vezes ou segurar o Shift direito deixa de abrir a janela das Teclas de Aderência ou de Filtro no meio do jogo. Os recursos continuam nas Configurações para quem precisar.'
     Caveat='você usa esses atalhos para ligar as Teclas de Aderência ou de Filtro.'
     Risk=0; Restart='nenhum'; Rec=$true; RecWhy='evita janelas no meio do jogo'
     Keys=@('HKCU\Control Panel\Accessibility\StickyKeys', 'HKCU\Control Panel\Accessibility\Keyboard Response', 'HKCU\Control Panel\Accessibility\ToggleKeys')
     Auto={ param($pc) @{ Apply=$true; Why='evita que a janela das Teclas de Aderência apareça no meio da partida' } }
     Get={ $a = 'HKCU:\Control Panel\Accessibility'
           (([int](Get-RegValue "$a\StickyKeys" 'Flags') -band 4) -eq 0) -and (([int](Get-RegValue "$a\Keyboard Response" 'Flags') -band 4) -eq 0) -and (([int](Get-RegValue "$a\ToggleKeys" 'Flags') -band 4) -eq 0) }
     Set={ param($on) [JanusAccess]::SetHotkeys(-not $on) } }

  @{ Id='teclado-repeticao'; Prio=8; Page='Entrada'; Scope='usuario'; Glyph=[char]0xE92E; Title='Teclas repetem mais rápido ao segurar'
     Desc='Diminui a espera até uma tecla segurada começar a repetir, e a repetição fica no máximo. Ajuda a apagar, andar no texto e navegar em menus. Os jogos leem o teclado direto, então isso não muda o atraso das teclas dentro do jogo.'
     Caveat='você costuma repetir letras sem querer quando digita devagar.'
     Risk=0; Restart='nenhum'; Rec=$null; RecWhy=''
     Keys=@('HKCU\Control Panel\Keyboard')
     Auto={ param($pc) @{ Apply=$false; Why='questão de gosto: não mexo sozinho' } }
     Get={ ((Get-RegValue 'HKCU:\Control Panel\Keyboard' 'KeyboardDelay') -eq '0') -and ((Get-RegValue 'HKCU:\Control Panel\Keyboard' 'KeyboardSpeed') -eq '31') }
     Set={ param($on)
           if ($on) {
               $d0 = [string](Get-RegValue 'HKCU:\Control Panel\Keyboard' 'KeyboardDelay'); $s0 = [string](Get-RegValue 'HKCU:\Control Panel\Keyboard' 'KeyboardSpeed')
               if ($d0 -and -not ($d0 -eq '0' -and $s0 -eq '31')) { $script:Config.TecladoAntes = @($d0, $s0); Save-Config }
               [void][PANative]::SystemParametersInfo(0x0017, 0, [IntPtr]::Zero, 3); [void][PANative]::SystemParametersInfo(0x000B, 31, [IntPtr]::Zero, 3)
           } else {
               $prev = @($script:Config.TecladoAntes); $d1 = $(if ($prev.Count -eq 2) { [int]$prev[0] } else { 1 }); $s1 = $(if ($prev.Count -eq 2) { [int]$prev[1] } else { 31 })
               [void][PANative]::SystemParametersInfo(0x0017, $d1, [IntPtr]::Zero, 3); [void][PANative]::SystemParametersInfo(0x000B, $s1, [IntPtr]::Zero, 3)
           } } }

  @{ Id='xbox-guia'; Prio=7; Page='Entrada'; Scope='usuario'; Glyph=[char]0xE7FC; Title='Botão Xbox do controle não abre a Game Bar'
     Desc='Apertar o botão Xbox do controle deixa de abrir a Game Bar por cima do jogo.'
     Caveat='você usa o botão Xbox para abrir a Game Bar, gravar trechos ou ver amigos.'
     Risk=0; Restart='nenhum'; Rec=$null; RecWhy=''
     Keys=@('HKCU\Software\Microsoft\GameBar')
     Auto={ param($pc) @{ Apply=$false; Why='depende de como você usa o controle: não mexo sozinho' } }
     Get={ (Get-RegValue 'HKCU:\Software\Microsoft\GameBar' 'UseNexusForGameBarEnabled') -eq 0 }
     Set={ param($on) Set-RegValue 'HKCU:\Software\Microsoft\GameBar' 'UseNexusForGameBarEnabled' $(if ($on) { 0 } else { 1 }) } }
)


# ---------- verificações (o que o Windows já faz certo por padrão) ----------
# Level: nível quando falha -> 'crit' (vermelho, urgente) ou 'warn' (amarelo, atenção)
$script:Checks = @(
  @{ Page='Graficos'; Level='warn'; Glyph=[char]0xE7FC; Title='Modo de Jogo ligado'; Desc='O Windows prioriza o jogo aberto e segura atualizações durante a partida.'
     Get={ $v = Get-RegValue 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled'; ($null -eq $v) -or ($v -ne 0) }
     FixText='Ligar'; Fix={ Set-RegValue 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1; Set-RegValue 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode' 1 }; FixRestart='nenhum' }
  @{ Page='Graficos'; Level='warn'; Glyph=[char]0xE7F4; Title='Otimizações para jogos em janela ligadas'; Desc='Jogos em tela cheia sem bordas usam o modo moderno de apresentação: menos atraso e G-Sync funcionando.'
     Get={ ([string](Get-RegValue 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' 'DirectXUserGlobalSettings')) -notmatch 'SwapEffectUpgradeEnable=0' }
     FixText='Ligar'; Fix={ Set-WindowedOpt $true }; FixRestart='nenhum' }
  @{ Page='Graficos'; Level='warn'; Glyph=[char]0xE714; Title='Gravação em segundo plano do Xbox desligada'; Desc='Ela grava o jogo sem parar e gasta um pouco da placa de vídeo. Quem grava pelo OBS ou outro programa não precisa dela.'
     Get={ (Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled') -ne 1 }
     FixText='Desligar'; Fix={ Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0; Set-RegValue 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0 }; FixRestart='nenhum' }
  @{ Page='Graficos'; Level='warn'; Glyph=[char]0xE950; Title='Agendamento de GPU por hardware não desligado'; Desc='Necessário para a geração de quadros (DLSS Frame Generation) da placa de vídeo.'
     Get={ (Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode') -ne 1 }
     FixText='Ligar'; Fix={ Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2 }; FixRestart='pc' }
  @{ Page='Rede'; Level='warn'; Glyph=[char]0xE945; Title='Plano de energia Equilibrado'; Desc='Recomendado pela AMD para processadores Ryzen (principalmente os X3D) e bom para a maioria dos PCs: gerencia o turbo melhor que o "Alto desempenho".'
     Get={ (& powercfg /getactivescheme) -match '381b4222-f694-41f0-9685-ff5bb260df2e' }
     FixText='Usar Equilibrado'; Fix={ & powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e | Out-Null }; FixRestart='nenhum' }
  @{ Page='Seguranca'; Id='hvci'; Level='warn'; Glyph=[char]0xEA18; Title='Integridade de memória ligada'; Desc='Usa a virtualização do processador para impedir drivers maliciosos ou vulneráveis no núcleo do Windows.'
     Get={ (Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled') -eq 1 }
     FixText='Ligar'; Fix={ Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled' 1 }; FixRestart='pc' }
  @{ Page='Seguranca'; Id='av'; Level='crit'; Glyph=[char]0xE83D; Title='Antivírus em tempo real ligado'; Desc='O Microsoft Defender examina os arquivos no momento em que são abertos ou baixados.'
     Get={ (Get-MpComputerStatus).RealTimeProtectionEnabled }
     FixText='Abrir Segurança do Windows'; Fix={ Start-Process 'windowsdefender://threatsettings' }; FixRestart='nenhum' }
  @{ Page='Seguranca'; Id='tamper'; Level='crit'; Glyph=[char]0xE72E; Title='Proteção contra adulteração ligada'; Desc='Impede que programas desliguem o Defender por conta própria.'
     Get={ (Get-MpComputerStatus).IsTamperProtected }
     FixText='Abrir Segurança do Windows'; Fix={ Start-Process 'windowsdefender://threatsettings' }; FixRestart='nenhum' }
  @{ Page='Seguranca'; Id='exclusoes'; Level='warn'; Glyph=[char]0xE8F8; Title='Nenhuma pasta excluída do Defender'; Desc='Pastas excluídas não são examinadas. Instaladores às vezes criam exclusões sem avisar.'
     Get={ @((Get-MpPreference).ExclusionPath | Where-Object { $_ }).Count -eq 0 }
     FixText='Abrir Segurança do Windows'; Fix={ Start-Process 'windowsdefender://threatsettings' }; FixRestart='nenhum' }
  @{ Page='Seguranca'; Id='uac'; Level='crit'; Glyph=[char]0xE7EF; Title='Controle de Conta de Usuário (UAC) ligado'; Desc='Pede confirmação antes de um programa ganhar poder de administrador.'
     Get={ (Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'EnableLUA') -eq 1 }
     FixText='Ligar'; Fix={ Set-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'EnableLUA' 1 }; FixRestart='pc' }
  @{ Page='Seguranca'; Id='firewall'; Level='crit'; Glyph=[char]0xE785; Title='Firewall ligado nos três perfis'; Desc='Bloqueia conexões de entrada não autorizadas na rede doméstica, pública e de domínio.'
     Get={ @(Get-NetFirewallProfile | Where-Object { -not $_.Enabled }).Count -eq 0 }
     FixText='Ligar'; Fix={ Set-NetFirewallProfile -All -Enabled True }; FixRestart='nenhum' }
)

for ($ci = 0; $ci -lt $script:Checks.Count; $ci++) { $script:Checks[$ci].Idx = $ci }

# Highlight: 'top' (Sugestões) e 'bottom' (Ativos) ganham destaque na barra lateral
# Mode: 'simples' = só no modo Simplificado | 'categorias' = só no modo Por categoria | sem Mode = nos dois
$script:Pages = [ordered]@{
  'Sugestoes'   = @{ Glyph=[char]0xE734; Title='Sugestões';                 Sub='Ajustes recomendados para este PC. Aplique ou descarte: eles somem da lista.'; Highlight='top' }
  'Inicio'      = @{ Glyph=[char]0xE80F; Title='Visão geral';               Sub='Seus ajustes, a segurança e o hardware do PC agora.' }
  'Automacao'   = @{ Glyph=[char]0xE945; Title='Automação';                 Sub='O Janus lê o seu PC e decide sozinho o que vale a pena ajustar, explicando cada decisão.' }
  'Otimizacoes' = @{ Glyph=[char]0xE9F5; Title='Otimizações';               Sub='Todos os ajustes num lugar só. Ordene por prioridade, nome ou categoria.'; Mode='simples' }
  'Entrada'     = @{ Glyph=[char]0xE962; Title='Mouse, teclado e controle'; Sub='Mira, digitação e controle durante as partidas.'; Mode='categorias' }
  'Graficos'    = @{ Glyph=[char]0xE7F4; Title='Gráficos e jogos';          Sub='Placa de vídeo, monitor e como o Windows trata os jogos.'; Mode='categorias' }
  'Rede'        = @{ Glyph=[char]0xE701; Title='Rede e energia';            Sub='Conexões, DNS, teste de velocidade, economia de energia e inicialização.'; SimpleTitle='Internet e DNS'; SimpleSub='DNS seguro e teste de velocidade de cada conexão.' }
  'Privacidade' = @{ Glyph=[char]0xE72E; Title='Privacidade';               Sub='O que o Windows envia e mostra para você.'; Mode='categorias' }
  'Interface'   = @{ Glyph=[char]0xE771; Title='Interface';                 Sub='Aparência e atalhos do dia a dia.'; Mode='categorias' }
  'Jogos'       = @{ Glyph=[char]0xE7FC; Title='Jogos';                     Sub='Os jogos instalados neste PC e a configuração ideal de cada um, pesquisada com a IA que você escolher.' }
  'Seguranca'   = @{ Glyph=[char]0xEA18; Title='Segurança';                 Sub='O padrão do Windows é o certo. Recomendamos deixar tudo ligado.' }
  'Manutencao'  = @{ Glyph=[char]0xE90F; Title='Manutenção';                Sub='Ações rápidas: ponto de restauração, verificação, limpeza.' }
  'Registro'    = @{ Glyph=[char]0xE8A5; Title='Registro de mudanças';      Sub='Tudo o que o Janus já alterou, com data e hora.' }
  'Sobre'       = @{ Glyph=[char]0xE946; Title='Sobre';                     Sub='Quem fez, de onde veio e como o Janus funciona.' }
  'Ativos'      = @{ Glyph=[char]0xE73E; Title='Mudanças aplicadas';        Sub='Todas as mudanças que o Janus fez e que estão valendo agora. Desfaça o que quiser.'; Bottom=$true }
}
$CategoryNames = [ordered]@{ Entrada = 'Mouse, teclado e controle'; Graficos = 'Gráficos e jogos'; Rede = 'Rede e energia'; Privacidade = 'Privacidade'; Interface = 'Interface' }
function Get-PageTitle([string]$k) { $p = $script:Pages[$k]; if ($script:Config.NavMode -eq 'simples' -and $p.SimpleTitle) { $p.SimpleTitle } else { $p.Title } }
function Set-PageSub([string]$name) {
    $ui.PageSub.Inlines.Clear(); $ui.PageSub.Text = (T (Get-PageSub $name))
    if ($name -ne 'Inicio') { return }
    # legenda: ícone + nome de cada nível (no lugar do texto explicando as cores)
    foreach ($k in 'ok', 'warn', 'crit') {
        $g = Glyph ([string]$LevelStyle[$k][0]) 12 $LevelStyle[$k][1]; $g.Margin = $(if ($k -eq 'ok') { '14,0,5,-2' } else { '12,0,5,-2' })
        $c = New-Object System.Windows.Documents.InlineUIContainer $g; $c.BaselineAlignment = 'Center'; $ui.PageSub.Inlines.Add($c)
        $ui.PageSub.Inlines.Add((New-Object System.Windows.Documents.Run (T $LevelStyle[$k][2])))
    }
}
function Get-PageSub([string]$k) { $p = $script:Pages[$k]; if ($script:Config.NavMode -eq 'simples' -and $p.SimpleSub) { $p.SimpleSub } else { $p.Sub } }
function Test-PageInMode([string]$k) { $m = $script:Pages[$k].Mode; (-not $m) -or ($m -eq $script:Config.NavMode) }

# ---------- janela ----------
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Janus" Width="1260" Height="840" MinWidth="1020" MinHeight="660"
        WindowStartupLocation="CenterScreen" Background="#0E1117" FontFamily="Segoe UI Variable Text, Segoe UI, Microsoft YaHei UI"
        Foreground="#E6E9EF" UseLayoutRounding="True" TextOptions.TextFormattingMode="Display">
  <Window.Resources>
    <Style x:Key="Switch" TargetType="ToggleButton">
      <Setter Property="Width" Value="46"/><Setter Property="Height" Value="24"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ToggleButton">
            <Grid>
              <Border x:Name="Track" CornerRadius="12" Background="#2A2112" BorderBrush="#78350F" BorderThickness="1"/>
              <!-- desligado: seta âmbar para a esquerda (padrão do Windows). ligado: seta verde para a direita (ajuste aplicado) -->
              <Grid x:Name="Arrow" Width="18" Height="14" HorizontalAlignment="Left" VerticalAlignment="Center" Margin="6,0,0,0">
                <Grid.RenderTransform><TranslateTransform x:Name="Tx" X="0"/></Grid.RenderTransform>
                <Path x:Name="ArrowOff" Data="M16,7 L3,7 M8,2 L3,7 L8,12" Stroke="#F59E0B" StrokeThickness="2.6" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
                <Path x:Name="ArrowOn" Data="M2,7 L15,7 M10,2 L15,7 L10,12" Stroke="#22C55E" StrokeThickness="2.6" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round" Visibility="Collapsed"/>
              </Grid>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Track" Property="Background" Value="#163A2C"/>
                <Setter TargetName="Track" Property="BorderBrush" Value="#22C55E"/>
                <Setter TargetName="Arrow" Property="HorizontalAlignment" Value="Right"/>
                <Setter TargetName="Arrow" Property="Margin" Value="0,0,6,0"/>
                <Setter TargetName="ArrowOn" Property="Visibility" Value="Visible"/>
                <Setter TargetName="ArrowOff" Property="Visibility" Value="Collapsed"/>
                <Trigger.EnterActions><BeginStoryboard><Storyboard>
                  <DoubleAnimation Storyboard.TargetName="Tx" Storyboard.TargetProperty="X" From="-16" To="0" Duration="0:0:0.22"><DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction></DoubleAnimation>
                  <DoubleAnimation Storyboard.TargetName="ArrowOn" Storyboard.TargetProperty="Opacity" From="0" To="1" Duration="0:0:0.22"/>
                </Storyboard></BeginStoryboard></Trigger.EnterActions>
                <Trigger.ExitActions><BeginStoryboard><Storyboard>
                  <DoubleAnimation Storyboard.TargetName="Tx" Storyboard.TargetProperty="X" From="16" To="0" Duration="0:0:0.22"><DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction></DoubleAnimation>
                  <DoubleAnimation Storyboard.TargetName="ArrowOff" Storyboard.TargetProperty="Opacity" From="0" To="1" Duration="0:0:0.22"/>
                </Storyboard></BeginStoryboard></Trigger.ExitActions>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Track" Property="Opacity" Value="0.85"/></Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Track" Property="Background" Value="#1C2029"/>
                <Setter TargetName="Track" Property="BorderBrush" Value="#262B35"/>
                <Setter TargetName="ArrowOff" Property="Stroke" Value="#4A5161"/>
                <Setter TargetName="ArrowOn" Property="Stroke" Value="#4A5161"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Nav" TargetType="Button">
      <Setter Property="Foreground" Value="#AEB6C4"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/><Setter Property="Margin" Value="10,2"/>
      <Setter Property="BorderBrush" Value="Transparent"/><Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8" Padding="12,9">
              <ContentPresenter HorizontalAlignment="Stretch"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Opacity" Value="0.85"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Accent" TargetType="Button">
      <Setter Property="Foreground" Value="White"/><Setter Property="Background" Value="#3B82F6"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Padding" Value="16,8"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Opacity" Value="0.85"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="Bd" Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Setter Property="HorizontalContentAlignment" Value="Center"/>
    </Style>
    <Style x:Key="Ghost" TargetType="Button" BasedOn="{StaticResource Accent}">
      <Setter Property="Background" Value="#232A37"/><Setter Property="Foreground" Value="#E6E9EF"/>
    </Style>
    <Style x:Key="Danger" TargetType="Button" BasedOn="{StaticResource Accent}">
      <Setter Property="Background" Value="#3A2026"/><Setter Property="Foreground" Value="#FCA5A5"/>
    </Style>
    <Style x:Key="JMenu" TargetType="ContextMenu">
      <Setter Property="OverridesDefaultStyle" Value="True"/><Setter Property="SnapsToDevicePixels" Value="True"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ContextMenu">
        <Border Background="#171C26" BorderBrush="#2A303C" BorderThickness="1" CornerRadius="10" Padding="6">
          <StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Cycle"/>
        </Border>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="JMenuSep" TargetType="Separator">
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Separator"><Border Height="1" Background="#2A303C" Margin="8,5"/></ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="JMenuItem" TargetType="MenuItem">
      <Setter Property="Foreground" Value="#E6E9EF"/><Setter Property="FontSize" Value="13"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="MenuItem">
        <Border x:Name="Bd" Background="Transparent" CornerRadius="6" Padding="10,7,10,7">
          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width="22"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <TextBlock x:Name="Check" Text="&#xE73E;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12" Foreground="#60A5FA" VerticalAlignment="Center" Visibility="Collapsed"/>
            <ContentPresenter Grid.Column="1" ContentSource="Header" RecognizesAccessKey="True" VerticalAlignment="Center" MinWidth="170"/>
            <TextBlock x:Name="Arrow" Grid.Column="2" Text="&#xE76C;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="10" Foreground="#8B94A5" VerticalAlignment="Center" Margin="12,0,0,0" Visibility="Collapsed"/>
            <Popup x:Name="PART_Popup" Placement="Right" HorizontalOffset="8" VerticalOffset="-7" IsOpen="{Binding IsSubmenuOpen, RelativeSource={RelativeSource TemplatedParent}}" AllowsTransparency="True" Focusable="False" PopupAnimation="Fade">
              <Border Background="#171C26" BorderBrush="#2A303C" BorderThickness="1" CornerRadius="10" Padding="6">
                <StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Cycle"/>
              </Border>
            </Popup>
          </Grid>
        </Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsHighlighted" Value="True"><Setter TargetName="Bd" Property="Background" Value="#232A37"/></Trigger>
          <Trigger Property="IsChecked" Value="True"><Setter TargetName="Check" Property="Visibility" Value="Visible"/></Trigger>
          <Trigger Property="Role" Value="SubmenuHeader"><Setter TargetName="Arrow" Property="Visibility" Value="Visible"/></Trigger>
          <Trigger Property="Role" Value="TopLevelHeader"><Setter TargetName="Arrow" Property="Visibility" Value="Visible"/></Trigger>
          <Trigger Property="IsEnabled" Value="False"><Setter TargetName="Bd" Property="Opacity" Value="0.45"/></Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
  </Window.Resources>
  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="256"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
    <Border Grid.Column="0" Background="#121620" BorderBrush="#1E2532" BorderThickness="0,0,1,0">
      <DockPanel>
        <StackPanel DockPanel.Dock="Top" Margin="22,26,22,16">
          <StackPanel Orientation="Horizontal">
            <Image x:Name="LogoImg" Width="36" Height="36"/>
            <StackPanel Margin="11,0,0,0" VerticalAlignment="Center">
              <StackPanel Orientation="Horizontal">
                <TextBlock x:Name="BrandText" Text="Janus" FontSize="16" FontWeight="SemiBold"/>
                <Border x:Name="BetaBadge" Margin="8,2,0,0" Padding="6,0" CornerRadius="5" Background="#2A2112" BorderBrush="#78350F" BorderThickness="1" VerticalAlignment="Center">
                  <TextBlock Text="BETA" FontSize="9.5" FontWeight="Bold" Foreground="#F59E0B"/>
                </Border>
              </StackPanel>
              <TextBlock x:Name="MachineText" Text="" FontSize="11" Foreground="#7F8899"/>
            </StackPanel>
          </StackPanel>
        </StackPanel>
        <TextBlock DockPanel.Dock="Bottom" x:Name="FooterText" Margin="22,8,22,16" FontSize="10.5" Foreground="#5F6878" TextWrapping="Wrap"/>
        <StackPanel DockPanel.Dock="Bottom" x:Name="NavBottom" Margin="0,8,0,0"/>
        <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel x:Name="Nav" Margin="0,2,0,0"/></ScrollViewer>
      </DockPanel>
    </Border>
    <Grid Grid.Column="1">
      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
      <Grid Grid.Row="0" Margin="32,28,32,12">
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <StackPanel>
          <TextBlock x:Name="PageTitle" FontSize="26" FontWeight="SemiBold" FontFamily="Segoe UI Variable Display, Segoe UI"/>
          <TextBlock x:Name="PageSub" FontSize="13" Foreground="#8B94A5" Margin="0,4,0,0" TextWrapping="Wrap"/>
          <StackPanel Orientation="Horizontal" Margin="0,6,0,0">
            <Ellipse x:Name="LiveDot" Width="9" Height="9" Fill="#22C55E" VerticalAlignment="Center" Margin="0,0,7,0" Cursor="Help"/>
            <TextBlock x:Name="UpdatedText" FontSize="11.5" Foreground="#5F6878"/>
          </StackPanel>
        </StackPanel>
        <StackPanel Grid.Column="1" VerticalAlignment="Center">
          <StackPanel x:Name="LangTop" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,0,0,8"/>
          <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <StackPanel x:Name="HeaderExtra" Orientation="Horizontal" VerticalAlignment="Center"/>
          <Button x:Name="BtnRefresh" Style="{StaticResource Ghost}" Height="36" Padding="12,0" Margin="0,0,10,0" ToolTip="Ler tudo de novo agora">
            <StackPanel Orientation="Horizontal">
              <TextBlock x:Name="RefreshIcon" Text="&#xE72C;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" VerticalAlignment="Center" Margin="0,0,8,0" Foreground="#22C55E"/>
              <TextBlock x:Name="RefreshLabel" Text="Atualizar" VerticalAlignment="Center"/>
            </StackPanel>
          </Button>
          <Border x:Name="SearchBox" CornerRadius="8" Background="#171C26" BorderBrush="#262E3C" BorderThickness="1" Width="240" Height="36" VerticalAlignment="Center">
            <Grid>
              <TextBlock Text="&#xE721;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Foreground="#6B7486" Margin="12,0,0,0" VerticalAlignment="Center"/>
              <TextBox x:Name="Search" Background="Transparent" BorderThickness="0" Foreground="#E6E9EF" CaretBrush="#E6E9EF" Margin="34,0,10,0" VerticalAlignment="Center" FontSize="13"/>
              <TextBlock x:Name="SearchHint" Text="Procurar ajuste..." Foreground="#5F6878" Margin="36,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False" FontSize="13"/>
            </Grid>
          </Border>
          </StackPanel>
        </StackPanel>
      </Grid>
      <ScrollViewer Grid.Row="1" x:Name="Scroll" VerticalScrollBarVisibility="Auto" Padding="32,4,20,24">
        <StackPanel x:Name="Body"/>
      </ScrollViewer>
      <Border Grid.Row="2" x:Name="PendingBar" Visibility="Collapsed" Background="#1A2234" BorderBrush="#2C3A57" BorderThickness="0,1,0,0" Padding="32,12">
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
          <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
            <TextBlock Text="&#xE777;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Foreground="#A78BFA" FontSize="16" VerticalAlignment="Center"/>
            <TextBlock x:Name="PendingText" Margin="10,0,0,0" TextWrapping="Wrap" VerticalAlignment="Center" Foreground="#D6DCE8"/>
          </StackPanel>
          <StackPanel Grid.Column="1" Orientation="Horizontal">
            <Button x:Name="BtnExplorer" Style="{StaticResource Ghost}" Content="Reiniciar o Explorer" Margin="0,0,8,0"/>
            <Button x:Name="BtnReboot" Style="{StaticResource Accent}" Content="Reiniciar o PC"/>
          </StackPanel>
        </Grid>
      </Border>
      <Border Grid.Row="1" x:Name="Toast" Visibility="Collapsed" VerticalAlignment="Bottom" HorizontalAlignment="Center" Margin="0,0,0,18" Background="#E6E9EF" CornerRadius="10" Padding="16,10">
        <TextBlock x:Name="ToastText" Foreground="#0E1117" FontWeight="SemiBold"/>
      </Border>
    </Grid>
  </Grid>
</Window>
'@
if ($script:IsLight) { $xaml = [xml](Convert-ThemeText $xaml.OuterXml) }
$reader = New-Object System.Xml.XmlNodeReader $xaml
$W = [Windows.Markup.XamlReader]::Load($reader)
$ui = @{}
foreach ($n in 'Nav','NavBottom','PageTitle','PageSub','SearchBox','Search','SearchHint','Scroll','Body','PendingBar','PendingText','BtnExplorer','BtnReboot','Toast','ToastText','MachineText','FooterText','LogoImg','BtnRefresh','UpdatedText','LiveDot','RefreshIcon','RefreshLabel','LangTop','HeaderExtra','BetaBadge') { $ui[$n] = $W.FindName($n) }
if (Test-Path -LiteralPath $IconPath) {
    try { $W.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create((New-Object System.Uri $IconPath)); $ui.LogoImg.Source = (New-PngImage 72) } catch {}
}

# ---------- componentes ----------
$script:Pending = @{ explorer = New-Object System.Collections.ArrayList; pc = New-Object System.Collections.ArrayList; desligar = New-Object System.Collections.ArrayList }
$script:ToastTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:ToastTimer.Interval = [TimeSpan]::FromSeconds(2.8)
$script:ToastTimer.add_Tick({ $ui.Toast.Visibility = 'Collapsed'; $script:ToastTimer.Stop() })
function Show-Toast([string]$msg) { $ui.ToastText.Text = (T $msg); $ui.Toast.Visibility = 'Visible'; $script:ToastTimer.Stop(); $script:ToastTimer.Start() }

function New-Text([string]$t, [double]$size = 13, [string]$color = '#E6E9EF', [string]$weight = 'Normal') {
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = (T $t); $tb.FontSize = $size; $tb.Foreground = Brush $color; $tb.FontWeight = $weight; $tb.TextWrapping = 'Wrap'
    return $tb
}
function New-Badge([string]$text, [string]$color) {
    $b = New-Object System.Windows.Controls.Border
    $b.CornerRadius = 6; $b.Padding = '7,2,7,2'; $b.Margin = '0,0,6,6'
    $c = [System.Windows.Media.Color]((New-Object System.Windows.Media.ColorConverter).ConvertFrom($color))
    $b.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(38, $c.R, $c.G, $c.B))
    $tb = New-Text $text 10.5 $color 'SemiBold'; $tb.TextWrapping = 'NoWrap'
    $b.Child = $tb
    return $b
}
function New-Card { $c = New-Object System.Windows.Controls.Border; $c.CornerRadius = 12; $c.Background = Brush '#171C26'; $c.BorderBrush = Brush '#232A36'; $c.BorderThickness = 1; $c.Padding = '20,16,20,14'; $c.Margin = '0,0,12,12'; return $c }
function New-Section([string]$t) { $s = New-Text $t 11.5 '#7F8899' 'SemiBold'; $s.Margin = '2,14,0,10'; return $s }
function Glyph([string]$g, [double]$size, [string]$color) { $t = New-Text $g $size $color; $t.FontFamily = 'Segoe Fluent Icons, Segoe MDL2 Assets'; $t.TextWrapping = 'NoWrap'; return $t }
function New-Button([string]$text, [string]$style = 'Ghost', $tag = $null) { $b = New-Object System.Windows.Controls.Button; $b.Style = $W.FindResource($style); $b.Content = (T $text); $b.Tag = $tag; $b.VerticalAlignment = 'Center'; return $b }
function Grid-Cols($g, [string[]]$widths) { foreach ($cw in $widths) { $cd = New-Object System.Windows.Controls.ColumnDefinition; $cd.Width = $cw; $g.ColumnDefinitions.Add($cd) } }
function Put($g, $el, [int]$col) { [System.Windows.Controls.Grid]::SetColumn($el, $col); $g.Children.Add($el) | Out-Null }

$LevelStyle = @{ ok = @([char]0xE73E, '#22C55E', 'Normal'); warn = @([char]0xE7BA, '#F59E0B', 'Atenção'); crit = @([char]0xEA39, '#EF4444', 'Urgente') }
# O que cada luz quer dizer ao passar o mouse: o que está acontecendo ou o que fazer
function Get-LevelHint([string]$level, [string]$fix = '') {
    $h = @{ ok = 'Normal: está como deveria. Nada a fazer.'
            warn = 'Atenção: vale olhar. Clique no ? ao lado para entender e saber o que fazer.'
            crit = 'Urgente: precisa de ação. Clique no ? ao lado para saber o que fazer.' }[$level]
    $h = T $h
    if ($fix) { $h += "`n" + ((T 'Para resolver: botão "{0}".') -f (T $fix)) }
    return $h
}

function Is-Dismissed($t) { ($script:Config.Dismissed -contains $t.Id) -or ($script:DismissedSession -contains $t.Id) }
function Get-PendingSuggestions { @($script:Tweaks | Where-Object { $_.Rec -eq $true -and (Is-Available $_) -and -not (Is-Dismissed $_) -and ((Get-State $_) -ne $true) }) }
function Get-ActiveTweaks { @($script:Tweaks | Where-Object { (Is-Available $_) -and ((Get-State $_) -eq $true) }) }

function Update-Pending {
    $parts = @()
    if ($script:Pending.pc.Count) { $parts += ((T 'Precisa reiniciar o PC:') + ' ' + (($script:Pending.pc | ForEach-Object { T $_ }) -join ', ')) }
    if ($script:Pending.explorer.Count) { $parts += ((T 'Precisa reiniciar o Explorer:') + ' ' + (($script:Pending.explorer | ForEach-Object { T $_ }) -join ', ')) }
    if ($script:Pending.desligar.Count) { $parts += ((T 'Vale no próximo desligamento:') + ' ' + (($script:Pending.desligar | ForEach-Object { T $_ }) -join ', ')) }
    if ($parts.Count) { $ui.PendingText.Text = ($parts -join '   |   '); $ui.PendingBar.Visibility = 'Visible' } else { $ui.PendingBar.Visibility = 'Collapsed' }
    $ui.BtnExplorer.Visibility = $(if ($script:Pending.explorer.Count) { 'Visible' } else { 'Collapsed' })
    $ui.BtnReboot.Visibility = $(if ($script:Pending.pc.Count) { 'Visible' } else { 'Collapsed' })
}
function Add-Pending([string]$restart, [string]$title) {
    if ($restart -eq 'nenhum' -or -not $restart) { return }
    $list = $script:Pending[$restart]
    if ($null -ne $list -and -not $list.Contains($title)) { [void]$list.Add($title) }
    Update-Pending
}

function Refresh-Card($t) {
    if (-not $t.UI) { return }
    $state = Get-State $t
    $t.UI.Updating = $true
    $t.UI.Toggle.IsChecked = ($state -eq $true)
    $t.UI.Toggle.ToolTip = (T $(if ($state) { 'Ativado. Clique para desativar e voltar ao padrão do Windows.' } else { 'Desativado (padrão do Windows). Clique para ativar.' }))
    [System.Windows.Controls.ToolTipService]::SetInitialShowDelay($t.UI.Toggle, 150)
    $t.UI.Updating = $false
    $t.UI.Card.BorderBrush = Brush $(if ($state) { '#2D4A7C' } else { '#232A36' })
    $t.UI.Icon.Foreground = Brush $(if ($state) { '#60A5FA' } else { '#8EA3C8' })
}

$script:Busy = $false
function Apply-Tweak($t, [bool]$on, [switch]$Silent) {
    $W.Cursor = [System.Windows.Input.Cursors]::Wait
    try {
        Ensure-RestorePoint
        $before = Read-State $t
        if ($t.Keys.Count) { Backup-Keys $t.Id $t.Keys }
        & $t.Set $on
        $after = Read-State $t
        $script:Snap.State[$t.Id] = $after; $script:SnapVersion++
        $f = { param($x) if ($x) { 'ativo' } elseif ($null -eq $x) { '?' } else { 'inativo' } }
        Write-Log ("{0}: {1} -> {2}" -f $t.Title, (& $f $before), (& $f $after))
        if ($after -ne $before) { Add-Pending $t.Restart $t.Title }
        return ($after -eq $on)
    } catch {
        $msg = $_.Exception.Message
        Write-Log ("ERRO ao mudar {0}: {1}" -f $t.Title, $msg)
        if (-not $Silent) {
            $W.Cursor = $null
            $r = Show-Choice 'Não consegui aplicar' $t.Title ((T 'O Windows recusou a mudança:') + ' ' + $msg + "`n`n" + (T 'Quer pedir ajuda ao Claude ou reportar o erro? Os dois montam um arquivo com tudo sobre o problema.')) @(@('ask', 'Perguntar ao Claude', 'Accent'), @('report', 'Reportar erro', 'Ghost'), @('no', 'Agora não', 'Ghost')) 'crit'
            if ($r -eq 'ask') { Ask-Claude 'Ajuste' $t $msg }
            if ($r -eq 'report') { Show-ReportDialog 'erro' ("Erro: $msg`r`nAjuste: " + $t.Id) | Out-Null }
        }
        return $false
    } finally { $W.Cursor = $null }
}

$restartLabel = @{ nenhum = @('Efeito imediato','#8B94A5'); explorer = @('Reinicia o Explorer','#A78BFA'); desligar = @('Vale no próximo desligamento','#A78BFA'); pc = @('Precisa reiniciar o PC','#C084FC') }
$riskLabel = @{ 0 = @('Seguro','#22C55E'); 1 = @('Atenção','#F59E0B') }
function Add-TweakBadges($wp, $t, [switch]$NoRec) {
    $rl = $riskLabel[[int]$t.Risk]; $wp.Children.Add((New-Badge $rl[0] $rl[1])) | Out-Null
    $rs = $restartLabel[$t.Restart]; $wp.Children.Add((New-Badge $rs[0] $rs[1])) | Out-Null
    if ($t.Scope -eq 'pc') { $wp.Children.Add((New-Badge 'Todo o PC' '#2DD4BF')) | Out-Null } else { $wp.Children.Add((New-Badge 'Só na sua conta' '#94A3B8')) | Out-Null }
    if (-not $NoRec) { if ($t.Rec -eq $true) { $wp.Children.Add((New-Badge ('Sugerido: ' + $t.RecWhy) '#60A5FA')) | Out-Null } else { $wp.Children.Add((New-Badge 'A gosto' '#8B94A5')) | Out-Null } }
}

# ---------- janelas no estilo do app ----------
function New-StyledWindow([string]$title, [double]$width) {
    $d = New-Object System.Windows.Window
    $d.Title = (T $title); $d.Width = $width; $d.SizeToContent = 'Height'; $d.ResizeMode = 'NoResize'; $d.ShowInTaskbar = $false
    if ($W.IsVisible) { $d.Owner = $W; $d.WindowStartupLocation = 'CenterOwner' } else { $d.WindowStartupLocation = 'CenterScreen' }
    if ($W.Icon) { $d.Icon = $W.Icon }
    $d.Background = Brush '#0E1117'; $d.Foreground = Brush '#E6E9EF'; $d.FontFamily = 'Segoe UI Variable Text, Segoe UI, Microsoft YaHei UI'
    return $d
}
# botões: @( @('id','texto','Accent|Ghost|Danger'), ... ) | level: info, warn, crit
function Show-Choice([string]$title, [string]$heading, [string]$text, $buttons, [string]$level = 'info') {
    $d = New-StyledWindow $title 540
    $root = New-Object System.Windows.Controls.StackPanel; $root.Margin = '26,22,26,22'
    $row = New-Object System.Windows.Controls.StackPanel; $row.Orientation = 'Horizontal'
    $lv = @{ info = @([char]0xE946, '#60A5FA'); warn = @([char]0xE7BA, '#F59E0B'); crit = @([char]0xEA39, '#EF4444') }[$level]
    $ic = Glyph ([string]$lv[0]) 22 $lv[1]; $ic.Margin = '0,0,12,0'; $ic.VerticalAlignment = 'Center'; $row.Children.Add($ic) | Out-Null
    $h = New-Text $heading 18 '#E6E9EF' 'SemiBold'; $h.VerticalAlignment = 'Center'; $row.Children.Add($h) | Out-Null
    $root.Children.Add($row) | Out-Null
    $tx = New-Text $text 13 '#AEB6C4'; $tx.Margin = '0,12,0,20'; $tx.LineHeight = 19; $root.Children.Add($tx) | Out-Null
    $br = New-Object System.Windows.Controls.StackPanel; $br.Orientation = 'Horizontal'; $br.HorizontalAlignment = 'Right'
    if ($buttons.Count -and $buttons[0] -is [string]) { $buttons = @(, $buttons) }   # @(@(1 botão)) vira lista plana no PowerShell
    foreach ($bt in $buttons) {
        $b = New-Button $bt[1] $bt[2] $bt[0]; $b.Margin = '8,0,0,0'
        $b.add_Click({ $win = [System.Windows.Window]::GetWindow($this); $win.Tag = $this.Tag; $win.DialogResult = $true })
        $br.Children.Add($b) | Out-Null
    }
    $root.Children.Add($br) | Out-Null
    $d.Content = $root; $d.Tag = 'cancel'
    if ($Teste) { $d.Close(); return 'cancel' }
    $script:Busy = $true; try { [void]$d.ShowDialog() } finally { $script:Busy = $false }
    return [string]$d.Tag
}

function Show-Welcome {
    $d = New-StyledWindow 'Bem-vindo ao Janus' 620
    $root = New-Object System.Windows.Controls.StackPanel; $root.Margin = '30,26,30,24'
    $hrow = New-Object System.Windows.Controls.StackPanel; $hrow.Orientation = 'Horizontal'
    $img = New-Object System.Windows.Controls.Image; $img.Width = 52; $img.Height = 52; try { $img.Source = (New-PngImage 104) } catch {}
    $hrow.Children.Add($img) | Out-Null
    $ht = New-Object System.Windows.Controls.StackPanel; $ht.Margin = '14,0,0,0'; $ht.VerticalAlignment = 'Center'
    $ht.Children.Add((New-Text 'Antes de começar' 22 '#E6E9EF' 'SemiBold')) | Out-Null
    $ht.Children.Add((New-Text 'Leva 20 segundos e vale a pena ler.' 12.5 '#8B94A5')) | Out-Null
    $hrow.Children.Add($ht) | Out-Null; $root.Children.Add($hrow) | Out-Null
    $warn = New-Object System.Windows.Controls.Border; $warn.CornerRadius = 10; $warn.Margin = '0,20,0,16'; $warn.Padding = '16,12'
    $warn.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(36, 0xF5, 0x9E, 0x0B))
    $wt = New-Text 'O Janus muda configurações do Windows. Para isso ele roda como administrador, com o mesmo poder de um instalador de programas. Use com calma e leia o que cada botão faz antes de ligar.' 13 '#FCD38D' 'SemiBold'; $wt.LineHeight = 19
    $warn.Child = $wt; $root.Children.Add($warn) | Out-Null
    $root.Children.Add((New-Text 'O que ele faz para você ficar seguro:' 13 '#E6E9EF' 'SemiBold')) | Out-Null
    foreach ($pair in @(
        @([char]0xE73E, 'Mostra o estado real de cada ajuste, lido direto do Windows.'),
        @([char]0xE81C, 'Cria um ponto de restauração e guarda um backup antes de mudar qualquer coisa.'),
        @([char]0xE8A5, 'Anota tudo no Registro de mudanças. Todo ajuste pode ser desfeito, um por um ou todos de uma vez.'),
        @([char]0xEA18, 'Não mexe na segurança sozinho: antivírus, firewall e UAC ficam ligados. Só é desligado o que você pedir, com avisos.'),
        @([char]0xE9CE, 'Ficou com dúvida? O botão ? ao lado de cada item monta um resumo e pergunta ao Claude por você.')
    )) {
        $r = New-Object System.Windows.Controls.Grid; Grid-Cols $r @('Auto', '*'); $r.Margin = '0,10,0,0'
        $gi = Glyph ([string]$pair[0]) 16 '#60A5FA'; $gi.Margin = '2,1,12,0'; $gi.VerticalAlignment = 'Top'; Put $r $gi 0
        $tt = New-Text $pair[1] 12.8 '#AEB6C4'; $tt.LineHeight = 18; Put $r $tt 1
        $root.Children.Add($r) | Out-Null
    }
    $foot = New-Object System.Windows.Controls.Grid; Grid-Cols $foot @('*', 'Auto'); $foot.Margin = '0,24,0,0'
    $cb = New-Object System.Windows.Controls.CheckBox; $cb.Content = (T 'Não mostrar de novo'); $cb.IsChecked = $true; $cb.Foreground = Brush '#8B94A5'; $cb.VerticalAlignment = 'Center'
    Put $foot $cb 0
    $ok = New-Button 'Entendi, vamos lá' 'Accent'; $ok.add_Click({ [System.Windows.Window]::GetWindow($this).DialogResult = $true }); Put $foot $ok 1
    $root.Children.Add($foot) | Out-Null
    $d.Content = $root
    if ($Teste) { $d.Close(); return }
    $script:Busy = $true; try { [void]$d.ShowDialog() } finally { $script:Busy = $false }
    if ($cb.IsChecked) { $script:Config.WarningSeen = $true; Save-Config }
    Write-Log 'Aviso inicial mostrado.'
}

# ---------- cartões ----------
function New-TweakCard($t) {
    $card = New-Card; $card.Padding = '18,16,18,14'
    $sp = New-Object System.Windows.Controls.StackPanel
    $top = New-Object System.Windows.Controls.Grid; Grid-Cols $top @('*', 'Auto')
    $ic = Glyph ([string]$t.Glyph) 24 '#8EA3C8'; Put $top $ic 0
    $tg = New-Object System.Windows.Controls.Primitives.ToggleButton
    $tg.Style = $W.FindResource('Switch'); $tg.VerticalAlignment = 'Center'
    $tr = New-Object System.Windows.Controls.StackPanel; $tr.Orientation = 'Horizontal'; $tr.VerticalAlignment = 'Top'
    $hb = New-HelpButton 'Ajuste' $t; $hb.Margin = '0,0,10,0'
    $tr.Children.Add($hb) | Out-Null; $tr.Children.Add($tg) | Out-Null
    Put $top $tr 1
    $sp.Children.Add($top) | Out-Null
    $tt = New-Text $t.Title 14.5 '#E6E9EF' 'SemiBold'; $tt.Margin = '0,12,0,0'; $sp.Children.Add($tt) | Out-Null
    $d = New-Text $t.Desc 12.2 '#9AA3B2'; $d.Margin = '0,5,0,10'; $d.LineHeight = 17; $sp.Children.Add($d) | Out-Null
    $wp = New-Object System.Windows.Controls.WrapPanel; Add-TweakBadges $wp $t; $sp.Children.Add($wp) | Out-Null
    if (-not (Is-Available $t)) {
        $tg.IsEnabled = $false
        $why = New-Text ('Indisponível: ' + $t.UnavailableWhy) 11.5 '#F59E0B' 'SemiBold'; $why.Margin = '0,2,0,6'
        $sp.Children.Add($why) | Out-Null
        $tg.ToolTip = (T $t.UnavailableWhy); $card.ToolTip = (T $t.UnavailableWhy)
    }
    $link = New-Text 'Não recomendado se...' 11.5 '#8B94A5'; $link.TextDecorations = [System.Windows.TextDecorations]::Underline; $link.Cursor = [System.Windows.Input.Cursors]::Hand; $link.Margin = '0,4,0,0'
    $cav = New-Text $t.Caveat 11.8 '#C9CED6'; $cav.Margin = '0,4,0,0'; $cav.Visibility = 'Collapsed'
    $link.Tag = $cav
    $link.add_MouseLeftButtonUp({ $this.Tag.Visibility = $(if ($this.Tag.Visibility -eq 'Visible') { 'Collapsed' } else { 'Visible' }) })
    $sp.Children.Add($link) | Out-Null; $sp.Children.Add($cav) | Out-Null
    $card.Child = $sp
    $t.UI = @{ Card = $card; Toggle = $tg; Icon = $ic; Updating = $false }
    $tg.Tag = $t
    if (Is-Available $t) {
        $tg.add_Click({
            $tw = $this.Tag
            if ($tw.UI.Updating) { return }
            $want = [bool]$this.IsChecked
            $script:Busy = $true
            try { $ok = Apply-Tweak $tw $want } finally { $script:Busy = $false }
            Refresh-Card $tw; Update-NavCounts
            if ($ok) { Show-Toast ($tw.Title + ': ' + $(if ($want) { 'ativado' } else { 'desativado (padrão do Windows)' })) }
        })
        Refresh-Card $t
    }
    return $card
}

function New-CheckCard($c) {
    $card = New-Card; $card.Padding = '16,12,16,12'; $card.Margin = '0,0,12,10'
    $g = New-Object System.Windows.Controls.Grid; Grid-Cols $g @('Auto', '*', 'Auto')
    $ok = Get-CheckOk $c
    $lv = $(if ($ok) { 'ok' } elseif ($null -eq $ok) { 'warn' } else { $c.Level })
    $st = $LevelStyle[$lv]
    if ($lv -ne 'ok') { $card.BorderBrush = Brush $(if ($lv -eq 'crit') { '#5C2A30' } else { '#5A4520' }) }
    if ($lv -eq 'ok') { $ic = Glyph ([string][char]0xE73E) 18 '#22C55E'; $ic.ToolTip = (Get-LevelHint 'ok') }
    else { $ic = Glyph ([string]$st[0]) 18 $st[1]; $ic.ToolTip = (Get-LevelHint $lv $(if ($c.Fix) { $c.FixText } else { '' })) }
    $ic.Margin = '0,1,14,0'; $ic.VerticalAlignment = 'Top'; Put $g $ic 0
    $sp = New-Object System.Windows.Controls.StackPanel; $sp.Margin = '0,0,16,0'
    $sp.Children.Add((New-Text $c.Title 13.5 '#E6E9EF' 'SemiBold')) | Out-Null
    $dd = New-Text $c.Desc 12 '#8B94A5'; $dd.Margin = '0,3,0,0'; $sp.Children.Add($dd) | Out-Null
    if ($null -eq $ok) { $n = New-Text 'Não consegui verificar agora.' 11.5 '#F59E0B'; $n.Margin = '0,3,0,0'; $sp.Children.Add($n) | Out-Null }
    Put $g $sp 1
    $act = New-Object System.Windows.Controls.StackPanel; $act.Orientation = 'Horizontal'; $act.VerticalAlignment = 'Center'; Put $g $act 2
    if ($ok) {
        $okT = New-Text 'Tudo certo' 12 '#22C55E' 'SemiBold'; $okT.VerticalAlignment = 'Center'; $okT.TextWrapping = 'NoWrap'; $act.Children.Add($okT) | Out-Null
        if ($c.Page -eq 'Seguranca' -and $c.Id -in 'hvci', 'av', 'tamper', 'firewall', 'uac') {
            $db = New-Button 'Desativar...' 'Danger' $c; $db.Padding = '10,4'; $db.FontSize = 11.5; $db.Margin = '10,0,0,0'
            $db.ToolTip = (T 'Recomendamos estritamente deixar ligado. Abre os avisos e as opções.')
            $db.add_Click({ Show-SecurityDisable $this.Tag }); $act.Children.Add($db) | Out-Null
        }
    } elseif ($c.Fix) {
        $b = New-Button $c.FixText 'Accent' $c
        $b.add_Click({
            $ck = $this.Tag
            try { Ensure-RestorePoint; & $ck.Fix; $script:SnapVersion++; if ($null -ne $script:Snap.Checks) { $script:Snap.Checks[$ck.Idx] = Read-CheckOk $ck }; $script:ForceFull = $true; Write-Log ('Verificação corrigida: ' + $ck.Title); Add-Pending $ck.FixRestart $ck.Title; Show-Toast ('Corrigido: ' + $ck.Title) }
            catch {
                $msg = $_.Exception.Message
                Write-Log ('ERRO ao corrigir ' + $ck.Title + ': ' + $msg)
                $r = Show-Choice 'Não consegui corrigir' $ck.Title ('O Windows recusou a correção: ' + $msg + "`n`nQuer pedir ajuda ao Claude?") @(@('ask', 'Perguntar ao Claude', 'Accent'), @('no', 'Agora não', 'Ghost')) 'crit'
                if ($r -eq 'ask') { Ask-Claude 'Verificacao' $ck $msg }
            }
            Show-Page $script:CurrentPage $ui.Scroll.VerticalOffset
        })
        $act.Children.Add($b) | Out-Null
    }
    $hb = New-HelpButton 'Verificacao' $c; $hb.Margin = '10,0,0,0'; $act.Children.Add($hb) | Out-Null
    $card.Child = $g
    return $card
}

# Cartão largo usado em Sugestões, Ativos e Automação
function New-WideCard($t, [string]$why, $buttons, [string]$accent = '#60A5FA') {
    $card = New-Card; $card.Padding = '18,14,18,14'; $card.Margin = '0,0,12,10'
    $g = New-Object System.Windows.Controls.Grid; Grid-Cols $g @('Auto', '*', 'Auto')
    $ic = Glyph ([string]$t.Glyph) 22 $accent; $ic.Margin = '0,2,16,0'; $ic.VerticalAlignment = 'Top'; Put $g $ic 0
    $sp = New-Object System.Windows.Controls.StackPanel; $sp.Margin = '0,0,18,0'
    $sp.Children.Add((New-Text $t.Title 14.5 '#E6E9EF' 'SemiBold')) | Out-Null
    $wy = New-Text $why 12 '#9AA3B2'; $wy.LineHeight = 17; $wy.Margin = '0,5,0,0'; $sp.Children.Add($wy) | Out-Null
    $cv = New-Text ('Não recomendado se ' + $t.Caveat) 11.5 '#6F7889'; $cv.Margin = '0,5,0,0'; $sp.Children.Add($cv) | Out-Null
    $wp = New-Object System.Windows.Controls.WrapPanel; $wp.Margin = '0,8,0,0'; Add-TweakBadges $wp $t -NoRec; $sp.Children.Add($wp) | Out-Null
    Put $g $sp 1
    $act = New-Object System.Windows.Controls.StackPanel; $act.Orientation = 'Horizontal'; $act.VerticalAlignment = 'Center'
    $hb = New-HelpButton 'Ajuste' $t; $hb.Margin = '0,0,8,0'; $act.Children.Add($hb) | Out-Null
    foreach ($b in $buttons) { $b.Margin = '0,0,8,0'; $act.Children.Add($b) | Out-Null }
    Put $g $act 2
    $card.Child = $g
    return $card
}

# ---------- "Perguntar ao Claude" ----------
$script:ClaudeCli = $null; $script:ClaudeCliChecked = $false
function Find-ClaudeCli {
    if ($script:ClaudeCliChecked) { return $script:ClaudeCli }
    $script:ClaudeCliChecked = $true
    $c = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { $script:ClaudeCli = $c.Source; return $script:ClaudeCli }
    $base = Join-Path $env:LOCALAPPDATA 'Claude-Data'
    if (Test-Path -LiteralPath $base) {
        $f = Get-ChildItem -Path (Join-Path $base '*\claude-code\*\*\claude.exe') -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($f) { $script:ClaudeCli = $f.FullName }
    }
    return $script:ClaudeCli
}
function Get-KeyValuesText([string[]]$keys) {
    $out = @()
    foreach ($k in $keys) {
        $ps = $k -replace '^HKCU\\', 'HKCU:\' -replace '^HKLM\\', 'HKLM:\'
        $out += ('- `' + $k + '`')
        if (Test-Path -LiteralPath $ps) {
            $p = Get-ItemProperty -LiteralPath $ps
            $props = @($p.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' })
            if ($props.Count) { foreach ($pr in $props) { $out += ('  - ' + $pr.Name + ' = ' + (($pr.Value | Out-String).Trim())) } } else { $out += '  - (chave existe, sem valores)' }
        } else { $out += '  - (chave não existe)' }
    }
    if (-not $out.Count) { $out = @('- (este item não usa chaves de registro)') }
    return $out
}
function New-HelpMd([string]$kind, $item, [string]$err) {
    $pc = Get-PcInfo
    $L = New-Object System.Collections.Generic.List[string]
    $L.Add('# Pedido de ajuda - Janus'); $L.Add('')
    $L.Add('Arquivo gerado pelo Janus (painel de ajustes do Windows feito para este PC). Explique em linguagem simples o que está acontecendo e como resolver com segurança. Não altere nada sem perguntar antes.'); $L.Add('Responda no idioma da pessoa: ' + @{ pt = 'português do Brasil'; en = 'English'; zh = 'Simplified Chinese (简体中文)'; es = 'español' }[$script:Lang] + '.'); $L.Add('')
    $L.Add('## Contexto'); $L.Add('')
    $L.Add('- Data: ' + (Get-Date -Format 'dd/MM/yyyy HH:mm:ss'))
    $L.Add('- Janus versão ' + $AppVersion + ' | script: `' + $PSCommandPath + '`')
    foreach ($k in 'Windows', 'Cpu', 'Gpu', 'Tela', 'Monitor', 'Ram', 'Disco', 'Rede', 'Energia', 'Tipo') { $L.Add(('- {0}: {1}' -f $k, $pc[$k])) }
    $L.Add('- App rodando como administrador: ' + $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)); $L.Add('')
    switch ($kind) {
        'Ajuste' {
            $t = $item; $st = Get-State $t
            $L.Add('## Ajuste: ' + $t.Title); $L.Add('')
            $L.Add('- Página: ' + $t.Page + ' | escopo: ' + $(if ($t.Scope -eq 'pc') { 'todo o PC' } else { 'só a conta atual' }))
            $L.Add('- Estado lido agora: ' + $(if ($st) { 'ATIVO (ajuste aplicado)' } elseif ($null -eq $st) { 'não consegui ler' } else { 'inativo (padrão do Windows)' }))
            $L.Add('- Sugerido para este PC: ' + $(if ($t.Rec -eq $true) { 'ativo (' + $t.RecWhy + ')' } else { 'a gosto' }))
            $L.Add('- Disponível: ' + (Is-Available $t) + $(if ($t.UnavailableWhy -and -not (Is-Available $t)) { ' | motivo: ' + $t.UnavailableWhy } else { '' }))
            $L.Add('- Reinício: ' + $t.Restart); $L.Add('- O que faz: ' + $t.Desc); $L.Add('- Não recomendado se: ' + $t.Caveat); $L.Add('')
            $L.Add('### Valores atuais no registro'); $L.Add(''); foreach ($x in (Get-KeyValuesText $t.Keys)) { $L.Add($x) }; $L.Add('')
            $L.Add('### Código que lê o estado'); $L.Add(''); $L.Add('```powershell'); $L.Add($t.Get.ToString().Trim()); $L.Add('```'); $L.Add('')
            $L.Add('### Código que aplica (param $on: $true = ativar, $false = voltar ao padrão)'); $L.Add(''); $L.Add('```powershell'); $L.Add($t.Set.ToString().Trim()); $L.Add('```')
        }
        'Verificacao' {
            $c = $item; $ok = Get-CheckOk $c
            $L.Add('## Verificação: ' + $c.Title); $L.Add('')
            $L.Add('- Resultado agora: ' + $(if ($ok) { 'OK' } elseif ($null -eq $ok) { 'não consegui verificar' } else { 'PROBLEMA (' + $c.Level + ')' }))
            $L.Add('- O que verifica: ' + $c.Desc); $L.Add('')
            $L.Add('### Código da verificação'); $L.Add(''); $L.Add('```powershell'); $L.Add($c.Get.ToString().Trim()); $L.Add('```'); $L.Add('')
            if ($c.Fix) { $L.Add('### Código do botão "' + $c.FixText + '"'); $L.Add(''); $L.Add('```powershell'); $L.Add($c.Fix.ToString().Trim()); $L.Add('```') }
        }
        'Status' { $L.Add('## Status de segurança: ' + $item.Name); $L.Add(''); $L.Add('- Valor agora: ' + $item.Value + ' | nível: ' + $item.Level) }
        default {
            $L.Add('## Visão geral (pedido geral de ajuda)'); $L.Add('')
            foreach ($t in $script:Tweaks) { $L.Add(('- Ajuste "{0}": {1}' -f $t.Title, $(if (-not (Is-Available $t)) { 'indisponível' } elseif (Get-State $t) { 'ativo' } else { 'inativo' }))) }
            foreach ($c in $script:Checks) { $L.Add(('- Verificação "{0}": {1}' -f $c.Title, $(if (Get-CheckOk $c) { 'ok' } else { 'PROBLEMA' }))) }
        }
    }
    if ($err) { $L.Add(''); $L.Add('## Erro mostrado'); $L.Add(''); $L.Add('```'); $L.Add($err); $L.Add('```') }
    $L.Add(''); $L.Add('## Segurança agora'); $L.Add('')
    foreach ($s in (Get-SecurityStatus)) { $L.Add(('- {0}: {1} ({2})' -f $s.Name, $s.Value, $LevelStyle[$s.Level][2])) }
    $L.Add(''); $L.Add('## Últimas linhas do registro de mudanças'); $L.Add(''); $L.Add('```')
    if (Test-Path -LiteralPath $LogFile) { foreach ($x in @(Get-Content -LiteralPath $LogFile -Encoding UTF8 -Tail 30)) { $L.Add($x) } } else { $L.Add('(vazio)') }
    $L.Add('```')
    $safe = ($(if ($item -and $item.Id) { $item.Id } else { $kind.ToLower() }) -replace '[^\w\-]', '')
    $path = Join-Path $HelpDir ('ajuda-{0}-{1}.md' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $safe)
    [System.IO.File]::WriteAllLines($path, $L, (New-Object System.Text.UTF8Encoding($false)))
    return $path
}
function Show-AskDialog([string]$md, [string]$title) {
    $cli = Find-ClaudeCli
    $d = New-StyledWindow 'Perguntar a uma IA' 560
    $sp = New-Object System.Windows.Controls.StackPanel; $sp.Margin = '24,20,24,22'
    $sp.Children.Add((New-Text 'Perguntar a uma IA' 19 '#E6E9EF' 'SemiBold')) | Out-Null
    $dd = New-Text ('Gerei um arquivo com tudo sobre "' + $title + '": estado atual, valores do registro, o código que o botão usa, a segurança do PC e o registro de mudanças. Não tem senha nem e-mail.') 12.5 '#9AA3B2'; $dd.Margin = '0,6,0,6'
    $sp.Children.Add($dd) | Out-Null
    $p = New-Text $md 11 '#5F6878'; $p.Margin = '0,0,0,16'; $sp.Children.Add($p) | Out-Null
    $ai = $script:Config.AiChoice
    $opts = @()
    if ($cli) { $opts += , @('code', 'Abrir no Claude Code', 'Abre um terminal separado (sem poder de administrador) com o Claude Code, que lê o arquivo e investiga o problema. Ele pede permissão antes de mudar algo. O Claude Code exige plano pago do Claude.', $true, 'Accent') }
    if ($ai -and $AiList.Contains($ai)) { $opts += , @('web', ((T 'Abrir no {0} do navegador') -f $AiList[$ai].Name), ((T 'Copia o texto do arquivo e abre o site. Lá, é só colar com Ctrl+V e enviar.') + ' ' + (Get-AiPrivacy $ai)), $true, $(if ($cli) { 'Ghost' } else { 'Accent' })) }
    else { $opts += , @('setup', 'Integrar com uma IA', 'Escolha uma IA (Claude, ChatGPT, Gemini, Grok ou DeepSeek) para o Janus abrir com a pergunta pronta.', $true, 'Ghost') }
    $opts += , @('file', 'Só abrir o arquivo', 'Abre o .md no Bloco de Notas para você ler ou mandar para quem quiser.', $true, 'Ghost')
    foreach ($o in $opts) {
        $b = New-Object System.Windows.Controls.Button; $b.Style = $W.FindResource($o[4]); $b.HorizontalContentAlignment = 'Left'; $b.Margin = '0,0,0,8'; $b.Padding = '14,10'; $b.IsEnabled = $o[3]; $b.Tag = $o[0]
        $bs = New-Object System.Windows.Controls.StackPanel
        $bs.Children.Add((New-Text $o[1] 13.5 $(if ($o[4] -eq 'Accent') { 'White' } else { '#E6E9EF' }) 'SemiBold')) | Out-Null
        $bd = New-Text $o[2] 11.5 $(if ($o[4] -eq 'Accent') { '#DCE7FF' } else { '#9AA3B2' }); $bs.Children.Add($bd) | Out-Null
        $b.Content = $bs
        $b.add_Click({ $win = [System.Windows.Window]::GetWindow($this); $win.Tag = $this.Tag; $win.DialogResult = $true })
        $sp.Children.Add($b) | Out-Null
    }
    $bc = New-Button 'Cancelar' 'Ghost'; $bc.HorizontalAlignment = 'Right'; $bc.Margin = '0,6,0,0'
    $bc.add_Click({ [System.Windows.Window]::GetWindow($this).DialogResult = $false }); $sp.Children.Add($bc) | Out-Null
    $d.Content = $sp; $d.Tag = 'cancel'
    if ($Teste) { $d.Close(); return 'cancel' }
    [void]$d.ShowDialog()
    $r = [string]$d.Tag
    if ($r -eq 'setup') { if (Show-AiSetup) { $r = 'web' } else { $r = 'cancel' } }
    return $r
}
function Ask-Claude([string]$kind, $item, [string]$err = '') {
    $wasBusy = $script:Busy; $script:Busy = $true
    try {
        $title = $(if ($kind -eq 'Status') { $item.Name } elseif ($item -and $item.Title) { $item.Title } else { 'visão geral do PC' })
        $md = New-HelpMd $kind $item $err
        Write-Log ('Arquivo de ajuda gerado: ' + $md)
        $choice = Show-AskDialog $md $title
        switch ($choice) {
            'code' {
                $cli = Find-ClaudeCli
                $prompt = "Leia o arquivo de ajuda '$md'. Ele descreve um problema no Janus, um painel de ajustes do Windows deste PC. Explique o que está acontecendo e como resolver com segurança, em linguagem simples, no idioma: " + @{ pt = 'português do Brasil'; en = 'English'; zh = 'Simplified Chinese'; es = 'español' }[$script:Lang] + '. Não altere nada sem me perguntar antes.'
                # abre pelo Explorer: o Claude Code roda SEM o poder de administrador do Janus
                $cmdFile = Join-Path $HelpDir 'abrir-claude-code.cmd'
                $pr = $prompt -replace '"', "'" -replace '[&|<>^%]', ' '
                $lines = @('@echo off', 'chcp 65001 >nul', ('cd /d "{0}"' -f $HelpDir), 'title Claude Code - Janus', ('"{0}" "{1}"' -f $cli, $pr))
                [IO.File]::WriteAllLines($cmdFile, $lines, (New-Object Text.UTF8Encoding($false)))
                Start-Unelevated $cmdFile
                Write-Log ('Claude Code aberto para: ' + $title)
            }
            'web' {
                if (-not $AiList.Contains([string]$script:Config.AiChoice)) { [System.Windows.Clipboard]::SetText([System.IO.File]::ReadAllText($md)); return }
                Open-AiWithPrompt ([System.IO.File]::ReadAllText($md))
                Write-Log ('Ajuda copiada para o navegador: ' + $title)
            }
            'file' { Start-Process notepad.exe $md }
        }
    } catch {
        Write-Log ('ERRO no Perguntar ao Claude: ' + $_.Exception.Message)
        [System.Windows.MessageBox]::Show('Não consegui preparar a ajuda: ' + $_.Exception.Message, 'Perguntar ao Claude', 'OK', 'Error') | Out-Null
    } finally { $script:Busy = $wasBusy }
}
function New-HelpButton([string]$kind, $item) {
    $b = New-Object System.Windows.Controls.Button
    $b.Style = $W.FindResource('Ghost'); $b.Width = 26; $b.Height = 26; $b.Padding = '0'
    $b.Content = (New-Text '?' 13 '#AEB6C4' 'Bold'); $b.ToolTip = (T 'Perguntar ao Claude sobre isto')
    $b.Tag = @{ Kind = $kind; Item = $item }
    $b.add_Click({ Ask-Claude $this.Tag.Kind $this.Tag.Item })
    return $b
}

# ---------- tela de revisão (antes de aplicar vários) ----------
function Update-Preview($st) {
    $sel = @($st.Toggles | Where-Object { $_.IsChecked })
    $st.Ok.Content = (T $(if ($sel.Count -eq 1) { 'Aplicar 1 ajuste' } else { 'Aplicar {0} ajustes' -f $sel.Count }))
    $st.Ok.IsEnabled = ($sel.Count -gt 0)
    $need = @()
    if (@($sel | Where-Object { $_.Tag.Restart -eq 'pc' }).Count) { $need += 'reiniciar o PC' }
    if (@($sel | Where-Object { $_.Tag.Restart -eq 'explorer' }).Count) { $need += 'reiniciar o Explorer' }
    if (@($sel | Where-Object { $_.Tag.Restart -eq 'desligar' }).Count) { $need += 'desligar o PC uma vez' }
    $st.Info.Text = $(if ($need.Count) { (T 'Depois, para valer tudo:') + ' ' + (($need | ForEach-Object { T $_ }) -join ', ') + '.' } elseif ($sel.Count) { T 'Tudo vale na hora, sem reiniciar.' } else { T 'Nada selecionado.' })
}
function Show-ChangePreview($todo, $whyMap = $null, [string]$heading = '') {
    $dlg = New-StyledWindow 'Revisar antes de aplicar' 720; $dlg.MaxHeight = 800
    $root = New-Object System.Windows.Controls.DockPanel; $root.Margin = '26,22,26,22'; $root.LastChildFill = $true
    $head = New-Object System.Windows.Controls.StackPanel
    $head.Children.Add((New-Text $(if ($heading) { $heading } else { '{0} ajuste(s) para aplicar' -f $todo.Count }) 20 '#E6E9EF' 'SemiBold')) | Out-Null
    $hsub = New-Text 'Veja o que cada um faz e por quê. Desligue o botão de qualquer item que você não quiser. Antes de aplicar, crio um ponto de restauração e salvo um backup de cada chave.' 12.5 '#9AA3B2'
    $hsub.Margin = '0,6,0,16'; $head.Children.Add($hsub) | Out-Null
    [System.Windows.Controls.DockPanel]::SetDock($head, 'Top'); $root.Children.Add($head) | Out-Null
    $foot = New-Object System.Windows.Controls.Grid; $foot.Margin = '0,16,0,0'; Grid-Cols $foot @('*', 'Auto', 'Auto')
    $info = New-Text '' 12 '#A78BFA' 'SemiBold'; $info.VerticalAlignment = 'Center'; $info.Margin = '0,0,16,0'; Put $foot $info 0
    $bc = New-Button 'Cancelar' 'Ghost'; $bc.Margin = '0,0,8,0'; $bc.add_Click({ [System.Windows.Window]::GetWindow($this).DialogResult = $false }); Put $foot $bc 1
    $bo = New-Button '' 'Accent'; $bo.add_Click({ [System.Windows.Window]::GetWindow($this).DialogResult = $true }); Put $foot $bo 2
    [System.Windows.Controls.DockPanel]::SetDock($foot, 'Bottom'); $root.Children.Add($foot) | Out-Null
    $list = New-Object System.Windows.Controls.StackPanel
    $toggles = New-Object System.Collections.ArrayList
    foreach ($t in $todo) {
        $reason = $(if ($whyMap -and $whyMap[$t.Id]) { $whyMap[$t.Id] } else { $t.RecWhy })
        $card = New-Card; $card.Padding = '18,14,18,12'; $card.Margin = '0,0,0,10'
        $g = New-Object System.Windows.Controls.Grid; Grid-Cols $g @('Auto', '*', 'Auto')
        $ic = Glyph ([string]$t.Glyph) 22 '#60A5FA'; $ic.Margin = '0,2,16,0'; $ic.VerticalAlignment = 'Top'; Put $g $ic 0
        $sp = New-Object System.Windows.Controls.StackPanel; $sp.Margin = '0,0,18,0'
        $sp.Children.Add((New-Text $t.Title 14.5 '#E6E9EF' 'SemiBold')) | Out-Null
        $why = New-Text ('Por quê: ' + $reason + '. ' + $t.Desc) 12 '#9AA3B2'; $why.LineHeight = 17; $why.Margin = '0,5,0,0'; $sp.Children.Add($why) | Out-Null
        $cv = New-Text ('Não recomendado se ' + $t.Caveat) 11.5 '#6F7889'; $cv.Margin = '0,5,0,0'; $sp.Children.Add($cv) | Out-Null
        $wp = New-Object System.Windows.Controls.WrapPanel; $wp.Margin = '0,8,0,0'; Add-TweakBadges $wp $t -NoRec; $sp.Children.Add($wp) | Out-Null
        Put $g $sp 1
        $tg = New-Object System.Windows.Controls.Primitives.ToggleButton
        $tg.Style = $W.FindResource('Switch'); $tg.IsChecked = $true; $tg.Tag = $t; $tg.VerticalAlignment = 'Center'; $tg.ToolTip = (T 'Incluir este ajuste')
        $tg.add_Click({ Update-Preview ([System.Windows.Window]::GetWindow($this).Tag) })
        Put $g $tg 2
        $card.Child = $g
        $list.Children.Add($card) | Out-Null
        [void]$toggles.Add($tg)
    }
    $sv = New-Object System.Windows.Controls.ScrollViewer; $sv.VerticalScrollBarVisibility = 'Auto'; $sv.MaxHeight = 480; $sv.Content = $list
    $root.Children.Add($sv) | Out-Null
    $st = @{ Toggles = $toggles; Ok = $bo; Info = $info }
    $dlg.Tag = $st
    Update-Preview $st
    $dlg.Content = $root
    if ($Teste) { $dlg.Close(); return @($toggles | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag }) }
    $script:Busy = $true
    try { $res = $dlg.ShowDialog() } finally { $script:Busy = $false }
    if ($res -eq $true) { return @($toggles | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag }) }
    return @()
}
function Apply-Many($list, [bool]$on, [string]$label) {
    $script:Busy = $true
    try { $n = 0; foreach ($tw in $list) { if (Apply-Tweak $tw $on -Silent) { $n++ } } } finally { $script:Busy = $false }
    Write-Log ("{0}: {1} de {2} ajustes" -f $label, $n, $list.Count)
    if ($n -lt $list.Count) { Show-Toast ("{0} de {1} aplicados. Veja o Registro de mudanças." -f $n, $list.Count) } else { Show-Toast ("{0} ajuste(s) {1}" -f $n, $(if ($on) { 'ativados' } else { 'voltaram ao padrão' })) }
    Update-NavCounts
}


# ---------- páginas ----------
function Clear-Body { $ui.Body.Children.Clear() }
function Add-Body($el) { $ui.Body.Children.Add($el) | Out-Null }
function New-Hero([string]$title, [string]$text, $buttons, [string]$c1 = '#1C2A4A') {
    $hero = New-Card; $hero.Padding = '24,20,24,20'
    $hero.Background = New-Object System.Windows.Media.LinearGradientBrush (Col $c1), (Col '#171C26'), 0
    $hg = New-Object System.Windows.Controls.Grid; Grid-Cols $hg @('*', 'Auto')
    $hs = New-Object System.Windows.Controls.StackPanel; $hs.Margin = '0,0,24,0'
    $hs.Children.Add((New-Text $title 20 '#E6E9EF' 'SemiBold')) | Out-Null
    $sub = New-Text $text 12.5 '#AEB6C4'; $sub.Margin = '0,6,0,0'; $sub.LineHeight = 18; $hs.Children.Add($sub) | Out-Null
    Put $hg $hs 0
    $bs = New-Object System.Windows.Controls.StackPanel; $bs.Orientation = 'Horizontal'; $bs.VerticalAlignment = 'Center'
    foreach ($b in $buttons) { $b.Margin = '8,0,0,0'; $bs.Children.Add($b) | Out-Null }
    Put $hg $bs 1
    $hero.Child = $hg
    return $hero
}
function New-EmptyState([string]$glyph, [string]$title, [string]$text) {
    $c = New-Card; $c.Padding = '24,34,24,34'
    $sp = New-Object System.Windows.Controls.StackPanel; $sp.HorizontalAlignment = 'Center'
    $g = Glyph $glyph 34 '#22C55E'; $g.HorizontalAlignment = 'Center'; $sp.Children.Add($g) | Out-Null
    $t = New-Text $title 17 '#E6E9EF' 'SemiBold'; $t.HorizontalAlignment = 'Center'; $t.Margin = '0,12,0,0'; $sp.Children.Add($t) | Out-Null
    $x = New-Text $text 12.5 '#8B94A5'; $x.HorizontalAlignment = 'Center'; $x.TextAlignment = 'Center'; $x.Margin = '0,6,0,0'; $x.MaxWidth = 520; $sp.Children.Add($x) | Out-Null
    $c.Child = $sp
    return $c
}

function Build-Sugestoes {
    $pend = Get-PendingSuggestions
    $dismissedForever = @($script:Tweaks | Where-Object { $script:Config.Dismissed -contains $_.Id })
    if ($pend.Count) {
        $all = New-Button ('Aplicar todas ({0})' -f $pend.Count) 'Accent'
        $all.add_Click({
            $p = Get-PendingSuggestions; if (-not $p.Count) { return }
            $sel = @(Show-ChangePreview $p $null ('{0} sugestão(ões) para este PC' -f $p.Count))
            if (-not $sel.Count) { return }
            Apply-Many $sel $true 'Sugestões aplicadas'
            Show-Page 'Sugestoes'
        })
        Add-Body (New-Hero ('{0} sugestão(ões) para este PC' -f $pend.Count) 'Cada sugestão explica o que faz e por quê. Aplique uma por uma, todas de uma vez, ou descarte o que não quiser. Tudo pode ser desfeito na aba Mudanças aplicadas.' @($all))
        Add-Body (New-Section 'SUGESTÕES PENDENTES')
        foreach ($t in $pend) {
            $ap = New-QuickSwitch $t
            $ds = New-Button 'Descartar' 'Ghost' $t; $ds.Padding = '12,6'
            $ds.add_Click({
                $tw = $this.Tag
                $r = Show-Choice 'Descartar sugestão' $tw.Title 'Quer esconder esta sugestão só até fechar o Janus, ou para sempre? As descartadas para sempre podem ser trazidas de volta no fim desta aba.' @(@('forever', 'Para sempre', 'Danger'), @('session', 'Só até fechar o app', 'Ghost'), @('cancel', 'Cancelar', 'Ghost')) 'info'
                if ($r -eq 'forever') { $script:Config.Dismissed = @($script:Config.Dismissed + $tw.Id | Select-Object -Unique); Save-Config; Write-Log ('Sugestão descartada para sempre: ' + $tw.Title) }
                elseif ($r -eq 'session') { [void]$script:DismissedSession.Add($tw.Id); Write-Log ('Sugestão descartada até fechar o app: ' + $tw.Title) }
                else { return }
                Update-NavCounts; Show-Page 'Sugestoes' $ui.Scroll.VerticalOffset
            })
            Add-Body (New-WideCard $t ('Por quê: ' + $t.RecWhy + '. ' + $t.Desc) @($ds, $ap))
        }
    } else {
        Add-Body (New-EmptyState ([string][char]0xE73E) 'Tudo em dia' 'Não há sugestões pendentes para este PC. Quando algo mudar, por exemplo um ajuste desfeito ou um adaptador novo, a sugestão volta a aparecer aqui.')
    }
    if ($dismissedForever.Count -or $script:DismissedSession.Count) {
        Add-Body (New-Section 'DESCARTADAS')
        $names = @($script:Tweaks | Where-Object { Is-Dismissed $_ } | ForEach-Object { $_.Title })
        $c = New-Card; $g = New-Object System.Windows.Controls.Grid; Grid-Cols $g @('*', 'Auto')
        $tx = New-Text ('Escondidas: ' + ($names -join ', ')) 12.5 '#8B94A5'; $tx.Margin = '0,0,16,0'; Put $g $tx 0
        $rb = New-Button 'Mostrar de novo' 'Ghost'
        $rb.add_Click({ $script:Config.Dismissed = @(); Save-Config; $script:DismissedSession.Clear(); Write-Log 'Sugestões descartadas trazidas de volta.'; Update-NavCounts; Show-Page 'Sugestoes' })
        Put $g $rb 1; $c.Child = $g; Add-Body $c
    }
}

function Build-Ativos {
    $act = Get-ActiveTweaks
    if ($act.Count) {
        $all = New-Button ('Desfazer todos ({0})' -f $act.Count) 'Danger'
        $all.add_Click({
            $a = Get-ActiveTweaks; if (-not $a.Count) { return }
            $list = ($a | ForEach-Object { '• ' + (T $_.Title) }) -join "`n"
            $r = Show-Choice 'Desfazer todos os ajustes' 'Voltar tudo ao padrão do Windows?' ("Estes ajustes vão voltar ao padrão:`n`n$list`n`nAntes, crio um ponto de restauração e salvo um backup de cada chave.") @(@('yes', 'Desfazer todos', 'Danger'), @('no', 'Cancelar', 'Ghost')) 'warn'
            if ($r -ne 'yes') { return }
            Apply-Many $a $false 'Desfazer todos'
            Show-Page 'Ativos'
        })
        Add-Body (New-Hero ('{0} ajuste(s) valendo agora' -f $act.Count) 'Tudo o que foi mudado neste PC e continua ativo, lido direto do Windows. Desfazer volta aquele item ao padrão.' @($all) '#163A2C')
        Add-Body (New-Section 'ATIVOS AGORA')
        foreach ($t in $act) {
            $ud = New-QuickSwitch $t
            Add-Body (New-WideCard $t $t.Desc @($ud) '#22C55E')
        }
    } else {
        Add-Body (New-EmptyState ([string][char]0xE73E) 'Nada mudado' 'Todos os ajustes estão no padrão do Windows. Os que você ativar aparecem aqui, prontos para desfazer.')
    }
}

function Build-Automacao {
    $pc = Get-PcInfo
    $plan = @(); $why = @{}
    foreach ($t in $script:Tweaks) {
        if (-not $t.Auto) { continue }
        $r = & $t.Auto $pc
        $st = Get-State $t
        $avail = Is-Available $t
        $status = $(if (-not $avail) { 'indisp' } elseif ($r.Apply -and $st) { 'feito' } elseif ($r.Apply) { 'aplicar' } else { 'nao' })
        $plan += @{ T = $t; Apply = $r.Apply; Why = $r.Why; Status = $status }
        $why[$t.Id] = $r.Why
    }
    $todo = @($plan | Where-Object { $_.Status -eq 'aplicar' } | ForEach-Object { $_.T })
    $btn = New-Button $(if ($todo.Count) { 'Aplicar ajustes automáticos ({0})' -f $todo.Count } else { 'Nada a aplicar' }) 'Accent'
    $btn.IsEnabled = ($todo.Count -gt 0)
    $btn.Tag = @{ Todo = $todo; Why = $why }
    $btn.add_Click({
        $sel = @(Show-ChangePreview $this.Tag.Todo $this.Tag.Why 'Ajustes automáticos para este PC')
        if (-not $sel.Count) { return }
        Apply-Many $sel $true 'Automação'
        Show-Page 'Automacao'
    })
    $done = @($plan | Where-Object { $_.Status -eq 'feito' }).Count
    Add-Body (New-Hero 'Leitura automática do PC' ("Li o hardware e as conexões deste PC e decidi, para cada ajuste, se vale a pena e por quê. {0} já estão aplicados, {1} faltam. Ajustes de gosto pessoal nunca são aplicados sozinhos." -f $done, $todo.Count) @($btn) '#2A1F4A')

    Add-Body (New-Section 'ESTE PC')
    $ug = New-Object System.Windows.Controls.Primitives.UniformGrid; $ug.Columns = 3
    $links = @{ 'Windows' = 'ms-settings:about'; 'Processador' = 'taskmgr'; 'Placa de vídeo' = 'ms-settings:display-advancedgraphics'; 'Tela' = 'ms-settings:display'; 'Monitor' = 'ms-settings:display-advanced'; 'Memória' = 'taskmgr'; 'Disco' = 'ms-settings:storagesense'; 'Rede ativa' = 'janus:Rede'; 'Plano de energia' = 'ms-settings:powersleep' }
    $cpuShort = ($pc.Cpu -replace '\s*\d+-Core Processor', '' -replace '\(R\)|\(TM\)', '')
    foreach ($row in @(@([char]0xE7F8, 'Tipo', $pc.Tipo), @([char]0xE7C3, 'Windows', $pc.Windows), @([char]0xE950, 'Processador', $cpuShort), @([char]0xE7F4, 'Placa de vídeo', $pc.Gpu), @([char]0xE7F4, 'Tela', $pc.Tela), @([char]0xE7F7, 'Monitor', $pc.Monitor), @([char]0xE964, 'Memória', $pc.Ram), @([char]0xEDA2, 'Disco', $pc.Disco), @([char]0xE701, 'Rede ativa', $pc.Rede), @([char]0xE945, 'Plano de energia', $pc.Energia))) {
        $c = New-Card; $c.Padding = '14,10,14,10'
        $sp = New-Object System.Windows.Controls.StackPanel
        $hr = New-Object System.Windows.Controls.Grid; Grid-Cols $hr @('Auto', '*', 'Auto')
        $gi = Glyph ([string]$row[0]) 14 '#8EA3C8'; $gi.Margin = '0,0,8,0'; $gi.VerticalAlignment = 'Center'; Put $hr $gi 0
        Put $hr (New-Text $row[1] 11.5 '#7F8899' 'SemiBold') 1
        $lk = $links[$row[1]]
        if ($lk) { $go = Glyph ([string][char]0xE8A7) 12 '#5F6878'; $go.VerticalAlignment = 'Center'; Put $hr $go 2 }
        $sp.Children.Add($hr) | Out-Null
        # valor principal curto + detalhes menores
        $parts = @(([string]$row[2]) -split '\s\|\s|;\s' | Where-Object { $_ })
        $v = New-Text $(if ($parts.Count) { $parts[0] } else { '-' }) 12.8 '#E6E9EF' 'SemiBold'; $v.Margin = '0,5,0,0'; $sp.Children.Add($v) | Out-Null
        if ($parts.Count -gt 1) { $sp.Children.Add((New-Text (($parts | Select-Object -Skip 1) -join '  |  ') 11.5 '#7F8899')) | Out-Null }
        $c.Child = $sp
        if ($lk) {
            $c.Cursor = [System.Windows.Input.Cursors]::Hand; $c.Tag = $lk
            $c.ToolTip = (T $(if ($lk -like 'janus:*') { 'Abrir a aba de rede do Janus' } elseif ($lk -eq 'taskmgr') { 'Abrir o Gerenciador de Tarefas' } else { 'Abrir nas Configurações do Windows' }))
            $c.add_MouseLeftButtonUp({ $l = [string]$this.Tag; if ($l -like 'janus:*') { Show-Page ($l -replace '^janus:', '') } elseif ($l -eq 'taskmgr') { Start-Process taskmgr.exe } else { Open-Url $l } })
        }
        $ug.Children.Add($c) | Out-Null
    }
    Add-Body $ug
    Add-Body (New-Section 'O QUE A LEITURA DECIDIU')
    $map = @{ aplicar = @('Vou aplicar', '#60A5FA', [char]0xE896); feito = @('Já aplicado', '#22C55E', [char]0xE73E); nao = @('Não precisa', '#8B94A5', [char]0xE711); indisp = @('Indisponível', '#F59E0B', [char]0xE7BA) }
    foreach ($p in $plan) {
        $m = $map[$p.Status]
        $c = New-Card; $c.Padding = '16,11,16,11'; $c.Margin = '0,0,12,8'
        $g = New-Object System.Windows.Controls.Grid; Grid-Cols $g @('Auto', '*', 'Auto', 'Auto')
        $gi = Glyph ([string]$p.T.Glyph) 18 '#8EA3C8'; $gi.Margin = '0,1,14,0'; $gi.VerticalAlignment = 'Top'; Put $g $gi 0
        $sw = New-QuickSwitch $p.T; $sw.Margin = '12,0,0,0'
        $go = New-Button 'Ir para o ajuste' 'Ghost' $p.T; $go.Padding = '10,4'; $go.FontSize = 11.5; $go.Margin = '10,0,0,0'; $go.VerticalAlignment = 'Center'; $go.add_Click({ Focus-Tweak $this.Tag })
        $rt = New-Object System.Windows.Controls.StackPanel; $rt.Orientation = 'Horizontal'; $rt.VerticalAlignment = 'Center'; $rt.Children.Add($go) | Out-Null; $rt.Children.Add($sw) | Out-Null
        Put $g $rt 3
        $sp = New-Object System.Windows.Controls.StackPanel; $sp.Margin = '0,0,16,0'
        $sp.Children.Add((New-Text $p.T.Title 13.5 '#E6E9EF' 'SemiBold')) | Out-Null
        $wy = New-Text ('Motivo: ' + $p.Why) 12 '#8B94A5'; $wy.Margin = '0,2,0,0'; $sp.Children.Add($wy) | Out-Null
        Put $g $sp 1
        $bd = New-Badge $m[0] $m[1]; $bd.VerticalAlignment = 'Center'; Put $g $bd 2
        $c.Child = $g; Add-Body $c
    }
}

# selo da edição especial, com as cores do arco-íris passando (RGB) e brilho que troca de cor
function New-EditionBanner {
    $cols = @('#FF0040', '#FF8000', '#FFE000', '#00FF6A', '#00C8FF', '#4060FF', '#C040FF', '#FF0040')
    $lg = New-Object System.Windows.Media.LinearGradientBrush; $lg.StartPoint = '0,0.5'; $lg.EndPoint = '1,0.5'; $lg.SpreadMethod = 'Repeat'
    for ($i = 0; $i -lt $cols.Count; $i++) { $lg.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.ColorConverter]::ConvertFromString($cols[$i])), ($i / ($cols.Count - 1)))) }
    $tt = New-Object System.Windows.Media.TranslateTransform; $lg.RelativeTransform = $tt
    $an = New-Object System.Windows.Media.Animation.DoubleAnimation 0, 1, (New-Object System.Windows.Duration ([TimeSpan]::FromSeconds(3))); $an.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $an)
    $bd = New-Object System.Windows.Controls.Border; $bd.CornerRadius = 14; $bd.Padding = '22,14,22,14'; $bd.Margin = '0,0,12,14'; $bd.Background = Brush '#121620'; $bd.BorderThickness = 2; $bd.BorderBrush = $lg
    $fx = New-Object System.Windows.Media.Effects.DropShadowEffect; $fx.ShadowDepth = 0; $fx.BlurRadius = 22; $fx.Opacity = 0.85
    $ca = New-Object System.Windows.Media.Animation.ColorAnimationUsingKeyFrames; $ca.Duration = New-Object System.Windows.Duration ([TimeSpan]::FromSeconds(4)); $ca.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    for ($i = 0; $i -lt $cols.Count; $i++) { [void]$ca.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearColorKeyFrame ([System.Windows.Media.ColorConverter]::ConvertFromString($cols[$i])), ([System.Windows.Media.Animation.KeyTime]::FromPercent($i / ($cols.Count - 1))))) }
    $fx.BeginAnimation([System.Windows.Media.Effects.DropShadowEffect]::ColorProperty, $ca)
    $bd.Effect = $fx
    $sp = New-Object System.Windows.Controls.StackPanel; $sp.HorizontalAlignment = 'Center'
    $t1 = New-Object System.Windows.Controls.TextBlock; $t1.Text = ([string]$Edition.Selo).ToUpper(); $t1.FontSize = 26; $t1.FontWeight = 'Black'; $t1.Foreground = $lg; $t1.HorizontalAlignment = 'Center'
    $sp.Children.Add($t1) | Out-Null
    $sub = $(if ($Edition.SubSelo) { [string]$Edition.SubSelo } else { 'VIP beta tester' })
    $t2 = New-Object System.Windows.Controls.TextBlock; $t2.Text = ($sub + '  ·  ' + $AppName + ' ' + (Format-Version $AppVersion)); $t2.FontSize = 12; $t2.Foreground = Brush '#9AA3B2'; $t2.HorizontalAlignment = 'Center'; $t2.Margin = '0,4,0,0'
    $sp.Children.Add($t2) | Out-Null
    $bd.Child = $sp
    return $bd
}
function Build-Inicio {
    if ($Edition.Selo) { Add-Body (New-EditionBanner) }
    Add-SecOffBanner
    $avail = @($script:Tweaks | Where-Object { Is-Available $_ })
    $active = Get-ActiveTweaks
    $pend = Get-PendingSuggestions
    # botões só aparecem quando há algo para ver
    $btns = @()
    if ($active.Count) { $b2 = New-Button ('Ver mudanças ({0})' -f $active.Count) 'Ghost'; $b2.add_Click({ Show-Page 'Ativos' }); $btns += $b2 }
    if ($pend.Count) { $b1 = New-Button ('Ver sugestões ({0})' -f $pend.Count) 'Accent'; $b1.add_Click({ Show-Page 'Sugestoes' }); $btns += $b1 }
    $txt = $(if ($pend.Count) { (T ("{0} sugestão(ões) para este PC ainda estão pendentes." -f $pend.Count)) + ' ' } else { '' }) + (T 'Todo ajuste pode ser desfeito, e tudo fica no Registro de mudanças.')
    Add-Body (New-Hero ("{0} de {1} ajustes ativos" -f $active.Count, $avail.Count) $txt $btns)
    Add-MonSection

    Add-Body (New-Section 'AUTENTICIDADE E ATUALIZAÇÃO')
    Add-Body (New-AuthCard)

    $sec = Get-SecurityStatus
    $nCrit = @($sec | Where-Object { $_.Level -eq 'crit' }).Count; $nWarn = @($sec | Where-Object { $_.Level -eq 'warn' }).Count
    $hdr = New-Object System.Windows.Controls.Grid; Grid-Cols $hdr @('*', 'Auto'); $hdr.Margin = '0,4,12,0'
    Put $hdr (New-Section 'SEGURANÇA AGORA') 0
    $lg = New-Object System.Windows.Controls.StackPanel; $lg.Orientation = 'Horizontal'; $lg.VerticalAlignment = 'Center'
    foreach ($lv in 'ok', 'warn', 'crit') { $s = $LevelStyle[$lv]; $gi = Glyph ([string]$s[0]) 12 $s[1]; $gi.Margin = '12,0,5,0'; $gi.VerticalAlignment = 'Center'; $lg.Children.Add($gi) | Out-Null; $lt = New-Text $s[2] 11.5 '#8B94A5'; $lt.TextWrapping = 'NoWrap'; $lg.Children.Add($lt) | Out-Null }
    Put $hdr $lg 1
    Add-Body $hdr
    if ($nCrit -or $nWarn) {
        $alert = New-Card; $alert.Padding = '16,12,16,12'
        $alert.BorderBrush = Brush $(if ($nCrit) { '#7F1D1D' } else { '#78350F' })
        $alert.Background = Brush $(if ($nCrit) { '#2A1416' } else { '#2A2112' })
        $alert.Child = (New-Text $(if ($nCrit) { "{0} item(ns) urgente(s) e {1} de atenção. Clique no ? do item para entender o que fazer." -f $nCrit, $nWarn } else { "{0} item(ns) pedem atenção. Nada urgente." -f $nWarn }) 12.8 $(if ($nCrit) { '#FCA5A5' } else { '#FCD38D' }) 'SemiBold')
        Add-Body $alert
    }
    $ug = New-Object System.Windows.Controls.Primitives.UniformGrid; $ug.Columns = 3
    foreach ($s in $sec) {
        $st = $LevelStyle[$s.Level]
        $c = New-Card; $c.Padding = '16,14,16,14'
        if ($s.Level -eq 'crit') { $c.BorderBrush = Brush '#7F1D1D' } elseif ($s.Level -eq 'warn') { $c.BorderBrush = Brush '#78350F' }
        $sp = New-Object System.Windows.Controls.StackPanel
        $row = New-Object System.Windows.Controls.Grid; Grid-Cols $row @('Auto', '*', 'Auto')
        $gi = Glyph ([string]$st[0]) 14 $st[1]; $gi.Margin = '0,0,8,0'; $gi.VerticalAlignment = 'Center'; $gi.ToolTip = (Get-LevelHint $s.Level); $c.ToolTip = (Get-LevelHint $s.Level); Put $row $gi 0
        $nm = New-Text $s.Name 12 '#8B94A5'; $nm.TextWrapping = 'NoWrap'; $nm.VerticalAlignment = 'Center'; Put $row $nm 1
        if ($s.Level -ne 'ok') { $hb = New-HelpButton 'Status' $s; $hb.Width = 22; $hb.Height = 22; Put $row $hb 2 }
        $sp.Children.Add($row) | Out-Null
        $v = New-Text $s.Value 16 $(if ($s.Level -eq 'crit') { '#FCA5A5' } elseif ($s.Level -eq 'warn') { '#FCD38D' } else { '#E6E9EF' }) 'SemiBold'; $v.Margin = '22,6,0,0'
        $sp.Children.Add($v) | Out-Null
        $c.Child = $sp; $ug.Children.Add($c) | Out-Null
    }
    Add-Body $ug
}

function Build-Page([string]$page) {
    $list = @($script:Tweaks | Where-Object { $_.Page -eq $page })
    if ($list.Count) {
        Add-Body (New-Section 'AJUSTES')
        $ug = New-Object System.Windows.Controls.Primitives.UniformGrid; $ug.Columns = $(if ($list.Count -ge 3) { 3 } else { 2 })
        foreach ($t in $list) { $ug.Children.Add((New-TweakCard $t)) | Out-Null }
        Add-Body $ug
    }
    $checks = @($script:Checks | Where-Object { $_.Page -eq $page })
    if ($checks.Count) {
        Add-Body (New-Section 'VERIFICAÇÕES')
        foreach ($c in $checks) { Add-Body (New-CheckCard $c) }
    }
    if ($page -eq 'Seguranca') { $n = New-Text 'Secure Boot e TPM só mudam na BIOS, por isso aparecem apenas na Visão geral.' 12 '#5F6878'; $n.Margin = '2,6,0,0'; Add-Body $n }
}

# Botões de ação com o logo do Janus: seta verde = fazer, seta âmbar = desfazer, logo completo = ver/abrir, cinza = indisponível.
# Todos do mesmo tamanho (a tela fica simétrica); o nome da ação aparece ao passar o mouse.
$script:ActionIcons = @{}
$ActionKinds = @{ do = @('Fazer', '#22C55E'); undo = @('Desfazer', '#F59E0B'); info = @('Ver ou abrir', '#818CF8'); off = @('Indisponível no momento', '#8B94A5') }
function Get-ActionIcon([string]$kind) {
    if (-not $script:ActionIcons.ContainsKey($kind)) { $script:ActionIcons[$kind] = New-PngImage 64 $(if ($kind -eq 'info') { 'app' } else { $kind }) }
    return $script:ActionIcons[$kind]
}
# Botão de ação com texto: "do" em destaque (azul), "undo"/"info" discreto, "off" desabilitado.
# Ligar/desligar um ajuste NÃO usa botão: usa o interruptor de setas (New-QuickSwitch).
function New-ActionButton([string]$text, [string]$kind, $tag) {
    $b = New-Object System.Windows.Controls.Button
    $b.Style = $W.FindResource($(if ($kind -eq 'do') { 'Accent' } else { 'Ghost' })); $b.MinWidth = 120; $b.Height = 34; $b.Padding = '14,0'; $b.Tag = $tag; $b.VerticalAlignment = 'Center'
    $b.Content = (T $text)
    [System.Windows.Automation.AutomationProperties]::SetName($b, (T $text))
    if ($kind -eq 'off') { $b.IsEnabled = $false }
    return $b
}
# Interruptor de setas para ligar/desligar um ajuste direto de qualquer lista (Sugestões, Mudanças aplicadas, Automação)
function New-QuickSwitch($t) {
    $tg = New-Object System.Windows.Controls.Primitives.ToggleButton
    $tg.Style = $W.FindResource('Switch'); $tg.VerticalAlignment = 'Center'; $tg.Tag = $t
    $st = Get-State $t
    $tg.IsChecked = ($st -eq $true)
    if (-not (Is-Available $t)) { $tg.IsEnabled = $false; $tg.ToolTip = (T $t.UnavailableWhy); [System.Windows.Controls.ToolTipService]::SetShowOnDisabled($tg, $true); return $tg }
    $tg.ToolTip = (T $(if ($st) { 'Ativado. Clique para desativar e voltar ao padrão do Windows.' } else { 'Desativado (padrão do Windows). Clique para ativar.' }))
    [System.Windows.Controls.ToolTipService]::SetInitialShowDelay($tg, 150)
    $tg.add_Click({
        $tw = $this.Tag; $want = [bool]$this.IsChecked
        $script:Busy = $true; try { $ok = Apply-Tweak $tw $want } finally { $script:Busy = $false }
        if ($ok) { Show-Toast ($tw.Title + ': ' + $(if ($want) { 'ativado' } else { 'desativado (padrão do Windows)' })) } else { $this.IsChecked = -not $want }
        Update-NavCounts
        # espera a seta terminar de deslizar antes de remontar a lista
        $script:QsPage = $script:CurrentPage
        $tm = New-Object System.Windows.Threading.DispatcherTimer; $tm.Interval = [TimeSpan]::FromMilliseconds(380)
        $tm.add_Tick({ $this.Stop(); if (-not $script:Busy) { Show-Page $script:QsPage $ui.Scroll.VerticalOffset } }); $tm.Start()
    })
    return $tg
}
function New-StateIcon($state, [string]$tip = '') {
    $kind = $(if ($null -eq $state) { 'off' } elseif ($state) { 'do' } else { 'undo' })
    $img = New-Object System.Windows.Controls.Image; $img.Width = 22; $img.Height = 22
    try { $img.Source = (Get-ActionIcon $kind) } catch {}
    if (-not $tip) { $tip = T $(if ($null -eq $state) { 'Indisponível neste PC' } elseif ($state) { 'Ativado agora' } else { 'Desativado agora (padrão do Windows)' }) }
    $img.ToolTip = $tip; [System.Windows.Controls.ToolTipService]::SetInitialShowDelay($img, 120)
    return $img
}function New-ActionLegend {
    $row = New-Object System.Windows.Controls.WrapPanel; $row.Margin = '2,0,0,12'
    foreach ($k in 'do', 'undo', 'info', 'off') {
        $img = New-Object System.Windows.Controls.Image; $img.Width = 18; $img.Height = 18; $img.Margin = '0,0,6,0'; try { $img.Source = (Get-ActionIcon $k) } catch {}
        $row.Children.Add($img) | Out-Null
        $tx = New-Text $ActionKinds[$k][0] 11.5 '#8B94A5'; $tx.Margin = '0,1,18,0'; $tx.TextWrapping = 'NoWrap'; $row.Children.Add($tx) | Out-Null
    }
    return $row
}
function New-ActionCard([string]$glyph, [string]$title, [string]$desc, [string]$btnText, [scriptblock]$action, [string]$kind = 'do') {
    $card = New-Card; $card.Padding = '20,12,14,12'
    $g = New-Object System.Windows.Controls.Grid; Grid-Cols $g @('Auto', '*', 'Auto')
    $ic = Glyph $glyph 22 '#60A5FA'; $ic.Margin = '0,2,18,0'; $ic.VerticalAlignment = 'Top'; Put $g $ic 0
    $sp = New-Object System.Windows.Controls.StackPanel; $sp.Margin = '0,0,20,0'; $sp.VerticalAlignment = 'Center'
    $sp.Children.Add((New-Text $title 15 '#E6E9EF' 'SemiBold')) | Out-Null
    $d = New-Text $desc 12.5 '#9AA3B2'; $d.Margin = '0,4,0,0'; $sp.Children.Add($d) | Out-Null
    Put $g $sp 1
    $b = New-ActionButton $btnText $kind $action
    $b.add_Click({ $W.Cursor = [System.Windows.Input.Cursors]::Wait; try { & $this.Tag } catch { [System.Windows.MessageBox]::Show($_.Exception.Message, 'Erro', 'OK', 'Error') | Out-Null } finally { $W.Cursor = $null } })
    $b.MinWidth = 140
    Put $g $b 2
    $card.Child = $g
    return $card
}
function Restart-Janus {
    # abre uma cópia nova e fecha esta de forma limpa (o "lock" desta sessão não vira aviso de travamento)
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', "`"$PSCommandPath`"")
    if ($script:CurrentPage) { $a += @('-Pagina', $script:CurrentPage) }
    if ($script:DismissedSession.Count) { $a += @('-Descartadas', ($script:DismissedSession -join ',')) }
    Start-Process powershell.exe -ArgumentList $a
    $script:CleanExit = $true; $W.Close()
}
function Restart-Explorer {
    Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 800
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
    $script:Pending.explorer.Clear(); Update-Pending
    Write-Log 'Explorer reiniciado.'
}
function Set-LightMode([bool]$on) {
    $script:Config.LightMode = $on; Save-Config
    Write-Log $(if ($on) { 'Modo leve ligado: leituras a cada 30 s / 5 min, pausadas fora de foco.' } else { 'Modo completo ligado: leituras a cada 5 s / 1 min, sempre.' })
    Show-Toast $(if ($on) { 'Modo leve ligado: o Janus gasta menos do PC' } else { 'Modo completo ligado: tudo em tempo real' })
    Update-UpdatedText
}
function Build-Manutencao {
    Add-Body (New-ActionCard ([char]0xE81C) 'Criar ponto de restauração' 'Salva o estado atual do Windows para voltar depois, se algo der errado. O Windows limita a um por dia.' 'Criar agora' {
        try { Checkpoint-Computer -Description 'Janus (manual)' -RestorePointType MODIFY_SETTINGS -WarningAction SilentlyContinue -WarningVariable avisoRp
              if ($avisoRp) { Write-Log ('Ponto manual: ' + ($avisoRp -join ' ')); Show-Choice 'Ponto de restauração' 'O Windows não criou agora' ($avisoRp -join ' ') @(@('ok', 'Ok', 'Accent')) 'info' | Out-Null } else { Write-Log 'Ponto de restauração manual criado.'; Show-Toast 'Ponto de restauração criado' } }
        catch { Write-Log ('Ponto manual falhou: ' + $_.Exception.Message); throw } })
    Add-Body (New-ActionCard ([char]0xEA18) 'Verificação rápida do Defender' 'Roda em segundo plano. O resultado aparece na Segurança do Windows e na Visão geral.' 'Verificar' {
        Start-Process powershell.exe -WindowStyle Hidden -ArgumentList '-NoProfile', '-Command', 'Start-MpScan -ScanType QuickScan'
        Write-Log 'Verificação rápida do Defender iniciada.'; Show-Toast 'Verificação iniciada em segundo plano' })
    Add-Body (New-ActionCard ([char]0xE74D) 'Limpar arquivos temporários' 'Apaga arquivos com mais de 2 dias nas pastas temporárias do usuário e do Windows. Arquivos em uso são ignorados.' 'Limpar' {
        $r = Show-Choice 'Limpar temporários' 'Apagar arquivos temporários?' 'Só arquivos com mais de 2 dias nas pastas temporárias. Não há como desfazer, mas são arquivos descartáveis.' @(@('yes', 'Limpar', 'Accent'), @('no', 'Cancelar', 'Ghost')) 'info'
        if ($r -ne 'yes') { return }
        $lim = (Get-Date).AddDays(-2); $n = 0; $bytes = 0
        foreach ($dir in @($env:TEMP, (Join-Path $env:windir 'Temp'))) {
            Get-ChildItem -LiteralPath $dir -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $lim } | ForEach-Object {
                $len = $_.Length; try { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop; $n++; $bytes += $len } catch {} }
        }
        $mb = [math]::Round($bytes / 1MB, 1)
        Write-Log ("Temporários: {0} arquivo(s) apagados, {1} MB" -f $n, $mb); Show-Toast ("{0} arquivos apagados ({1} MB)" -f $n, $mb) })
    Add-Body (New-ActionCard ([char]0xE9CE) 'Perguntar a uma IA sobre o PC' 'Monta um arquivo com o estado de todos os ajustes, verificações e segurança, e abre na IA que você escolheu.' 'Perguntar' { Ask-Claude 'Geral' $null } 'info')
    Add-Body (New-ActionCard ([char]0xE72C) 'Reiniciar o Explorer' 'Recarrega a área de trabalho e a barra de tarefas. Aplica mudanças de interface sem reiniciar o PC.' 'Reiniciar' { Restart-Explorer; Show-Toast 'Explorer reiniciado' })
    $n = New-Text 'Idioma, tema, visualização, IA, monitoramento, atualizações e o modo leve ficam na engrenagem, no canto de cima.' 12 '#6F7889'; $n.Margin = '2,6,0,0'; Add-Body $n
}
function Open-Url([string]$url) {
    # abre pelo Explorer: assim o navegador NÃO herda o modo administrador do Janus
    try { Start-Process explorer.exe "`"$url`"" } catch { Start-Process $url }
}
function New-LinkButton([string]$text, [string]$url) {
    $b = New-Button $text 'Ghost' $url; $b.Padding = '10,5'; $b.FontSize = 12; $b.Margin = '0,10,8,0'; $b.HorizontalAlignment = 'Left'
    $b.ToolTip = $url; $b.add_Click({ Open-Url $this.Tag }); return $b
}
function Build-Sobre {
    $hero = New-Card; $hero.Padding = '26,24,26,24'
    $hero.Background = New-Object System.Windows.Media.LinearGradientBrush (Col '#23245A'), (Col '#103A3A'), 0
    $hg = New-Object System.Windows.Controls.Grid; Grid-Cols $hg @('Auto', '*')
    $img = New-Object System.Windows.Controls.Image; $img.Width = 72; $img.Height = 72; $img.VerticalAlignment = 'Top'; try { $img.Source = (New-PngImage 144) } catch {}
    Put $hg $img 0
    $hs = New-Object System.Windows.Controls.StackPanel; $hs.Margin = '20,0,0,0'; $hs.VerticalAlignment = 'Center'
    $hs.Children.Add((New-Text 'Janus' 26 '#FFFFFF' 'SemiBold')) | Out-Null
    $hs.Children.Add((New-Text ('Versão: {0}' -f (Format-Version $AppVersion)) 12.5 '#AEB6C4')) | Out-Null
    $hs.Children.Add((New-Text $(if ($Instalado) { 'Instalado' } else { 'Versão portátil' }) 12 '#7F8899')) | Out-Null
    $tg = New-Text 'O Janus é um programa feito para otimização e jogos, mas vai além: acompanha a saúde e a segurança do PC e ajuda você a aplicar e desfazer as configurações que julgar necessárias.' 13 '#D6DCE8'; $tg.Margin = '0,10,0,0'; $tg.LineHeight = 19
    $hs.Children.Add($tg) | Out-Null
    Put $hg $hs 1; $hero.Child = $hg; Add-Body $hero

    Add-Body (New-Section 'CRÉDITOS')
    $ug = New-Object System.Windows.Controls.Primitives.UniformGrid; $ug.Columns = 2
    foreach ($c in @(
        @([char]0xE77B, 'IDEIA E PEDIDO', 'iAlencari', 'Criador da ideia: imaginou o Janus, testou cada versão e decidiu cada recurso.', '#818CF8', 'GitHub', "https://github.com/$RepoOwner"),
        @([char]0xE99A, 'CRIADO COM', 'Claude Code', 'Escrito com o Claude Opus 5.5 e revisado com o Claude Fable 5.2, da Anthropic.', '#A78BFA', 'claude.ai/code', 'https://claude.ai/code')
    )) {
        $cd = New-Card; $cd.Padding = '18,16,18,14'
        $sp = New-Object System.Windows.Controls.StackPanel
        $hr = New-Object System.Windows.Controls.StackPanel; $hr.Orientation = 'Horizontal'
        $gi = Glyph ([string]$c[0]) 16 $c[4]; $gi.Margin = '0,0,8,0'; $gi.VerticalAlignment = 'Center'; $hr.Children.Add($gi) | Out-Null
        $hr.Children.Add((New-Text $c[1] 11 '#7F8899' 'SemiBold')) | Out-Null
        $sp.Children.Add($hr) | Out-Null
        $nm = New-Text $c[2] 17 '#E6E9EF' 'SemiBold'; $nm.Margin = '0,8,0,0'; $sp.Children.Add($nm) | Out-Null
        $ds = New-Text $c[3] 12 '#9AA3B2'; $ds.Margin = '0,6,0,0'; $ds.LineHeight = 17; $sp.Children.Add($ds) | Out-Null
        $sp.Children.Add((New-LinkButton $c[5] $c[6])) | Out-Null
        $cd.Child = $sp; $ug.Children.Add($cd) | Out-Null
    }
    Add-Body $ug

    Add-Body (New-Section 'COMO ELE FUNCIONA')
    $cw = New-Card; $sp = New-Object System.Windows.Controls.StackPanel
    foreach ($pair in @(
        @([char]0xE73E, 'Cada botão mostra o estado real, lido do registro, do plano de energia ou do dispositivo. Ligado = ajuste aplicado, desligado = padrão do Windows.'),
        @([char]0xE81C, 'Antes de mudar algo: ponto de restauração (1 por dia, limite do Windows) e backup .reg de cada chave.'),
        @([char]0xE895, 'As leituras rodam numa thread separada: a janela não trava esperando o Windows. O modo leve, na engrenagem, espaça essas leituras.'),
        @([char]0xEA18, 'Antivírus, firewall, UAC e integridade de memória ficam ligados. O Janus só desliga o firewall ou a integridade de memória se você pedir, com avisos e lembretes.'),
        @([char]0xE8D7, 'Cada versão publicada é assinada digitalmente. O Janus confere a assinatura e os próprios arquivos e mostra o selo na Visão geral.'),
        @([char]0xE9CE, 'O botão ? monta um resumo do item (estado, registro e o código usado) para você perguntar à IA que escolheu.')
    )) {
        $r = New-Object System.Windows.Controls.Grid; Grid-Cols $r @('Auto', '*'); $r.Margin = '0,4,0,6'
        $gi = Glyph ([string]$pair[0]) 15 '#818CF8'; $gi.Margin = '0,1,12,0'; $gi.VerticalAlignment = 'Top'; Put $r $gi 0
        $tt = New-Text $pair[1] 12.8 '#AEB6C4'; $tt.LineHeight = 18; Put $r $tt 1
        $sp.Children.Add($r) | Out-Null
    }
    $cw.Child = $sp; Add-Body $cw

    Add-Body (New-Section 'ESTE APP')
    $ci = New-Card; $sp = New-Object System.Windows.Controls.StackPanel
    $iv = Get-Intervals
    foreach ($row in @(
        @('Versão', (Format-Version $AppVersion)),
        @('Código de autenticidade', $(if ($PublicKeyXml) { Get-KeyFingerprint } else { 'Ainda não configurado (versão de desenvolvimento)' })),
        @('Licença', 'GPL-3.0. O nome Janus e o ícone são do projeto original: versões modificadas precisam usar outro nome.'),
        @('Código-fonte', $RepoUrl),
        @('Programa', $PSCommandPath),
        @('Dados (log, backups, ajuda)', $DataDir),
        @('Modo de leitura', $(if ($script:Config.LightMode) { (T 'Leve: ajustes a cada {0} s, segurança a cada {1} min, pausa fora de foco') -f $iv.Fast, ($iv.Full / 60) } else { (T 'Completo: ajustes a cada {0} s, segurança a cada {1} min') -f $iv.Fast, ($iv.Full / 60) })),
        @('Última leitura completa', $(if ($script:Snap.FullMs) { '{0} ms em segundo plano' -f $script:Snap.FullMs } else { '-' })),
        @('Monitoramento do hardware', (T $MonLevels[$script:Config.MonLevel][0])),
        @('Criado com', 'Claude Code (Claude Opus 5.5, revisado com Claude Fable 5.2)'),
        @('Tecnologia', 'PowerShell 5.1 + WPF')
    )) {
        $g = New-Object System.Windows.Controls.Grid; Grid-Cols $g @('220', '*'); $g.Margin = '0,3,0,3'
        Put $g (New-Text $row[0] 12.5 '#7F8899') 0
        $v = New-Text ([string]$row[1]) 12.5 '#E6E9EF'; $v.TextWrapping = 'Wrap'; Put $g $v 1
        $sp.Children.Add($g) | Out-Null
    }
    $op = New-SmallToggle ([string][char]0xE713) 'Configurações do Janus' 'Abre o menu da engrenagem: idioma, tema, visualização, IA, monitoramento e modo leve.' { Show-GearMenu $ui.LangTop }; $op.HorizontalAlignment = 'Left'; $op.Margin = '0,10,0,0'
    $sp.Children.Add($op) | Out-Null
    $ci.Child = $sp; Add-Body $ci
}

# ---------- relatório de erros ----------
# Nada é enviado sozinho: o Janus monta um arquivo, você vê o que vai junto e decide se manda.
$script:InReport = $false
function Protect-Text([string]$s, [bool]$on = $true) {
    if (-not $on -or -not $s) { return $s }
    $s = $s.Replace($env:USERPROFILE, '%USERPROFILE%')
    if ($env:USERNAME.Length -ge 3) { $s = [regex]::Replace($s, [regex]::Escape($env:USERNAME), '<usuario>', 'IgnoreCase') }
    if ($env:COMPUTERNAME.Length -ge 3) { $s = [regex]::Replace($s, [regex]::Escape($env:COMPUTERNAME), '<pc>', 'IgnoreCase') }
    $s = [regex]::Replace($s, '[\w\.\-+]+@[\w\-]+\.[\w\.\-]+', '<email>')
    return $s
}
function Get-ErrorText($err) {
    if ($err -is [System.Management.Automation.ErrorRecord]) {
        return (@('Erro: ' + $err.Exception.Message, 'Tipo: ' + $err.Exception.GetType().FullName, 'Onde no script:', $err.ScriptStackTrace, $err.InvocationInfo.PositionMessage) -join "`r`n")
    }
    if ($err -is [Exception]) {
        $e = $err; while ($e.InnerException) { $e = $e.InnerException }
        return (@('Erro: ' + $e.Message, 'Tipo: ' + $e.GetType().FullName, 'Pilha:', [string]$e.StackTrace) -join "`r`n")
    }
    return [string]$err
}
function Save-CrashInfo($err, [string]$where) {
    $txt = (@('Quando: ' + (Get-Date -Format 'dd/MM/yyyy HH:mm:ss'), 'Onde: ' + $where, 'Versão: ' + $AppVersion, (Get-ErrorText $err)) -join "`r`n")
    try { [IO.File]::WriteAllText($CrashFile, $txt, (New-Object Text.UTF8Encoding($false))) } catch {}
    try { Write-Log ('ERRO GRAVE em ' + $where + ': ' + ((Get-ErrorText $err) -split "`r?`n")[0]) } catch {}
    return $txt
}
function New-ErrorReport([hashtable]$opt) {
    $an = [bool]$opt.Anon
    $L = New-Object System.Collections.Generic.List[string]
    $L.Add('# Relatório de problema - Janus'); $L.Add('')
    $L.Add('- Versão: ' + $AppVersion + $(if ($Instalado) { ' (instalado)' } else { ' (portátil)' }))
    $L.Add('- Data: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'))
    $L.Add('- Idioma: ' + $script:Lang + ' | Windows: ' + [Environment]::OSVersion.VersionString + ' | PowerShell ' + $PSVersionTable.PSVersion)
    $L.Add('- Motivo: ' + $opt.Reason); $L.Add('')
    if ($opt.UserText) { $L.Add('## O que a pessoa estava fazendo'); $L.Add(''); $L.Add((Protect-Text $opt.UserText $an)); $L.Add('') }
    if ($opt.Detail -and $opt.IncDetail) { $L.Add('## Detalhes do erro'); $L.Add(''); $L.Add('```'); $L.Add((Protect-Text $opt.Detail $an)); $L.Add('```'); $L.Add('') }
    if ($opt.IncPc) {
        $L.Add('## PC'); $L.Add('')
        try { $pc = Get-PcInfo; foreach ($k in 'Tipo', 'Windows', 'Cpu', 'Gpu', 'Tela', 'Ram', 'Energia') { $L.Add(('- {0}: {1}' -f $k, (Protect-Text ([string]$pc[$k]) $an))) } } catch { $L.Add('- (não consegui ler)') }
        $L.Add('')
    }
    if ($opt.IncState) {
        $L.Add('## Ajustes e segurança'); $L.Add('')
        foreach ($t in $script:Tweaks) { $L.Add(('- {0}: {1}' -f $t.Id, $(if (-not (Is-Available $t)) { 'indisponível' } else { [string](Get-State $t) }))) }
        foreach ($s in @(Get-SecurityStatus)) { $L.Add(('- {0}: {1} [{2}]' -f $s.Name, $s.Value, $s.Level)) }
        $L.Add('- Selo: ' + $script:Auth.Level + ' | ' + $script:Auth.Title); $L.Add('')
    }
    if ($opt.IncEvents) {
        $L.Add('## Erros recentes do Windows (24 h)'); $L.Add('')
        try {
            $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Level = 1, 2; StartTime = (Get-Date).AddDays(-1) } -MaxEvents 300 -ErrorAction Stop |
                Where-Object { $_.ProviderName -in 'Application Error', '.NET Runtime', 'Windows Error Reporting', 'PowerShell', 'Application Hang' -or $_.Message -match 'powershell|Janus' } | Select-Object -First 15)
            if (-not $ev.Count) { $L.Add('- nenhum relacionado') }
            foreach ($e in $ev) { $m = ([string]$e.Message -replace '\s+', ' '); if ($m.Length -gt 400) { $m = $m.Substring(0, 400) + '...' }; $L.Add(('- {0} | {1} | {2} | {3}' -f $e.TimeCreated.ToString('dd/MM HH:mm'), $e.ProviderName, $e.Id, (Protect-Text $m $an))) }
        } catch { $L.Add('- nenhum ou sem acesso: ' + $_.Exception.Message) }
        $L.Add('')
    }
    if ($opt.IncConfig) { $L.Add('## Preferências do Janus'); $L.Add(''); $L.Add('```json'); $L.Add((Protect-Text ($script:Config | ConvertTo-Json -Compress) $an)); $L.Add('```'); $L.Add('') }
    if ($opt.IncLog) {
        $L.Add('## Registro do Janus (últimas 300 linhas)'); $L.Add(''); $L.Add('```')
        if (Test-Path -LiteralPath $LogFile) { foreach ($x in @(Get-Content -LiteralPath $LogFile -Encoding UTF8 -Tail 300)) { $L.Add((Protect-Text $x $an)) } } else { $L.Add('(vazio)') }
        $L.Add('```')
    }
    $path = Join-Path $ReportDir ('relatorio-janus-{0}.md' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    [IO.File]::WriteAllLines($path, $L, (New-Object Text.UTF8Encoding($false)))
    return $path
}
# Reason: erro (agora), fechou (na última vez), repetido (não consegue abrir), manual
function Show-ReportDialog([string]$reason, [string]$detail = '') {
    if ($script:InReport) { return 'cancel' }
    $script:InReport = $true
    try {
        $d = New-StyledWindow 'Reportar um problema' 640
        $root = New-Object System.Windows.Controls.StackPanel; $root.Margin = '28,22,28,22'
        $head = @{ erro = @('O Janus encontrou um erro', 'crit'); fechou = @('O Janus fechou sozinho da última vez', 'warn'); repetido = @('O Janus não está conseguindo abrir', 'crit'); manual = @('Reportar um problema', 'info') }[$reason]
        $lv = @{ info = @([char]0xEBE8, '#818CF8'); warn = @([char]0xE7BA, '#F59E0B'); crit = @([char]0xEA39, '#EF4444') }[$head[1]]
        $hr = New-Object System.Windows.Controls.StackPanel; $hr.Orientation = 'Horizontal'
        $ic = Glyph ([string]$lv[0]) 22 $lv[1]; $ic.Margin = '0,0,12,0'; $ic.VerticalAlignment = 'Center'; $hr.Children.Add($ic) | Out-Null
        $ht = New-Text $head[0] 19 '#E6E9EF' 'SemiBold'; $ht.VerticalAlignment = 'Center'; $hr.Children.Add($ht) | Out-Null
        $root.Children.Add($hr) | Out-Null
        if ($reason -eq 'repetido') { $rp = New-Text 'Ele fechou várias vezes seguidas, então abri só esta janela. Você pode mandar o relatório, tentar abrir de novo ou voltar as preferências do Janus ao padrão.' 12.8 '#FCA5A5'; $rp.Margin = '0,10,0,0'; $root.Children.Add($rp) | Out-Null }
        $opt = New-Object System.Windows.Controls.Border; $opt.CornerRadius = 10; $opt.Margin = '0,14,0,14'; $opt.Padding = '14,10'
        $opt.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(40, 0x81, 0x8C, 0xF8))
        $ot = New-Text 'Enviar é opcional e ajuda a melhorar o Janus. Você escolhe o que vai junto, pode ler o arquivo antes e nada é enviado sozinho.' 12.8 '#C7D2FE' 'SemiBold'; $ot.LineHeight = 18
        $opt.Child = $ot; $root.Children.Add($opt) | Out-Null
        if ($detail) {
            $db = New-Object System.Windows.Controls.TextBox; $db.Text = (Protect-Text (($detail -split "`r?`n" | Select-Object -First 6) -join "`r`n") $true); $db.IsReadOnly = $true; $db.TextWrapping = 'Wrap'
            $db.Background = Brush '#171C26'; $db.Foreground = Brush '#FCA5A5'; $db.BorderThickness = 0; $db.Padding = '8'; $db.FontFamily = 'Cascadia Mono, Consolas'; $db.FontSize = 11.5; $db.MaxHeight = 110; $db.VerticalScrollBarVisibility = 'Auto'
            $root.Children.Add($db) | Out-Null
        }
        $root.Children.Add((New-Text 'O que você estava fazendo? (opcional)' 12.5 '#AEB6C4' 'SemiBold')) | Out-Null
        $ut = New-Object System.Windows.Controls.TextBox; $ut.AcceptsReturn = $true; $ut.TextWrapping = 'Wrap'; $ut.Height = 64; $ut.Margin = '0,6,0,12'
        $ut.Background = Brush '#171C26'; $ut.Foreground = Brush '#E6E9EF'; $ut.CaretBrush = Brush '#E6E9EF'; $ut.BorderBrush = Brush '#262E3C'; $ut.Padding = '6'
        $root.Children.Add($ut) | Out-Null
        $root.Children.Add((New-Text 'O que mandar junto:' 12.5 '#AEB6C4' 'SemiBold')) | Out-Null
        $boxes = [ordered]@{}
        $items = @(
            @('IncDetail', 'Detalhes do erro', [bool]$detail),
            @('IncLog', 'Registro do Janus (últimas 300 linhas)', $true),
            @('IncPc', 'Dados do PC (Windows, processador, placa de vídeo, tela, memória)', $true),
            @('IncState', 'Estado dos ajustes e da segurança', $true),
            @('IncEvents', 'Erros recentes do Windows ligados ao PowerShell (últimas 24 h)', $true),
            @('IncConfig', 'Preferências do Janus', $true),
            @('Anon', 'Esconder meu nome de usuário, nome do PC e e-mails', [bool]$script:Config.Anonimizar)
        )
        foreach ($it in $items) {
            if ($it[0] -eq 'IncDetail' -and -not $detail) { continue }
            $cb = New-Object System.Windows.Controls.CheckBox; $cb.Content = (T $it[1]); $cb.IsChecked = $it[2]; $cb.Foreground = Brush '#D6DCE8'; $cb.Margin = '0,6,0,0'
            $root.Children.Add($cb) | Out-Null; $boxes[$it[0]] = $cb
        }
        $gh = New-Text 'Para enviar pelo GitHub é preciso uma conta gratuita. O Janus abre a página do relatório já preenchida e a pasta com o arquivo: é só arrastar o arquivo para a página.' 11.5 '#6F7889'; $gh.Margin = '0,12,0,0'
        $root.Children.Add($gh) | Out-Null
        $br = New-Object System.Windows.Controls.WrapPanel; $br.HorizontalAlignment = 'Right'; $br.Margin = '0,16,0,0'
        $btns = @(@('send', 'Gerar e enviar pelo GitHub', 'Accent'), @('save', 'Só salvar o arquivo', 'Ghost'))
        if ($reason -eq 'repetido') { $btns += , @('reset', 'Voltar preferências ao padrão', 'Ghost'); $btns += , @('open', 'Tentar abrir o Janus', 'Ghost'); $btns += , @('cancel', 'Fechar', 'Ghost') }
        else { $btns += , @('cancel', 'Agora não', 'Ghost') }
        foreach ($bt in $btns) {
            $b = New-Button $bt[1] $bt[2] $bt[0]; $b.Margin = '8,4,0,0'
            $b.add_Click({ $win = [System.Windows.Window]::GetWindow($this); $win.Tag = $this.Tag; $win.DialogResult = $true })
            $br.Children.Add($b) | Out-Null
        }
        $root.Children.Add($br) | Out-Null
        $sv = New-Object System.Windows.Controls.ScrollViewer; $sv.VerticalScrollBarVisibility = 'Auto'; $sv.MaxHeight = 820; $sv.Content = $root
        $d.Content = $sv; $d.Tag = 'cancel'
        if ($Teste) { $d.Close(); return 'cancel' }
        $wasBusy = $script:Busy; $script:Busy = $true
        try { [void]$d.ShowDialog() } finally { $script:Busy = $wasBusy }
        $choice = [string]$d.Tag
        if ($choice -in 'send', 'save') {
            $o = @{ Reason = $reason; Detail = $detail; UserText = $ut.Text }
            foreach ($k in $boxes.Keys) { $o[$k] = [bool]$boxes[$k].IsChecked }
            if ($script:Config.Anonimizar -ne $o.Anon) { $script:Config.Anonimizar = $o.Anon; Save-Config }
            $file = New-ErrorReport $o
            Write-Log ('Relatório de problema gerado: ' + $file)
            if ($choice -eq 'send') {
                $first = $(if ($detail) { (Protect-Text (($detail -split "`r?`n" | Where-Object { $_ -like 'Erro:*' } | Select-Object -First 1)) $true) } else { '' })
                $title = '[' + (Format-Version $AppVersion) + '] ' + $(if ($first) { ($first -replace '^Erro:\s*', '') } else { $head[0] })
                if ($title.Length -gt 110) { $title = $title.Substring(0, 110) }
                $body = "**Versão:** $AppVersion`n**Windows:** " + [Environment]::OSVersion.Version + "`n**Motivo:** $reason`n`n"
                if ($ut.Text) { $u = Protect-Text $ut.Text $o.Anon; if ($u.Length -gt 1200) { $u = $u.Substring(0, 1200) + '...' }; $body += "**O que eu estava fazendo:**`n$u`n`n" }
                $body += '📎 Arraste para cá o arquivo `' + (Split-Path -Leaf $file) + '` (o Janus abriu a pasta dele).'
                Open-Url ("$RepoUrl/issues/new?labels=bug&title=" + [uri]::EscapeDataString($title) + '&body=' + [uri]::EscapeDataString($body))
            }
            Start-Process explorer.exe "/select,`"$file`""
            if ($ui -and $W.IsVisible) { Show-Toast 'Relatório salvo. Obrigado por ajudar!' }
        }
        if ($choice -eq 'reset') {
            foreach ($k in 'LightMode', 'Lang') { $script:Config[$k] = $(if ($k -eq 'Lang') { '' } else { $false }) }
            $script:Config.CrashCount = 0; Save-Config; Write-Log 'Preferências do Janus voltaram ao padrão (modo de segurança).'
        }
        return $choice
    } finally { $script:InReport = $false }
}

# ---------- selo de autenticidade e atualizações ----------
$script:Auth = @{ Level = 'off'; Title = 'Ainda não verifiquei'; Text = 'A verificação roda em segundo plano logo depois de abrir.'; Latest = $null; LatestMan = $null; Url = $RepoUrl; Avisos = @(); CheckedAt = $null; Assets = @() }
$script:NetJob = $null; $script:NextUpdateCheck = [datetime]::MinValue; $script:ManualCheck = $false
$UpdateWorker = @'
param($inp)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$r = @{ Ok = $false; Error = ''; NoReleases = $false; Current = $null; Latest = $null }
function Get-Bytes([string]$url) {
    $wc = New-Object System.Net.WebClient; $wc.Headers.Add('User-Agent', 'Janus-app')
    try { return , $wc.DownloadData($url) } finally { $wc.Dispose() }
}
function Pack($rel) {
    $m = $rel.assets | Where-Object { $_.name -eq 'manifesto.json' } | Select-Object -First 1
    $s = $rel.assets | Where-Object { $_.name -eq 'manifesto.sig' } | Select-Object -First 1
    if (-not $m -or -not $s) { return $null }
    return @{ Tag = [string]$rel.tag_name; Pre = [bool]$rel.prerelease; Url = [string]$rel.html_url; Notes = [string]$rel.body
              Man = (Get-Bytes $m.browser_download_url); Sig = [Text.Encoding]::ASCII.GetString((Get-Bytes $s.browser_download_url))
              Assets = @($rel.assets | ForEach-Object { @{ Name = [string]$_.name; Url = [string]$_.browser_download_url; Size = [int64]$_.size } }) }
}
try {
    $h = @{ 'User-Agent' = 'Janus-app'; 'Accept' = 'application/vnd.github+json' }
    $rels = @(Invoke-RestMethod -Uri ('https://api.github.com/repos/{0}/{1}/releases?per_page=30' -f $inp.Owner, $inp.Repo) -Headers $h -TimeoutSec 20 -UseBasicParsing)
    $rels = @($rels | Where-Object { -not $_.draft -and ($inp.IncludePre -or -not $_.prerelease) })
    if (-not $rels.Count) { $r.NoReleases = $true; $r.Ok = $true; return $r }
    $cur = $rels | Where-Object { ($_.tag_name -replace '^v', '') -eq $inp.Version } | Select-Object -First 1
    if ($cur) { $r.Current = Pack $cur }
    $r.Latest = Pack $rels[0]
    $r.Ok = $true
} catch {
    # repositório ainda não criado (404) = nenhuma versão publicada, não "sem conexão"
    if ($_.Exception.Message -match '404') { $r.NoReleases = $true; $r.Ok = $true } else { $r.Error = $_.Exception.Message }
}
$r
'@
function Get-KeyFingerprint {
    if (-not $PublicKeyXml) { return '' }
    $sha = [Security.Cryptography.SHA256]::Create()
    $hx = -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($PublicKeyXml)) | Select-Object -First 4 | ForEach-Object { $_.ToString('X2') })
    return ('JN-{0}-{1}' -f $hx.Substring(0, 4), $hx.Substring(4, 4))
}
function Test-Signature([byte[]]$data, [string]$sigB64) {
    if (-not $PublicKeyXml -or -not $data -or -not $sigB64) { return $false }
    try {
        $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider; $rsa.PersistKeyInCsp = $false
        $rsa.FromXmlString($PublicKeyXml)
        return $rsa.VerifyData($data, 'SHA256', [Convert]::FromBase64String($sigB64.Trim()))
    } catch { return $false }
}
function Get-FileSha([string]$p) { if (Test-Path -LiteralPath $p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLower() } else { '' } }
function Start-UpdateCheck {
    if ($script:NetJob) { return }
    if (-not $script:RsNet) { $script:RsNet = [runspacefactory]::CreateRunspace(); $script:RsNet.Open() }
    $ps = [powershell]::Create(); $ps.Runspace = $script:RsNet
    [void]$ps.AddScript($UpdateWorker).AddArgument(@{ Owner = $RepoOwner; Repo = $RepoName; Version = $AppVersion; IncludePre = ($AppVersion -match '-beta') })
    $script:NetJob = @{ PS = $ps; Handle = $ps.BeginInvoke() }
    $script:NextUpdateCheck = (Get-Date).AddHours(6)
}
function Receive-UpdateCheck([switch]$Wait) {
    $j = $script:NetJob; if (-not $j) { return }
    if (-not $Wait -and -not $j.Handle.IsCompleted) { return }
    try { $out = $j.PS.EndInvoke($j.Handle) } finally { $j.PS.Dispose(); $script:NetJob = $null }
    $res = $(if ($out -and $out.Count) { [hashtable]$out[0] } else { @{ Ok = $false; Error = 'sem resposta' } })
    Set-AuthFromCheck $res
}
function Set-AuthFromCheck($res) {
    $a = @{ Level = 'off'; Title = ''; Text = ''; Latest = $null; LatestMan = $null; Url = $RepoUrl; Avisos = @(); CheckedAt = (Get-Date); Assets = @() }
    if (-not $PublicKeyXml) {
        # sem chave ainda: mesmo assim mostra o que o GitHub respondeu, para o botão Verificar sempre dar um retorno
        $a.Title = 'Selo ainda não configurado'
        $gh = $(if (-not $res.Ok) { 'GitHub: sem conexão agora.' } elseif ($res.NoReleases) { 'GitHub: o repositório ainda não tem versões publicadas.' } elseif ($res.Latest) { 'GitHub: há versões publicadas, mas esta cópia não tem a chave para conferir.' } else { 'GitHub: respondeu, sem versões assinadas.' })
        $a.Text = @('Esta cópia é de desenvolvimento: ainda não existe chave de assinatura. O selo passa a funcionar na primeira versão publicada.', $gh)
        if (-not $res.Ok) { Write-Log ('Verificação no GitHub falhou: ' + $res.Error) }
    } elseif (-not $res.Ok) {
        $a.Title = 'Sem conexão com o GitHub agora'; $a.Text = 'Não consegui conferir a assinatura agora. Tento de novo mais tarde.'
        if ($script:Auth.CheckedAt -and $script:Auth.Level -ne 'off') { $a.Text += ' ' + ('Última verificação: {0}.' -f $script:Auth.CheckedAt.ToString('dd/MM HH:mm')) }
        Write-Log ('Verificação de atualização falhou: ' + $res.Error)
    } elseif ($res.NoReleases) {
        $a.Title = 'Nenhuma versão publicada ainda'; $a.Text = 'Quando a primeira versão sair no GitHub, o selo aparece aqui.'
    } else {
        $lat = $res.Latest; $cur = $res.Current
        $latOk = $lat -and (Test-Signature $lat.Man $lat.Sig)
        $curOk = $cur -and (Test-Signature $cur.Man $cur.Sig)
        if (($lat -and -not $latOk) -or ($cur -and -not $curOk)) {
            $a.Level = 'crit'; $a.Title = 'Assinatura inválida'; $a.Text = 'Um arquivo publicado não bate com a assinatura do projeto. Não atualize e confira o GitHub oficial.'
        } elseif (-not $cur) {
            $a.Level = 'warn'; $a.Title = 'Esta versão não está entre as publicadas'; $a.Text = 'Pode ser uma cópia de desenvolvimento ou modificada. Para ter o selo, instale pelo GitHub oficial.'
        } else {
            $man = [Text.Encoding]::UTF8.GetString($cur.Man) | ConvertFrom-Json
            $bad = @(); foreach ($f in @($man.files)) { if ($f.name -match '\.(ps1|json|ico)$' -and $f.name -notmatch 'Setup') { $lp = Join-Path $Pasta $f.name; if ((Get-FileSha $lp) -ne ([string]$f.sha256).ToLower()) { $bad += $f.name } } }
            if ($bad.Count) { $a.Level = 'crit'; $a.Title = 'Arquivos diferentes do original'; $a.Text = ('Alterados: {0}. Reinstale pelo GitHub oficial.' -f ($bad -join ', ')) }
            else { $a.Level = 'ok'; $a.Title = 'Original e verificado'; $a.Text = ('Assinatura válida e arquivos intactos. Código: {0}' -f (Get-KeyFingerprint)) }
        }
        if ($latOk) {
            $lm = [Text.Encoding]::UTF8.GetString($lat.Man) | ConvertFrom-Json
            $a.Latest = [string]$lm.version; $a.LatestMan = $lm; $a.Url = $lat.Url; $a.Assets = $lat.Assets; $a.Notes = $lat.Notes
            foreach ($av in @($lm.avisos)) { if ($av -and (@($av.afeta) -contains $AppVersion)) { $tx = $av.texto.($script:Lang); if (-not $tx) { $tx = $av.texto.pt }; $a.Avisos += @{ Level = [string]$av.nivel; Text = [string]$tx } } }
            if ($a.Level -ne 'crit' -and (Compare-AppVersion $a.Latest $AppVersion) -gt 0) {
                $a.Level = 'warn'; $a.Title = ('Versão nova disponível: {0}' -f (Format-Version $a.Latest)); $a.Text = 'A atualização é baixada do GitHub oficial e conferida pela assinatura antes de instalar.'
            }
        }
    }
    $script:Auth = $a
    Write-Log ('Selo: [' + $a.Level + '] ' + $a.Title)
    if ($ui -and $W.IsVisible -and $script:CurrentPage -in 'Inicio', 'Manutencao', 'Sobre' -and -not $script:Busy) { Show-Page $script:CurrentPage $ui.Scroll.VerticalOffset }
    if ($script:ManualCheck) { $script:ManualCheck = $false; if ($ui -and $W.IsVisible) { Show-Toast ('Verificação concluída: ' + $a.Title) } }
}
function Install-Update {
    $a = $script:Auth
    if (-not $a.LatestMan -or (Compare-AppVersion $a.Latest $AppVersion) -le 0) { return }
    $notes = $(if ($a.Notes) { $n = [string]$a.Notes; if ($n.Length -gt 700) { $n.Substring(0, 700) + '...' } else { $n } } else { '' })
    $r = Show-Choice 'Atualizar o Janus' ('Atualizar para {0}?' -f (Format-Version $a.Latest)) ((T 'O Janus baixa os arquivos do GitHub oficial, confere cada um pela assinatura e só então troca. A versão atual fica guardada para voltar, se precisar.') + $(if ($notes) { "`n`n" + $notes } else { '' })) @(@('yes', 'Atualizar agora', 'Accent'), @('no', 'Depois', 'Ghost')) 'info'
    if ($r -ne 'yes') { return }
    $W.Cursor = [System.Windows.Input.Cursors]::Wait
    $tmp = Join-Path $env:TEMP ('janus-update-' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $wanted = @($a.LatestMan.files | Where-Object { $_.name -in 'Janus.ps1', 'idiomas.json', 'Janus.ico' })
        if (-not ($wanted | Where-Object { $_.name -eq 'Janus.ps1' })) { throw 'o manifesto não traz o Janus.ps1' }
        foreach ($f in $wanted) {
            $asset = $a.Assets | Where-Object { $_.Name -eq $f.name } | Select-Object -First 1
            if (-not $asset) { throw ('arquivo não encontrado na versão: ' + $f.name) }
            $dst = Join-Path $tmp $f.name
            $wc = New-Object System.Net.WebClient; $wc.Headers.Add('User-Agent', 'Janus-app'); try { $wc.DownloadFile($asset.Url, $dst) } finally { $wc.Dispose() }
            if ((Get-FileSha $dst) -ne ([string]$f.sha256).ToLower()) { throw ('o arquivo baixado não bate com a assinatura: ' + $f.name) }
        }
        $old = Join-Path $DataDir ('versao-anterior\' + $AppVersion); New-Item -ItemType Directory -Force -Path $old | Out-Null
        foreach ($f in $wanted) { $cur = Join-Path $Pasta $f.name; if (Test-Path -LiteralPath $cur) { Copy-Item -LiteralPath $cur -Destination $old -Force } }
        foreach ($f in $wanted) { Copy-Item -LiteralPath (Join-Path $tmp $f.name) -Destination (Join-Path $Pasta $f.name) -Force }
        Write-Log ('Atualizado de {0} para {1}. Versão anterior guardada em {2}' -f $AppVersion, $a.Latest, $old)
        if ($Instalado) { $uk = $(if ($Edition.Pasta) { ([string]$Edition.Pasta -replace '[^A-Za-z0-9]', '') } else { 'Janus' }); try { Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$uk" -Name DisplayVersion -Value $a.Latest -ErrorAction Stop } catch {} }
        Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', "`"$PSCommandPath`"")
        $script:CleanExit = $true; $W.Close()
    } catch {
        Write-Log ('Atualização cancelada: ' + $_.Exception.Message)
        Show-Choice 'Atualizar o Janus' 'A atualização foi cancelada' ((T 'Nada foi trocado. Motivo:') + ' ' + $_.Exception.Message) @(@('ok', 'Ok', 'Accent')) 'warn' | Out-Null
    } finally { $W.Cursor = $null; Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
function New-AuthCard {
    $a = $script:Auth
    $st = $(if ($a.Level -eq 'off') { @([char]0xE8D7, '#8B94A5') } else { @($LevelStyle[$a.Level][0], $LevelStyle[$a.Level][1]) })
    $c = New-Card; $c.Padding = '18,14,18,14'
    if ($a.Level -eq 'crit') { $c.BorderBrush = Brush '#7F1D1D' } elseif ($a.Level -eq 'warn') { $c.BorderBrush = Brush '#78350F' } elseif ($a.Level -eq 'ok') { $c.BorderBrush = Brush '#1F5C45' }
    $g = New-Object System.Windows.Controls.Grid; Grid-Cols $g @('Auto', '*', 'Auto')
    $ic = Glyph ([string]$st[0]) 22 $st[1]; $ic.Margin = '0,2,16,0'; $ic.VerticalAlignment = 'Top'; Put $g $ic 0
    $sp = New-Object System.Windows.Controls.StackPanel; $sp.Margin = '0,0,16,0'
    $sp.Children.Add((New-Text $a.Title 14.5 '#E6E9EF' 'SemiBold')) | Out-Null
    $tx = New-Text ((@($a.Text) | ForEach-Object { T $_ }) -join ' ') 12 '#9AA3B2'; $tx.Margin = '0,4,0,0'; $sp.Children.Add($tx) | Out-Null
    foreach ($av in $a.Avisos) { $at = New-Text ('⚠ ' + $av.Text) 12.5 $(if ($av.Level -eq 'crit') { '#FCA5A5' } else { '#FCD38D' }) 'SemiBold'; $at.Margin = '0,6,0,0'; $sp.Children.Add($at) | Out-Null }
    if ($a.CheckedAt) { $ck = New-Text ('Verificado às {0}' -f $a.CheckedAt.ToString('HH:mm')) 11 '#5F6878'; $ck.Margin = '0,4,0,0'; $sp.Children.Add($ck) | Out-Null }
    Put $g $sp 1
    $bs = New-Object System.Windows.Controls.StackPanel; $bs.Orientation = 'Horizontal'; $bs.VerticalAlignment = 'Center'
    if ($a.Latest -and (Compare-AppVersion $a.Latest $AppVersion) -gt 0 -and $a.Level -ne 'crit') { $u = New-Button 'Atualizar agora' 'Accent'; $u.Margin = '8,0,0,0'; $u.add_Click({ Install-Update }); $bs.Children.Add($u) | Out-Null }
    $v = New-Button 'Verificar agora' 'Ghost'; $v.Margin = '8,0,0,0'; $v.add_Click({ $script:ManualCheck = $true; Start-UpdateCheck; Show-Toast 'Verificando no GitHub...' }); $bs.Children.Add($v) | Out-Null
    $o = New-Button 'GitHub' 'Ghost' $a.Url; $o.Margin = '8,0,0,0'; $o.add_Click({ Open-Url $this.Tag }); $bs.Children.Add($o) | Out-Null
    Put $g $bs 2
    $c.Child = $g
    return $c
}
function Build-Registro {
    $simple = ($script:Config.LogView -ne 'detalhado')
    $lines = @(); if (Test-Path -LiteralPath $LogFile) { $lines = @(Get-Content -LiteralPath $LogFile -Encoding UTF8 -Tail 600) }
    if (-not $lines.Count) { Add-Body (New-EmptyState ([string][char]0xE8A5) 'Nada por aqui ainda' 'Nenhuma mudança registrada ainda.'); return }
    if (-not $simple) {
        $card = New-Card
        $tb = New-Object System.Windows.Controls.TextBox
        $tb.IsReadOnly = $true; $tb.Background = Brush '#0E1117'; $tb.Foreground = Brush '#C9CED6'; $tb.BorderThickness = 0
        $tb.FontFamily = 'Cascadia Mono, Consolas'; $tb.FontSize = 12; $tb.TextWrapping = 'Wrap'; $tb.MinHeight = 420; $tb.Padding = '6'
        $tb.VerticalScrollBarVisibility = 'Auto'
        $r = @($lines | Select-Object -Last 400); [array]::Reverse($r); $tb.Text = ($r -join "`r`n")
        $card.Child = $tb; Add-Body $card; return
    }
    # versão simples: sem data, frases curtas, só o que importa
    $items = New-Object System.Collections.ArrayList; $last = ''
    $rev = @($lines); [array]::Reverse($rev)
    foreach ($ln in $rev) {
        $m = [regex]::Match($ln, '^\[[^\]]+\]\s*(.*)$'); $x = $(if ($m.Success) { $m.Groups[1].Value } else { $ln })
        $e = $null
        if ($x -match '^(.+): (?:inativo|ativo|\?) -> ativo$') { $e = @('do', 'Ativado: {0}', $Matches[1]) }
        elseif ($x -match '^(.+): (?:inativo|ativo|\?) -> inativo$') { $e = @('undo', 'Voltou ao padrão: {0}', $Matches[1]) }
        elseif ($x -match '^Verificação corrigida: (.+)$') { $e = @('do', 'Corrigido: {0}', $Matches[1]) }
        elseif ($x -match '^PROTEÇÃO DESLIGADA pelo Janus: ([^(]+)') { $e = @('crit', 'Proteção desligada: {0}', $Matches[1].Trim()) }
        elseif ($x -match '^Proteção religada: (.+)$') { $e = @('do', 'Proteção religada: {0}', $Matches[1]) }
        elseif ($x -match '^DNS trocado para (.+)$') { $e = @('info', 'DNS em uso: {0}', $Matches[1]) }
        elseif ($x -match '^DNS voltou ao automático') { $e = @('undo', 'DNS voltou ao automático', '') }
        elseif ($x -match '^Velocidade: (\d+) ms, ([\d.,]+) Mbps de download, ([\d.,]+) Mbps de upload') { $e = @('info', 'Teste de velocidade: {0}', ('{0} ms, {1} / {2} Mbps' -f $Matches[1], $Matches[2], $Matches[3])) }
        elseif ($x -match '^Temporários: (\d+) arquivo\(s\) apagados, ([\d.,]+) MB') { $e = @('info', 'Limpeza: {0}', ('{0} / {1} MB' -f $Matches[1], $Matches[2])) }
        elseif ($x -match '^Ponto de restauração (manual )?criado') { $e = @('info', 'Ponto de restauração criado', '') }
        elseif ($x -match '^Atualizado de (\S+) para (\S+)') { $e = @('do', 'Janus atualizado para {0}', (Format-Version $Matches[2])) }
        elseif ($x -match '^(ERRO|Teste de velocidade falhou|Atualização cancelada)[^:]*:\s*(.*)$') { $msg = $Matches[2]; if ($msg.Length -gt 110) { $msg = $msg.Substring(0, 110) + '...' }; $e = @('warn', 'Erro: {0}', $msg) }
        elseif ($x -match '^(Tema|Idioma|Modo da barra lateral|Monitoramento): (.+)$') { $e = @('info', 'Preferência: {0}', ($Matches[1] + ' = ' + $Matches[2])) }
        if (-not $e) { continue }
        $key = $e -join '|'; if ($key -eq $last) { continue }; $last = $key
        [void]$items.Add($e); if ($items.Count -ge 80) { break }
    }
    if (-not $items.Count) { Add-Body (New-EmptyState ([string][char]0xE8A5) 'Nada por aqui ainda' 'Nenhuma mudança registrada ainda.'); return }
    $card = New-Card; $card.Padding = '20,10,20,10'
    $sp = New-Object System.Windows.Controls.StackPanel
    $style = @{ do = @([char]0xE73E, '#22C55E'); undo = @([char]0xE7A7, '#F59E0B'); info = @([char]0xE946, '#60A5FA'); warn = @([char]0xE7BA, '#F59E0B'); crit = @([char]0xEA39, '#EF4444') }
    foreach ($it in $items) {
        $g = New-Object System.Windows.Controls.Grid; Grid-Cols $g @('Auto', '*'); $g.Margin = '0,7,0,7'
        $st = $style[$it[0]]
        $gi = Glyph ([string]$st[0]) 16 $st[1]; $gi.Margin = '0,1,14,0'; $gi.VerticalAlignment = 'Top'; Put $g $gi 0
        $txt = $(if ($it[2]) { (T $it[1]) -f (T $it[2]) } else { T $it[1] })
        $tx = New-Text $txt 14.5 '#E6E9EF'; Put $g $tx 1
        $sp.Children.Add($g) | Out-Null
    }
    $card.Child = $sp; Add-Body $card
    $hint = New-Text 'Mostrando o mais recente primeiro. Para ver tudo, com data e hora, use "Detalhado" no topo.' 11.5 '#6F7889'; $hint.Margin = '2,4,0,0'; Add-Body $hint
}

# ---------- modo Simplificado / Por categoria ----------

function Set-NavMode([string]$m) {
    if ($m -eq $script:Config.NavMode) { return }
    $script:Config.NavMode = $m; Save-Config; Write-Log ('Modo da barra lateral: ' + $m)
    Build-Nav
    $cur = $script:CurrentPage
    $target = $(if (Test-PageInMode $cur) { $cur } elseif ($m -eq 'simples') { 'Otimizacoes' } else { 'Entrada' })
    Show-Page $target
}

# ---------- aba Otimizações (modo Simplificado) ----------
function Wire-TweakToggle($tg, $t) {
    $tg.Tag = $t
    if (Is-Available $t) {
        $tg.add_Click({
            $tw = $this.Tag
            if ($tw.UI.Updating) { return }
            $want = [bool]$this.IsChecked
            $script:Busy = $true
            try { $ok = Apply-Tweak $tw $want } finally { $script:Busy = $false }
            Refresh-Card $tw; Update-NavCounts
            if ($ok) { Show-Toast ($tw.Title + ': ' + $(if ($want) { 'ativado' } else { 'desativado (padrão do Windows)' })) }
        })
        Refresh-Card $t
    } else { $tg.IsEnabled = $false; $tg.ToolTip = (T $t.UnavailableWhy) }
}
# Linha larga (modo Detalhado): descrição completa e "não recomendado se" sempre visíveis
function New-TweakRow($t) {
    $card = New-Card; $card.Padding = '18,14,16,14'; $card.Margin = '0,0,12,10'
    $g = New-Object System.Windows.Controls.Grid; Grid-Cols $g @('Auto', '*', 'Auto')
    $ic = Glyph ([string]$t.Glyph) 22 '#8EA3C8'; $ic.Margin = '0,2,16,0'; $ic.VerticalAlignment = 'Top'; Put $g $ic 0
    $sp = New-Object System.Windows.Controls.StackPanel; $sp.Margin = '0,0,18,0'
    $sp.Children.Add((New-Text $t.Title 14.5 '#E6E9EF' 'SemiBold')) | Out-Null
    $d = New-Text $t.Desc 12.3 '#9AA3B2'; $d.LineHeight = 17; $d.Margin = '0,4,0,0'; $sp.Children.Add($d) | Out-Null
    $cv = New-Text ('Não recomendado se ' + $t.Caveat) 11.8 '#6F7889'; $cv.Margin = '0,4,0,0'; $sp.Children.Add($cv) | Out-Null
    if (-not (Is-Available $t)) { $why = New-Text ('Indisponível: ' + $t.UnavailableWhy) 11.5 '#F59E0B' 'SemiBold'; $why.Margin = '0,4,0,0'; $sp.Children.Add($why) | Out-Null }
    $wp = New-Object System.Windows.Controls.WrapPanel; $wp.Margin = '0,8,0,0'
    if ($CategoryNames.Contains($t.Page)) { $wp.Children.Add((New-Badge $CategoryNames[$t.Page] '#818CF8')) | Out-Null }
    Add-TweakBadges $wp $t; $sp.Children.Add($wp) | Out-Null
    Put $g $sp 1
    $tr = New-Object System.Windows.Controls.StackPanel; $tr.Orientation = 'Horizontal'; $tr.VerticalAlignment = 'Center'
    $hb = New-HelpButton 'Ajuste' $t; $hb.Margin = '0,0,10,0'; $tr.Children.Add($hb) | Out-Null
    $tg = New-Object System.Windows.Controls.Primitives.ToggleButton; $tg.Style = $W.FindResource('Switch'); $tg.VerticalAlignment = 'Center'
    $tr.Children.Add($tg) | Out-Null
    Put $g $tr 2
    $card.Child = $g
    $t.UI = @{ Card = $card; Toggle = $tg; Icon = $ic; Updating = $false }
    Wire-TweakToggle $tg $t
    return $card
}
function New-SmallToggle([string]$glyph, [string]$text, [string]$tip, [scriptblock]$action) {
    $b = New-Object System.Windows.Controls.Button; $b.Style = $W.FindResource('Ghost'); $b.Padding = '10,5'; $b.Margin = '0,0,8,0'
    $sp = New-Object System.Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'
    $g = Glyph $glyph 13 '#AEB6C4'; $g.Margin = '0,0,7,0'; $g.VerticalAlignment = 'Center'; $sp.Children.Add($g) | Out-Null
    $tx = New-Text $text 12 '#E6E9EF'; $tx.TextWrapping = 'NoWrap'; $sp.Children.Add($tx) | Out-Null
    $b.Content = $sp; $b.ToolTip = (T $tip); $b.Tag = $action; $b.add_Click({ & $this.Tag })
    return $b
}
function Add-TweakGroup($items) {
    if (-not $items.Count) { return }
    if ($script:Config.OptView -eq 'detalhado') { foreach ($t in $items) { Add-Body (New-TweakRow $t) } }
    else {
        $ug = New-Object System.Windows.Controls.Primitives.UniformGrid; $ug.Columns = 3
        foreach ($t in $items) { $ug.Children.Add((New-TweakCard $t)) | Out-Null }
        Add-Body $ug
    }
}
function Add-Separator { $s = New-Object System.Windows.Controls.Border; $s.Height = 1; $s.Background = Brush '#232A36'; $s.Margin = '2,14,14,2'; Add-Body $s }
function Build-Otimizacoes {
    $sortNames = @{ prio = 'Ordem: prioridade'; alfa = 'Ordem: alfabética'; cat = 'Ordem: por categoria' }
    $bar = New-Object System.Windows.Controls.WrapPanel; $bar.Margin = '0,0,0,10'
    $bar.Children.Add((New-SmallToggle ([string][char]0xE8CB) $sortNames[$script:Config.OptSort] 'Muda a ordem: prioridade (o que mais faz diferença primeiro), alfabética ou separada por categoria.' {
        $script:Config.OptSort = @{ prio = 'alfa'; alfa = 'cat'; cat = 'prio' }[$script:Config.OptSort]; Save-Config; Show-Page 'Otimizacoes' })) | Out-Null
    $bar.Children.Add((New-SmallToggle $(if ($script:Config.OptView -eq 'detalhado') { [string][char]0xE8FD } else { [string][char]0xF0E2 }) $(if ($script:Config.OptView -eq 'detalhado') { 'Ver: detalhado' } else { 'Ver: grade' }) 'Grade mostra os ajustes em cartões; detalhado usa a largura toda com a descrição completa.' {
        $script:Config.OptView = $(if ($script:Config.OptView -eq 'detalhado') { 'grade' } else { 'detalhado' }); Save-Config; Show-Page 'Otimizacoes' })) | Out-Null
    Add-Body $bar
    $all = @($script:Tweaks | Where-Object { $CategoryNames.Contains($_.Page) })
    switch ($script:Config.OptSort) {
        'alfa' { Add-Body (New-Section 'TODOS OS AJUSTES (A-Z)'); Add-TweakGroup @($all | Sort-Object { T $_.Title }) }
        'cat' {
            $first = $true
            foreach ($cat in $CategoryNames.Keys) {
                $items = @($all | Where-Object { $_.Page -eq $cat } | Sort-Object { $_.Prio })
                if (-not $items.Count) { continue }
                if (-not $first) { Add-Separator }; $first = $false
                Add-Body (New-Section ($CategoryNames[$cat]).ToUpper()); Add-TweakGroup $items
            }
        }
        default { Add-Body (New-Section 'POR PRIORIDADE: O QUE MAIS FAZ DIFERENÇA PRIMEIRO'); Add-TweakGroup @($all | Sort-Object { $_.Prio }) }
    }
    $checks = @($script:Checks | Where-Object { $_.Page -ne 'Seguranca' })
    if ($checks.Count) { Add-Separator; Add-Body (New-Section 'VERIFICAÇÕES'); foreach ($c in $checks) { Add-Body (New-CheckCard $c) } }
}
# Leva até o ajuste (na aba certa para o modo atual) e pisca a borda do cartão
function Focus-Tweak($t) {
    $target = $(if ($script:Config.NavMode -eq 'simples') { 'Otimizacoes' } else { $t.Page })
    Show-Page $target
    if (-not $t.UI) { return }
    $script:FocusCard = $t.UI.Card
    [void]$W.Dispatcher.BeginInvoke([System.Action]{
        try { $script:FocusCard.BringIntoView() } catch {}
        $script:FocusCard.BorderBrush = Brush '#818CF8'; $script:FocusCard.BorderThickness = 2
        $tm = New-Object System.Windows.Threading.DispatcherTimer; $tm.Interval = [TimeSpan]::FromSeconds(2.2)
        $tm.add_Tick({ try { $script:FocusCard.BorderThickness = 1; $script:FocusCard.BorderBrush = Brush '#232A36' } catch {}; $this.Stop() }); $tm.Start()
    }, [System.Windows.Threading.DispatcherPriority]::Loaded)
}

# ---------- tarefas em segundo plano (genérico) ----------
# Cada tarefa roda num "runspace" próprio; o Poll confere quando acabou e chama o OnDone na janela.
$script:BgJobs = @{}
function Start-BgJob([string]$name, [string]$code, $arg, [scriptblock]$onDone, [switch]$Keep) {
    if ($script:BgJobs.ContainsKey($name)) { return $false }
    # -Keep: reaproveita o mesmo ambiente (tarefas que se repetem muito, como o monitor)
    if ($Keep) { if (-not $script:KeepRs) { $script:KeepRs = @{} }; if (-not $script:KeepRs[$name]) { $r0 = [runspacefactory]::CreateRunspace(); $r0.Open(); $script:KeepRs[$name] = $r0 }; $rs = $script:KeepRs[$name] }
    else { $rs = [runspacefactory]::CreateRunspace(); $rs.Open() }
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript($code).AddArgument($arg)
    $script:BgJobs[$name] = @{ PS = $ps; RS = $rs; Handle = $ps.BeginInvoke(); OnDone = $onDone; Started = Get-Date; Keep = [bool]$Keep }
    return $true
}
function Receive-BgJobs([switch]$Wait) {
    foreach ($name in @($script:BgJobs.Keys)) {
        $j = $script:BgJobs[$name]
        if (-not $Wait -and -not $j.Handle.IsCompleted) { continue }
        $res = $null; $err = ''
        try { $out = $j.PS.EndInvoke($j.Handle); if ($out -and $out.Count) { $last = $out[$out.Count - 1]; try { $res = [hashtable]$last } catch { $res = $last } } }
        catch { $err = $_.Exception.Message }
        finally { try { $j.PS.Dispose(); if (-not $j.Keep) { $j.RS.Dispose() } } catch {}; $script:BgJobs.Remove($name) }
        if ($err) { Write-Log ("Tarefa '$name' falhou: " + $err) }
        try { & $j.OnDone $res $err } catch { Write-Log ("Resultado da tarefa '$name' falhou: " + $_.Exception.Message) }
    }
}

# ---------- rede: adaptadores, DNS e velocidade ----------
if (-not ('JanusNet' -as [type])) {
Add-Type -TypeDefinition @"
using System; using System.Net; using System.Net.Sockets; using System.IO; using System.Threading; using System.Diagnostics; using System.Collections.Generic;
public static class JanusNet {
  // amarra a conexão ao IP de um adaptador: assim dá para testar o Wi-Fi com o cabo ligado
  static HttpWebRequest Req(string url, string v4, string v6, string method) {
    var r = (HttpWebRequest)WebRequest.Create(url); r.Method = method; r.Timeout = 15000; r.ReadWriteTimeout = 15000;
    r.UserAgent = "Janus-app"; r.KeepAlive = false; r.Proxy = null; r.AllowWriteStreamBuffering = false;
    IPAddress a4 = string.IsNullOrEmpty(v4) ? null : IPAddress.Parse(v4); IPAddress a6 = string.IsNullOrEmpty(v6) ? null : IPAddress.Parse(v6);
    if (a4 != null || a6 != null) {
      r.ServicePoint.BindIPEndPointDelegate = (sp, remote, retry) => {
        if (retry > 3) return null;
        if (remote.AddressFamily == AddressFamily.InterNetwork && a4 != null) return new IPEndPoint(a4, 0);
        if (remote.AddressFamily == AddressFamily.InterNetworkV6 && a6 != null) return new IPEndPoint(a6, 0);
        return new IPEndPoint(remote.AddressFamily == AddressFamily.InterNetworkV6 ? IPAddress.IPv6None : IPAddress.None, 0);
      };
    }
    return r;
  }
  public static double[] Ping(string host, string v4, int count) {
    var list = new List<double>();
    IPAddress target = null; foreach (var ip in Dns.GetHostAddresses(host)) if (ip.AddressFamily == AddressFamily.InterNetwork) { target = ip; break; }
    if (target == null) throw new Exception("sem endereço IPv4 para " + host);
    for (int i = 0; i < count; i++) {
      using (var s = new Socket(AddressFamily.InterNetwork, SocketType.Stream, ProtocolType.Tcp)) {
        if (!string.IsNullOrEmpty(v4)) s.Bind(new IPEndPoint(IPAddress.Parse(v4), 0));
        var sw = Stopwatch.StartNew(); var ar = s.BeginConnect(target, 443, null, null);
        if (ar.AsyncWaitHandle.WaitOne(3000)) { s.EndConnect(ar); list.Add(sw.Elapsed.TotalMilliseconds); }
      }
      Thread.Sleep(120);
    }
    if (list.Count == 0) throw new Exception("sem resposta");
    list.Sort(); double med = list[list.Count / 2]; double jit = 0;
    for (int i = 1; i < list.Count; i++) jit += Math.Abs(list[i] - list[i - 1]);
    if (list.Count > 1) jit /= (list.Count - 1);
    return new double[] { med, jit };
  }
  // vários fluxos em paralelo por alguns segundos; devolve Mbps e o total de MB
  public static double[] Download(string v4, string v6, int seconds, int streams) {
    long total = 0; var stop = DateTime.UtcNow.AddSeconds(seconds); Exception last = null; var sw = Stopwatch.StartNew();
    var th = new List<Thread>();
    for (int s = 0; s < streams; s++) {
      var t = new Thread(() => {
        var buf = new byte[65536];
        while (DateTime.UtcNow < stop) {
          try {
            var r = Req("https://speed.cloudflare.com/__down?bytes=50000000", v4, v6, "GET");
            using (var resp = r.GetResponse()) using (var st = resp.GetResponseStream()) {
              int n; while (DateTime.UtcNow < stop && (n = st.Read(buf, 0, buf.Length)) > 0) Interlocked.Add(ref total, n);
            }
          } catch (Exception e) { last = e; Thread.Sleep(200); }
        }
      }); t.IsBackground = true; t.Start(); th.Add(t);
    }
    foreach (var t in th) t.Join();
    if (total == 0 && last != null) throw last;
    double secs = sw.Elapsed.TotalSeconds;
    return new double[] { total * 8.0 / secs / 1000000.0, total / 1048576.0 };
  }
  public static double[] Upload(string v4, string v6, int seconds, int streams) {
    long total = 0; var stop = DateTime.UtcNow.AddSeconds(seconds); Exception last = null; var sw = Stopwatch.StartNew();
    var th = new List<Thread>(); var chunk = new byte[65536]; new Random().NextBytes(chunk);
    for (int s = 0; s < streams; s++) {
      var t = new Thread(() => {
        while (DateTime.UtcNow < stop) {
          try {
            var r = Req("https://speed.cloudflare.com/__up", v4, v6, "POST"); long size = 25000000; r.ContentLength = size; r.ContentType = "application/octet-stream";
            long sent = 0;
            using (var st = r.GetRequestStream()) {
              while (sent < size && DateTime.UtcNow < stop) { int n = (int)Math.Min(chunk.Length, size - sent); st.Write(chunk, 0, n); sent += n; Interlocked.Add(ref total, n); }
              if (sent < size) { r.Abort(); continue; }
            }
            using (var resp = r.GetResponse()) { }
          } catch (Exception e) { if (!(e is WebException && ((WebException)e).Status == WebExceptionStatus.RequestCanceled)) last = e; }
        }
      }); t.IsBackground = true; t.Start(); th.Add(t);
    }
    foreach (var t in th) t.Join();
    if (total == 0 && last != null) throw last;
    double secs = sw.Elapsed.TotalSeconds;
    return new double[] { total * 8.0 / secs / 1000000.0, total / 1048576.0 };
  }
}
"@
}

# Lista de DNS públicos. Privacy: o aviso de privacidade vale para TODOS.
$DnsList = @(
  @{ Id='quad9'; Name='Quad9'; Who='Quad9 Foundation (Suíça, sem fins lucrativos)'; V4=@('9.9.9.9','149.112.112.112'); V6=@('2620:fe::fe','2620:fe::9'); Doh='https://dns.quad9.net/dns-query'; Filter='Bloqueia sites maliciosos'; Note='' }
  @{ Id='cloudflare'; Name='Cloudflare'; Who='Cloudflare (EUA)'; V4=@('1.1.1.1','1.0.0.1'); V6=@('2606:4700:4700::1111','2606:4700:4700::1001'); Doh='https://cloudflare-dns.com/dns-query'; Filter='Sem filtro'; Note='' }
  @{ Id='cloudflare-sec'; Name='Cloudflare (proteção)'; Who='Cloudflare (EUA)'; V4=@('1.1.1.2','1.0.0.2'); V6=@('2606:4700:4700::1112','2606:4700:4700::1002'); Doh='https://security.cloudflare-dns.com/dns-query'; Filter='Bloqueia sites maliciosos'; Note='' }
  @{ Id='google'; Name='Google'; Who='Google (EUA)'; V4=@('8.8.8.8','8.8.4.4'); V6=@('2001:4860:4860::8888','2001:4860:4860::8844'); Doh='https://dns.google/dns-query'; Filter='Sem filtro'; Note='' }
  @{ Id='adguard'; Name='AdGuard'; Who='AdGuard (Chipre)'; V4=@('94.140.14.14','94.140.15.15'); V6=@('2a10:50c0::ad1:ff','2a10:50c0::ad2:ff'); Doh='https://dns.adguard-dns.com/dns-query'; Filter='Bloqueia anúncios e rastreadores'; Note='Pode quebrar alguns sites e apps que dependem de anúncios.' }
  @{ Id='opendns'; Name='OpenDNS'; Who='Cisco (EUA)'; V4=@('208.67.222.222','208.67.220.220'); V6=@('2620:119:35::35','2620:119:53::53'); Doh='https://doh.opendns.com/dns-query'; Filter='Sem filtro'; Note='' }
  @{ Id='controld'; Name='Control D'; Who='Control D (Canadá)'; V4=@('76.76.2.0','76.76.10.0'); V6=@(); Doh='https://freedns.controld.com/p0'; Filter='Sem filtro'; Note='' }
  @{ Id='nextdns'; Name='NextDNS'; Who='NextDNS (EUA)'; V4=@('45.90.28.0','45.90.30.0'); V6=@(); Doh='https://dns.nextdns.io'; Filter='Sem filtro'; Note='Sem conta no site da NextDNS funciona como DNS comum, sem os filtros.' }
  @{ Id='ultradns'; Name='UltraDNS (ex-Verisign)'; Who='Vercara / DigiCert (EUA)'; V4=@('64.6.64.6','64.6.65.6'); V6=@('2620:74:1b::1:1','2620:74:1c::2:2'); Doh=''; Filter='Sem filtro'; Note='' }
  @{ Id='ultradns-sec'; Name='UltraDNS Proteção (ex-Neustar)'; Who='Vercara / DigiCert (EUA)'; V4=@('156.154.70.2','156.154.71.2'); V6=@('2610:a1:1018::2','2610:a1:1019::2'); Doh=''; Filter='Bloqueia sites maliciosos'; Note='' }
)
function Get-NetAdapters {
    $route = @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object { $_.RouteMetric + $_.InterfaceMetric })
    $primary = $(if ($route.Count) { $route[0].InterfaceIndex } else { -1 })
    @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch 'Hyper-V|Virtual|Loopback|VPN|TAP|WireGuard|ExitLag' } | ForEach-Object {
        $v4 = @(Get-NetIPAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1).IPAddress
        $v6 = @(Get-NetIPAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv6 -ErrorAction SilentlyContinue | Where-Object { $_.PrefixOrigin -ne 'WellKnown' -and $_.IPAddress -notlike 'fe80*' -and $_.AddressState -eq 'Preferred' } | Select-Object -First 1).IPAddress
        $dns = @((Get-DnsClientServerAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses)
        $static = [string](Get-RegValue ("HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\" + $_.InterfaceGuid) 'NameServer')
        @{ Index = $_.ifIndex; Name = $_.Name; Desc = $_.InterfaceDescription; Guid = $_.InterfaceGuid; Speed = $_.LinkSpeed; Wifi = ($_.Name -match 'Wi-?Fi' -or $_.InterfaceDescription -match 'Wi-?Fi|Wireless|802\.11')
           V4 = $v4; V6 = $v6; Dns = $dns; Manual = [bool]$static; Primary = ($_.ifIndex -eq $primary) }
    } | Sort-Object @{ e = { [int][bool]$_.Wifi } }, @{ e = { $_.Index } })   # cabo primeiro, depois Wi-Fi
}
function Get-CurrentDnsProvider($adapters) {
    $used = @($adapters | Where-Object { $_.Manual } | ForEach-Object { $_.Dns } | Select-Object -First 1)
    if (-not $used) { return $null }
    foreach ($p in $DnsList) { if ($p.V4 -contains $used[0]) { return $p } }
    return @{ Id = 'outro'; Name = $used[0] }
}
$DnsTestCode = @'
param($inp)
$res = @{}
$names = @('www.google.com', 'www.microsoft.com', 'www.wikipedia.org', 'www.cloudflare.com')
foreach ($s in $inp.Servers) {
    $times = New-Object System.Collections.ArrayList
    foreach ($n in $names) {
        try { $sw = [Diagnostics.Stopwatch]::StartNew(); Resolve-DnsName -Name $n -Server $s.Ip -DnsOnly -NoHostsFile -Type A -QuickTimeout -ErrorAction Stop | Out-Null; [void]$times.Add($sw.Elapsed.TotalMilliseconds) } catch {}
    }
    if ($times.Count) { $sorted = @($times | Sort-Object); $res[$s.Id] = [math]::Round($sorted[[int][math]::Floor($sorted.Count / 2)]) } else { $res[$s.Id] = -1 }
}
$res
'@
$script:DnsTimes = @{}; $script:DnsTestedAt = $null
function Start-DnsTest {
    $servers = @($DnsList | ForEach-Object { @{ Id = $_.Id; Ip = $_.V4[0] } })
    $ad = @(Get-NetAdapters | Where-Object { $_.Primary } | Select-Object -First 1)
    if ($ad -and $ad[0].Dns.Count) { $servers += @{ Id = 'atual'; Ip = $ad[0].Dns[0] } }
    [void](Start-BgJob 'dns' $DnsTestCode @{ Servers = $servers } {
        param($res, $err)
        if ($res) { $script:DnsTimes = $res; $script:DnsTestedAt = Get-Date }
        if ($script:CurrentPage -eq 'Rede' -and -not $script:Busy) { Show-Page 'Rede' $ui.Scroll.VerticalOffset }
    })
}
function Set-DnsProvider($p) {
    $ads = @(Get-NetAdapters)
    if ($p) {
        $txt = (T 'O Janus troca o DNS do cabo e do Wi-Fi para {0} ({1}). Para voltar, use "Voltar ao automático".') -f $p.Name, ($p.V4 -join ' / ')
        $txt += "`n`n" + ((T 'Privacidade: ao usar {0}, os endereços que você acessa passam pelos servidores de {1} e seguem a política de privacidade dessa empresa. O Janus não tem ligação com ela e não se responsabiliza pelo serviço.') -f $p.Name, (T $p.Who))
        $r = Show-Choice 'DNS' ((T 'Usar {0}?') -f $p.Name) $txt @(@('yes', 'Usar este DNS', 'Accent'), @('no', 'Cancelar', 'Ghost')) 'info'
        if ($r -ne 'yes') { return }
    }
    $W.Cursor = [System.Windows.Input.Cursors]::Wait
    try {
        Ensure-RestorePoint
        foreach ($a in $ads) {
            Write-Log ('DNS antes em {0}: {1}{2}' -f $a.Name, ($a.Dns -join ', '), $(if ($a.Manual) { ' (manual)' } else { ' (automático)' }))
            $dohKey = "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\$($a.Guid)\DohInterfaceSettings"
            if ($p) {
                Set-DnsClientServerAddress -InterfaceIndex $a.Index -ServerAddresses @($p.V4 + $p.V6)
                if ($p.Doh) {
                    foreach ($ip in @($p.V4 + $p.V6)) {
                        try { if (-not (Get-DnsClientDohServerAddress -ServerAddress $ip -ErrorAction SilentlyContinue)) { Add-DnsClientDohServerAddress -ServerAddress $ip -DohTemplate $p.Doh -AllowFallbackToUdp $true -AutoUpgrade $true -ErrorAction Stop } } catch { Write-Log ('DoH não registrado para ' + $ip + ': ' + $_.Exception.Message) }
                        $sub = $(if ($ip -match ':') { 'Doh6' } else { 'Doh' })
                        try { New-Item -Path "$dohKey\$sub\$ip" -Force | Out-Null; New-ItemProperty -Path "$dohKey\$sub\$ip" -Name 'DohFlags' -Value 1 -PropertyType QWord -Force | Out-Null } catch {}
                    }
                }
            } else {
                Set-DnsClientServerAddress -InterfaceIndex $a.Index -ResetServerAddresses
                if (Test-Path -LiteralPath $dohKey) { Remove-Item -LiteralPath $dohKey -Recurse -Force -ErrorAction SilentlyContinue }
            }
        }
        Clear-DnsClientCache
        Write-Log $(if ($p) { 'DNS trocado para ' + $p.Name } else { 'DNS voltou ao automático (do provedor)' })
        Show-Toast $(if ($p) { (T 'DNS em uso: {0}') -f $p.Name } else { 'DNS voltou ao automático' })
    } catch {
        Write-Log ('ERRO ao trocar o DNS: ' + $_.Exception.Message)
        Show-Choice 'DNS' 'Não consegui trocar o DNS' $_.Exception.Message @(@('ok', 'Ok', 'Accent')) 'crit' | Out-Null
    } finally { $W.Cursor = $null }
    Show-Page 'Rede' $ui.Scroll.VerticalOffset
}
function Add-DnsSection {
    $ads = @(Get-NetAdapters)
    $cur = Get-CurrentDnsProvider $ads
    Add-Body (New-Section 'DNS SEGURO')
    $info = New-Card; $info.Padding = '18,14,18,14'
    $isp = New-Object System.Windows.Controls.StackPanel
    $isp.Children.Add((New-Text 'O DNS é o "catálogo" que transforma nomes de sites em endereços. Trocar por um DNS público pode trazer privacidade (o provedor de internet deixa de ver quais sites você acessa, quando há criptografia), proteção contra sites maliciosos e, às vezes, respostas mais rápidas.' 12.5 '#AEB6C4')) | Out-Null
    $neg = New-Text 'Pode piorar: o DNS do provedor às vezes manda para servidores de vídeo e downloads mais próximos; telas de login de Wi-Fi público podem falhar; e quem usa o DNS passa a ver os sites que você acessa. O ping do jogo não muda.' 12 '#8B94A5'; $neg.Margin = '0,6,0,0'; $isp.Children.Add($neg) | Out-Null
    $now = New-Text $(if ($cur) { (T 'Em uso agora: {0}') -f $cur.Name } else { 'Em uso agora: automático (DNS do provedor de internet)' }) 12.5 '#E6E9EF' 'SemiBold'; $now.Margin = '0,8,0,0'; $isp.Children.Add($now) | Out-Null
    $info.Child = $isp; Add-Body $info
    # barra: testar de novo / automático
    $bar = New-Object System.Windows.Controls.WrapPanel; $bar.Margin = '0,0,0,8'
    $bar.Children.Add((New-SmallToggle ([string][char]0xE72C) 'Testar de novo' 'Mede quanto cada DNS demora para responder agora, a partir desta conexão.' { Start-DnsTest; Show-Toast 'Testando os DNS...' })) | Out-Null
    $bar.Children.Add((New-SmallToggle $(if ($script:Config.DnsAuto) { [string][char]0xE8FB } else { [string][char]0xE711 }) $(if ($script:Config.DnsAuto) { 'Atualizar sozinho: ligado (5 min)' } else { 'Atualizar sozinho: desligado' }) 'Repete o teste a cada 5 minutos enquanto esta aba estiver aberta. É leve: poucas consultas pequenas.' {
        $script:Config.DnsAuto = -not $script:Config.DnsAuto; Save-Config; Show-Page 'Rede' $ui.Scroll.VerticalOffset })) | Out-Null
    if ($cur) { $bar.Children.Add((New-SmallToggle ([string][char]0xE7A7) 'Voltar ao automático' 'Volta a usar o DNS do provedor de internet em todas as conexões.' { Set-DnsProvider $null })) | Out-Null }
    if ($script:DnsTestedAt) { $tt = New-Text ((T 'Testado às {0}') -f $script:DnsTestedAt.ToString('HH:mm:ss')) 11.5 '#6F7889'; $tt.VerticalAlignment = 'Center'; $tt.Margin = '4,6,0,0'; $bar.Children.Add($tt) | Out-Null }
    elseif ($script:BgJobs.ContainsKey('dns')) { $tt = New-Text 'Testando...' 11.5 '#F59E0B'; $tt.Margin = '4,6,0,0'; $bar.Children.Add($tt) | Out-Null }
    Add-Body $bar
    $valid = @($script:DnsTimes.Values | Where-Object { $_ -ge 0 })
    $best = $(if ($valid.Count) { ($valid | Measure-Object -Minimum).Minimum } else { -2 })
    $ordered = @($DnsList | Sort-Object { $v = $script:DnsTimes[$_.Id]; if ($null -eq $v -or $v -lt 0) { 99999 } else { $v } })
    $rank = 0
    foreach ($p in $ordered) {
        $rank++
        $c = New-Card; $c.Padding = '16,12,14,12'; $c.Margin = '0,0,12,8'
        if ($cur -and $cur.Id -eq $p.Id) { $c.BorderBrush = Brush '#1F5C45' }
        $g = New-Object System.Windows.Controls.Grid; Grid-Cols $g @('Auto', '*', 'Auto', 'Auto')
        $num = New-Object System.Windows.Controls.Border; $num.Width = 34; $num.Height = 34; $num.CornerRadius = 8; $num.BorderBrush = Brush '#2A303C'; $num.BorderThickness = 1; $num.Margin = '0,0,14,0'; $num.VerticalAlignment = 'Top'
        $nt = New-Text ([string]$rank) 14 '#E6E9EF' 'SemiBold'; $nt.HorizontalAlignment = 'Center'; $nt.VerticalAlignment = 'Center'; $num.Child = $nt; Put $g $num 0
        $sp = New-Object System.Windows.Controls.StackPanel; $sp.Margin = '0,0,12,0'
        $hr = New-Object System.Windows.Controls.WrapPanel
        $nm = New-Text $p.Name 14 '#E6E9EF' 'SemiBold'; $nm.Margin = '0,0,10,0'; $nm.TextWrapping = 'NoWrap'; $hr.Children.Add($nm) | Out-Null
        $ip = New-Text ($p.V4 -join ' / ') 12 '#7F8899'; $ip.Margin = '0,2,10,0'; $ip.TextWrapping = 'NoWrap'; $hr.Children.Add($ip) | Out-Null
        $v = $script:DnsTimes[$p.Id]
        if ($null -ne $v -and $v -ge 0 -and $v -eq $best) { $hr.Children.Add((New-Badge '⚡ Mais rápido' '#22C55E')) | Out-Null }
        if ($cur -and $cur.Id -eq $p.Id) { $hr.Children.Add((New-Badge 'Em uso' '#60A5FA')) | Out-Null }
        $sp.Children.Add($hr) | Out-Null
        $wp = New-Object System.Windows.Controls.WrapPanel; $wp.Margin = '0,6,0,0'
        $wp.Children.Add((New-Badge $p.Filter $(if ($p.Filter -eq 'Sem filtro') { '#94A3B8' } else { '#2DD4BF' }))) | Out-Null
        $wp.Children.Add((New-Badge $(if ($p.Doh) { 'Criptografado (DoH)' } else { 'Sem criptografia' }) $(if ($p.Doh) { '#22C55E' } else { '#F59E0B' }))) | Out-Null
        if ($p.V6.Count) { $wp.Children.Add((New-Badge 'IPv6' '#94A3B8')) | Out-Null }
        $sp.Children.Add($wp) | Out-Null
        if ($p.Note) { $nn = New-Text $p.Note 11.5 '#F59E0B'; $nn.Margin = '0,4,0,0'; $sp.Children.Add($nn) | Out-Null }
        $pv = New-Text ((T 'Privacidade: os endereços que você acessa passam pelos servidores de {0}. O Janus não tem ligação com essa empresa e não se responsabiliza pelo serviço.') -f (T $p.Who)) 11 '#6F7889'; $pv.Margin = '0,4,0,0'; $sp.Children.Add($pv) | Out-Null
        Put $g $sp 1
        $ms = New-Text $(if ($null -eq $v) { '—' } elseif ($v -lt 0) { T 'sem resposta' } else { '{0} ms' -f $v }) 15 $(if ($null -ne $v -and $v -ge 0 -and $v -eq $best) { '#22C55E' } elseif ($null -ne $v -and $v -lt 0) { '#EF4444' } else { '#E6E9EF' }) 'SemiBold'
        $ms.VerticalAlignment = 'Center'; $ms.Margin = '0,0,14,0'; $ms.TextWrapping = 'NoWrap'; $ms.ToolTip = (T 'Tempo para responder uma consulta, medido a partir desta conexão (mediana de 4).'); Put $g $ms 2
        if ($cur -and $cur.Id -eq $p.Id) { $b = New-ActionButton 'Voltar ao automático' 'undo' $null; $b.add_Click({ Set-DnsProvider $null }) }
        else { $b = New-ActionButton 'Usar este DNS' 'do' $p; $b.add_Click({ Set-DnsProvider $this.Tag }) }
        Put $g $b 3
        $c.Child = $g; Add-Body $c
    }
    if ($script:DnsTimes.ContainsKey('atual') -and $script:DnsTimes['atual'] -ge 0) {
        $at = New-Text ((T 'Para comparar: o DNS em uso agora respondeu em {0} ms.') -f $script:DnsTimes['atual']) 12 '#8B94A5'; $at.Margin = '2,4,0,0'; Add-Body $at
    }
}

# Teste de velocidade por conexão (servidores da Cloudflare)
$script:SpeedResults = @{}
$SpeedCode = @'
param($inp)
$r = @{ Index = $inp.Index; Ok = $false; Error = '' }
try {
    $pg = [JanusNet]::Ping('speed.cloudflare.com', $inp.V4, 8); $r.Ping = [math]::Round($pg[0]); $r.Jitter = [math]::Round($pg[1], 1)
    $dl = [JanusNet]::Download($inp.V4, $inp.V6, 8, 4); $r.Down = [math]::Round($dl[0], 1); $r.DownMB = [math]::Round($dl[1])
    $ul = [JanusNet]::Upload($inp.V4, $inp.V6, 6, 3); $r.Up = [math]::Round($ul[0], 1); $r.UpMB = [math]::Round($ul[1])
    $r.Ok = $true
} catch { $r.Error = $_.Exception.Message; if ($_.Exception.InnerException) { $r.Error = $_.Exception.InnerException.Message } }
$r.At = Get-Date
$r
'@
function Start-SpeedTest($a) {
    if (@($script:BgJobs.Keys | Where-Object { $_ -like 'speed-*' }).Count) { Show-Toast 'Já tem um teste rodando. Espere ele terminar.'; return }
    if (-not $a.Primary -and -not $script:Config.SpeedWarnOff) {
        $d = New-StyledWindow 'Teste de velocidade' 560
        $root = New-Object System.Windows.Controls.StackPanel; $root.Margin = '26,22,26,22'
        $root.Children.Add((New-Text ((T 'Testar {0} sem trocar de conexão') -f $a.Name) 18 '#E6E9EF' 'SemiBold')) | Out-Null
        $tx = New-Text ((T 'O Janus vai mandar o teste pela conexão "{0}", mesmo com a outra ligada. Durante uns 20 segundos a internet pode ficar mais lenta. Se o Windows não deixar usar essa conexão, desconecte a outra (por exemplo, o cabo) por um momento: a internet cai até o Windows trocar de conexão, e aí é só testar de novo.') -f $a.Name) 13 '#AEB6C4'
        $tx.Margin = '0,10,0,14'; $tx.LineHeight = 19; $root.Children.Add($tx) | Out-Null
        $cb = New-Object System.Windows.Controls.CheckBox; $cb.Content = (T 'Não mostrar de novo'); $cb.Foreground = Brush '#8B94A5'; $root.Children.Add($cb) | Out-Null
        $br = New-Object System.Windows.Controls.StackPanel; $br.Orientation = 'Horizontal'; $br.HorizontalAlignment = 'Right'; $br.Margin = '0,16,0,0'
        $b1 = New-Button 'Testar' 'Accent' 'yes'; $b1.Margin = '8,0,0,0'; $b1.add_Click({ $w2 = [System.Windows.Window]::GetWindow($this); $w2.Tag = 'yes'; $w2.DialogResult = $true })
        $b2 = New-Button 'Cancelar' 'Ghost' 'no'; $b2.Margin = '8,0,0,0'; $b2.add_Click({ [System.Windows.Window]::GetWindow($this).DialogResult = $false })
        $br.Children.Add($b2) | Out-Null; $br.Children.Add($b1) | Out-Null; $root.Children.Add($br) | Out-Null
        $d.Content = $root; $d.Tag = ''
        if ($Teste) { $d.Close(); return }
        $wasBusy = $script:Busy; $script:Busy = $true; try { [void]$d.ShowDialog() } finally { $script:Busy = $wasBusy }
        if ($cb.IsChecked) { $script:Config.SpeedWarnOff = $true; Save-Config }
        if ($d.Tag -ne 'yes') { return }
    }
    $script:SpeedResults[$a.Index] = @{ Running = $true }
    Write-Log ('Teste de velocidade iniciado em ' + $a.Name)
    [void](Start-BgJob ('speed-' + $a.Index) $SpeedCode @{ Index = $a.Index; V4 = $a.V4; V6 = $a.V6 } {
        param($res, $err)
        if ($res) { $script:SpeedResults[$res.Index] = $res; if ($res.Ok) { Write-Log ('Velocidade: {0} ms, {1} Mbps de download, {2} Mbps de upload' -f $res.Ping, $res.Down, $res.Up) } else { Write-Log ('Teste de velocidade falhou: ' + $res.Error) } }
        if ($script:CurrentPage -eq 'Rede' -and -not $script:Busy) { Show-Page 'Rede' $ui.Scroll.VerticalOffset }
    })
    Show-Page 'Rede' $ui.Scroll.VerticalOffset
}
function Add-SpeedSection {
    Add-Body (New-Section 'TESTE DE VELOCIDADE')
    $note = New-Text 'Mede ping, download e upload de cada conexão detectada. Usa os servidores da Cloudflare (speed.cloudflare.com), que veem o seu IP como qualquer site. O Janus não tem ligação com a Cloudflare. Cada teste gasta uns 100 a 400 MB de internet.' 12 '#8B94A5'
    $note.Margin = '2,0,12,10'; Add-Body $note
    $ads = @(Get-NetAdapters)
    if (-not $ads.Count) { Add-Body (New-Text 'Nenhuma conexão ativa encontrada.' 12.5 '#F59E0B'); return }
    $ug = New-Object System.Windows.Controls.Primitives.UniformGrid; $ug.Columns = [math]::Min(3, [math]::Max(2, $ads.Count))
    foreach ($a in $ads) {
        $c = New-Card; $c.Padding = '18,14,14,14'
        $sp = New-Object System.Windows.Controls.StackPanel
        $top = New-Object System.Windows.Controls.Grid; Grid-Cols $top @('Auto', '*', 'Auto')
        $gi = Glyph $(if ($a.Wifi) { [string][char]0xE701 } else { [string][char]0xE839 }) 20 '#60A5FA'; $gi.Margin = '0,0,12,0'; $gi.VerticalAlignment = 'Top'; Put $top $gi 0
        $ns = New-Object System.Windows.Controls.StackPanel
        $ns.Children.Add((New-Text $a.Name 14.5 '#E6E9EF' 'SemiBold')) | Out-Null
        $ns.Children.Add((New-Text ($a.Desc + '  |  ' + $a.Speed) 11.5 '#7F8899')) | Out-Null
        if ($a.Primary) { $pb = New-Badge 'Conexão principal' '#60A5FA'; $pb.Margin = '0,4,0,0'; $pb.HorizontalAlignment = 'Left'; $ns.Children.Add($pb) | Out-Null }
        Put $top $ns 1
        $r = $script:SpeedResults[$a.Index]
        $b = New-ActionButton $(if ($r -and $r.Running) { 'Testando...' } else { 'Testar' }) $(if ($r -and $r.Running) { 'off' } else { 'do' }) $a
        $b.add_Click({ Start-SpeedTest $this.Tag }); Put $top $b 2
        $sp.Children.Add($top) | Out-Null
        $res = New-Object System.Windows.Controls.StackPanel; $res.Margin = '0,10,0,0'
        if ($r -and $r.Running) { $res.Children.Add((New-Text 'Testando... (uns 20 segundos)' 13 '#F59E0B' 'SemiBold')) | Out-Null }
        elseif ($r -and $r.Ok) {
            $vals = New-Object System.Windows.Controls.Primitives.UniformGrid; $vals.Columns = 3
            foreach ($row in @(@('Ping', ('{0} ms' -f $r.Ping), ((T 'variação {0} ms') -f $r.Jitter)), @('Download', ('{0} Mbps' -f $r.Down), ('{0} MB' -f $r.DownMB)), @('Upload', ('{0} Mbps' -f $r.Up), ('{0} MB' -f $r.UpMB)))) {
                $cell = New-Object System.Windows.Controls.StackPanel
                $cell.Children.Add((New-Text $row[0] 11 '#7F8899' 'SemiBold')) | Out-Null
                $cell.Children.Add((New-Text $row[1] 16 '#E6E9EF' 'SemiBold')) | Out-Null
                $cell.Children.Add((New-Text $row[2] 10.5 '#6F7889')) | Out-Null
                $vals.Children.Add($cell) | Out-Null
            }
            $res.Children.Add($vals) | Out-Null
            $res.Children.Add((New-Text ((T 'Testado às {0}') -f $r.At.ToString('HH:mm:ss')) 11 '#5F6878')) | Out-Null
        } elseif ($r -and -not $r.Ok) {
            $res.Children.Add((New-Text ((T 'O teste falhou: {0}') -f $r.Error) 12 '#EF4444')) | Out-Null
            if (-not $a.Primary) { $hint = New-Text 'O Windows pode não ter deixado usar esta conexão com a outra ligada. Desconecte a outra por um momento e teste de novo.' 11.5 '#F59E0B'; $hint.Margin = '0,4,0,0'; $res.Children.Add($hint) | Out-Null }
        } else { $res.Children.Add((New-Text 'Ainda não testado.' 12 '#6F7889')) | Out-Null }
        $sp.Children.Add($res) | Out-Null
        $c.Child = $sp; $ug.Children.Add($c) | Out-Null
    }
    Add-Body $ug
}
function Build-Rede {
    if ($script:Config.NavMode -eq 'categorias') { Build-Page 'Rede'; Add-Separator }
    Add-SpeedSection
    Add-Separator
    Add-FailoverSection
    Add-Separator
    Add-DnsSection
    if (-not $script:DnsTestedAt -and -not $script:BgJobs.ContainsKey('dns')) { Start-DnsTest }
}

# ---------- monitor de hardware (só o que o Windows e o driver de vídeo informam, sem programas de terceiros) ----------
$MonLevels = [ordered]@{ off = @('Desligado', 0, 'Lê só ao abrir e quando você clica em Atualizar.'); leve = @('Leve', 30, 'Lê a cada 30 segundos. Quase não gasta nada.'); normal = @('Normal', 5, 'Lê a cada 5 segundos. Bom para o dia a dia.'); real = @('Tempo real', 1, 'Lê a cada 1 segundo. Em PCs mais fracos, a leitura constante pode causar lentidão ou pequenos travamentos.') }
$MonCode = @'
param($inp)
$ErrorActionPreference = 'SilentlyContinue'
$r = @{ At = Get-Date }
$p = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'"
if ($p) { $r.Cpu = [int]$p.PercentProcessorTime }
$os = Get-CimInstance Win32_OperatingSystem
if ($os) { $tot = [double]$os.TotalVisibleMemorySize; $free = [double]$os.FreePhysicalMemory; $r.RamTotal = [math]::Round($tot / 1MB, 1); $r.RamUsed = [math]::Round(($tot - $free) / 1MB, 1); $r.Ram = [int](100 * ($tot - $free) / $tot) }
$d = Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk -Filter "Name='_Total'"
if ($d) { $r.DiskBusy = [int][math]::Max(0, 100 - [int]$d.PercentIdleTime) }
$v = Get-Volume -DriveLetter ($env:SystemDrive.TrimEnd(':'))
if ($v -and $v.Size) { $r.DiskUsedPct = [int](100 * ($v.Size - $v.SizeRemaining) / $v.Size); $r.DiskFree = [math]::Round($v.SizeRemaining / 1GB) }
if ($inp.Smi) {
    $line = & $inp.Smi --query-gpu=name,utilization.gpu,temperature.gpu,fan.speed,power.draw,memory.used,memory.total --format=csv,noheader,nounits 2>$null | Select-Object -First 1
    if ($line) { $x = $line -split ',\s*'; $r.Gpu = @{ Name = $x[0]; Use = [int][double]$x[1]; Temp = [int][double]$x[2]; Fan = $(if ($x[3] -match '^\d') { [int][double]$x[3] } else { $null }); Power = $(if ($x[4] -match '^\d') { [int][double]$x[4] } else { $null }); MemUsed = [double]$x[5]; MemTotal = [double]$x[6] } }
}
if ($inp.Disks) {
    $r.Ssd = @(Get-PhysicalDisk | ForEach-Object { $c = $_ | Get-StorageReliabilityCounter; @{ Name = $_.FriendlyName; Temp = $c.Temperature; Wear = $c.Wear } } | Where-Object { $_.Temp -or $null -ne $_.Wear })
}
$nis = @(Get-CimInstance Win32_PerfFormattedData_Tcpip_NetworkInterface | Where-Object { $_.CurrentBandwidth -gt 0 -and $_.Name -notmatch 'isatap|Teredo|Loopback|vEthernet|Hyper-V|VPN|TAP|WireGuard|ExitLag' })
if ($nis.Count) {
    $rx = ($nis | Measure-Object BytesReceivedPersec -Sum).Sum * 8 / 1e6; $tx = ($nis | Measure-Object BytesSentPersec -Sum).Sum * 8 / 1e6
    $bw = ($nis | Measure-Object CurrentBandwidth -Maximum).Maximum / 1e6
    $r.NetRx = [math]::Round($rx, 1); $r.NetTx = [math]::Round($tx, 1); $r.NetPct = [int][math]::Min(100, 100 * [math]::Max($rx, $tx) / [math]::Max(1, $bw))
}
$tz = Get-CimInstance Win32_PerfFormattedData_Counters_ThermalZoneInformation | Where-Object { $_.Temperature -gt 273 } | Select-Object -First 1
if ($tz) { $r.CpuTemp = [int]($tz.Temperature - 273.15) }
$r
'@
$script:Mon = $null; $script:MonAt = [datetime]::MinValue; $script:MonDiskAt = [datetime]::MinValue; $script:MonUI = $null
$script:SmiPath = @("$env:windir\System32\nvidia-smi.exe", "$env:ProgramFiles\NVIDIA Corporation\NVSMI\nvidia-smi.exe") | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
function Start-MonRead {
    # discos (SMART) mudam devagar: lidos no máximo a cada 60 s
    $disks = ((Get-Date) - $script:MonDiskAt).TotalSeconds -ge 60
    [void](Start-BgJob -Keep 'mon' $MonCode @{ Smi = $script:SmiPath; Disks = $disks } {
        param($res, $err)
        if (-not $res) { return }
        if (-not $res.Ssd -and $script:Mon -and $script:Mon.Ssd) { $res.Ssd = $script:Mon.Ssd } else { $script:MonDiskAt = Get-Date }
        $script:Mon = $res; $script:MonAt = Get-Date
        Apply-Sims
        Update-MonTiles
        Check-Alerts
    })
}
# nível de cada leitura: ok / warn / crit
function Get-MonLevel([string]$kind, $v) {
    if ($null -eq $v) { return 'ok' }
    switch ($kind) {
        'gputemp' { if ($v -ge 90) { 'crit' } elseif ($v -ge 83) { 'warn' } else { 'ok' } }
        'cputemp' { if ($v -ge 95) { 'crit' } elseif ($v -ge 85) { 'warn' } else { 'ok' } }
        'ssdtemp' { if ($v -ge 70) { 'crit' } elseif ($v -ge 60) { 'warn' } else { 'ok' } }
        'space'   { if ($v -ge 90) { 'crit' } elseif ($v -ge 80) { 'warn' } else { 'ok' } }
        'wear'    { if ($v -ge 95) { 'crit' } elseif ($v -ge 80) { 'warn' } else { 'ok' } }
        'ram'     { if ($v -ge 95) { 'crit' } elseif ($v -ge 90) { 'warn' } else { 'ok' } }
        default   { 'ok' }
    }
}
$MonHints = @{ gputemp = 'Placa de vídeo muito quente. Veja se as ventoinhas estão girando e se o gabinete tem ventilação.'; cputemp = 'Processador muito quente. Confira o cooler e a pasta térmica.'; ssdtemp = 'SSD muito quente. Melhore a ventilação perto dele.'; space = 'Disco quase cheio. Com pouco espaço o Windows fica lento e atualizações falham. Use Manutenção > Limpar arquivos temporários ou apague o que não usa.'; wear = 'O SSD está perto do fim da vida útil estimada. Faça backup dos seus arquivos.'; ram = 'Memória quase cheia. Feche programas que não está usando.' }
function New-MonTile([string]$glyph, [string]$title, [string]$alert = '') {
    $c = New-Card; $c.Padding = '16,12,16,12'
    $sp = New-Object System.Windows.Controls.StackPanel
    $hr = New-Object System.Windows.Controls.Grid; Grid-Cols $hr @('Auto', '*', 'Auto', 'Auto')
    if ($glyph.Length -gt 1) {
        # mais de um ícone (ex.: cabo e Wi-Fi conectados)
        $gi = New-Object System.Windows.Controls.StackPanel; $gi.Orientation = 'Horizontal'
        foreach ($ch in $glyph.ToCharArray()) { $x = Glyph ([string]$ch) 14 '#8EA3C8'; $x.Margin = '0,0,5,0'; $gi.Children.Add($x) | Out-Null }
    } else { $gi = Glyph $glyph 14 '#8EA3C8' }
    $gi.Margin = '0,0,8,0'; $gi.VerticalAlignment = 'Center'; Put $hr $gi 0
    $tt = New-Text $title 12 '#8B94A5'; $tt.VerticalAlignment = 'Center'; Put $hr $tt 1
    $bb = $null
    if ($alert) {
        # sininho: avisar quando ESTE item ficar vermelho
        $on = (@($script:Config.NotifyItems) -contains $alert)
        $bb = New-Object System.Windows.Controls.Button; $bb.Style = $W.FindResource('Ghost'); $bb.Padding = '6,2'; $bb.Margin = '0,0,8,0'; $bb.Tag = $alert; $bb.Background = Brush $(if ($on) { '#2A2112' } else { 'Transparent' })
        $bt = New-Object System.Windows.Controls.TextBlock; $bt.Text = [string][char]0xEA8F; $bt.FontFamily = 'Segoe Fluent Icons, Segoe MDL2 Assets'; $bt.FontSize = 12; $bt.Foreground = Brush $(if ($on) { '#F59E0B' } else { '#5F6878' }); $bb.Content = $bt
        $bb.ToolTip = (T $(if ($on) { 'Avisando quando este item ficar vermelho. Clique para parar.' } else { 'Clique para ser avisado quando este item ficar vermelho.' }))
        $bb.add_Click({
            $k = [string]$this.Tag; $list = @($script:Config.NotifyItems | Where-Object { $_ })
            if ($list -contains $k) { $list = @($list | Where-Object { $_ -ne $k }) } else { $list += $k }
            $script:Config.NotifyItems = $list; Save-Config; Write-Log ('Avisos do hardware: ' + $(if ($list.Count) { $list -join ', ' } else { 'nenhum' }))
            Show-Page 'Inicio' $ui.Scroll.VerticalOffset
        })
        Put $hr $bb 2
    }
    $lv = Glyph ([string]$LevelStyle['ok'][0]) 13 $LevelStyle['ok'][1]; $lv.VerticalAlignment = 'Center'; Put $hr $lv 3
    $sp.Children.Add($hr) | Out-Null
    $big = New-Text '…' 20 '#E6E9EF' 'SemiBold'; $big.Margin = '0,6,0,0'; $sp.Children.Add($big) | Out-Null
    $track = New-Object System.Windows.Controls.Border; $track.Height = 8; $track.CornerRadius = 4; $track.Margin = '0,8,0,4'
    $track.Background = Brush '#06080C'; $track.BorderBrush = Brush '#1E2532'; $track.BorderThickness = 1
    $bg = New-Object System.Windows.Controls.Grid
    $c0 = New-Object System.Windows.Controls.ColumnDefinition; $c1 = New-Object System.Windows.Controls.ColumnDefinition; $bg.ColumnDefinitions.Add($c0); $bg.ColumnDefinitions.Add($c1)
    $fill = New-Object System.Windows.Controls.Border; $fill.CornerRadius = 3; [System.Windows.Controls.Grid]::SetColumn($fill, 0); $bg.Children.Add($fill) | Out-Null
    $track.Child = $bg; $sp.Children.Add($track) | Out-Null
    $sub = New-Text '' 11.5 '#7F8899'; $sub.Margin = '0,2,0,0'; $sp.Children.Add($sub) | Out-Null
    $c.Child = $sp
    return @{ Card = $c; Big = $big; Sub = $sub; Lv = $lv; Fill = $fill; C0 = $c0; C1 = $c1; Bell = $bb }
}
function Set-MonTile($tile, [string]$big, [string]$sub, [string]$lv = 'ok', [string]$hint = '', $pct = $null) {
    if (-not $tile) { return }
    $tile.Big.FontStyle = 'Normal'
    $tile.Big.Text = $big; $tile.Sub.Text = $sub
    $tile.Lv.Text = [string]$LevelStyle[$lv][0]; $tile.Lv.Foreground = Brush $LevelStyle[$lv][1]
    $tile.Card.BorderBrush = Brush $(if ($lv -eq 'crit') { '#7F1D1D' } elseif ($lv -eq 'warn') { '#78350F' } else { '#232A36' })
    if ($null -ne $pct) {
        $p = [math]::Max(0, [math]::Min(100, [double]$pct))
        $tile.C0.Width = New-Object System.Windows.GridLength ([math]::Max(0.001, $p)), 'Star'
        $tile.C1.Width = New-Object System.Windows.GridLength ([math]::Max(0.001, 100 - $p)), 'Star'
        $col = Get-HeatColor $p
        $tile.Fill.Background = New-Object System.Windows.Media.SolidColorBrush $col
        $tile.Big.Foreground = New-Object System.Windows.Media.SolidColorBrush $col
    } else {
        $tile.C0.Width = New-Object System.Windows.GridLength 0.001, 'Star'; $tile.C1.Width = New-Object System.Windows.GridLength 100, 'Star'
        $tile.Big.Foreground = Brush '#E6E9EF'
    }
    $tip = (Get-LevelHint $lv); if ($hint -and $lv -ne 'ok') { $tip = (T $hint) }
    $tile.Card.ToolTip = $tip; $tile.Lv.ToolTip = $tip
}
# ícone da rede conforme a conexão: cabo, Wi-Fi ou os dois (cabo primeiro)
$script:NetGlyph = ''; $script:NetGlyphAt = [datetime]::MinValue
function Get-NetGlyphs {
    if ($script:NetGlyph -and ((Get-Date) - $script:NetGlyphAt).TotalSeconds -lt 60) { return $script:NetGlyph }
    $up = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch 'Hyper-V|Virtual|Loopback|VPN|TAP|WireGuard|ExitLag|Bluetooth' })
    $wifi = @($up | Where-Object { $_.Name -match 'Wi-?Fi' -or $_.InterfaceDescription -match 'Wi-?Fi|Wireless|802\.11' })
    $g = ''; if ($up.Count -gt $wifi.Count) { $g += [char]0xE839 }; if ($wifi.Count) { $g += [char]0xE701 }
    if (-not $g) { $g = [string][char]0xE701 }
    $script:NetGlyph = $g; $script:NetGlyphAt = Get-Date; return $g
}
# número grande com uso e temperatura lado a lado (a temperatura na cor do nível)
function Set-BigTemp($tile, [string]$main, $pct, $temp, [string]$lv) {
    $tile.Big.Inlines.Clear()
    $r1 = New-Object System.Windows.Documents.Run $main; $r1.Foreground = New-Object System.Windows.Media.SolidColorBrush (Get-HeatColor ([double]$pct)); $tile.Big.Inlines.Add($r1)
    $r2 = New-Object System.Windows.Documents.Run '  |  '; $r2.Foreground = Brush '#3A4252'; $r2.FontWeight = 'Normal'; $tile.Big.Inlines.Add($r2)
    $r3 = New-Object System.Windows.Documents.Run ('{0} °C' -f $temp); $r3.Foreground = Brush $LevelStyle[$lv][1]; $tile.Big.Inlines.Add($r3)
}
function Update-MonTiles {
    $u = $script:MonUI; $m = $script:Mon
    if (-not $u -or -not $m -or $script:CurrentPage -ne 'Inicio') { return }
    # processador
    $ctl = $(if ($null -ne $m.CpuTemp) { Get-MonLevel 'cputemp' $m.CpuTemp } else { 'ok' })
    Set-MonTile $u.Cpu $(if ($null -ne $m.Cpu) { '{0}%' -f $m.Cpu } else { '—' }) $(if ($null -ne $m.CpuTemp) { T 'em uso | temperatura' } else { T 'em uso | temperatura: o Windows não informa neste PC' }) $ctl $MonHints.cputemp $m.Cpu
    if ($null -ne $m.CpuTemp -and $null -ne $m.Cpu) { Set-BigTemp $u.Cpu ('{0}%' -f $m.Cpu) $m.Cpu $m.CpuTemp $ctl }
    # sem temperatura não há o que avisar: o sininho do processador some
    if ($u.Cpu.Bell) { $u.Cpu.Bell.Visibility = $(if ($null -eq $m.CpuTemp) { 'Collapsed' } else { 'Visible' }) }
    if ($null -eq $m.CpuTemp) { $u.Cpu.Sub.Inlines.Clear(); $u.Cpu.Sub.Inlines.Add((New-Object System.Windows.Documents.Run (T 'em uso | temperatura: '))); $ri = New-Object System.Windows.Documents.Run (T 'indisponível'); $ri.FontStyle = 'Italic'; $u.Cpu.Sub.Inlines.Add($ri) }
    # memória
    Set-MonTile $u.Ram $(if ($null -ne $m.Ram) { '{0}%' -f $m.Ram } else { '—' }) $(if ($m.RamTotal) { (T '{0} de {1} GB em uso') -f (Fmt-Num $m.RamUsed), (Fmt-Num $m.RamTotal) } else { '' }) (Get-MonLevel 'ram' $m.Ram) $MonHints.ram $m.Ram
    # placa de vídeo
    if ($m.Gpu) {
        $g = $m.Gpu; $extra = @((T 'em uso | temperatura')); if ($null -ne $g.Fan) { $extra += ((T 'ventoinha {0}%') -f $g.Fan) }; if ($null -ne $g.Power) { $extra += ('{0} W' -f $g.Power) }
        $extra += ((T 'memória {0}/{1} GB') -f (Fmt-Num ($g.MemUsed / 1024)), (Fmt-Num ($g.MemTotal / 1024)))
        $lvG = Get-MonLevel 'gputemp' $g.Temp
        Set-MonTile $u.Gpu ('{0}%' -f $g.Use) ($extra -join '  |  ') $lvG $MonHints.gputemp $g.Use
        if ($null -ne $g.Temp) { Set-BigTemp $u.Gpu ('{0}%' -f $g.Use) $g.Use $g.Temp $lvG }
    } else { Set-MonTile $u.Gpu (T 'indisponível') (T 'Só placas NVIDIA por enquanto (pelo driver da NVIDIA).'); $u.Gpu.Big.FontStyle = 'Italic' }
    # disco do Windows
    Set-MonTile $u.Disk $(if ($null -ne $m.DiskUsedPct) { (T '{0}% cheio') -f $m.DiskUsedPct } else { '—' }) $(if ($null -ne $m.DiskFree) { (T '{0} GB livres | atividade {1}%') -f $m.DiskFree, $m.DiskBusy } else { '' }) (Get-MonLevel 'space' $m.DiskUsedPct) $MonHints.space $m.DiskUsedPct
    # SSD (barra = temperatura até 80 °C)
    $s = @($m.Ssd | Where-Object { $_ }) | Select-Object -First 1
    if ($s) {
        $lvT = Get-MonLevel 'ssdtemp' $s.Temp; $lvW = Get-MonLevel 'wear' $s.Wear
        $lv = $(if ('crit' -in $lvT, $lvW) { 'crit' } elseif ('warn' -in $lvT, $lvW) { 'warn' } else { 'ok' })
        Set-MonTile $u.Ssd $(if ($s.Temp) { '{0} °C' -f $s.Temp } else { '—' }) ($s.Name + $(if ($null -ne $s.Wear) { '  |  ' + ((T 'desgaste {0}%') -f $s.Wear) } else { '' })) $lv $(if ($lvW -ne 'ok') { $MonHints.wear } else { $MonHints.ssdtemp }) $(if ($s.Temp) { 100 * $s.Temp / 80 } else { $null })
    } else { Set-MonTile $u.Ssd (T 'indisponível') ''; $u.Ssd.Big.FontStyle = 'Italic' }
    # rede (barra = uso da velocidade do adaptador)
    if ($null -ne $m.NetRx) {
        Set-MonTile $u.Net ((T '↓ {0} Mbps') -f (Fmt-Num $m.NetRx)) ((T '↑ {0} Mbps | {1}% da conexão') -f (Fmt-Num $m.NetTx), $m.NetPct) 'ok' '' $m.NetPct
    } else { Set-MonTile $u.Net '—' (T 'Sem conexão ativa.') }
    $u.When.Text = ((T 'Leitura às {0}') -f $m.At.ToString('HH:mm:ss'))
}
function Show-MonMenu {
    $d = New-StyledWindow 'Monitoramento' 520
    $root = New-Object System.Windows.Controls.StackPanel; $root.Margin = '26,22,26,22'
    $root.Children.Add((New-Text 'Com que frequência ler o hardware?' 18 '#E6E9EF' 'SemiBold')) | Out-Null
    $sub = New-Text 'Vale só enquanto o Janus está aberto. Não mexe em nada no PC, só lê.' 12.5 '#9AA3B2'; $sub.Margin = '0,6,0,14'; $root.Children.Add($sub) | Out-Null
    foreach ($k in $MonLevels.Keys) {
        $lv = $MonLevels[$k]
        $b = New-Object System.Windows.Controls.Button; $b.Style = $W.FindResource($(if ($script:Config.MonLevel -eq $k) { 'Accent' } else { 'Ghost' })); $b.HorizontalContentAlignment = 'Left'; $b.Margin = '0,0,0,8'; $b.Padding = '14,9'; $b.Tag = $k
        $bs = New-Object System.Windows.Controls.StackPanel
        $t1 = New-Object System.Windows.Controls.TextBlock; $t1.Text = (T $lv[0]); $t1.FontSize = 14; $t1.FontWeight = 'SemiBold'; $t1.Foreground = Brush $(if ($script:Config.MonLevel -eq $k) { 'White' } else { '#E6E9EF' }); $bs.Children.Add($t1) | Out-Null
        $t2 = New-Object System.Windows.Controls.TextBlock; $t2.Text = (T $lv[2]); $t2.FontSize = 11.5; $t2.TextWrapping = 'Wrap'; $t2.Foreground = Brush $(if ($k -eq 'real') { '#F59E0B' } elseif ($script:Config.MonLevel -eq $k) { '#DCE7FF' } else { '#9AA3B2' }); $bs.Children.Add($t2) | Out-Null
        $b.Content = $bs
        $b.add_Click({ $w2 = [System.Windows.Window]::GetWindow($this); $w2.Tag = $this.Tag; $w2.DialogResult = $true })
        $root.Children.Add($b) | Out-Null
    }
    $d.Content = $root; $d.Tag = ''
    if ($Teste) { $d.Close(); return }
    $wasBusy = $script:Busy; $script:Busy = $true; try { [void]$d.ShowDialog() } finally { $script:Busy = $wasBusy }
    if ($d.Tag) {
        if ($d.Tag -eq 'real') {
            $r = Show-Choice 'Monitoramento' 'Ler em tempo real?' 'A leitura a cada segundo pode deixar PCs mais fracos lentos ou com pequenos travamentos, principalmente durante jogos. Se notar algo assim, volte para Normal.' @(@('yes', 'Usar tempo real', 'Accent'), @('no', 'Cancelar', 'Ghost')) 'warn'
            if ($r -ne 'yes') { return }
        }
        $script:Config.MonLevel = [string]$d.Tag; Save-Config; Write-Log ('Monitoramento: ' + $d.Tag)
        if ($script:CurrentPage -eq 'Inicio') { Show-Page 'Inicio' $ui.Scroll.VerticalOffset }
    }
}
function Add-MonSection {
    $hdr = New-Object System.Windows.Controls.Grid; Grid-Cols $hdr @('*', 'Auto'); $hdr.Margin = '0,4,12,0'
    Put $hdr (New-Section 'HARDWARE AGORA') 0
    $right = New-Object System.Windows.Controls.StackPanel; $right.Orientation = 'Horizontal'; $right.VerticalAlignment = 'Center'
    $when = New-Text '' 11 '#5F6878'; $when.VerticalAlignment = 'Center'; $when.Margin = '0,0,10,0'; $right.Children.Add($when) | Out-Null
    $nl = New-SmallToggle ([string][char]0xEA8F) 'Como avisar' 'Escolha como o Janus avisa e teste cada jeito. Para escolher O QUE avisar, use o sininho de cada item.' { Show-NotifySettings }
    $right.Children.Add($nl) | Out-Null
    $lvName = T $MonLevels[$script:Config.MonLevel][0]
    $right.Children.Add((New-SmallToggle ([string][char]0xE9D9) ((T 'Monitoramento: {0}') -f $lvName) 'Escolha de quanto em quanto tempo o hardware é lido, até em tempo real.' { Show-MonMenu })) | Out-Null
    Put $hdr $right 1
    Add-Body $hdr
    $ug = New-Object System.Windows.Controls.Primitives.UniformGrid; $ug.Columns = 3
    $u = @{ When = $when }
    foreach ($row in @(@('Cpu', [char]0xE950, 'Processador', 'cputemp'), @('Ram', [char]0xE964, 'Memória', 'ram'), @('Gpu', [char]0xE7F4, 'Placa de vídeo', 'gputemp'), @('Disk', [char]0xEDA2, 'Disco do Windows', ''), @('Ssd', [char]0xE958, 'SSD', 'ssd'), @('Net', (Get-NetGlyphs), 'Rede', ''))) {
        $tile = New-MonTile ([string]$row[1]) $row[2] $row[3]; $u[$row[0]] = $tile; $ug.Children.Add($tile.Card) | Out-Null
    }
    Add-Body $ug
    $script:MonUI = $u
    if ($script:Mon) { Update-MonTiles } else { $when.Text = (T 'Fazendo a leitura do hardware...') }
}

# ---------- segurança: desligar com aviso, timer, lembretes e "não perturbe" ----------
# O que dá para desligar: firewall (com timer real) e integridade de memória (vale após reiniciar).
# Antivírus e proteção contra adulteração: o Windows não deixa programas desligarem; só abrimos a tela dele.
# UAC: não oferecemos (quebra apps da Store e deixa qualquer programa virar administrador sem perguntar).
$SecInfo = @{
    firewall = @{ Name = 'Firewall'; Risk = 'Sem firewall, qualquer aparelho da rede pode tentar se conectar ao seu PC. Em Wi-Fi público isso é muito perigoso.'; Timer = $true }
    hvci     = @{ Name = 'Integridade de memória'; Risk = 'Sem ela, drivers maliciosos ou com falhas conseguem rodar no núcleo do Windows. Alguns jogos com anticheat podem exigir que fique ligada.'; Timer = $false }
    av       = @{ Name = 'Antivírus em tempo real'; Risk = 'Sem o antivírus, arquivos baixados e abertos não são examinados.'; Manual = $true }
    tamper   = @{ Name = 'Proteção contra adulteração'; Risk = 'Sem ela, programas maliciosos podem desligar o Defender sozinhos.'; Manual = $true }
}
function Get-SecOffList { @($script:Config.SecOff | Where-Object { $_ -and $_.Id }) }
function Save-SecOff($list) { $script:Config.SecOff = @($list); Save-Config }
function Show-SecurityDisable($c) {
    $info = $SecInfo[$c.Id]
    if (-not $info) {
        if ($c.Id -eq 'uac') { Show-Choice 'Segurança' 'O Janus não desliga o UAC' 'Desligar o Controle de Conta exige reiniciar, quebra os apps da Microsoft Store e deixa qualquer programa virar administrador sem perguntar. O risco não compensa, por isso essa opção não existe no Janus.' @(@('ok', 'Entendi', 'Accent')) 'info' | Out-Null }
        return
    }
    $d = New-StyledWindow 'Desativar proteção' 600
    $root = New-Object System.Windows.Controls.StackPanel; $root.Margin = '26,22,26,22'
    $root.Children.Add((New-Text ((T 'Desativar: {0}') -f (T $info.Name)) 19 '#E6E9EF' 'SemiBold')) | Out-Null
    $box = New-Object System.Windows.Controls.Border; $box.CornerRadius = 10; $box.Margin = '0,14,0,12'; $box.Padding = '16,12'; $box.Background = Brush '#2A1416'; $box.BorderBrush = Brush '#7F1D1D'; $box.BorderThickness = 1
    $bx = New-Object System.Windows.Controls.StackPanel
    $bx.Children.Add((New-Text 'ATENÇÃO: RECOMENDAMOS ESTRITAMENTE DEIXAR TODAS AS PROTEÇÕES DE SEGURANÇA LIGADAS.' 13.5 '#FCA5A5' 'Bold')) | Out-Null
    $rk = New-Text $info.Risk 12.5 '#FCA5A5'; $rk.Margin = '0,8,0,0'; $bx.Children.Add($rk) | Out-Null
    $rk2 = New-Text 'Desligue só se souber exatamente por quê, e religue assim que terminar. O Janus vai lembrar você.' 12.5 '#FCA5A5'; $rk2.Margin = '0,6,0,0'; $bx.Children.Add($rk2) | Out-Null
    $box.Child = $bx; $root.Children.Add($box) | Out-Null
    $durBox = $null
    if ($info.Manual) {
        $root.Children.Add((New-Text 'O Windows não deixa nenhum programa desligar isto (é uma proteção contra vírus). Se mesmo assim precisar, desligue na tela que vai abrir. O próprio Windows volta a ligar sozinho depois de um tempo.' 12.8 '#AEB6C4')) | Out-Null
    } elseif ($info.Timer) {
        $root.Children.Add((New-Text 'Por quanto tempo?' 12.8 '#AEB6C4' 'SemiBold')) | Out-Null
        $durBox = New-Object System.Windows.Controls.ComboBox; $durBox.Margin = '0,6,0,8'; $durBox.FontSize = 13
        foreach ($o in @('15 minutos', '1 hora', 'Até reiniciar o PC', 'Até eu religar')) { [void]$durBox.Items.Add((T $o)) }
        $durBox.SelectedIndex = 0; $root.Children.Add($durBox) | Out-Null
        $root.Children.Add((New-Text 'Com tempo marcado, o Windows religa sozinho mesmo com o Janus fechado.' 11.5 '#6F7889')) | Out-Null
    } else {
        $root.Children.Add((New-Text 'Vale depois de reiniciar o PC. Fica desligado até você religar (botão Ligar nesta mesma tela), e o Janus lembra você enquanto estiver desligado.' 12.8 '#AEB6C4')) | Out-Null
    }
    $cb = New-Object System.Windows.Controls.CheckBox; $cb.Content = (T 'Entendo os riscos e quero desativar mesmo assim'); $cb.Foreground = Brush '#E6E9EF'; $cb.Margin = '0,14,0,0'; $root.Children.Add($cb) | Out-Null
    $br = New-Object System.Windows.Controls.StackPanel; $br.Orientation = 'Horizontal'; $br.HorizontalAlignment = 'Right'; $br.Margin = '0,16,0,0'
    $bc = New-Button 'Manter ligado' 'Accent' 'no'; $bc.Margin = '8,0,0,0'; $bc.add_Click({ [System.Windows.Window]::GetWindow($this).DialogResult = $false })
    $bo = New-Button $(if ($info.Manual) { 'Abrir Segurança do Windows' } else { 'Desativar' }) 'Danger' 'yes'; $bo.Margin = '8,0,0,0'; $bo.IsEnabled = $false
    $bo.add_Click({ $w2 = [System.Windows.Window]::GetWindow($this); $w2.Tag = 'yes'; $w2.DialogResult = $true })
    $cb.Tag = $bo; $cb.add_Click({ $this.Tag.IsEnabled = [bool]$this.IsChecked })
    $br.Children.Add($bo) | Out-Null; $br.Children.Add($bc) | Out-Null; $root.Children.Add($br) | Out-Null
    $d.Content = $root; $d.Tag = ''
    if ($Teste) { $d.Close(); return }
    $wasBusy = $script:Busy; $script:Busy = $true; try { [void]$d.ShowDialog() } finally { $script:Busy = $wasBusy }
    if ($d.Tag -ne 'yes') { return }
    if ($info.Manual) { Start-Process 'windowsdefender://threatsettings'; Write-Log ('Segurança do Windows aberta para desligar: ' + $info.Name); return }
    $last = Show-Choice 'Último aviso' ((T 'Desativar {0} agora?') -f (T $info.Name)) 'Último aviso: o PC fica menos protegido a partir de agora. Recomendamos estritamente deixar ligado.' @(@('yes', 'Desativar', 'Danger'), @('no', 'Manter ligado', 'Accent')) 'crit'
    if ($last -ne 'yes') { return }
    $until = 'manual'; $W.Cursor = [System.Windows.Input.Cursors]::Wait
    try {
        Ensure-RestorePoint
        if ($c.Id -eq 'firewall') {
            Set-NetFirewallProfile -All -Enabled False
            $idx = $(if ($durBox) { $durBox.SelectedIndex } else { 3 })
            if ($idx -le 2) {
                $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -Command `"Set-NetFirewallProfile -All -Enabled True; Unregister-ScheduledTask -TaskName 'Religar firewall' -TaskPath '\Janus\' -Confirm:`$false`""
                if ($idx -eq 2) { $trg = New-ScheduledTaskTrigger -AtStartup; $until = 'reboot' }
                else { $at = (Get-Date).AddMinutes($(if ($idx -eq 0) { 15 } else { 60 })); $trg = New-ScheduledTaskTrigger -Once -At $at; $until = $at.ToString('o') }
                $pr = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
                $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
                Register-ScheduledTask -TaskName 'Religar firewall' -TaskPath '\Janus\' -Action $act -Trigger $trg -Principal $pr -Settings $set -Force | Out-Null
            }
        } elseif ($c.Id -eq 'hvci') {
            Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled' 0
            Add-Pending 'pc' $info.Name
        }
        $list = @(Get-SecOffList | Where-Object { $_.Id -ne $c.Id }) + @(@{ Id = $c.Id; Until = $until; At = (Get-Date).ToString('o') })
        Save-SecOff $list
        $script:SnapVersion++; $script:ForceFull = $true
        Write-Log ('PROTEÇÃO DESLIGADA pelo Janus: {0} (até: {1})' -f $info.Name, $until)
        Show-Toast ((T '{0} desligado. Religue assim que puder.') -f (T $info.Name))
    } catch {
        Write-Log ('ERRO ao desligar ' + $info.Name + ': ' + $_.Exception.Message)
        Show-Choice 'Segurança' 'Não consegui desativar' $_.Exception.Message @(@('ok', 'Ok', 'Accent')) 'crit' | Out-Null
    } finally { $W.Cursor = $null }
    Show-Page $script:CurrentPage $ui.Scroll.VerticalOffset
}
# Quando a verificação volta a ficar OK (religado pelo timer, pelo botão Ligar ou pelo Windows), sai da lista
function Sync-SecOff {
    $list = @(Get-SecOffList); if (-not $list.Count) { return }
    $keep = @()
    foreach ($s in $list) {
        $chk = $script:Checks | Where-Object { $_.Id -eq $s.Id } | Select-Object -First 1
        $ok = $(if ($chk) { Get-CheckOk $chk } else { $true })
        if ($ok) {
            Write-Log ('Proteção religada: ' + $SecInfo[$s.Id].Name)
            if ($s.Id -eq 'firewall') { try { Unregister-ScheduledTask -TaskName 'Religar firewall' -TaskPath '\Janus\' -Confirm:$false -ErrorAction Stop } catch {} }
        } else { $keep += $s }
    }
    if ($keep.Count -ne $list.Count) { Save-SecOff $keep }
}
function Test-Dnd { if (-not $script:Config.DndUntil) { return $false }; if ($script:Config.DndUntil -eq 'reboot') { return $script:Config.DndBoot -eq [string](Get-CimInstance Win32_OperatingSystem).LastBootUpTime }; try { return (Get-Date) -lt [datetime]$script:Config.DndUntil } catch { return $false } }
function Show-Dnd {
    $r = Show-Choice 'Não perturbe' 'Silenciar os lembretes de segurança?' 'Os lembretes do Janus sobre proteções desligadas param por um tempo. A proteção continua desligada: religue assim que puder.' @(@('1h', '1 hora', 'Ghost'), @('reboot', 'Até reiniciar', 'Ghost'), @('no', 'Cancelar', 'Accent')) 'warn'
    if ($r -notin '1h', 'reboot') { return }
    $last = Show-Choice 'Último aviso' 'Último aviso' 'Enquanto o "não perturbe" estiver ligado, o Janus não vai lembrar você das proteções desligadas. Recomendamos estritamente religar tudo antes de silenciar.' @(@('yes', 'Silenciar mesmo assim', 'Danger'), @('no', 'Cancelar', 'Accent')) 'crit'
    if ($last -ne 'yes') { return }
    if ($r -eq '1h') { $script:Config.DndUntil = (Get-Date).AddHours(1).ToString('o') } else { $script:Config.DndUntil = 'reboot'; $script:Config.DndBoot = [string](Get-CimInstance Win32_OperatingSystem).LastBootUpTime }
    Save-Config; Write-Log ('Não perturbe (segurança): ' + $script:Config.DndUntil)
    Show-Page $script:CurrentPage $ui.Scroll.VerticalOffset
}
function Add-SecOffBanner {
    $list = @(Get-SecOffList); if (-not $list.Count) { return }
    $c = New-Card; $c.Padding = '18,14,18,14'; $c.Background = Brush '#2A1416'; $c.BorderBrush = Brush '#7F1D1D'
    $g = New-Object System.Windows.Controls.Grid; Grid-Cols $g @('Auto', '*', 'Auto')
    $ic = Glyph ([string][char]0xEA39) 24 '#EF4444'; $ic.Margin = '0,0,14,0'; $ic.VerticalAlignment = 'Top'; Put $g $ic 0
    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Children.Add((New-Text 'PROTEÇÕES DESLIGADAS PELO JANUS' 14 '#FCA5A5' 'Bold')) | Out-Null
    foreach ($s in $list) {
        $when = $(if ($s.Until -eq 'manual') { T 'até você religar' } elseif ($s.Until -eq 'reboot') { T 'religa ao reiniciar o PC' } else { (T 'religa sozinho às {0}') -f ([datetime]$s.Until).ToString('HH:mm') })
        $sp.Children.Add((New-Text ('• ' + (T $SecInfo[$s.Id].Name) + ': ' + $when) 12.5 '#FCA5A5')) | Out-Null
    }
    $sp.Children.Add((New-Text 'Recomendamos estritamente religar tudo assim que possível.' 12 '#FCA5A5')) | Out-Null
    if (Test-Dnd) { $sp.Children.Add((New-Text 'Lembretes silenciados (não perturbe).' 11.5 '#F59E0B')) | Out-Null }
    Put $g $sp 1
    $bs = New-Object System.Windows.Controls.StackPanel; $bs.Orientation = 'Horizontal'; $bs.VerticalAlignment = 'Center'
    $b1 = New-Button 'Ir para Segurança' 'Accent'; $b1.Margin = '8,0,0,0'; $b1.add_Click({ Show-Page 'Seguranca' }); $bs.Children.Add($b1) | Out-Null
    if (-not (Test-Dnd)) { $b2 = New-Button 'Não perturbe' 'Ghost'; $b2.Margin = '8,0,0,0'; $b2.add_Click({ Show-Dnd }); $bs.Children.Add($b2) | Out-Null }
    Put $g $bs 2
    $c.Child = $g; Add-Body $c
}
$script:SecRemindAt = [datetime]::MinValue
function Invoke-SecReminder {
    if (-not @(Get-SecOffList).Count -or (Test-Dnd)) { return }
    if (((Get-Date) - $script:SecRemindAt).TotalMinutes -lt 15) { return }
    $script:SecRemindAt = Get-Date
    $names = (@(Get-SecOffList) | ForEach-Object { T $SecInfo[$_.Id].Name }) -join ', '
    Show-Toast ((T 'Lembrete: {0} continua desligado. Religue assim que puder.') -f $names)
}

# ---------- IAs e aba Jogos ----------
# O Janus não tem ligação com nenhuma dessas empresas. Tudo vai pelo site de cada uma (ou pelo Claude Code, se instalado).
$AiList = [ordered]@{
    # Ask: endereço que já abre com a pergunta escrita ({0} = pergunta). Sem Ask, a pergunta vai copiada para colar.
    claude   = @{ Name = 'Claude';   Who = 'Anthropic (EUA)'; Url = 'https://claude.ai/new'; Ask = 'https://claude.ai/new?q={0}'; Extra = ''; Plan = 'Gratuito com limite de uso. O Claude Code (resposta dentro do Janus) exige plano pago.' }
    chatgpt  = @{ Name = 'ChatGPT';  Who = 'OpenAI (EUA)'; Url = 'https://chatgpt.com/'; Ask = 'https://chatgpt.com/?q={0}'; Extra = ''; Plan = 'Gratuito com limite de uso. Os modelos mais avançados pedem plano pago.' }
    gemini   = @{ Name = 'Gemini';   Who = 'Google (EUA)'; Url = 'https://gemini.google.com/app'; Extra = ''; Plan = 'Gratuito com conta Google. Recursos avançados pedem plano pago.' }
    grok     = @{ Name = 'Grok';     Who = 'xAI (EUA)'; Url = 'https://grok.com/'; Ask = 'https://grok.com/?q={0}'; Extra = ''; Plan = 'Pede conta. Uso maior e modelos avançados pedem plano pago.' }
    deepseek = @{ Name = 'DeepSeek'; Who = 'DeepSeek (China)'; Url = 'https://chat.deepseek.com/'; Extra = 'Os dados ficam em servidores na China, e vários governos restringiram o uso desse serviço.'; Plan = 'Gratuito com conta.' }
}
function Get-AiPrivacy([string]$k) {
    $a = $AiList[$k]
    $s = (T 'Privacidade: o texto que você enviar vai para os servidores de {0} e segue a política de privacidade dessa empresa. O Janus não tem ligação com ela e não se responsabiliza pelas respostas.') -f (T $a.Who)
    if ($a.Extra) { $s += ' ' + (T $a.Extra) }
    return $s
}
$GamesCode = @'
param($inp)
$ErrorActionPreference = 'SilentlyContinue'
$out = New-Object System.Collections.ArrayList
function Add-Game($name, $src, $id, $icon = '') { $name = ([string]$name -replace '[®™©]', ''); if ($icon -and -not (Test-Path -LiteralPath $icon)) { $icon = '' }; if ($name -and $name -notmatch 'Redistributable|Steamworks|Proton|Steam Linux Runtime|SteamVR|DirectX|Visual C\+\+') { [void]$out.Add(@{ Name = $name.Trim(); Source = $src; Id = $id; Icon = $icon }) } }
# ícone pequeno que a própria Steam guarda no PC (appcache\librarycache\<id>\<código>.jpg)
function Get-SteamIcon($sp, $id) {
    $f = Get-ChildItem (Join-Path $sp "appcache\librarycache\$id") -File -Filter '*.jpg' -ErrorAction SilentlyContinue | Where-Object { $_.BaseName -match '^[0-9a-f]{40}$' } | Sort-Object Length | Select-Object -First 1
    if ($f) { return $f.FullName }
    $old = Join-Path $sp "appcache\librarycache\${id}_icon.jpg"; if (Test-Path $old) { return $old }
    return ''
}
# Steam
$sp = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
if ($sp) {
    $libs = @($sp -replace '/', '\')
    $vdf = Join-Path $libs[0] 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) { foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) { $libs += ($m.Groups[1].Value -replace '\\\\', '\') } }
    foreach ($l in ($libs | Select-Object -Unique)) {
        foreach ($acf in Get-ChildItem (Join-Path $l 'steamapps') -Filter 'appmanifest_*.acf' -ErrorAction SilentlyContinue) {
            $c = Get-Content $acf.FullName -Raw -Encoding UTF8; $n = [regex]::Match($c, '"name"\s+"([^"]+)"').Groups[1].Value; $id = [regex]::Match($c, '"appid"\s+"(\d+)"').Groups[1].Value
            Add-Game $n 'Steam' $id (Get-SteamIcon $libs[0] $id)
        }
    }
}
# Epic
foreach ($it in Get-ChildItem 'C:\ProgramData\Epic\EpicGamesLauncher\Data\Manifests' -Filter '*.item' -ErrorAction SilentlyContinue) {
    try { $j = Get-Content $it.FullName -Raw | ConvertFrom-Json; if ($j.bIsApplication -ne $false) { $ic = $(if ($j.InstallLocation -and $j.LaunchExecutable) { Join-Path $j.InstallLocation $j.LaunchExecutable } else { '' }); Add-Game $j.DisplayName 'Epic' '' $ic } } catch {}
}
# Xbox / Game Pass
foreach ($xr in @(Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Z]:\\$' } | ForEach-Object { Join-Path $_.Root 'XboxGames' } | Where-Object { Test-Path $_ })) { foreach ($d in Get-ChildItem $xr -Directory -ErrorAction SilentlyContinue) { if ($d.Name -ne 'GameSave') {
    # logo pequeno do jogo, indicado no MicrosoftGame.config
    $ic = ''; $cfgF = Join-Path $d.FullName 'Content\MicrosoftGame.config'
    if (Test-Path $cfgF) { try { $lg = [string]([xml](Get-Content $cfgF -Raw)).Game.ShellVisuals.Square44x44Logo; if ($lg) { $p = Join-Path (Split-Path $cfgF) $lg; if (-not (Test-Path $p)) { $p = @(Get-ChildItem (Split-Path $p) -Filter ([IO.Path]::GetFileNameWithoutExtension($p) + '*.png') -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName) }; $ic = [string]$p } } catch {} }
    Add-Game $d.Name 'Xbox' '' $ic
} } }
# Riot, Blizzard, EA, Ubisoft (pelos programas instalados)
$pubs = @{ 'Riot Games, Inc' = 'Riot'; 'Blizzard Entertainment' = 'Battle.net'; 'Electronic Arts' = 'EA'; 'Ubisoft' = 'Ubisoft' }
foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*') {
    foreach ($e in Get-ItemProperty $k -ErrorAction SilentlyContinue) {
        foreach ($p in $pubs.Keys) { if ($e.Publisher -like "$p*" -and $e.DisplayName -notmatch 'Launcher|Client|App|Battle\.net|Desktop|Connect|Riot Vanguard') { Add-Game $e.DisplayName $pubs[$p] '' ([string]$e.DisplayIcon -replace '"', '' -replace ',\s*-?\d+$', '') } }
    }
}
$seen = @{}; $list = @(foreach ($g in ($out | Sort-Object { $_.Name })) { $key = ($g.Name -replace '\s+', ' ').ToLower().Trim(); if (-not $seen[$key]) { $seen[$key] = 1; $g } })
@{ Games = $list }
'@
$script:Games = $null
# procura os jogos instalados (com os ícones) em segundo plano; roda ao abrir a aba Jogos e no botão "Procurar jogos"
$script:GameScanManual = $false
function Start-GameScan {
    [void](Start-BgJob 'jogos' $GamesCode @{} {
        param($res, $err)
        $script:Games = $(if ($res) { @($res.Games) } else { @() })
        $script:Games = @($script:Games) + @(Get-ManualGames | Where-Object { $mn = $_.Name; -not @($script:Games | Where-Object { $_.Name -eq $mn }).Count })
        if ($script:GameScanManual) { $script:GameScanManual = $false; Show-Toast ((T '{0} jogo(s) encontrado(s)') -f $script:Games.Count); Write-Log ('Jogos procurados de novo: ' + $script:Games.Count) }
        if ($script:CurrentPage -eq 'Jogos' -and -not $script:Busy) { Show-Page 'Jogos' $ui.Scroll.VerticalOffset }
    })
}
$GoalNames = [ordered]@{ fps = 'Máximo de FPS (competitivo)'; equil = 'Equilíbrio entre FPS e imagem'; qual = 'Melhor imagem possível' }
# Ficha do jogo em Markdown: dados do PC + pedido de três configurações (equilibrada, qualidade, desempenho máximo)
function New-GamePrompt($g) {
    # o "|" dos dados do PC quebraria a tabela do Markdown
    $pc0 = Get-PcInfo; $pc = @{}; foreach ($k in 'Cpu', 'Gpu', 'Ram', 'Tela', 'Monitor', 'Disco', 'Windows', 'Energia', 'Tipo') { $pc[$k] = ([string]$pc0[$k]) -replace '\s*\|\s*', ', ' }
    $hz = [regex]::Match([string]$pc.Tela, '(\d+) Hz').Groups[1].Value; if (-not $hz) { $hz = '60' }
    if ($script:Lang -eq 'pt') {
        return (@(
            "# Configuração de jogo: $($g.Name)", '',
            "Jogo **$($g.Name)** no PC (loja: $($g.Source)). Responda em português do Brasil.", '',
            '## O PC', '', '| Item | Valor |', '|---|---|',
            "| Processador | $($pc.Cpu) |", "| Placa de vídeo | $($pc.Gpu) |", "| Memória | $($pc.Ram) |", "| Tela | $($pc.Tela) |", "| Monitor | $($pc.Monitor) |",
            "| Disco do Windows | $($pc.Disco) |", "| Windows | $($pc.Windows) |", "| Plano de energia | $($pc.Energia) |", "| Tipo | $($pc.Tipo) |", '',
            '## O que eu quero', '',
            '1. Três configurações gráficas dentro do jogo, numa tabela só com as colunas: **Opção | Equilibrada | Qualidade | Desempenho máximo | Por quê**.',
            "   - **Equilibrada:** boa imagem com FPS estável perto da taxa do monitor ($hz Hz).",
            '   - **Qualidade:** a melhor imagem mantendo pelo menos 60 FPS estáveis.',
            '   - **Desempenho máximo:** o máximo de FPS e o menor atraso possível (competitivo).',
            '2. O FPS médio esperado em cada uma, neste hardware (estimativa).',
            '3. Ajustes no painel da placa de vídeo, só se fizerem diferença real neste jogo.',
            '4. Onde fica o arquivo de configuração do jogo.',
            '5. O que **não** devo mexer por causa do anticheat ou risco de banimento.', '',
            'Cite só opções que existem de verdade neste jogo. Se não tiver certeza de algo, diga isso em vez de inventar.'
        ) -join "`n")
    }
    $lang = @{ en = 'English'; zh = 'Simplified Chinese'; es = 'Spanish' }[$script:Lang]; if (-not $lang) { $lang = 'English' }
    @(
        "# Game settings: $($g.Name)", '',
        "Game **$($g.Name)** on PC (store: $($g.Source)). Please answer in $lang.", '',
        '## The PC', '', '| Item | Value |', '|---|---|',
        "| CPU | $($pc.Cpu) |", "| GPU | $($pc.Gpu) |", "| RAM | $($pc.Ram) |", "| Display | $($pc.Tela) |", "| Monitor | $($pc.Monitor) |",
        "| Windows drive | $($pc.Disco) |", "| Windows | $($pc.Windows) |", "| Power plan | $($pc.Energia) |", "| Type | $($pc.Tipo) |", '',
        '## What I want', '',
        '1. Three in-game graphics presets in one table with the columns: **Setting | Balanced | Quality | Maximum performance | Why**.',
        "   - **Balanced:** good image with stable FPS close to the monitor refresh rate ($hz Hz).",
        '   - **Quality:** the best image while keeping at least a stable 60 FPS.',
        '   - **Maximum performance:** the highest FPS and lowest input latency (competitive).',
        '2. The expected average FPS for each one on this hardware (estimate).',
        '3. GPU control panel settings, only if they really matter for this game.',
        '4. Where the game''s config file is.',
        '5. Anything I must **not** change because of anti-cheat or ban risk.', '',
        'Only list settings that really exist in this game. If you are not sure about something, say so instead of guessing.'
    ) -join "`n"
}
# grava a ficha como .md (para anexar no chat da IA) e devolve o caminho
function Save-GameBrief($g) {
    $dir = Join-Path $HelpDir 'jogos'; New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $safe = ($g.Name -replace '[\\/:*?"<>|]', '').Trim(); if (-not $safe) { $safe = 'jogo' }
    $p = Join-Path $dir ("Janus - $safe.md")
    [IO.File]::WriteAllText($p, (New-GamePrompt $g), (New-Object Text.UTF8Encoding($false)))
    return $p
}
# abre a IA com uma frase curta já escrita e deixa o .md pronto para anexar (selecionado no Explorer e copiado)
function Open-AiWithFile([string]$path, [string]$what) {
    $ai = $AiList[$script:Config.AiChoice]; if (-not $ai) { return }
    $short = (T 'Anexei o arquivo "{0}" com os dados do meu PC e o pedido sobre {1}. Leia o arquivo e responda exatamente ao que ele pede.') -f [IO.Path]::GetFileName($path), $what
    try { $fl = New-Object System.Collections.Specialized.StringCollection; [void]$fl.Add($path); [System.Windows.Clipboard]::SetFileDropList($fl) } catch {}
    Open-Url $(if ($ai.Ask) { $ai.Ask -f [uri]::EscapeDataString($short) } else { $ai.Url })
    try { Start-Process explorer.exe -ArgumentList ('/select,"{0}"' -f $path) } catch {}
    Show-Toast ((T 'No {0}: arraste para o chat o arquivo que abriu no Explorer (ou cole com Ctrl+V) e envie.') -f $ai.Name)
}
function Ask-GameAi($g, [string]$mode) {
    $prompt = New-GamePrompt $g
    if ($mode -eq 'code') {
        $cli = Find-ClaudeCli; if (-not $cli) { return }
        $script:AiAnswerFor = $g.Name
        Show-Toast 'Perguntando ao Claude Code... (pode levar até 2 minutos)'
        # o Claude Code roda SEM administrador (via Explorer, escondido); a tarefa só espera a resposta
        $dir = Join-Path $HelpDir ('ia-' + (Get-Date -Format 'yyyyMMdd-HHmmss')); New-Item -ItemType Directory -Force -Path $dir | Out-Null
        [IO.File]::WriteAllText((Join-Path $dir 'pergunta.txt'), $prompt, (New-Object Text.UTF8Encoding($false)))
        $cmd = 'cmd /c chcp 65001 >nul & cd /d "' + $dir + '" & type pergunta.txt | "' + $cli + '" -p "Responda ao pedido do texto recebido." > resposta.txt 2>&1 & echo ok> pronto.txt'
        $vbs = Join-Path $dir 'rodar.vbs'
        [IO.File]::WriteAllText($vbs, ('CreateObject("WScript.Shell").Run "' + ($cmd -replace '"', '""') + '", 0, False'), [Text.Encoding]::Default)
        Start-Unelevated $vbs
        [void](Start-BgJob 'ia' @'
param($inp)
$done = Join-Path $inp.Dir 'pronto.txt'; $sw = [Diagnostics.Stopwatch]::StartNew()
while (-not (Test-Path $done) -and $sw.Elapsed.TotalSeconds -lt 240) { Start-Sleep -Milliseconds 500 }
$f = Join-Path $inp.Dir 'resposta.txt'
@{ Text = $(if (Test-Path $f) { [IO.File]::ReadAllText($f, [Text.Encoding]::UTF8) } else { 'tempo esgotado' }) }
'@ @{ Dir = $dir } {
            param($res, $err)
            $txt = $(if ($res -and $res.Text) { $res.Text } else { (T 'Sem resposta. ') + $err })
            Show-AiAnswer $script:AiAnswerFor $txt
        })
        return
    }
    $md = Save-GameBrief $g
    Open-AiWithFile $md $g.Name
    Write-Log ('Ficha do jogo {0} pronta para o {1}: {2}' -f $g.Name, $AiList[$script:Config.AiChoice].Name, $md)
}
# Abre a IA escolhida já com a pergunta escrita (quando o site aceita); sempre deixa copiada também, para colar se precisar
function Open-AiWithPrompt([string]$prompt) {
    $ai = $AiList[$script:Config.AiChoice]; if (-not $ai) { return }
    try { [System.Windows.Clipboard]::SetText($prompt) } catch {}
    $u = $(if ($ai.Ask) { $ai.Ask -f [uri]::EscapeDataString($prompt) } else { '' })
    if ($u -and $u.Length -le 2000) {
        Open-Url $u
        Show-Toast ((T 'A pergunta já vai escrita no {0}: confira e envie. Se não aparecer, cole com Ctrl+V.') -f $ai.Name)
    } else {
        Open-Url $ai.Url
        Show-Toast ((T 'Pergunta copiada. No {0}, cole com Ctrl+V e envie.') -f $ai.Name)
    }
}
function Show-AiAnswer([string]$game, [string]$text) {
    $d = New-StyledWindow 'Resposta do Claude Code' 760; $d.SizeToContent = 'Manual'; $d.Height = 620; $d.ResizeMode = 'CanResize'
    $root = New-Object System.Windows.Controls.DockPanel; $root.Margin = '22,18,22,18'
    $hd = New-Object System.Windows.Controls.StackPanel
    $hd.Children.Add((New-Text $game 18 '#E6E9EF' 'SemiBold')) | Out-Null
    $wn = New-Text 'IAs podem errar. Confira antes de aplicar, e faça backup do arquivo de configuração do jogo.' 12 '#F59E0B'; $wn.Margin = '0,4,0,10'; $hd.Children.Add($wn) | Out-Null
    [System.Windows.Controls.DockPanel]::SetDock($hd, 'Top'); $root.Children.Add($hd) | Out-Null
    $bc = New-Button 'Fechar' 'Ghost'; $bc.HorizontalAlignment = 'Right'; $bc.Margin = '0,10,0,0'; $bc.add_Click({ [System.Windows.Window]::GetWindow($this).Close() })
    [System.Windows.Controls.DockPanel]::SetDock($bc, 'Bottom'); $root.Children.Add($bc) | Out-Null
    $tb = New-Object System.Windows.Controls.TextBox; $tb.Text = $text; $tb.IsReadOnly = $true; $tb.TextWrapping = 'Wrap'; $tb.VerticalScrollBarVisibility = 'Auto'
    $tb.Background = Brush '#171C26'; $tb.Foreground = Brush '#E6E9EF'; $tb.BorderThickness = 0; $tb.Padding = '10'; $tb.FontFamily = 'Cascadia Mono, Consolas'; $tb.FontSize = 12.5
    $root.Children.Add($tb) | Out-Null
    $d.Content = $root
    if ($Teste) { $d.Close(); return }
    [void]$d.ShowDialog()
}
# ícone do jogo: imagem (jpg/png/ico) ou o ícone do .exe; guardado na memória para não reler
$script:GameIconCache = @{}
function Get-GameIcon([string]$p) {
    if (-not $p) { return $null }
    if ($script:GameIconCache.ContainsKey($p)) { return $script:GameIconCache[$p] }
    $src = $null
    try {
        if (Test-Path -LiteralPath $p) {
            if ($p -match '\.(exe|dll)$') {
                $ico = [System.Drawing.Icon]::ExtractAssociatedIcon($p)
                $src = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon($ico.Handle, [System.Windows.Int32Rect]::Empty, [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions()); $ico.Dispose()
            } else {
                $bi = New-Object System.Windows.Media.Imaging.BitmapImage; $bi.BeginInit(); $bi.CacheOption = 'OnLoad'; $bi.DecodePixelWidth = 56; $bi.UriSource = New-Object Uri $p; $bi.EndInit(); $src = $bi
            }
            $src.Freeze()
        }
    } catch { $src = $null }
    $script:GameIconCache[$p] = $src; return $src
}
# jogos adicionados à mão (o .exe escolhido pela pessoa), guardados nas preferências
function Get-ManualGames {
    @($script:Config.ManualGames | Where-Object { $_ -and $_.Path } | ForEach-Object { @{ Name = [string]$_.Name; Source = (T 'adicionado manualmente'); Id = ''; Icon = [string]$_.Path; Manual = $true; Path = [string]$_.Path } })
}
function Add-ManualGame {
    $dlg = New-Object Microsoft.Win32.OpenFileDialog; $dlg.Title = (T 'Escolha o arquivo .exe do jogo'); $dlg.Filter = ((T 'Programas') + ' (*.exe)|*.exe')
    if ($dlg.ShowDialog() -ne $true) { return }
    $p = $dlg.FileName
    $vi = (Get-Item -LiteralPath $p).VersionInfo
    $n = $(if ($vi.ProductName -and $vi.ProductName.Trim().Length -gt 1) { ($vi.ProductName -replace '[®™©]', '').Trim() } else { [IO.Path]::GetFileNameWithoutExtension($p) })
    $list = @($script:Config.ManualGames | Where-Object { $_ })
    if (@($list | Where-Object { $_.Path -eq $p }).Count) { Show-Toast 'Esse jogo já está na lista'; return }
    $script:Config.ManualGames = @($list) + @(@{ Name = $n; Path = $p }); Save-Config
    Write-Log ('Jogo adicionado à mão: ' + $n + ' (' + $p + ')')
    if ($null -ne $script:Games) { $script:Games = @($script:Games) + @(Get-ManualGames | Where-Object { $_.Path -eq $p }) }
    Show-Toast ((T '{0} adicionado') -f $n); Show-Page 'Jogos' $ui.Scroll.VerticalOffset
}
function Remove-ManualGame([string]$p) {
    $script:Config.ManualGames = @($script:Config.ManualGames | Where-Object { $_ -and $_.Path -ne $p }); Save-Config
    if ($null -ne $script:Games) { $script:Games = @($script:Games | Where-Object { -not ($_.Manual -and $_.Path -eq $p) }) }
    Write-Log ('Jogo tirado da lista: ' + $p); Show-Page 'Jogos' $ui.Scroll.VerticalOffset
}
function Build-Jogos {
    $ai = $script:Config.AiChoice
    if (-not $ai -or -not $AiList.Contains($ai)) {
        # sem IA integrada: só o botão para ativar
        $box = New-Card; $box.Padding = '20,16,20,16'
        $g = New-Object System.Windows.Controls.Grid; Grid-Cols $g @('*', 'Auto')
        $sp = New-Object System.Windows.Controls.StackPanel; $sp.Margin = '0,0,16,0'
        $sp.Children.Add((New-Text 'Otimização por IA' 16 '#E6E9EF' 'SemiBold')) | Out-Null
        $d1 = New-Text 'Com uma IA, o Janus pesquisa a configuração ideal de cada jogo para o seu hardware. Você escolhe o modelo e o objetivo.' 12.5 '#9AA3B2'; $d1.Margin = '0,4,0,0'; $sp.Children.Add($d1) | Out-Null
        Put $g $sp 0
        $b = New-Button 'Ativar otimização por IA' 'Accent'; $b.add_Click({ if (Show-AiSetup) { Show-Page 'Jogos' } }); Put $g $b 1
        $box.Child = $g; Add-Body $box
    } else {
        $box = New-Card; $box.Padding = '18,14,18,14'
        $bx = New-Object System.Windows.Controls.StackPanel
        $r1 = New-Object System.Windows.Controls.WrapPanel
        $l1 = New-Text 'Modelo:' 12.5 '#8B94A5' 'SemiBold'; $l1.VerticalAlignment = 'Center'; $l1.Margin = '0,0,8,0'; $r1.Children.Add($l1) | Out-Null
        $cur = New-Text ($AiList[$ai].Name + '  (' + (T $AiList[$ai].Who) + ')') 13 '#E6E9EF' 'SemiBold'; $cur.VerticalAlignment = 'Center'; $cur.Margin = '0,0,12,0'; $r1.Children.Add($cur) | Out-Null
        $sb = New-Button 'Selecionar modelo' 'Ghost'; $sb.Padding = '10,4'; $sb.FontSize = 12; $sb.add_Click({ if (Show-AiSetup) { Show-Page 'Jogos' $ui.Scroll.VerticalOffset } }); $r1.Children.Add($sb) | Out-Null
        $bx.Children.Add($r1) | Out-Null
        $r2 = New-Text 'A resposta vem com três configurações lado a lado: equilibrada, qualidade e desempenho máximo. O Janus monta um arquivo com os dados do PC para você anexar no chat.' 12.5 '#AEB6C4'; $r2.Margin = '0,10,0,0'
        $bx.Children.Add($r2) | Out-Null
        # ressalvas (aparecem depois que o modelo foi escolhido)
        $wn = New-Text 'IAs não são 100% confiáveis: confira antes de aplicar e faça backup do arquivo de configuração do jogo.' 12 '#FCD38D' 'SemiBold'; $wn.Margin = '0,8,0,0'; $bx.Children.Add($wn) | Out-Null
        $pv = New-Text (Get-AiPrivacy $ai) 11.5 '#8B94A5'; $pv.Margin = '0,4,0,0'; $bx.Children.Add($pv) | Out-Null
        $pd = New-Text (T $AiList[$ai].Plan) 11.5 '#8B94A5'; $pd.Margin = '0,4,0,0'; $bx.Children.Add($pd) | Out-Null
        $hw = New-Text 'A pergunta leva o nome do jogo e o hardware do PC (processador, placa de vídeo, memória, tela e versão do Windows). Não leva seu nome, e-mail nem arquivos.' 11.5 '#6F7889'; $hw.Margin = '0,4,0,0'; $bx.Children.Add($hw) | Out-Null
        $box.Child = $bx; Add-Body $box
    }
    if ($null -eq $script:Games) {
        if (-not $script:BgJobs.ContainsKey('jogos')) { Start-GameScan }
        Add-Body (New-EmptyState ([string][char]0xE895) 'Procurando os jogos instalados...' 'Steam, Epic, Xbox, Riot, Battle.net, EA e Ubisoft.')
        return
    }
    $hdr = New-Object System.Windows.Controls.Grid; Grid-Cols $hdr @('*', 'Auto'); $hdr.Margin = '0,4,12,0'
    Put $hdr (New-Section ((T 'JOGOS INSTALADOS ({0})') -f $script:Games.Count)) 0
    $rf = New-Button 'Procurar jogos' 'Accent'; $rf.Padding = '12,5'; $rf.FontSize = 12.5; $rf.ToolTip = (T 'Procura de novo os jogos instalados (Steam, Epic, Xbox, Riot, Battle.net, EA e Ubisoft). Use depois de instalar ou desinstalar um jogo.')
    $rf.add_Click({ $script:Games = $null; $script:GameIconCache = @{}; $script:GameScanManual = $true; Show-Page 'Jogos' $ui.Scroll.VerticalOffset })
    # embaixo do botão, sem destaque: adicionar um jogo que a busca não achou
    $rcol = New-Object System.Windows.Controls.StackPanel; $rcol.HorizontalAlignment = 'Right'; $rcol.Children.Add($rf) | Out-Null
    $man = New-Text 'Procurar manualmente' 11.5 '#7F8899'; $man.HorizontalAlignment = 'Right'; $man.Margin = '0,5,2,0'; $man.Cursor = 'Hand'; $man.TextDecorations = [System.Windows.TextDecorations]::Underline
    $man.ToolTip = (T 'Escolha o arquivo .exe de um jogo que não apareceu na lista.')
    $man.add_MouseLeftButtonUp({ Add-ManualGame }); $rcol.Children.Add($man) | Out-Null
    Put $hdr $rcol 1
    Add-Body $hdr
    if (-not $script:Games.Count) { Add-Body (New-EmptyState ([string][char]0xE7FC) 'Nenhum jogo encontrado' 'Não achei jogos da Steam, Epic, Xbox, Riot, Battle.net, EA ou Ubisoft neste PC.'); return }
    $hasCode = [bool](Find-ClaudeCli)
    foreach ($g in $script:Games) {
        $c = New-Card; $c.Padding = '16,10,14,10'; $c.Margin = '0,0,12,8'
        $gr = New-Object System.Windows.Controls.Grid; Grid-Cols $gr @('Auto', '*', 'Auto')
        $im = Get-GameIcon $g.Icon
        if ($im) { $gi = New-Object System.Windows.Controls.Image; $gi.Source = $im; $gi.Width = 28; $gi.Height = 28; [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($gi, 'HighQuality') }
        else { $gi = Glyph ([string][char]0xE7FC) 18 '#8EA3C8'; $gi.Width = 28; $gi.TextAlignment = 'Center' }
        $gi.Margin = '0,0,14,0'; $gi.VerticalAlignment = 'Center'; Put $gr $gi 0
        $sp = New-Object System.Windows.Controls.StackPanel; $sp.VerticalAlignment = 'Center'
        $sp.Children.Add((New-Text $g.Name 14 '#E6E9EF' 'SemiBold')) | Out-Null
        $sp.Children.Add((New-Text $g.Source 11.5 '#7F8899')) | Out-Null
        Put $gr $sp 1
        $bs = New-Object System.Windows.Controls.StackPanel; $bs.Orientation = 'Horizontal'; $bs.VerticalAlignment = 'Center'
        if ($g.Manual) { $rm = New-Button 'Remover' 'Ghost' $g.Path; $rm.Padding = '10,5'; $rm.FontSize = 12; $rm.Margin = '0,0,8,0'; $rm.ToolTip = (T 'Tira da lista (não apaga o jogo).'); $rm.add_Click({ Remove-ManualGame $this.Tag }); $bs.Children.Add($rm) | Out-Null }
        $wk = New-LinkButton 'PCGamingWiki' ('https://www.pcgamingwiki.com/w/index.php?search=' + [uri]::EscapeDataString($g.Name)); $wk.Margin = '0,0,8,0'; $bs.Children.Add($wk) | Out-Null
        if ($ai -and $AiList.Contains($ai)) {
            if ($hasCode -and $ai -eq 'claude') { $bc = New-Button 'Responder aqui' 'Ghost' $g; $bc.Padding = '10,5'; $bc.FontSize = 12; $bc.Margin = '0,0,8,0'; $bc.ToolTip = (T 'Usa o Claude Code deste PC e mostra a resposta dentro do Janus. Exige plano pago do Claude.'); $bc.add_Click({ Ask-GameAi $this.Tag 'code' }); $bs.Children.Add($bc) | Out-Null }
            $ba = New-Button ((T 'Perguntar ao {0}') -f $AiList[$ai].Name) 'Accent' $g; $ba.Padding = '10,5'; $ba.FontSize = 12; $ba.add_Click({ Ask-GameAi $this.Tag 'web' }); $bs.Children.Add($ba) | Out-Null
        }
        Put $gr $bs 2
        $c.Child = $gr; Add-Body $c
    }
}

# ---------- números, cores das barras e abrir sem administrador ----------
# Números no formato do idioma: 15,1 em português/espanhol, 15.1 em inglês/chinês
function Fmt-Num($x, [int]$dec = 1) {
    if ($null -eq $x) { return '' }
    $ci = $(if ($script:Lang -in 'pt', 'es') { [Globalization.CultureInfo]::GetCultureInfo('pt-BR') } else { [Globalization.CultureInfo]::InvariantCulture })
    return ([double]$x).ToString(('0.' + ('#' * $dec)), $ci)
}
# Cor da barra: verde (0) -> amarelo (50) -> vermelho (100), com todos os tons no meio
function Get-HeatColor([double]$pct) {
    $p = [math]::Max(0, [math]::Min(100, $pct)) / 100
    $h = 120 * (1 - $p); $s = 0.78; $v = $(if ($script:IsLight) { 0.78 } else { 0.95 })
    $c = $v * $s; $x = $c * (1 - [math]::Abs((($h / 60) % 2) - 1)); $m = $v - $c
    $rgb = $(if ($h -lt 60) { @($c, $x, 0) } else { @($x, $c, 0) })
    return [System.Windows.Media.Color]::FromRgb([byte](255 * ($rgb[0] + $m)), [byte](255 * ($rgb[1] + $m)), [byte](255 * ($rgb[2] + $m)))
}
# Abre programas SEM o poder de administrador do Janus: o Explorer (que roda sem elevação) é quem executa
function Start-Unelevated([string]$file) {
    try { Start-Process explorer.exe "`"$file`"" } catch { Write-Log ('Não consegui abrir sem administrador: ' + $_.Exception.Message) }
}

# ---------- integração com IA ----------
function Show-AiSetup {
    $d = New-StyledWindow 'Inteligência artificial' 620
    $root = New-Object System.Windows.Controls.StackPanel; $root.Margin = '26,22,26,22'
    $root.Children.Add((New-Text 'Integrar o Janus com uma IA?' 19 '#E6E9EF' 'SemiBold')) | Out-Null
    $ex = New-Text 'Com uma IA, o Janus consegue: explicar qualquer item (botão ? ao lado de cada ajuste) e pesquisar a configuração ideal dos seus jogos (aba Jogos). O Janus monta a pergunta e abre o site da IA; você só cola e envia. Nada é enviado sozinho.' 12.8 '#AEB6C4'
    $ex.Margin = '0,8,0,14'; $ex.LineHeight = 18; $root.Children.Add($ex) | Out-Null
    $root.Children.Add((New-Text 'Escolha o modelo:' 12.5 '#8B94A5' 'SemiBold')) | Out-Null
    foreach ($k in $AiList.Keys) {
        $a = $AiList[$k]; $sel = ($script:Config.AiChoice -eq $k)
        $b = New-Object System.Windows.Controls.Button; $b.Style = $W.FindResource($(if ($sel) { 'Accent' } else { 'Ghost' })); $b.HorizontalContentAlignment = 'Stretch'; $b.Margin = '0,6,0,0'; $b.Padding = '14,9'; $b.Tag = $k
        $g = New-Object System.Windows.Controls.Grid; Grid-Cols $g @('*', 'Auto')
        $n = New-Object System.Windows.Controls.StackPanel
        $t1 = New-Object System.Windows.Controls.TextBlock; $t1.Text = $a.Name; $t1.FontSize = 14; $t1.FontWeight = 'SemiBold'; $t1.Foreground = Brush $(if ($sel) { 'White' } else { '#E6E9EF' }); $n.Children.Add($t1) | Out-Null
        $t2 = New-Object System.Windows.Controls.TextBlock; $t2.Text = (T $a.Plan); $t2.FontSize = 11.5; $t2.TextWrapping = 'Wrap'; $t2.Foreground = Brush $(if ($sel) { '#DCE7FF' } else { '#9AA3B2' }); $n.Children.Add($t2) | Out-Null
        Put $g $n 0
        $t3 = New-Object System.Windows.Controls.TextBlock; $t3.Text = (T $a.Who); $t3.FontSize = 11.5; $t3.VerticalAlignment = 'Center'; $t3.Margin = '12,0,0,0'; $t3.Foreground = Brush $(if ($sel) { '#DCE7FF' } else { '#7F8899' }); Put $g $t3 1
        $b.Content = $g
        $b.add_Click({ $w2 = [System.Windows.Window]::GetWindow($this); $w2.Tag = $this.Tag; $w2.DialogResult = $true })
        $root.Children.Add($b) | Out-Null
    }
    $pl = New-Text 'Planos e limites mudam com frequência: confira no site de cada uma.' 11.5 '#6F7889'; $pl.Margin = '0,10,0,0'; $root.Children.Add($pl) | Out-Null
    $br = New-Object System.Windows.Controls.StackPanel; $br.Orientation = 'Horizontal'; $br.HorizontalAlignment = 'Right'; $br.Margin = '0,16,0,0'
    $bn = New-Button 'Não usar IA' 'Ghost' 'none'; $bn.Margin = '8,0,0,0'; $bn.add_Click({ $w2 = [System.Windows.Window]::GetWindow($this); $w2.Tag = 'none'; $w2.DialogResult = $true })
    $bc = New-Button 'Cancelar' 'Ghost'; $bc.Margin = '8,0,0,0'; $bc.add_Click({ [System.Windows.Window]::GetWindow($this).DialogResult = $false })
    $br.Children.Add($bc) | Out-Null; $br.Children.Add($bn) | Out-Null; $root.Children.Add($br) | Out-Null
    $d.Content = $root; $d.Tag = ''
    if ($Teste) { $d.Close(); return $false }
    $wasBusy = $script:Busy; $script:Busy = $true; try { [void]$d.ShowDialog() } finally { $script:Busy = $wasBusy }
    $script:Config.AiAsked = $true
    $ch = [string]$d.Tag
    if (-not $ch) { Save-Config; return $false }
    if ($ch -eq 'none') { $script:Config.AiChoice = ''; Save-Config; Write-Log 'IA: nenhuma'; return $false }
    # ressalvas depois de escolher
    $a = $AiList[$ch]
    $txt = @((T 'IAs não são 100% confiáveis: confira as respostas antes de aplicar qualquer mudança.'), (Get-AiPrivacy $ch), (T $a.Plan)) -join "`n`n"
    $ok = Show-Choice 'Inteligência artificial' ((T 'Usar o {0}?') -f $a.Name) $txt @(@('yes', 'Usar este modelo', 'Accent'), @('no', 'Voltar', 'Ghost')) 'info'
    if ($ok -ne 'yes') { Save-Config; return (Show-AiSetup) }
    $script:Config.AiChoice = $ch; Save-Config; Write-Log ('IA: ' + $a.Name)
    Show-Toast ((T 'IA integrada: {0}') -f $a.Name)
    return $true
}

# ---------- engrenagem: menu simples com as preferências ----------
function New-MI([string]$header, [scriptblock]$action = $null, $checked = $null) {
    $mi = New-Object System.Windows.Controls.MenuItem
    $mi.Style = $W.FindResource('JMenuItem'); $mi.Header = (T $header)
    if ($null -ne $checked) { $mi.IsCheckable = $false; $mi.IsChecked = [bool]$checked }
    if ($action) { $mi.Tag = $action; $mi.add_Click({ param($s, $e) $e.Handled = $true; & $this.Tag }) }
    return $mi
}
function New-MSep { $s = New-Object System.Windows.Controls.Separator; $s.Style = $W.FindResource('JMenuSep'); return $s }
function Show-GearMenu($anchor) {
    $cm = New-Object System.Windows.Controls.ContextMenu; $cm.Style = $W.FindResource('JMenu')
    # Visualização
    $v = New-MI 'Visualização'
    [void]$v.Items.Add((New-MI 'Simplificado' { Set-NavMode 'simples' } ($script:Config.NavMode -eq 'simples')))
    [void]$v.Items.Add((New-MI 'Por categoria' { Set-NavMode 'categorias' } ($script:Config.NavMode -eq 'categorias')))
    [void]$cm.Items.Add($v)
    # IA
    $ia = New-MI 'Inteligência artificial'
    foreach ($k in $AiList.Keys) {
        $kk = $k
        [void]$ia.Items.Add((New-MI $AiList[$k].Name ([scriptblock]::Create("`$script:Config.AiChoice = '$kk'; `$script:Config.AiAsked = `$true; Save-Config; Write-Log ('IA: ' + `$AiList['$kk'].Name); Show-Toast ((T 'IA integrada: {0}') -f `$AiList['$kk'].Name); if (`$script:CurrentPage -eq 'Jogos') { Show-Page 'Jogos' }")) ($script:Config.AiChoice -eq $k)))
    }
    [void]$ia.Items.Add((New-MI 'Não usar IA' { $script:Config.AiChoice = ''; $script:Config.AiAsked = $true; Save-Config; Write-Log 'IA: nenhuma'; if ($script:CurrentPage -eq 'Jogos') { Show-Page 'Jogos' } } (-not $script:Config.AiChoice)))
    [void]$ia.Items.Add((New-MSep))
    [void]$ia.Items.Add((New-MI 'O que é isso?' { if (Show-AiSetup) { if ($script:CurrentPage -eq 'Jogos') { Show-Page 'Jogos' } } }))
    [void]$cm.Items.Add($ia)
    # Tema
    $tm = New-MI 'Tema'
    foreach ($p in @(@('dark', 'Escuro'), @('light', 'Claro'), @('auto', 'Seguir o Windows'))) {
        [void]$tm.Items.Add((New-MI $p[1] ([scriptblock]::Create("if (`$script:Config.Theme -ne '$($p[0])') { `$script:Config.Theme = '$($p[0])'; Save-Config; Write-Log 'Tema: $($p[0])'; Restart-Janus }")) ($script:Config.Theme -eq $p[0])))
    }
    [void]$cm.Items.Add($tm)
    # Idioma
    $lg = New-MI 'Idioma'
    foreach ($k in $Langs.Keys) { [void]$lg.Items.Add((New-MI $Langs[$k] ([scriptblock]::Create("Set-Language '$k'")) ($script:Lang -eq $k))) }
    [void]$lg.Items.Add((New-MSep)); [void]$lg.Items.Add((New-MI 'Mais idiomas...' { Show-LanguageDialog }))
    [void]$cm.Items.Add($lg)
    # Monitoramento
    $mo = New-MI 'Monitoramento do hardware'
    foreach ($k in $MonLevels.Keys) {
        $code = $(if ($k -eq 'real') { "`$r = Show-Choice 'Monitoramento' 'Ler em tempo real?' 'A leitura a cada segundo pode deixar PCs mais fracos lentos ou com pequenos travamentos, principalmente durante jogos. Se notar algo assim, volte para Normal.' @(@('yes', 'Usar tempo real', 'Accent'), @('no', 'Cancelar', 'Ghost')) 'warn'; if (`$r -ne 'yes') { return }" } else { '' }) + "`$script:Config.MonLevel = '$k'; Save-Config; Write-Log 'Monitoramento: $k'; if (`$script:CurrentPage -eq 'Inicio') { Show-Page 'Inicio' `$ui.Scroll.VerticalOffset }"
        [void]$mo.Items.Add((New-MI $MonLevels[$k][0] ([scriptblock]::Create($code)) ($script:Config.MonLevel -eq $k)))
    }
    [void]$cm.Items.Add($mo)
    [void]$cm.Items.Add((New-MSep))
    [void]$cm.Items.Add((New-MI 'Modo leve do Janus' { Set-LightMode (-not [bool]$script:Config.LightMode); if ($script:CurrentPage -eq 'Sobre') { Show-Page 'Sobre' $ui.Scroll.VerticalOffset } } ([bool]$script:Config.LightMode)))
    [void]$cm.Items.Add((New-MI 'Notificações...' { Show-NotifySettings }))
    [void]$cm.Items.Add((New-MI 'Ficar nos ícones ocultos ao fechar' { $script:Config.Tray = -not [bool]$script:Config.Tray; Save-Config; Write-Log ('Ícones ocultos ao fechar: ' + $script:Config.Tray) } ([bool]$script:Config.Tray)))
    [void]$cm.Items.Add((New-MI 'Iniciar com o Windows' { Set-Autostart (-not (Test-Autostart)) } (Test-Autostart)))
    [void]$cm.Items.Add((New-MI 'Abrir sem a tela de administrador' { Set-NoUac (-not (Test-NoUac)) } (Test-NoUac)))
    if (@($script:Config.Dismissed).Count -or $script:DismissedSession.Count) { [void]$cm.Items.Add((New-MI 'Mostrar sugestões descartadas' { $script:Config.Dismissed = @(); Save-Config; $script:DismissedSession.Clear(); Write-Log 'Sugestões descartadas trazidas de volta.'; Build-Nav; Update-NavCounts; Show-Toast 'Sugestões descartadas voltaram' })) }
    [void]$cm.Items.Add((New-MI 'Procurar atualizações sozinho' { $script:Config.AutoUpdate = -not $script:Config.AutoUpdate; Save-Config; Write-Log ('Procurar atualizações sozinho: ' + $script:Config.AutoUpdate) } ([bool]$script:Config.AutoUpdate)))
    [void]$cm.Items.Add((New-MSep))
    [void]$cm.Items.Add((New-MI $(if ($script:Auth.Latest -and (Compare-AppVersion $script:Auth.Latest $AppVersion) -gt 0) { 'Atualizar agora' } else { 'Procurar atualização agora' }) { if ($script:Auth.Latest -and (Compare-AppVersion $script:Auth.Latest $AppVersion) -gt 0) { Install-Update } else { $script:ManualCheck = $true; Start-UpdateCheck; Show-Toast 'Verificando no GitHub...' } }))
    [void]$cm.Items.Add((New-MI 'Reportar um problema' { Show-ReportDialog 'manual' | Out-Null }))
    [void]$cm.Items.Add((New-MI 'Ver o aviso inicial' { Show-Welcome }))
    [void]$cm.Items.Add((New-MI 'Abrir pasta do Janus' { Start-Process explorer.exe $DataDir }))
    [void]$cm.Items.Add((New-MI 'Novidades desta versão' { Show-Changelog }))
    [void]$cm.Items.Add((New-MI 'Sobre o Janus' { Show-Page 'Sobre' }))
    $cm.PlacementTarget = $anchor; $cm.Placement = 'Bottom'
    $cm.IsOpen = $true
    return $cm
}

# ---------- novidades de cada versão (aparece sozinha depois de atualizar) ----------
$Changelog = [ordered]@{
    '0.1.0-beta.3' = @(
        'Som de alerta próprio do Janus, mais agradável que o do Windows.',
        'Sininho em cada item do hardware: você escolhe o que quer que o Janus avise.',
        'Avisar só uma vez ou repetir, e de quanto em quanto tempo (engrenagem > Notificações).',
        'Placa de vídeo mostra o uso e a temperatura lado a lado.',
        'O ícone da rede mostra o tipo de conexão (cabo, Wi-Fi ou os dois). O cabo aparece primeiro em todas as listas.',
        'Ficar nos ícones ocultos ao fechar, para continuar monitorando e avisando.',
        'Opção de iniciar com o Windows (abre direto nos ícones ocultos).',
        'Ícones dos jogos na aba Jogos, e o botão Procurar jogos para achar os que você instalar depois.',
        'O aviso discreto aparece no canto inferior esquerdo da tela, no monitor onde está o mouse.',
        'Antes de ligar o Failover, o Janus procura o que pode interferir (VPN, acelerador de jogo, outra cópia do Janus, prioridade fixada) e mostra o que é.',
        'Opção de derrubar e desativar o que interfere no Failover (não recomendado), com o botão Reativar para voltar tudo como estava.',
        'Perguntar à IA monta um arquivo com os dados do PC para anexar no chat, e a resposta vem com três configurações: equilibrada, qualidade e desempenho máximo.',
        'Opção na engrenagem: abrir o Janus sem a tela de permissão do Windows.',
        'Procurar manualmente: adicione à aba Jogos um jogo que a busca não achou.',
        'Esta janela de novidades.',
        'Saíram o botão Testes e o aviso de piscar o ícone.'
    )
}
function Show-Changelog([string]$from = '') {
    $vers = @($Changelog.Keys | Where-Object { (Compare-AppVersion $_ $AppVersion) -le 0 -and $(if ($from) { (Compare-AppVersion $_ $from) -gt 0 } else { $_ -eq $AppVersion }) })
    if (-not $vers.Count) { $vers = @($Changelog.Keys | Select-Object -First 1) }
    $d = New-StyledWindow 'Novidades' 580
    $root = New-Object System.Windows.Controls.StackPanel; $root.Margin = '28,22,28,22'
    $hrow = New-Object System.Windows.Controls.StackPanel; $hrow.Orientation = 'Horizontal'
    $img = New-Object System.Windows.Controls.Image; $img.Width = 44; $img.Height = 44; try { $img.Source = (New-PngImage 88) } catch {}
    $hrow.Children.Add($img) | Out-Null
    $ht = New-Object System.Windows.Controls.StackPanel; $ht.Margin = '14,0,0,0'; $ht.VerticalAlignment = 'Center'
    $ht.Children.Add((New-Text 'O que há de novo' 20 '#E6E9EF' 'SemiBold')) | Out-Null
    $ht.Children.Add((New-Text ((T 'Versão {0}') -f (Format-Version $AppVersion)) 12.5 '#8B94A5')) | Out-Null
    $hrow.Children.Add($ht) | Out-Null; $root.Children.Add($hrow) | Out-Null
    foreach ($v in $vers) {
        if ($vers.Count -gt 1) { $vh = New-Text (Format-Version $v) 13 '#8EA3C8' 'SemiBold'; $vh.Margin = '0,16,0,0'; $root.Children.Add($vh) | Out-Null }
        foreach ($line in $Changelog[$v]) {
            $r = New-Object System.Windows.Controls.Grid; Grid-Cols $r @('Auto', '*'); $r.Margin = '0,10,0,0'
            $gi = Glyph ([string][char]0xE73E) 13 '#22C55E'; $gi.Margin = '2,2,12,0'; $gi.VerticalAlignment = 'Top'; Put $r $gi 0
            $tt = New-Text $line 12.8 '#AEB6C4'; $tt.LineHeight = 18; Put $r $tt 1
            $root.Children.Add($r) | Out-Null
        }
    }
    $ok = New-Button 'Entendi' 'Accent'; $ok.HorizontalAlignment = 'Right'; $ok.Margin = '0,22,0,0'; $ok.add_Click({ [System.Windows.Window]::GetWindow($this).DialogResult = $true })
    $root.Children.Add($ok) | Out-Null
    $d.Content = $root
    if ($Teste) { $d.Close(); return }
    $wasBusy = $script:Busy; $script:Busy = $true; try { [void]$d.ShowDialog() } finally { $script:Busy = $wasBusy }
}

# ---------- ícones ocultos (perto do relógio) ----------
$script:Tray = $null; $script:TrayTipShown = $false
function Show-FromTray {
    if ($script:Tray) { $script:Tray.Visible = $false }
    $W.Show(); if ($W.WindowState -eq 'Minimized') { $W.WindowState = 'Normal' }
    $W.Topmost = $true; $W.Topmost = $false; [void]$W.Activate()
}
function Hide-ToTray {
    if (-not $script:Tray) {
        $ni = New-Object System.Windows.Forms.NotifyIcon
        try { $ni.Icon = New-Object System.Drawing.Icon $IconPath } catch { $ni.Icon = [System.Drawing.SystemIcons]::Application }
        $ni.Text = $AppName
        $menu = New-Object System.Windows.Forms.ContextMenuStrip
        [void]$menu.Items.Add((T 'Abrir o Janus'), $null, [EventHandler]{ Show-FromTray })
        [void]$menu.Items.Add((T 'Fechar o Janus'), $null, [EventHandler]{ $script:CleanExit = $true; $W.Close() })
        $ni.ContextMenuStrip = $menu
        $ni.add_MouseClick({ param($s, $e) if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { Show-FromTray } })
        $script:Tray = $ni
    }
    $script:Tray.Visible = $true
    $W.Hide()
    if (-not $script:TrayTipShown) {
        $script:TrayTipShown = $true
        try { $script:Tray.ShowBalloonTip(4000, 'Janus', (T 'O Janus continua monitorando aqui nos ícones ocultos. Clique no ícone para abrir.'), [System.Windows.Forms.ToolTipIcon]::Info) } catch {}
    }
    Write-Log 'Janus foi para os ícones ocultos.'
}
# ao fechar sem a opção ligada: explica o que deixa de funcionar e oferece os ícones ocultos
function Show-CloseAsk {
    $d = New-StyledWindow 'Fechar o Janus' 560
    $root = New-Object System.Windows.Controls.StackPanel; $root.Margin = '26,22,26,22'
    $row = New-Object System.Windows.Controls.StackPanel; $row.Orientation = 'Horizontal'
    $ic = Glyph ([string][char]0xE7BA) 22 '#F59E0B'; $ic.Margin = '0,0,12,0'; $ic.VerticalAlignment = 'Center'; $row.Children.Add($ic) | Out-Null
    $h = New-Text 'Fechar o Janus?' 18 '#E6E9EF' 'SemiBold'; $h.VerticalAlignment = 'Center'; $row.Children.Add($h) | Out-Null
    $root.Children.Add($row) | Out-Null
    $tx = New-Text 'Ao fechar, o Janus deixa de monitorar o hardware, de avisar quando algo fica vermelho e de cuidar do Failover. Nos ícones ocultos (perto do relógio) ele continua fazendo isso, gastando pouco.' 13 '#AEB6C4'; $tx.Margin = '0,12,0,16'; $tx.LineHeight = 19; $root.Children.Add($tx) | Out-Null
    $foot = New-Object System.Windows.Controls.Grid; Grid-Cols $foot @('*', 'Auto', 'Auto')
    $cb = New-Object System.Windows.Controls.CheckBox; $cb.Content = (T 'Não mostrar novamente'); $cb.Foreground = Brush '#8B94A5'; $cb.VerticalAlignment = 'Center'; Put $foot $cb 0
    $bc = New-Button 'Fechar' 'Ghost' 'close'; $bc.Margin = '8,0,0,0'; $bc.add_Click({ $w2 = [System.Windows.Window]::GetWindow($this); $w2.Tag = $this.Tag; $w2.DialogResult = $true }); Put $foot $bc 1
    $bt = New-Button 'Minimizar para os ícones ocultos' 'Accent' 'tray'; $bt.Margin = '8,0,0,0'; $bt.add_Click({ $w2 = [System.Windows.Window]::GetWindow($this); $w2.Tag = $this.Tag; $w2.DialogResult = $true }); Put $foot $bt 2
    $root.Children.Add($foot) | Out-Null
    $sub = New-Text 'Dá para mudar depois na engrenagem > Ficar nos ícones ocultos ao fechar.' 11 '#6F7889'; $sub.Margin = '0,10,0,0'; $root.Children.Add($sub) | Out-Null
    $d.Content = $root; $d.Tag = 'cancel'
    if ($Teste) { $d.Close(); return 'cancel' }
    $wasBusy = $script:Busy; $script:Busy = $true; try { [void]$d.ShowDialog() } finally { $script:Busy = $wasBusy }
    $r = [string]$d.Tag
    if ($cb.IsChecked -and $r -ne 'cancel') {
        $script:Config.CloseAsked = $true; if ($r -eq 'tray') { $script:Config.Tray = $true }
        Save-Config; Write-Log ('Ao fechar: ' + $(if ($r -eq 'tray') { 'ir para os ícones ocultos' } else { 'fechar' }) + ' (não perguntar de novo)')
    }
    return $r
}

# ---------- iniciar com o Windows ----------
# tarefa agendada no logon com privilégio máximo: abre sem a pergunta do UAC, direto nos ícones ocultos
# ---------- abrir sem a tela de administrador do Windows ----------
# Tarefa agendada sem gatilho, com privilégio máximo: o atalho normal a chama e o Janus abre sem a pergunta do UAC.
# Em troca, qualquer programa da conta também consegue abrir o Janus como administrador sem perguntar (por isso é opção).
function Test-NoUac { return [bool](Get-ScheduledTask -TaskPath '\Janus\' -TaskName 'Abrir o Janus' -ErrorAction SilentlyContinue) }
function Set-NoUac([bool]$on) {
    try {
        if ($on) {
            $r = Show-Choice 'Abrir sem a tela de administrador' 'Abrir o Janus sem a pergunta do Windows?' 'O Janus passa a abrir direto, sem a tela azul de permissão. Em troca, qualquer programa aberto na sua conta também consegue abrir o Janus como administrador sem perguntar. Use só se você confia nos programas do seu PC. Dá para desligar quando quiser.' @(@('yes', 'Ativar', 'Danger'), @('no', 'Cancelar', 'Accent')) 'warn'
            if ($r -ne 'yes') { return }
            $me = "$env:USERDOMAIN\$env:USERNAME"
            $act = New-ScheduledTaskAction -Execute (Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe') -Argument ('-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "{0}"' -f $PSCommandPath) -WorkingDirectory $Pasta
            $pr = New-ScheduledTaskPrincipal -UserId $me -LogonType Interactive -RunLevel Highest
            $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances Parallel
            Register-ScheduledTask -TaskName 'Abrir o Janus' -TaskPath '\Janus\' -Action $act -Principal $pr -Settings $set -Force | Out-Null
            Write-Log 'Abrir sem a tela de administrador: ligado.'; Show-Toast 'Pronto: o Janus abre sem a tela de permissão'
        } else {
            Unregister-ScheduledTask -TaskPath '\Janus\' -TaskName 'Abrir o Janus' -Confirm:$false -ErrorAction Stop
            Write-Log 'Abrir sem a tela de administrador: desligado.'; Show-Toast 'O Janus volta a pedir permissão ao abrir'
        }
    } catch { Show-Toast ((T 'Não deu certo: {0}') -f $_.Exception.Message); Write-Log ('Abrir sem a tela de administrador falhou: ' + $_.Exception.Message) }
}
function Test-Autostart { return [bool](Get-ScheduledTask -TaskPath '\Janus\' -TaskName 'Iniciar com o Windows' -ErrorAction SilentlyContinue) }
function Set-Autostart([bool]$on) {
    try {
        if ($on) {
            $me = "$env:USERDOMAIN\$env:USERNAME"
            $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "{0}" -Bandeja' -f $PSCommandPath)
            $trg = New-ScheduledTaskTrigger -AtLogOn -User $me; $trg.Delay = 'PT15S'
            $pr = New-ScheduledTaskPrincipal -UserId $me -LogonType Interactive -RunLevel Highest
            $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
            Register-ScheduledTask -TaskName 'Iniciar com o Windows' -TaskPath '\Janus\' -Action $act -Trigger $trg -Principal $pr -Settings $set -Force | Out-Null
            Write-Log 'Iniciar com o Windows: ligado (abre nos ícones ocultos).'; Show-Toast 'O Janus vai abrir com o Windows, nos ícones ocultos'
        } else {
            Unregister-ScheduledTask -TaskPath '\Janus\' -TaskName 'Iniciar com o Windows' -Confirm:$false -ErrorAction Stop
            Write-Log 'Iniciar com o Windows: desligado.'; Show-Toast 'O Janus não abre mais com o Windows'
        }
    } catch { Show-Toast ((T 'Não deu certo: {0}') -f $_.Exception.Message); Write-Log ('Iniciar com o Windows falhou: ' + $_.Exception.Message) }
}

# ---------- som de alerta (criado pelo próprio Janus: dois tons suaves, livre de direitos) ----------
function New-ChimeWav([double[]]$freqs, [int]$stepMs = 150, [int]$noteMs = 420, [double]$vol = 0.32) {
    $rate = 44100
    $total = [int]($rate * (($stepMs * ($freqs.Count - 1)) + $noteMs) / 1000)
    $buf = New-Object double[] $total
    for ($n = 0; $n -lt $freqs.Count; $n++) {
        $start = [int]($rate * $stepMs * $n / 1000); $len = [int]($rate * $noteMs / 1000); $fq = $freqs[$n]
        for ($i = 0; $i -lt $len -and ($start + $i) -lt $total; $i++) {
            $tt = $i / $rate
            $env = [math]::Min(1, $tt / 0.006) * [math]::Exp(-$tt * 7.5)
            $buf[$start + $i] += $env * ([math]::Sin(2 * [math]::PI * $fq * $tt) + 0.28 * [math]::Sin(4 * [math]::PI * $fq * $tt) + 0.08 * [math]::Sin(6 * [math]::PI * $fq * $tt))
        }
    }
    $ms = New-Object System.IO.MemoryStream; $bw = New-Object System.IO.BinaryWriter $ms
    $data = $total * 2
    $bw.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $bw.Write([int](36 + $data)); $bw.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
    $bw.Write([int]16); $bw.Write([int16]1); $bw.Write([int16]1); $bw.Write([int]$rate); $bw.Write([int]($rate * 2)); $bw.Write([int16]2); $bw.Write([int16]16)
    $bw.Write([Text.Encoding]::ASCII.GetBytes('data')); $bw.Write([int]$data)
    foreach ($v in $buf) { $bw.Write([int16][math]::Max(-32767, [math]::Min(32767, $v * $vol * 32767))) }
    $bw.Flush(); return , $ms.ToArray()
}
$script:Chimes = @{}
function Play-Alert([string]$level = 'crit') {
    try {
        if (-not $script:Chimes.ContainsKey($level)) {
            # urgente: dois tons descendo (chama atenção); atenção/teste: dois tons subindo (mais leve)
            $script:Chimes[$level] = $(if ($level -eq 'crit') { New-ChimeWav @(1046.5, 784.0, 1046.5) 130 380 0.34 } else { New-ChimeWav @(784.0, 1046.5) 150 420 0.30 })
        }
        $script:ChimePlayer = New-Object System.Media.SoundPlayer (New-Object System.IO.MemoryStream (, $script:Chimes[$level]))
        $script:ChimePlayer.Play()
    } catch { [System.Media.SystemSounds]::Exclamation.Play() }
}

# ---------- notificações ----------
if (-not ('JanusWin' -as [type])) {
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class JanusWin {
  [StructLayout(LayoutKind.Sequential)] public struct FLASHWINFO { public uint cbSize; public IntPtr hwnd; public uint dwFlags; public uint uCount; public uint dwTimeout; }
  [DllImport("user32.dll")] static extern bool FlashWindowEx(ref FLASHWINFO f);
  public static void Flash(IntPtr h) { var f = new FLASHWINFO(); f.cbSize = (uint)Marshal.SizeOf(f); f.hwnd = h; f.dwFlags = 3 | 12; f.uCount = 5; f.dwTimeout = 0; FlashWindowEx(ref f); }
}
"@
}
$NotifyKinds = [ordered]@{
    corner = @('Aviso discreto no canto inferior esquerdo', 'Um cartão pequeno no canto de baixo à esquerda da tela (no monitor onde está o mouse), com som de alerta. Some sozinho em 8 segundos e não tira o foco do jogo.')
    toast  = @('Notificação do Windows', 'Aparece na Central de Notificações. Algumas pessoas deixam as notificações do Windows desligadas, ou o modo Não incomodar ligado.')
    popup  = @('Janela de aviso no meio da tela', 'Mais difícil de perder, mas pode atrapalhar no meio de um jogo. Bom para avisos graves.')
    sound  = @('Só um som de alerta', 'Toca o som de alerta do Janus, sem mostrar nada.')
}
function Show-CornerAlert([string]$title, [string]$text, [string]$level = 'crit') {
    $w2 = New-Object System.Windows.Window
    $w2.WindowStyle = 'None'; $w2.AllowsTransparency = $true; $w2.Background = [System.Windows.Media.Brushes]::Transparent
    $w2.Topmost = $true; $w2.ShowInTaskbar = $false; $w2.ShowActivated = $false; $w2.SizeToContent = 'WidthAndHeight'; $w2.ResizeMode = 'NoResize'
    $w2.FontFamily = 'Segoe UI Variable Text, Segoe UI, Microsoft YaHei UI'
    $col = @{ crit = '#EF4444'; warn = '#F59E0B'; info = '#60A5FA'; ok = '#22C55E' }[$level]
    $bd = New-Object System.Windows.Controls.Border; $bd.CornerRadius = 12; $bd.Background = Brush '#171C26'; $bd.BorderBrush = Brush $col; $bd.BorderThickness = '1,1,1,4'; $bd.Padding = '16,12,16,12'; $bd.Width = 360; $bd.Margin = '8'
    $bd.Effect = New-Object System.Windows.Media.Effects.DropShadowEffect -Property @{ BlurRadius = 18; ShadowDepth = 2; Opacity = 0.45 }
    $g = New-Object System.Windows.Controls.Grid; Grid-Cols $g @('Auto', '*')
    $ic = Glyph ([string]$(if ($level -eq 'ok') { [char]0xE73E } elseif ($level -eq 'info') { [char]0xE946 } else { $LevelStyle[$(if ($level -eq 'warn') { 'warn' } else { 'crit' })][0] })) 20 $col; $ic.Margin = '0,2,12,0'; $ic.VerticalAlignment = 'Top'; Put $g $ic 0
    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Children.Add((New-Text ('Janus  ·  ' + (T $title)) 13 '#E6E9EF' 'SemiBold')) | Out-Null
    $tx = New-Text $text 12 '#AEB6C4'; $tx.Margin = '0,4,0,0'; $sp.Children.Add($tx) | Out-Null
    Put $g $sp 1
    $bd.Child = $g; $w2.Content = $bd
    $w2.add_MouseLeftButtonUp({ $this.Close(); try { Show-FromTray } catch {} })
    # canto inferior esquerdo da TELA, no monitor onde o mouse está (onde a pessoa está olhando, até em jogo)
    $pos = $null
    try {
        $src = [System.Windows.PresentationSource]::FromVisual($W)
        $conv = $(if ($src) { $src.CompositionTarget.TransformFromDevice } else { $null })
        if ($conv) {
            $scr = [System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position)
            $tl = $conv.Transform((New-Object System.Windows.Point $scr.WorkingArea.Left, $scr.WorkingArea.Top)); $br = $conv.Transform((New-Object System.Windows.Point $scr.WorkingArea.Right, $scr.WorkingArea.Bottom))
            $pos = @{ L = $tl.X + 8; B = $br.Y - 8 }
        }
    } catch {}
    if (-not $pos) { $wa = [System.Windows.SystemParameters]::WorkArea; $pos = @{ L = $wa.Left + 8; B = $wa.Bottom - 8 } }
    $w2.Tag = $pos
    $w2.add_ContentRendered({ $this.Left = $this.Tag.L; $this.Top = $this.Tag.B - $this.ActualHeight })
    $w2.Left = -2000; $w2.Top = -2000
    $w2.Show()
    $tm = New-Object System.Windows.Threading.DispatcherTimer; $tm.Interval = [TimeSpan]::FromSeconds(8); $tm.Tag = $w2
    $tm.add_Tick({ $this.Stop(); try { $this.Tag.Close() } catch {} }); $tm.Start()
}
function Show-WinToast([string]$title, [string]$text) {
    try {
        [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        $xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
        $nodes = $xml.GetElementsByTagName('text')
        [void]$nodes.Item(0).AppendChild($xml.CreateTextNode('Janus: ' + (T $title)))
        [void]$nodes.Item(1).AppendChild($xml.CreateTextNode($text))
        $toast = New-Object Windows.UI.Notifications.ToastNotification $xml
        # o Windows só mostra notificações de apps registrados; usamos o registro do próprio PowerShell
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe').Show($toast)
    } catch { Write-Log ('Notificação do Windows falhou: ' + $_.Exception.Message) }
}
function Show-PopupAlert([string]$title, [string]$text, [string]$level = 'crit') {
    $d = New-Object System.Windows.Window
    $d.Title = 'Janus'; $d.Width = 460; $d.SizeToContent = 'Height'; $d.ResizeMode = 'NoResize'; $d.Topmost = $true; $d.WindowStartupLocation = 'CenterScreen'
    if ($W.Icon) { $d.Icon = $W.Icon }
    $d.Background = Brush '#0E1117'; $d.Foreground = Brush '#E6E9EF'; $d.FontFamily = 'Segoe UI Variable Text, Segoe UI, Microsoft YaHei UI'
    $root = New-Object System.Windows.Controls.StackPanel; $root.Margin = '24,20,24,20'
    $hr = New-Object System.Windows.Controls.StackPanel; $hr.Orientation = 'Horizontal'
    $ic = Glyph ([string]$LevelStyle[$(if ($level -eq 'warn') { 'warn' } else { 'crit' })][0]) 22 $(if ($level -eq 'warn') { '#F59E0B' } else { '#EF4444' }); $ic.Margin = '0,0,12,0'; $hr.Children.Add($ic) | Out-Null
    $hr.Children.Add((New-Text $title 17 '#E6E9EF' 'SemiBold')) | Out-Null
    $root.Children.Add($hr) | Out-Null
    $tx = New-Text $text 13 '#AEB6C4'; $tx.Margin = '0,10,0,16'; $root.Children.Add($tx) | Out-Null
    $b = New-Button 'Ok' 'Accent'; $b.HorizontalAlignment = 'Right'; $b.add_Click({ [System.Windows.Window]::GetWindow($this).Close() }); $root.Children.Add($b) | Out-Null
    $d.Content = $root; $d.Show()
}
# Envia um aviso pelos jeitos escolhidos (ou pelos informados em -Kinds)
function Send-Notify([string]$title, [string]$text, [string]$level = 'crit', $Kinds = $null) {
    $ks = @($(if ($Kinds) { $Kinds } else { $script:Config.NotifyKinds }) | ForEach-Object { if ($_ -eq 'janus') { 'corner' } else { $_ } } | Select-Object -Unique)   # 'janus' foi uma opção de teste: virou o próprio aviso do canto
    Write-Log ('Aviso: ' + $title + ' - ' + $text)
    if ($Teste) { return }
    foreach ($k in $ks) {
        try {
            switch ($k) {
                'corner' { Show-CornerAlert $title $text $level; Play-Alert $level }
                'toast'  { Show-WinToast $title $text }
                'popup'  { Show-PopupAlert $title $text $level }
                'sound'  { Play-Alert $level }
            }
        } catch { Write-Log ("Aviso '$k' falhou: " + $_.Exception.Message) }
    }
}
function Show-NotifySettings {
    $d = New-StyledWindow 'Notificações' 600
    $root = New-Object System.Windows.Controls.StackPanel; $root.Margin = '26,22,26,22'
    $root.Children.Add((New-Text 'Como o Janus deve avisar você?' 19 '#E6E9EF' 'SemiBold')) | Out-Null
    $ex = New-Text 'Escolha um ou mais jeitos e teste cada um. O QUE avisar você escolhe no sininho de cada item da Visão geral (processador, memória, placa de vídeo, SSD). O Failover também avisa quando troca de conexão.' 12.5 '#9AA3B2'; $ex.Margin = '0,6,0,12'; $root.Children.Add($ex) | Out-Null
    $boxes = [ordered]@{}
    foreach ($k in $NotifyKinds.Keys) {
        $g = New-Object System.Windows.Controls.Grid; Grid-Cols $g @('*', 'Auto'); $g.Margin = '0,6,0,0'
        $sp = New-Object System.Windows.Controls.StackPanel
        $cb = New-Object System.Windows.Controls.CheckBox; $cb.Content = (T $NotifyKinds[$k][0]); $cb.IsChecked = (@($script:Config.NotifyKinds) -contains $k); $cb.Foreground = Brush '#E6E9EF'
        $sp.Children.Add($cb) | Out-Null
        $ds = New-Text $NotifyKinds[$k][1] 11.5 '#7F8899'; $ds.Margin = '20,2,12,0'; $sp.Children.Add($ds) | Out-Null
        Put $g $sp 0
        $tb = New-Button 'Testar' 'Ghost' $k; $tb.Padding = '10,4'; $tb.FontSize = 12; $tb.VerticalAlignment = 'Top'
        $tb.add_Click({ Send-Notify 'Teste de notificação' (T 'Assim o Janus vai avisar você quando algo precisar de atenção.') 'warn' @($this.Tag) })
        Put $g $tb 1
        $root.Children.Add($g) | Out-Null; $boxes[$k] = $cb
    }
    # quantas vezes avisar
    $rh = New-Text 'Quantas vezes avisar' 14 '#E6E9EF' 'SemiBold'; $rh.Margin = '0,20,0,0'; $root.Children.Add($rh) | Out-Null
    $mins = @('1', '5', '10', '15', '30', '60')
    $rb1 = New-Object System.Windows.Controls.RadioButton; $rb1.Content = (T 'Só uma vez'); $rb1.GroupName = 'rep'; $rb1.Foreground = Brush '#E6E9EF'; $rb1.Margin = '0,10,0,0'; $rb1.IsChecked = ($script:Config.NotifyRepeat -ne 'repetir')
    $root.Children.Add($rb1) | Out-Null
    $w1 = New-Object System.Windows.Controls.WrapPanel; $w1.Margin = '20,4,0,0'
    $x1 = New-Text 'Avisar de novo só depois que o item ficar normal por pelo menos' 11.5 '#9AA3B2'; $x1.VerticalAlignment = 'Center'; $w1.Children.Add($x1) | Out-Null
    $cbA = New-Object System.Windows.Controls.ComboBox; $cbA.Width = 62; $cbA.Margin = '6,0,6,0'; $cbA.VerticalAlignment = 'Center'; foreach ($n in $mins) { [void]$cbA.Items.Add($n) }
    $cbA.SelectedItem = [string]$script:Config.NotifyRearm; if ($cbA.SelectedIndex -lt 0) { $cbA.SelectedItem = '30' }; $w1.Children.Add($cbA) | Out-Null
    $y1 = New-Text 'min' 11.5 '#9AA3B2'; $y1.VerticalAlignment = 'Center'; $w1.Children.Add($y1) | Out-Null
    $root.Children.Add($w1) | Out-Null
    $z1 = New-Text 'Assim, se o valor ficar subindo e descendo perto do limite, você não recebe vários avisos seguidos.' 11 '#6F7889'; $z1.Margin = '20,4,0,0'; $root.Children.Add($z1) | Out-Null
    $rb2 = New-Object System.Windows.Controls.RadioButton; $rb2.Content = (T 'Repetir enquanto continuar no vermelho'); $rb2.GroupName = 'rep'; $rb2.Foreground = Brush '#E6E9EF'; $rb2.Margin = '0,12,0,0'; $rb2.IsChecked = ($script:Config.NotifyRepeat -eq 'repetir')
    $root.Children.Add($rb2) | Out-Null
    $w2 = New-Object System.Windows.Controls.WrapPanel; $w2.Margin = '20,4,0,0'
    $x2 = New-Text 'Próximo aviso depois de' 11.5 '#9AA3B2'; $x2.VerticalAlignment = 'Center'; $w2.Children.Add($x2) | Out-Null
    $cbB = New-Object System.Windows.Controls.ComboBox; $cbB.Width = 62; $cbB.Margin = '6,0,6,0'; $cbB.VerticalAlignment = 'Center'; foreach ($n in $mins) { [void]$cbB.Items.Add($n) }
    $cbB.SelectedItem = [string]$script:Config.NotifyEvery; if ($cbB.SelectedIndex -lt 0) { $cbB.SelectedItem = '10' }; $w2.Children.Add($cbB) | Out-Null
    $y2 = New-Text 'min' 11.5 '#9AA3B2'; $y2.VerticalAlignment = 'Center'; $w2.Children.Add($y2) | Out-Null
    $root.Children.Add($w2) | Out-Null
    $br = New-Object System.Windows.Controls.StackPanel; $br.Orientation = 'Horizontal'; $br.HorizontalAlignment = 'Right'; $br.Margin = '0,18,0,0'
    $bc = New-Button 'Cancelar' 'Ghost'; $bc.Margin = '8,0,0,0'; $bc.add_Click({ [System.Windows.Window]::GetWindow($this).DialogResult = $false })
    $bo = New-Button 'Salvar' 'Accent'; $bo.Margin = '8,0,0,0'; $bo.add_Click({ [System.Windows.Window]::GetWindow($this).DialogResult = $true })
    $br.Children.Add($bc) | Out-Null; $br.Children.Add($bo) | Out-Null; $root.Children.Add($br) | Out-Null
    $d.Content = $root
    if ($Teste) { $d.Close(); return }
    $wasBusy = $script:Busy; $script:Busy = $true; try { $ok = $d.ShowDialog() } finally { $script:Busy = $wasBusy }
    if ($ok -ne $true) { return }
    $script:Config.NotifyKinds = @($boxes.Keys | Where-Object { $boxes[$_].IsChecked })
    if (-not $script:Config.NotifyKinds.Count) { $script:Config.NotifyKinds = @('corner') }
    $script:Config.NotifyRepeat = $(if ($rb2.IsChecked) { 'repetir' } else { 'uma' })
    $script:Config.NotifyRearm = [int]$cbA.SelectedItem; $script:Config.NotifyEvery = [int]$cbB.SelectedItem
    $script:AlertState = @{}
    Save-Config; Write-Log ('Notificações por: ' + ($script:Config.NotifyKinds -join ', ') + ' | ' + $(if ($script:Config.NotifyRepeat -eq 'repetir') { 'repetir a cada ' + $script:Config.NotifyEvery + ' min' } else { 'uma vez (de novo após ' + $script:Config.NotifyRearm + ' min normal)' }))
    if ($script:CurrentPage -eq 'Inicio') { Show-Page 'Inicio' $ui.Scroll.VerticalOffset }
}
# Depois de cada leitura do hardware: avisa quando um item com o sininho ligado fica vermelho.
# "uma vez": avisa e só avisa de novo depois que o item ficou normal por X min (evita avisos seguidos se o valor fica subindo e descendo no limite)
# "repetir": avisa a cada X min enquanto continuar vermelho
$script:AlertState = @{}
function Check-Alerts([switch]$Force) {
    $m = $script:Mon; if (-not $m) { return }
    if (-not @($script:Config.NotifyItems).Count -and -not $Force) { return }
    $items = @()
    if ($m.Gpu -and $null -ne $m.Gpu.Temp) { $items += , @('gputemp', $m.Gpu.Temp, 'Placa de vídeo muito quente', ('{0} °C' -f $m.Gpu.Temp)) }
    if ($null -ne $m.CpuTemp) { $items += , @('cputemp', $m.CpuTemp, 'Processador muito quente', ('{0} °C' -f $m.CpuTemp)) }
    $s = @($m.Ssd | Where-Object { $_ }) | Select-Object -First 1
    if ($s -and $s.Temp) { $items += , @('ssdtemp', $s.Temp, 'SSD muito quente', ('{0} °C' -f $s.Temp)) }
    if ($s -and $null -ne $s.Wear) { $items += , @('wear', $s.Wear, 'SSD perto do fim da vida útil', ((T 'desgaste {0}%') -f $s.Wear)) }
    if ($null -ne $m.Ram) { $items += , @('ram', $m.Ram, 'Memória quase cheia', ('{0}%' -f $m.Ram)) }
    $once = ($script:Config.NotifyRepeat -ne 'repetir')
    $rearm = [math]::Max(1, [double]$script:Config.NotifyRearm); $every = [math]::Max(1, [double]$script:Config.NotifyEvery); $now = Get-Date
    foreach ($it in $items) {
        $key = $(if ($it[0] -in 'ssdtemp', 'wear') { 'ssd' } else { $it[0] })
        if (-not $Force -and @($script:Config.NotifyItems) -notcontains $key) { continue }
        $st = $script:AlertState[$it[0]]
        if (-not $st) { $st = @{ Last = $null; Fired = $false; OkSince = $null }; $script:AlertState[$it[0]] = $st }
        if ((Get-MonLevel $it[0] $it[1]) -ne 'crit') {
            if ($st.Fired) {
                if (-not $st.OkSince) { $st.OkSince = $now }
                elseif (($now - $st.OkSince).TotalMinutes -ge $rearm) { $st.Fired = $false; $st.OkSince = $null }
            }
            continue
        }
        $st.OkSince = $null
        if (-not $Force) {
            if ($once) { if ($st.Fired) { continue } }
            elseif ($st.Last -and ($now - $st.Last).TotalMinutes -lt $every) { continue }
        }
        $st.Fired = $true; $st.Last = $now
        Send-Notify $it[2] ((T $it[3]) + '. ' + (T $MonHints[$it[0]])) 'crit'
    }
}
# ---------- testes e simulações (só na versão beta) ----------
$script:Sim = @{}
function Show-SimDialog([string]$title, $fields) {
    # fields: @( @('Rótulo', valorPadrão, 'unidade'), ... ) -> devolve os números ou $null
    $d = New-StyledWindow 'Testes' 480
    $root = New-Object System.Windows.Controls.StackPanel; $root.Margin = '26,22,26,22'
    $root.Children.Add((New-Text $title 18 '#E6E9EF' 'SemiBold')) | Out-Null
    $nt = New-Text 'É só uma simulação: nada no PC muda. Os números simulados aparecem na Visão geral e disparam os avisos como se fossem reais.' 12 '#9AA3B2'; $nt.Margin = '0,6,0,12'; $root.Children.Add($nt) | Out-Null
    $tbs = @()
    foreach ($fd in $fields) {
        $g = New-Object System.Windows.Controls.Grid; Grid-Cols $g @('*', '90', 'Auto'); $g.Margin = '0,6,0,0'
        $l = New-Text $fd[0] 13 '#AEB6C4'; $l.VerticalAlignment = 'Center'; Put $g $l 0
        $tb = New-Object System.Windows.Controls.TextBox; $tb.Text = [string]$fd[1]; $tb.Background = Brush '#171C26'; $tb.Foreground = Brush '#E6E9EF'; $tb.CaretBrush = Brush '#E6E9EF'; $tb.BorderBrush = Brush '#2A303C'; $tb.Padding = '6,4'; $tb.FontSize = 13
        Put $g $tb 1
        $u = New-Text $fd[2] 12 '#7F8899'; $u.VerticalAlignment = 'Center'; $u.Margin = '8,0,0,0'; Put $g $u 2
        $root.Children.Add($g) | Out-Null; $tbs += $tb
    }
    $cb = New-Object System.Windows.Controls.CheckBox; $cb.Content = (T 'Avisar mesmo com as notificações desligadas'); $cb.IsChecked = $true; $cb.Foreground = Brush '#E6E9EF'; $cb.Margin = '0,14,0,0'; $root.Children.Add($cb) | Out-Null
    $br = New-Object System.Windows.Controls.StackPanel; $br.Orientation = 'Horizontal'; $br.HorizontalAlignment = 'Right'; $br.Margin = '0,16,0,0'
    $bc = New-Button 'Cancelar' 'Ghost'; $bc.Margin = '8,0,0,0'; $bc.add_Click({ [System.Windows.Window]::GetWindow($this).DialogResult = $false })
    $bo = New-Button 'Simular' 'Accent'; $bo.Margin = '8,0,0,0'; $bo.add_Click({ [System.Windows.Window]::GetWindow($this).DialogResult = $true })
    $br.Children.Add($bc) | Out-Null; $br.Children.Add($bo) | Out-Null; $root.Children.Add($br) | Out-Null
    $d.Content = $root
    if ($Teste) { $d.Close(); return $null }
    $wasBusy = $script:Busy; $script:Busy = $true; try { $ok = $d.ShowDialog() } finally { $script:Busy = $wasBusy }
    if ($ok -ne $true) { return $null }
    $vals = @(); foreach ($tb in $tbs) { $n = 0; if (-not [double]::TryParse(($tb.Text -replace ',', '.'), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$n)) { return $null }; $vals += $n }
    return @{ Values = $vals; Force = [bool]$cb.IsChecked }
}
function Start-Sim([string]$kind, [string]$title, $fields) {
    $r = Show-SimDialog $title $fields; if (-not $r) { return }
    $script:Sim[$kind] = @{ Value = $r.Values[0]; Until = (Get-Date).AddSeconds([math]::Max(5, $r.Values[-1])); Force = $r.Force }
    Write-Log ("Simulação: $kind = " + $r.Values[0])
    Show-Toast ((T 'Simulação ligada por {0} s') -f [int]$r.Values[-1])
    Apply-Sims; Update-MonTiles; Check-Alerts -Force:$r.Force
}
# aplica as simulações ativas por cima da última leitura real
function Apply-Sims {
    if (-not $script:Mon) { return }
    foreach ($k in @($script:Sim.Keys)) {
        $s = $script:Sim[$k]; if ((Get-Date) -gt $s.Until) { $script:Sim.Remove($k); continue }
        switch ($k) {
            'ssdtemp' { if ($script:Mon.Ssd) { $script:Mon.Ssd = @(@{ Name = @($script:Mon.Ssd)[0].Name; Temp = [int]$s.Value; Wear = @($script:Mon.Ssd)[0].Wear }) } else { $script:Mon.Ssd = @(@{ Name = 'SSD'; Temp = [int]$s.Value; Wear = 0 }) } }
            'gputemp' { if ($script:Mon.Gpu) { $script:Mon.Gpu.Temp = [int]$s.Value } else { $script:Mon.Gpu = @{ Name = 'GPU'; Use = 50; Temp = [int]$s.Value; Fan = 100; Power = 200; MemUsed = 1024; MemTotal = 8192 } } }
            'cputemp' { $script:Mon.CpuTemp = [int]$s.Value }
            'space'   { $script:Mon.DiskUsedPct = [int]$s.Value }
            'ram'     { $script:Mon.Ram = [int]$s.Value }
        }
    }
}
function Show-TestMenu($anchor) {
    $cm = New-Object System.Windows.Controls.ContextMenu; $cm.Style = $W.FindResource('JMenu')
    $nt = New-MI 'Testar notificação'
    foreach ($k in $NotifyKinds.Keys) { [void]$nt.Items.Add((New-MI $NotifyKinds[$k][0] ([scriptblock]::Create("Send-Notify 'Teste de notificação' (T 'Assim o Janus vai avisar você quando algo precisar de atenção.') 'warn' @('$k')")))) }
    [void]$cm.Items.Add($nt)
    [void]$cm.Items.Add((New-MSep))
    [void]$cm.Items.Add((New-MI 'Simular temperatura do SSD...' { Start-Sim 'ssdtemp' (T 'Simular temperatura do SSD') @(@((T 'Temperatura'), 90, '°C'), @((T 'Por quanto tempo'), 30, 's')) }))
    [void]$cm.Items.Add((New-MI 'Simular temperatura da placa de vídeo...' { Start-Sim 'gputemp' (T 'Simular temperatura da placa de vídeo') @(@((T 'Temperatura'), 92, '°C'), @((T 'Por quanto tempo'), 30, 's')) }))
    [void]$cm.Items.Add((New-MI 'Simular temperatura do processador...' { Start-Sim 'cputemp' (T 'Simular temperatura do processador') @(@((T 'Temperatura'), 96, '°C'), @((T 'Por quanto tempo'), 30, 's')) }))
    [void]$cm.Items.Add((New-MI 'Simular disco quase cheio...' { Start-Sim 'space' (T 'Simular disco quase cheio') @(@((T 'Espaço usado'), 95, '%'), @((T 'Por quanto tempo'), 30, 's')) }))
    [void]$cm.Items.Add((New-MI 'Simular memória quase cheia...' { Start-Sim 'ram' (T 'Simular memória quase cheia') @(@((T 'Memória em uso'), 97, '%'), @((T 'Por quanto tempo'), 30, 's')) }))
    [void]$cm.Items.Add((New-MI 'Simular queda de conexão (Failover)...' { Start-FoSim }))
    [void]$cm.Items.Add((New-MSep))
    [void]$cm.Items.Add((New-MI 'Simular um erro do Janus' { Show-ReportDialog 'erro' "Erro: simulação de teste`r`nOnde: menu de testes" | Out-Null }))
    [void]$cm.Items.Add((New-MI 'Simular "o Janus fechou sozinho"' { Show-ReportDialog 'fechou' "Erro: simulação de teste" | Out-Null }))
    [void]$cm.Items.Add((New-MI 'Limpar as simulações' { $script:Sim = @{}; $script:FoSync.Sim = @{}; Write-Log 'Simulações limpas.'; Show-Toast 'Simulações limpas'; Start-MonRead }))
    $cm.PlacementTarget = $anchor; $cm.Placement = 'Bottom'; $cm.IsOpen = $true
    return $cm
}

# ---------- Failover: troca de conexão quando a principal fica instável ----------
if (-not ('JanusProbe' -as [type])) {
Add-Type -TypeDefinition @"
using System; using System.Net; using System.Net.Sockets; using System.Diagnostics;
public static class JanusProbe {
  // tempo para abrir uma conexão TCP saindo pelo IP de um adaptador; -1 = sem resposta
  public static double Probe(string v4, string target, int timeoutMs) {
    try {
      using (var s = new Socket(AddressFamily.InterNetwork, SocketType.Stream, ProtocolType.Tcp)) {
        if (!string.IsNullOrEmpty(v4)) s.Bind(new IPEndPoint(IPAddress.Parse(v4), 0));
        var sw = Stopwatch.StartNew(); var ar = s.BeginConnect(IPAddress.Parse(target), 443, null, null);
        if (!ar.AsyncWaitHandle.WaitOne(timeoutMs)) return -1;
        s.EndConnect(ar); return sw.Elapsed.TotalMilliseconds;
      }
    } catch { return -1; }
  }
}
"@
}
# Modos prontos. Loss = perda (%), Ms = atraso (ms), Jitter = variação (ms), Secs = por quanto tempo, Back = segundos estável para voltar
$FoPresets = [ordered]@{
    sensivel = @{ Name = 'Sensível'; Desc = 'Troca com qualquer instabilidade. Boa para quem não tolera nada, mas pode trocar várias vezes e cada troca derruba a conexão do jogo.'; Loss = 2; Ms = 100; Jitter = 30; Secs = 5; Back = 60 }
    moderado = @{ Name = 'Moderado'; Desc = 'Troca só com instabilidade pesada, do tipo que causa erros visíveis no jogo. Recomendado para jogar.'; Loss = 10; Ms = 200; Jitter = 80; Secs = 5; Back = 60 }
    queda    = @{ Name = 'Só em queda'; Desc = 'Troca só quando a conexão para de responder por completo. O mais estável: quase nunca troca à toa.'; Loss = 100; Ms = 0; Jitter = 0; Secs = 1; Back = 30 }
}
function Get-FoCfg {
    $c = $script:Config.Fo
    if (-not $c) { $c = @{ On = $false; Pref = ''; Preset = 'moderado'; Loss = 10; Ms = 200; Jitter = 80; Secs = 5; Back = 60; Expert = $false }; $script:Config.Fo = $c }
    if ($c -isnot [hashtable]) { $h = @{}; foreach ($p in $c.PSObject.Properties) { $h[$p.Name] = $p.Value }; $c = $h; $script:Config.Fo = $c }
    return $c
}
$script:FoSync = [hashtable]::Synchronized(@{ Stop = $true; Adapters = @(); Samples = @{}; Sim = @{}; Tick = 0 })
$script:FoActive = $null; $script:FoPrefGoodSince = $null; $script:FoUI = $null; $script:FoLastEval = [datetime]::MinValue
$FoLoop = @'
param($sync)
while (-not $sync.Stop) {
    $t = $(if (($sync.Tick % 2) -eq 0) { '1.1.1.1' } else { '8.8.8.8' })
    foreach ($a in @($sync.Adapters)) {
        $sim = $sync.Sim[[string]$a.Index]
        $ms = $(if ($sim -and (Get-Date) -lt $sim) { -1 } else { [JanusProbe]::Probe($a.V4, $t, 900) })
        $q = $sync.Samples[[string]$a.Index]
        if (-not $q) { $q = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList)); $sync.Samples[[string]$a.Index] = $q }
        [void]$q.Add(@((Get-Date), $ms)); while ($q.Count -gt 400) { $q.RemoveAt(0) }
    }
    $sync.Tick++
    Start-Sleep -Milliseconds 500
}
'@
# Procura o que pode brigar com o Failover pelo controle das conexões. Devolve uma lista de @{ Name; Why }.
# É genérico: olha rotas da internet por adaptadores virtuais/VPN, prioridade fixada à mão, outra cópia do Janus
# com Failover ligado e programas conhecidos que mexem nas rotas (aceleradores de jogo e VPNs).
$FoKnownApps = [ordered]@{
    'ExitLag' = 'ExitLag'; 'NoPing' = 'NoPing'; 'WTFast' = 'WTFast'; 'Mudfish' = 'Mudfish'; 'Haste' = 'Haste'; 'Outfox' = 'Outfox'; 'GearUP' = 'GearUP Booster'; 'LagoFast' = 'LagoFast'
    'Speedify' = 'Speedify'; 'Dispatch' = 'Connectify Dispatch'; 'Connectify' = 'Connectify'; 'openvpn' = 'OpenVPN'; 'wireguard' = 'WireGuard'; 'NordVPN' = 'NordVPN'; 'ProtonVPN' = 'Proton VPN'
    'ExpressVPN' = 'ExpressVPN'; 'Windscribe' = 'Windscribe'; 'warp-svc' = 'Cloudflare WARP'; 'tailscaled' = 'Tailscale'; 'zerotier' = 'ZeroTier'; 'hamachi' = 'Hamachi'; 'Surfshark' = 'Surfshark'
}
function Get-NetInterference {
    $out = New-Object System.Collections.ArrayList
    $phys = @(Get-NetAdapters | ForEach-Object { [int]$_.Index })
    # 1) internet passando por um adaptador que não é cabo/Wi-Fi (VPN, túnel, acelerador)
    try {
        $seen = @{}
        foreach ($r in @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue)) {
            if ($phys -contains [int]$r.InterfaceIndex -or $seen[$r.InterfaceIndex]) { continue }
            $seen[$r.InterfaceIndex] = 1
            $ad = Get-NetAdapter -InterfaceIndex $r.InterfaceIndex -ErrorAction SilentlyContinue
            if ($ad -and $ad.Status -ne 'Up') { continue }
            if ($ad -and ($ad.InterfaceDescription -match 'Hyper-V' -or $ad.Name -match 'vEthernet')) { continue }   # rede interna do Windows (WSL, máquinas virtuais)
            $nm = $(if ($ad) { '{0} ({1})' -f $ad.Name, $ad.InterfaceDescription } else { $r.InterfaceAlias })
            [void]$out.Add(@{ Name = $nm; Why = 'A internet também passa por esta conexão virtual (VPN, túnel ou acelerador de jogo). Os dois tentam decidir por onde a internet sai.'; Adapter = $(if ($ad) { $ad.Name } else { '' }) })
        }
    } catch {}
    # 2) prioridade fixada à mão (sem ser pelo Janus agora)
    if ($script:FoSync.Stop) {
        foreach ($i in @(Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $phys -contains [int]$_.InterfaceIndex -and $_.AutomaticMetric -eq 'Disabled' })) {
            if ($i.InterfaceMetric -in 5, 60) { continue }   # 5/60 são os valores do próprio Janus (sobra de um fechamento inesperado)
            [void]$out.Add(@{ Name = ('{0}: prioridade fixa {1}' -f $i.InterfaceAlias, $i.InterfaceMetric); Why = 'Alguém ou algum programa fixou a prioridade desta conexão. O Failover vai trocar esse valor e, ao desligar, volta para o automático do Windows.' })
        }
    }
    # 3) outra cópia do Janus (outra conta do PC) com o Failover ligado
    try {
        foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match 'Janus\.ps1' -and $_.CommandLine -notmatch '-Teste' })) {
            $own = Invoke-CimMethod -InputObject $p -MethodName GetOwner -ErrorAction SilentlyContinue
            if (-not $own -or $own.User -eq $env:USERNAME) { continue }
            $foOn = $null
            $cf = Join-Path $env:SystemDrive ('Users\{0}\AppData\Local\Janus\config.json' -f $own.User)
            if (Test-Path -LiteralPath $cf) { try { $foOn = [bool]((Get-Content -LiteralPath $cf -Raw -Encoding UTF8 | ConvertFrom-Json).Fo.On) } catch {} }
            if ($foOn -eq $false) { continue }
            [void]$out.Add(@{ Name = ((T 'Janus aberto na conta "{0}"') -f $own.User); Why = 'Duas cópias com o Failover ligado ficam trocando a prioridade uma da outra. Deixe o Failover ligado em uma conta só.' })
        }
    } catch {}
    # 4) programas conhecidos que mexem nas rotas, abertos agora
    # (guarda os arquivos e serviços de cada um, para o botão "derrubar e desativar" e para reativar depois)
    $all = @(Get-Process -ErrorAction SilentlyContinue); $svcAll = $null
    foreach ($k in $FoKnownApps.Keys) {
        $pp = @($all | Where-Object { $_.ProcessName -like "$k*" })
        if (-not $pp.Count -or @($out | Where-Object { $_.Name -like ('*' + $FoKnownApps[$k] + '*') }).Count) { continue }
        if ($null -eq $svcAll) { $svcAll = @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue) }
        $paths = @($pp | ForEach-Object { try { $_.Path } catch { $null } } | Where-Object { $_ } | Select-Object -Unique)
        $dirs = @($paths | ForEach-Object { Split-Path -Parent $_ } | Select-Object -Unique)
        $svcs = @($svcAll | Where-Object { $sv = $_; $sv.Name -like "*$k*" -or $sv.DisplayName -like "*$k*" -or @($dirs | Where-Object { $sv.PathName -and $sv.PathName -like "*$_*" }).Count } | ForEach-Object { $_.Name } | Select-Object -Unique)
        [void]$out.Add(@{ Name = ($FoKnownApps[$k] + ' (' + (T 'aberto') + ')'); Why = 'Este programa pode controlar por onde a internet sai (VPN ou acelerador de jogo, como o Multi Internet do ExitLag).'; Procs = $paths; Services = $svcs })
    }
    return , $out.ToArray()
}
# "Derrubar e desativar" (não recomendado): fecha os programas, para e desativa os serviços e desliga as conexões virtuais
# que interferem. Tudo fica anotado em Config.FoOverride e no Registro de mudanças, para o botão Reativar desfazer.
function Get-FoOverridePlan($found) {
    $l = @()
    foreach ($f in $found) {
        foreach ($sn in @($f.Services | Where-Object { $_ })) { $l += ((T 'parar e desativar o serviço {0}') -f $sn) }
        foreach ($pth in @($f.Procs | Where-Object { $_ })) { $l += ((T 'fechar {0}') -f [IO.Path]::GetFileName($pth)) }
        if ($f.Adapter) { $l += ((T 'desativar a conexão virtual {0}') -f $f.Adapter) }
    }
    return , $l
}
function Invoke-FoOverride($found) {
    $rec = New-Object System.Collections.ArrayList
    foreach ($x in @($script:Config.FoOverride | Where-Object { $_ })) { [void]$rec.Add($x) }
    foreach ($f in $found) {
        foreach ($sn in @($f.Services | Where-Object { $_ })) {
            $ws = Get-CimInstance Win32_Service -Filter ("Name='{0}'" -f ($sn -replace "'", "''")) -ErrorAction SilentlyContinue; if (-not $ws) { continue }
            if (-not @($rec | Where-Object { $_.Kind -eq 'service' -and $_.Name -eq $sn }).Count) { [void]$rec.Add(@{ Kind = 'service'; Name = $sn; Label = [string]$ws.DisplayName; StartMode = [string]$ws.StartMode; Running = ($ws.State -eq 'Running') }) }
            try { Stop-Service -Name $sn -Force -ErrorAction Stop } catch { Write-Log ('Override: não consegui parar o serviço {0}: {1}' -f $sn, $_.Exception.Message) }
            try { Set-Service -Name $sn -StartupType Disabled -ErrorAction Stop } catch { Write-Log ('Override: não consegui desativar o serviço {0}: {1}' -f $sn, $_.Exception.Message) }
            Write-Log ('Failover (override): serviço {0} parado e desativado (antes: {1}, {2})' -f $sn, $ws.StartMode, $ws.State)
        }
        foreach ($pth in @($f.Procs | Where-Object { $_ })) {
            if (-not @($rec | Where-Object { $_.Kind -eq 'process' -and $_.Path -eq $pth }).Count) { [void]$rec.Add(@{ Kind = 'process'; Path = $pth; Label = [IO.Path]::GetFileName($pth) }) }
            Get-Process -ErrorAction SilentlyContinue | Where-Object { try { $_.Path -eq $pth } catch { $false } } | Stop-Process -Force -ErrorAction SilentlyContinue
            Write-Log ('Failover (override): programa fechado: ' + $pth)
        }
        if ($f.Adapter) {
            if (-not @($rec | Where-Object { $_.Kind -eq 'adapter' -and $_.Name -eq $f.Adapter }).Count) { [void]$rec.Add(@{ Kind = 'adapter'; Name = $f.Adapter; Label = $f.Adapter }) }
            try { Disable-NetAdapter -Name $f.Adapter -Confirm:$false -ErrorAction Stop; Write-Log ('Failover (override): conexão virtual desativada: ' + $f.Adapter) } catch { Write-Log ('Override: não consegui desativar {0}: {1}' -f $f.Adapter, $_.Exception.Message) }
        }
    }
    $script:Config.FoOverride = @($rec); Save-Config
}
function Restore-FoOverride {
    $items = @($script:Config.FoOverride | Where-Object { $_ })
    $fail = @()
    # primeiro serviços e conexões, depois reabre os programas
    foreach ($it in @($items | Where-Object { $_.Kind -ne 'process' }) + @($items | Where-Object { $_.Kind -eq 'process' })) {
        try {
            switch ([string]$it.Kind) {
                'service' {
                    $m = @{ Auto = 'Automatic'; Manual = 'Manual'; Disabled = 'Disabled' }[[string]$it.StartMode]; if (-not $m) { $m = 'Manual' }
                    Set-Service -Name $it.Name -StartupType $m -ErrorAction Stop
                    if ($it.Running) { Start-Service -Name $it.Name -ErrorAction Stop }
                }
                'adapter' { Enable-NetAdapter -Name $it.Name -Confirm:$false -ErrorAction Stop }
                'process' { if (Test-Path -LiteralPath $it.Path) { Start-Unelevated $it.Path } }
            }
            Write-Log ('Failover: reativado ' + $it.Label)
        } catch { $fail += [string]$it.Label; Write-Log ('Failover: não consegui reativar {0}: {1}' -f $it.Label, $_.Exception.Message) }
    }
    $script:Config.FoOverride = @(); Save-Config
    if ($fail.Count) { Show-Toast ((T 'Reativado, menos: {0}') -f ($fail -join ', ')) } else { Show-Toast 'Tudo o que o Failover desligou foi reativado' }
}
function Start-Failover {
    $cfg = Get-FoCfg
    $ads = @(Get-NetAdapters | Where-Object { $_.V4 })
    if ($ads.Count -lt 2) { Show-Toast 'O Failover precisa de duas conexões ativas (por exemplo, cabo e Wi-Fi).'; return $false }
    if (-not $cfg.Pref -or -not ($ads | Where-Object { $_.Name -eq $cfg.Pref })) { $cfg.Pref = @($ads | Where-Object { $_.Primary } | Select-Object -First 1).Name; if (-not $cfg.Pref) { $cfg.Pref = $ads[0].Name } }
    $script:FoSync.Adapters = @($ads | ForEach-Object { @{ Index = $_.Index; V4 = $_.V4; Name = $_.Name } })
    if (-not $script:FoSync.Stop) { return $true }
    $script:FoSync.Stop = $false; $script:FoSync.Samples = @{}
    $rs = [runspacefactory]::CreateRunspace(); $rs.Open(); $ps = [powershell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript($FoLoop).AddArgument($script:FoSync)
    $script:FoJob = @{ PS = $ps; RS = $rs; Handle = $ps.BeginInvoke() }
    $pi = @($ads | Where-Object { $_.Name -eq $cfg.Pref } | Select-Object -First 1)
    Set-FoActive $pi[0] 'início'
    Write-Log ('Failover ligado. Preferida: ' + $cfg.Pref)
    return $true
}
function Stop-Failover {
    $script:FoSync.Stop = $true
    if ($script:FoJob) { try { $script:FoJob.PS.Stop(); $script:FoJob.PS.Dispose(); $script:FoJob.RS.Dispose() } catch {}; $script:FoJob = $null }
    # devolve as métricas ao automático do Windows
    foreach ($a in @($script:FoSync.Adapters)) { foreach ($af in 'IPv4', 'IPv6') { try { Set-NetIPInterface -InterfaceIndex $a.Index -AddressFamily $af -AutomaticMetric Enabled -ErrorAction Stop } catch {} } }
    $script:FoActive = $null
    Write-Log 'Failover desligado (prioridade das conexões voltou ao automático).'
}
function Set-FoActive($a, [string]$why) {
    if (-not $a) { return }
    foreach ($x in @($script:FoSync.Adapters)) {
        foreach ($af in 'IPv4', 'IPv6') { try { Set-NetIPInterface -InterfaceIndex $x.Index -AddressFamily $af -InterfaceMetric $(if ($x.Index -eq $a.Index) { 5 } else { 60 }) -ErrorAction Stop } catch {} }
    }
    $prev = $script:FoActive; $script:FoActive = $a.Index
    if ($prev -and $prev -ne $a.Index) {
        Write-Log ('Failover: conexão trocada para ' + $a.Name + ' (' + $why + ')')
        Send-Notify 'Conexão trocada' ((T 'O Janus passou a usar {0}: {1}.') -f $a.Name, (T $why)) 'warn'
    }
}
function Get-FoStats([string]$idx, [int]$secs) {
    $q = $script:FoSync.Samples[$idx]; if (-not $q) { return $null }
    $from = (Get-Date).AddSeconds(-[math]::Max(1, $secs))
    $win = @($q.ToArray() | Where-Object { $_[0] -ge $from })
    if (-not $win.Count) { return $null }
    $ok = @($win | Where-Object { $_[1] -ge 0 } | ForEach-Object { $_[1] })
    $loss = [math]::Round(100 * ($win.Count - $ok.Count) / $win.Count)
    $avg = $(if ($ok.Count) { [math]::Round(($ok | Measure-Object -Average).Average) } else { $null })
    $jit = 0; if ($ok.Count -gt 1) { for ($i = 1; $i -lt $ok.Count; $i++) { $jit += [math]::Abs($ok[$i] - $ok[$i - 1]) }; $jit = [math]::Round($jit / ($ok.Count - 1)) }
    $lastOk = @($q.ToArray() | Where-Object { $_[1] -ge 0 } | Select-Object -Last 1)
    $down = $(if ($lastOk.Count) { ((Get-Date) - $lastOk[0][0]).TotalSeconds } else { 999 })
    return @{ N = $win.Count; Loss = $loss; Avg = $avg; Jit = $jit; Down = $down; Full = ($win.Count -ge [math]::Max(2, $secs * 1.6)) }
}
function Test-FoBad($st, $cfg) {
    if (-not $st) { return $false }
    if ($cfg.Loss -ge 100 -or ($cfg.Ms -le 0 -and $cfg.Jitter -le 0)) { return ($st.Down -gt [math]::Max(1, $cfg.Secs)) }
    if ($st.Down -gt [math]::Max(1, $cfg.Secs)) { return $true }
    if (-not $st.Full) { return $false }
    return (($st.Loss -gt $cfg.Loss) -or ($cfg.Ms -gt 0 -and $null -ne $st.Avg -and $st.Avg -gt $cfg.Ms) -or ($cfg.Jitter -gt 0 -and $st.Jit -gt $cfg.Jitter))
}
function Invoke-FoEval {
    if ($script:FoSync.Stop) { return }
    if (((Get-Date) - $script:FoLastEval).TotalMilliseconds -lt 900) { return }
    $script:FoLastEval = Get-Date
    $cfg = Get-FoCfg
    $pref = @($script:FoSync.Adapters | Where-Object { $_.Name -eq $cfg.Pref } | Select-Object -First 1)[0]
    $act = @($script:FoSync.Adapters | Where-Object { $_.Index -eq $script:FoActive } | Select-Object -First 1)[0]
    if (-not $pref) { return }
    $bad = @{}; foreach ($a in $script:FoSync.Adapters) { $bad[[string]$a.Index] = Test-FoBad (Get-FoStats ([string]$a.Index) $cfg.Secs) $cfg }
    if ($bad[[string]$pref.Index]) { $script:FoPrefGoodSince = $null } elseif (-not $script:FoPrefGoodSince) { $script:FoPrefGoodSince = Get-Date }
    if ($act -and $act.Index -eq $pref.Index) {
        if ($bad[[string]$pref.Index]) {
            $alt = @($script:FoSync.Adapters | Where-Object { $_.Index -ne $pref.Index -and -not $bad[[string]$_.Index] } | Select-Object -First 1)[0]
            if ($alt) { Set-FoActive $alt $(if ((Get-FoStats ([string]$pref.Index) $cfg.Secs).Down -gt $cfg.Secs) { 'a conexão preferida caiu' } else { 'a conexão preferida ficou instável' }) }
        }
    } else {
        $back = $script:FoPrefGoodSince -and ((Get-Date) - $script:FoPrefGoodSince).TotalSeconds -ge [math]::Max(5, $cfg.Back)
        $actBad = (-not $act) -or $bad[[string]$act.Index]
        if ($back -or ($actBad -and -not $bad[[string]$pref.Index])) { Set-FoActive $pref 'a conexão preferida voltou a ficar estável' }
    }
    Update-FoStatus
}
function Start-FoSim {
    $ads = @($script:FoSync.Adapters)
    if ($script:FoSync.Stop -or -not $ads.Count) { Show-Choice 'Testes' 'Ligue o Failover primeiro' 'A simulação de queda só funciona com o Failover ligado (aba Rede > Failover).' @(@('ok', 'Ok', 'Accent')) 'info' | Out-Null; return }
    $cfg = Get-FoCfg
    $pref = @($ads | Where-Object { $_.Name -eq $cfg.Pref })[0]
    $r = Show-SimDialog ((T 'Simular queda de: {0}') -f $pref.Name) @(@((T 'Por quanto tempo'), 20, 's'))
    if (-not $r) { return }
    $script:FoSync.Sim[[string]$pref.Index] = (Get-Date).AddSeconds([math]::Max(3, $r.Values[0]))
    Write-Log ('Simulação: queda de ' + $pref.Name)
    Show-Toast ((T 'Simulando queda de {0} por {1} s') -f $pref.Name, [int]$r.Values[0])
}
# Texto e cor que explicam o que cada valor significa
function Get-FoHint([string]$field, [double]$v) {
    switch ($field) {
        'Loss'   { if ($v -ge 100) { @('#8B94A5', 'Ignorado: só troca em queda total.') } elseif ($v -le 2) { @('#22C55E', 'Exigente: troca com qualquer perda de pacotes.') } elseif ($v -le 10) { @('#84CC16', 'Equilibrado: perdas pequenas não trocam.') } elseif ($v -le 20) { @('#F59E0B', 'Tolerante: o jogo já pode mostrar travadas antes de trocar.') } else { @('#EF4444', 'Muito tolerante: com essa perda a conexão já está ruim para jogar.') } }
        'Ms'     { if ($v -le 0) { @('#8B94A5', 'Ignorado.') } elseif ($v -le 100) { @('#22C55E', 'Exigente: troca até com atraso que muita gente nem percebe.') } elseif ($v -le 200) { @('#84CC16', 'Equilibrado para a maioria dos jogos.') } elseif ($v -le 300) { @('#F59E0B', 'Tolerante: jogos competitivos já sentem esse atraso.') } else { @('#EF4444', 'Muito tolerante: com esse atraso a conexão já está ruim para jogar.') } }
        'Jitter' { if ($v -le 0) { @('#8B94A5', 'Ignorado.') } elseif ($v -le 30) { @('#22C55E', 'Exigente: troca com qualquer oscilação.') } elseif ($v -le 80) { @('#84CC16', 'Equilibrado.') } elseif ($v -le 150) { @('#F59E0B', 'Tolerante: oscilações assim já causam "teleportes" no jogo.') } else { @('#EF4444', 'Muito tolerante: a conexão já fica bem instável antes de trocar.') } }
        'Secs'   { if ($v -le 2) { @('#F59E0B', 'Reage muito rápido: pode trocar por um soluço de 1 segundo.') } elseif ($v -le 10) { @('#22C55E', 'Bom equilíbrio entre reagir rápido e não trocar à toa.') } else { @('#F59E0B', 'Demora para reagir: o problema dura mais antes da troca.') } }
        'Back'   { if ($v -lt 20) { @('#F59E0B', 'Volta rápido: se a preferida oscilar, o Janus pode ficar trocando.') } else { @('#22C55E', 'Seguro: só volta quando a preferida está estável de verdade.') } }
    }
}
function Test-FoTooLoose($cfg) { ($cfg.Loss -gt 20 -and $cfg.Loss -lt 100) -or $cfg.Ms -gt 300 -or $cfg.Jitter -gt 150 -or $cfg.Secs -gt 30 }
function Update-FoStatus {
    $u = $script:FoUI; if (-not $u -or $script:CurrentPage -ne 'Rede') { return }
    $cfg = Get-FoCfg
    foreach ($a in @($script:FoSync.Adapters)) {
        $tb = $u[[string]$a.Index]; if (-not $tb) { continue }
        $st = Get-FoStats ([string]$a.Index) ([math]::Max(5, $cfg.Secs))
        $isAct = ($script:FoActive -eq $a.Index)
        if (-not $st) { $tb.Text = $a.Name + ': ' + (T 'medindo...'); continue }
        $bad = Test-FoBad (Get-FoStats ([string]$a.Index) $cfg.Secs) $cfg
        $tb.Text = ('{0}{1}:  {2}  ·  {3}  ·  {4}' -f $(if ($isAct) { '● ' } else { '○ ' }), $a.Name, $(if ($null -ne $st.Avg) { '{0} ms' -f $st.Avg } else { T 'sem resposta' }), ((T 'perda {0}%') -f $st.Loss), ((T 'variação {0} ms') -f $st.Jit)) + $(if ($isAct) { '  ·  ' + (T 'em uso') } else { '' })
        $tb.Foreground = Brush $(if ($bad) { '#EF4444' } elseif ($st.Loss -gt 0 -or $st.Jit -gt 30) { '#F59E0B' } else { '#22C55E' })
    }
}
function Save-FoField([string]$field, [string]$text) {
    $cfg = Get-FoCfg; $n = 0
    if (-not [int]::TryParse(($text -replace '[^\d]', ''), [ref]$n)) { return }
    $lim = @{ Loss = @(0, 100); Ms = @(0, 2000); Jitter = @(0, 1000); Secs = @(1, 120); Back = @(5, 3600) }[$field]
    $n = [math]::Max($lim[0], [math]::Min($lim[1], $n))
    if ($cfg[$field] -ne $n) { $cfg[$field] = $n; $cfg.Preset = 'custom'; Save-Config; Write-Log ("Failover: $field = $n (personalizado)") }
    Show-Page 'Rede' $ui.Scroll.VerticalOffset
}
function Add-FailoverSection {
    $cfg = Get-FoCfg
    $ads = @(Get-NetAdapters | Where-Object { $_.V4 })
    $hdr = New-Object System.Windows.Controls.Grid; Grid-Cols $hdr @('*', 'Auto'); $hdr.Margin = '0,4,12,0'
    Put $hdr (New-Section 'FAILOVER') 0
    $sw = New-Object System.Windows.Controls.Primitives.ToggleButton; $sw.Style = $W.FindResource('Switch'); $sw.IsChecked = [bool]$cfg.On; $sw.VerticalAlignment = 'Center'
    $sw.ToolTip = (T $(if ($cfg.On) { 'Ligado. Clique para desligar.' } else { 'Desligado. Clique para ligar.' }))
    $sw.add_Click({
        $c = Get-FoCfg
        if ($this.IsChecked) {
            # antes de ligar: procura o que pode brigar pelas conexões e mostra o que é
            $ok = $true; $found = @(Get-NetInterference)
            if ($found.Count) {
                $lst = ($found | ForEach-Object { '• ' + $_.Name + "`n   " + (T $_.Why) }) -join "`n`n"
                Write-Log ('Failover: interferências encontradas: ' + (($found | ForEach-Object { $_.Name }) -join '; '))
                $plan = @(Get-FoOverridePlan $found)
                $btns = @(@('go', 'Ligar mesmo assim', 'Ghost'), @('no', 'Cancelar', 'Accent'))
                if ($plan.Count) { $btns = @(, @('kill', 'Derrubar e desativar (não recomendado)', 'Danger')) + $btns }
                $r = Show-Choice 'Failover' 'Algo pode interferir no Failover' ((T 'Encontrei:') + "`n`n" + $lst + "`n`n" + (T 'Recomendado: feche ou desligue isso antes. Se ligar mesmo assim, as trocas de conexão podem ficar erradas ou ir e voltar.')) $btns 'warn'
                if ($r -eq 'kill') {
                    $r2 = Show-Choice 'Failover' 'Derrubar e desativar?' ((T 'O Janus vai:') + "`n`n" + (($plan | ForEach-Object { '• ' + $_ }) -join "`n") + "`n`n" + (T 'Se houver uma partida em andamento, a conexão do jogo cai na hora. Os serviços ficam desativados até você reativar. Tudo fica anotado no Registro de mudanças, e o botão Reativar (em Internet e DNS) volta tudo como estava.')) @(@('yes', 'Derrubar e desativar', 'Danger'), @('no', 'Cancelar', 'Accent')) 'crit'
                    $ok = ($r2 -eq 'yes'); if ($ok) { Invoke-FoOverride $found }
                } else { $ok = ($r -eq 'go') }
            }
            if ($ok -and (Start-Failover)) { $c.On = $true } else { $this.IsChecked = $false; $c.On = $false }
        } else { Stop-Failover; $c.On = $false }
        Save-Config; $tm = New-Object System.Windows.Threading.DispatcherTimer; $tm.Interval = [TimeSpan]::FromMilliseconds(380); $tm.add_Tick({ $this.Stop(); Show-Page 'Rede' $ui.Scroll.VerticalOffset }); $tm.Start()
    })
    Put $hdr $sw 1; Add-Body $hdr
    $c = New-Card; $c.Padding = '18,14,18,14'
    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Children.Add((New-Text 'Acompanha suas conexões em tempo real e troca sozinho para a mais estável. Quando a conexão preferida volta a ficar estável, o Janus volta para ela.' 12.8 '#AEB6C4')) | Out-Null
    $w1 = New-Text 'Cada troca derruba a conexão do jogo, que precisa reconectar. O Failover evita ficar sem internet, não evita a reconexão. Funciona só com o Janus aberto.' 12 '#F59E0B'; $w1.Margin = '0,6,0,0'; $sp.Children.Add($w1) | Out-Null
    if ((Get-PcInfo).HasExitLag) { $w2 = New-Text 'O ExitLag está instalado: não use o Failover junto com o Multi Internet dele, os dois tentam controlar as conexões.' 12 '#F59E0B'; $w2.Margin = '0,4,0,0'; $sp.Children.Add($w2) | Out-Null }
    if ($ads.Count -lt 2) { $w3 = New-Text 'Precisa de duas conexões ativas ao mesmo tempo (por exemplo, cabo e Wi-Fi).' 12 '#EF4444'; $w3.Margin = '0,4,0,0'; $sp.Children.Add($w3) | Out-Null }
    # o que o "derrubar e desativar" desligou, com o botão para voltar
    $ov = @($script:Config.FoOverride | Where-Object { $_ })
    if ($ov.Count) {
        $ob = New-Object System.Windows.Controls.Border; $ob.CornerRadius = 10; $ob.Margin = '0,10,0,0'; $ob.Padding = '14,10'; $ob.BorderThickness = 1; $ob.BorderBrush = Brush '#7F1D1D'
        $ob.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(36, 0xEF, 0x44, 0x44))
        $og = New-Object System.Windows.Controls.Grid; Grid-Cols $og @('*', 'Auto')
        $ot = New-Text ((T 'Desligado pelo Failover para evitar interferência: {0}.') -f (($ov | ForEach-Object { [string]$_.Label }) -join ', ')) 12.5 '#FCA5A5'; $ot.VerticalAlignment = 'Center'; $ot.Margin = '0,0,12,0'; Put $og $ot 0
        $orb = New-Button 'Reativar' 'Ghost'; $orb.ToolTip = (T 'Volta os serviços, conexões e programas exatamente como estavam.'); $orb.add_Click({ Restore-FoOverride; Show-Page 'Rede' $ui.Scroll.VerticalOffset }); Put $og $orb 1
        $ob.Child = $og; $sp.Children.Add($ob) | Out-Null
    }
    # conexão preferida
    $r1 = New-Object System.Windows.Controls.WrapPanel; $r1.Margin = '0,12,0,0'
    $l1 = New-Text 'Conexão preferida:' 12.5 '#8B94A5' 'SemiBold'; $l1.VerticalAlignment = 'Center'; $l1.Margin = '0,0,10,0'; $r1.Children.Add($l1) | Out-Null
    $prefName = $(if ($cfg.Pref) { $cfg.Pref } else { @($ads | Where-Object { $_.Primary })[0].Name })
    foreach ($a in $ads) {
        $b = New-Object System.Windows.Controls.Button; $b.Style = $W.FindResource($(if ($a.Name -eq $prefName) { 'Accent' } else { 'Ghost' })); $b.Content = $a.Name; $b.Tag = $a.Name; $b.Padding = '12,4'; $b.Margin = '0,0,6,4'; $b.FontSize = 12
        $b.add_Click({ $c2 = Get-FoCfg; $c2.Pref = $this.Tag; Save-Config; Write-Log ('Failover: preferida = ' + $this.Tag); if (-not $script:FoSync.Stop) { $p2 = @($script:FoSync.Adapters | Where-Object { $_.Name -eq $c2.Pref })[0]; Set-FoActive $p2 'você escolheu outra conexão preferida' }; Show-Page 'Rede' $ui.Scroll.VerticalOffset })
        $r1.Children.Add($b) | Out-Null
    }
    $sp.Children.Add($r1) | Out-Null
    # modos prontos
    $r2 = New-Object System.Windows.Controls.WrapPanel; $r2.Margin = '0,8,0,0'
    $l2 = New-Text 'Modo:' 12.5 '#8B94A5' 'SemiBold'; $l2.VerticalAlignment = 'Center'; $l2.Margin = '0,0,10,0'; $r2.Children.Add($l2) | Out-Null
    foreach ($k in $FoPresets.Keys) {
        $b = New-Object System.Windows.Controls.Button; $b.Style = $W.FindResource($(if ($cfg.Preset -eq $k) { 'Accent' } else { 'Ghost' })); $b.Content = (T $FoPresets[$k].Name); $b.Tag = $k; $b.Padding = '12,4'; $b.Margin = '0,0,6,4'; $b.FontSize = 12
        $b.add_Click({ $c2 = Get-FoCfg; $p = $FoPresets[$this.Tag]; foreach ($f in 'Loss', 'Ms', 'Jitter', 'Secs', 'Back') { $c2[$f] = $p[$f] }; $c2.Preset = $this.Tag; Save-Config; Write-Log ('Failover: modo ' + $p.Name); Show-Page 'Rede' $ui.Scroll.VerticalOffset })
        $r2.Children.Add($b) | Out-Null
    }
    $pc2 = New-Object System.Windows.Controls.Border; $pc2.CornerRadius = 8; $pc2.Padding = '12,4'; $pc2.Margin = '0,0,6,4'; $pc2.BorderThickness = 1; $pc2.BorderBrush = Brush $(if ($cfg.Preset -eq 'custom') { '#818CF8' } else { '#2A303C' })
    $pc2.Child = (New-Text 'Personalizado' 12 $(if ($cfg.Preset -eq 'custom') { '#818CF8' } else { '#6F7889' }) 'SemiBold'); $r2.Children.Add($pc2) | Out-Null
    $sp.Children.Add($r2) | Out-Null
    $pd = New-Text $(if ($cfg.Preset -eq 'custom') { 'Personalizado: você mudou os valores abaixo. Para voltar a um modo pronto, clique nele.' } else { $FoPresets[$cfg.Preset].Desc }) 12 '#9AA3B2'; $pd.Margin = '0,4,0,8'; $sp.Children.Add($pd) | Out-Null
    # campos
    $fields = @(@('Loss', 'Trocar se a perda de pacotes passar de', '%'), @('Ms', 'Trocar se o atraso (ping) passar de', 'ms'), @('Jitter', 'Trocar se a variação passar de', 'ms'), @('Secs', 'Por pelo menos', 's'), @('Back', 'Voltar à preferida depois de estável por', 's'))
    foreach ($fd in $fields) {
        $g = New-Object System.Windows.Controls.Grid; Grid-Cols $g @('300', '80', '40', '*'); $g.Margin = '0,4,0,0'
        $lb = New-Text $fd[1] 12.5 '#AEB6C4'; $lb.VerticalAlignment = 'Center'; Put $g $lb 0
        $tb = New-Object System.Windows.Controls.TextBox; $tb.Text = [string]$cfg[$fd[0]]; $tb.Tag = $fd[0]
        $tb.Background = Brush '#0E1117'; $tb.Foreground = Brush '#E6E9EF'; $tb.CaretBrush = Brush '#E6E9EF'; $tb.BorderBrush = Brush '#2A303C'; $tb.Padding = '6,3'; $tb.FontSize = 13; $tb.HorizontalContentAlignment = 'Right'
        $tb.add_LostFocus({ Save-FoField $this.Tag $this.Text })
        $tb.add_KeyDown({ param($s, $e) if ($e.Key -eq 'Return') { Save-FoField $this.Tag $this.Text } })
        Put $g $tb 1
        $un = New-Text $fd[2] 12 '#7F8899'; $un.VerticalAlignment = 'Center'; $un.Margin = '6,0,0,0'; Put $g $un 2
        if (-not $cfg.Expert) { $h = Get-FoHint $fd[0] ([double]$cfg[$fd[0]]); $ht = New-Text $h[1] 11.5 $h[0]; $ht.VerticalAlignment = 'Center'; $ht.Margin = '10,0,0,0'; Put $g $ht 3 }
        $sp.Children.Add($g) | Out-Null
    }
    # aviso quando os valores aceitam conexão muito instável
    if (-not $cfg.Expert -and (Test-FoTooLoose $cfg)) {
        $wb = New-Object System.Windows.Controls.Border; $wb.CornerRadius = 10; $wb.Margin = '0,12,0,0'; $wb.Padding = '14,10'; $wb.Background = Brush '#2A2112'; $wb.BorderBrush = Brush '#78350F'; $wb.BorderThickness = 1
        $ws = New-Object System.Windows.Controls.StackPanel
        $ws.Children.Add((New-Text 'Com esses valores, a conexão já fica bem instável antes de o Janus trocar.' 12.8 '#FCD38D' 'SemiBold')) | Out-Null
        $wt = New-Text 'Se a ideia é jogar, prefira o modo Moderado. Mas pode ser de propósito, por exemplo para testar um servidor: nesse caso, marque abaixo e estes avisos param de aparecer.' 12 '#FCD38D'; $wt.Margin = '0,4,0,6'; $ws.Children.Add($wt) | Out-Null
        $ck = New-Object System.Windows.Controls.CheckBox; $ck.Content = (T 'Sei o que estou fazendo'); $ck.Foreground = Brush '#E6E9EF'
        $ck.add_Click({ $c2 = Get-FoCfg; $c2.Expert = [bool]$this.IsChecked; Save-Config; Show-Page 'Rede' $ui.Scroll.VerticalOffset }); $ws.Children.Add($ck) | Out-Null
        $wb.Child = $ws; $sp.Children.Add($wb) | Out-Null
    }
    if ($cfg.Expert) { $ex = New-Object System.Windows.Controls.CheckBox; $ex.Content = (T 'Sei o que estou fazendo (sem explicações e avisos)'); $ex.IsChecked = $true; $ex.Foreground = Brush '#7F8899'; $ex.Margin = '0,10,0,0'; $ex.add_Click({ $c2 = Get-FoCfg; $c2.Expert = [bool]$this.IsChecked; Save-Config; Show-Page 'Rede' $ui.Scroll.VerticalOffset }); $sp.Children.Add($ex) | Out-Null }
    # estado ao vivo
    $u = @{}
    if (-not $script:FoSync.Stop) {
        $st = New-Text 'Agora:' 12.5 '#8B94A5' 'SemiBold'; $st.Margin = '0,12,0,2'; $sp.Children.Add($st) | Out-Null
        foreach ($a in @($script:FoSync.Adapters)) { $tl = New-Text ($a.Name + ': ' + (T 'medindo...')) 12.8 '#AEB6C4'; $tl.Margin = '0,2,0,0'; $sp.Children.Add($tl) | Out-Null; $u[[string]$a.Index] = $tl }
    }
    $script:FoUI = $u
    $c.Child = $sp; Add-Body $c
    Update-FoStatus
}

# ---------- navegação ----------
$script:CurrentPage = ''
$script:NavButtons = @{}
$script:NavCounts = @{}
$NavTheme = @{ top = @('#16233D', '#2D4A7C', '#3B82F6'); bottom = @('#12271F', '#1F5C45', '#22C55E') }
function Update-NavCounts {
    $pairs = @{ 'Sugestoes' = @(Get-PendingSuggestions).Count; 'Ativos' = @(Get-ActiveTweaks).Count }
    if (($pairs['Sugestoes'] -gt 0) -ne $script:NavButtons.ContainsKey('Sugestoes')) { Build-Nav }
    foreach ($k in $pairs.Keys) {
        $nc = $script:NavCounts[$k]; if (-not $nc) { continue }
        $nc.Text.Text = [string]$pairs[$k]
        $nc.Pill.Visibility = $(if ($pairs[$k] -gt 0) { 'Visible' } else { 'Collapsed' })
    }
    if ($script:CurrentPage) { Paint-Nav $script:CurrentPage }
}
function Paint-Nav([string]$name) {
    foreach ($k in $script:NavButtons.Keys) {
        $nb = $script:NavButtons[$k]; $hl = $script:Pages[$k].Highlight
        # Sugestões só fica em destaque quando há sugestão pendente
        if ($k -eq 'Sugestoes' -and @(Get-PendingSuggestions).Count -eq 0) { $hl = $null }
        if ($hl) { $th = $NavTheme[$hl]; $nb.Background = Brush $th[0]; $nb.BorderBrush = Brush $(if ($k -eq $name) { $th[2] } else { $th[1] }); $nb.Foreground = Brush '#FFFFFF' }
        elseif ($k -eq $name) { $nb.Background = Brush '#1F2940'; $nb.BorderBrush = Brush 'Transparent'; $nb.Foreground = Brush '#FFFFFF' }
        else { $nb.Background = Brush 'Transparent'; $nb.BorderBrush = Brush 'Transparent'; $nb.Foreground = Brush '#AEB6C4' }
    }
}
function Show-Page([string]$name, [double]$keepScroll = -1) {
    if ($name -eq 'Sugestoes' -and -not @(Get-PendingSuggestions).Count -and -not $Teste) { $name = 'Inicio' }
    $samePage = ($script:CurrentPage -eq $name)
    $script:CurrentPage = $name
    $p = $script:Pages[$name]
    $ui.PageTitle.Text = (T (Get-PageTitle $name)); Set-PageSub $name
    if (-not $samePage) { $ui.Search.Text = '' }
    $isTweak = ($name -eq 'Otimizacoes') -or ($script:Config.NavMode -eq 'categorias' -and @($script:Tweaks | Where-Object { $_.Page -eq $name }).Count -gt 0)
    $ui.SearchBox.Visibility = $(if ($isTweak) { 'Visible' } else { 'Collapsed' })
    Paint-Nav $name
    $ui.HeaderExtra.Children.Clear()
    if ($name -eq 'Registro') {
        $lvw = $(if ($script:Config.LogView -eq 'detalhado') { 'detalhado' } else { 'simples' })
        foreach ($m in @(@('simples', 'Simples'), @('detalhado', 'Detalhado'))) {
            $hb = New-Object System.Windows.Controls.Button; $hb.Style = $W.FindResource($(if ($lvw -eq $m[0]) { 'Accent' } else { 'Ghost' })); $hb.Content = (T $m[1]); $hb.Tag = $m[0]
            $hb.Height = 36; $hb.Padding = '12,0'; $hb.Margin = '0,0,6,0'
            $hb.add_Click({ $script:Config.LogView = $this.Tag; Save-Config; Show-Page 'Registro' })
            $ui.HeaderExtra.Children.Add($hb) | Out-Null
        }
        $ui.HeaderExtra.Margin = '0,0,4,0'
    }
    $ui.BtnRefresh.Margin = $(if ($isTweak) { '0,0,10,0' } else { '0' })
    Clear-Body
    switch ($name) {
        'Sugestoes'  { Build-Sugestoes }
        'Ativos'     { Build-Ativos }
        'Automacao'  { Build-Automacao }
        'Inicio'     { Build-Inicio }
        'Manutencao' { Build-Manutencao }
        'Registro'   { Build-Registro }
        'Sobre'      { Build-Sobre }
        'Otimizacoes' { Build-Otimizacoes }
        'Jogos'      { Build-Jogos }
        'Rede'       { Build-Rede }
        default      { Build-Page $name }
    }
    if ($keepScroll -ge 0) {
        $script:ScrollTarget = $keepScroll
        [void]$W.Dispatcher.BeginInvoke([System.Action]{ $ui.Scroll.ScrollToVerticalOffset($script:ScrollTarget) }, [System.Windows.Threading.DispatcherPriority]::Loaded)
    } else { $ui.Scroll.ScrollToTop() }
    Update-UpdatedText
    Update-NavCounts
}

function Build-Nav {
    $ui.Nav.Children.Clear(); $ui.NavBottom.Children.Clear(); $script:NavButtons = @{}; $script:NavCounts = @{}
    $hasSug = @(Get-PendingSuggestions).Count -gt 0
    foreach ($k in @($script:Pages.Keys | Where-Object { (Test-PageInMode $_) -and ($_ -ne 'Sugestoes' -or $hasSug) })) {
        $p = $script:Pages[$k]
        $b = New-Object System.Windows.Controls.Button
        $b.Style = $W.FindResource('Nav'); $b.Background = Brush 'Transparent'; $b.Tag = $k
        $gr = New-Object System.Windows.Controls.Grid; Grid-Cols $gr @('Auto', '*', 'Auto')
        $gl = Glyph ([string]$p.Glyph) 16 $(if ($p.Highlight) { $NavTheme[$p.Highlight][2] } else { '#8EA3C8' }); $gl.Width = 26; $gl.VerticalAlignment = 'Center'; Put $gr $gl 0
        $tx = New-Text (Get-PageTitle $k) 13.5 '#D6DCE8' $(if ($p.Highlight) { 'SemiBold' } else { 'Normal' }); $tx.TextWrapping = 'NoWrap'; $tx.VerticalAlignment = 'Center'; $tx.TextTrimming = 'CharacterEllipsis'
        $tx.SetBinding([System.Windows.Controls.TextBlock]::ForegroundProperty, (New-Object System.Windows.Data.Binding('Foreground') -Property @{ Source = $b })) | Out-Null
        Put $gr $tx 1
        if ($p.Highlight -or $p.Bottom) {
            $pill = New-Object System.Windows.Controls.Border; $pill.CornerRadius = 9; $pill.Padding = '7,1,7,1'; $pill.Background = Brush $(if ($p.Highlight) { $NavTheme[$p.Highlight][2] } else { '#2A303C' }); $pill.VerticalAlignment = 'Center'
            $pt = New-Text '0' 11 $(if ($p.Highlight) { 'White' } else { '#AEB6C4' }) 'Bold'; $pt.TextWrapping = 'NoWrap'; $pill.Child = $pt; Put $gr $pill 2
            $script:NavCounts[$k] = @{ Pill = $pill; Text = $pt }
        }
        $b.Content = $gr
        $b.add_Click({ Show-Page $this.Tag })
        if ($p.Bottom) { $ui.NavBottom.Children.Add($b) | Out-Null } else { $ui.Nav.Children.Add($b) | Out-Null }
        if ($p.Highlight -eq 'top') { $sep = New-Object System.Windows.Controls.Border; $sep.Height = 1; $sep.Background = Brush '#1E2532'; $sep.Margin = '18,8,18,8'; $ui.Nav.Children.Add($sep) | Out-Null }
        $script:NavButtons[$k] = $b
    }
}
# Textos fixos da janela (vêm do XAML) no idioma atual
function Apply-StaticTexts {
    $ui.RefreshLabel.Text = (T 'Atualizar'); $ui.BtnRefresh.ToolTip = (T 'Ler tudo de novo agora')
    $ui.SearchHint.Text = (T 'Procurar ajuste...')
    $ui.BtnExplorer.Content = (T 'Reiniciar o Explorer'); $ui.BtnReboot.Content = (T 'Reiniciar o PC')
    $ui.FooterText.Text = (T 'Log, backups e ajuda em:') + "`n" + $DataDir
    $ui.MachineText.Text = "$env:COMPUTERNAME  |  v" + (Format-Version $AppVersion)
    Build-LangTop
    $ui.BetaBadge.Visibility = $(if ($AppVersion -match 'beta') { 'Visible' } else { 'Collapsed' })
    $ui.BetaBadge.ToolTip = (T 'Versão de testes: pode ter erros. Se algo der errado, use engrenagem > Reportar um problema.')
    Update-Pending
}
# Idiomas no topo: atalho para os 3 principais que não são o atual (em português: English, 中文, Español).
# A lista completa (português e os que vierem) fica em Manutenção > Idiomas.
$TopLangs = @('pt', 'en', 'zh', 'es')
$LangEnglish = @{ pt = 'Portuguese (Brazil)'; en = 'English'; zh = 'Chinese (Simplified)'; es = 'Spanish' }
function Build-LangTop {
    $ui.LangTop.Children.Clear()
    # globo: abre a janela de idiomas. Pisca (em destaque) até a pessoa abrir os idiomas pela primeira vez.
    $gb = New-Object System.Windows.Controls.Button
    $chosen = [bool]$script:Config.LangChosen
    $gb.Style = $W.FindResource($(if ($chosen) { 'Ghost' } else { 'Accent' })); $gb.Padding = '9,3'; $gb.Margin = '0,0,2,0'
    $gl = New-Object System.Windows.Controls.TextBlock; $gl.Text = [string][char]0xE774; $gl.FontFamily = 'Segoe Fluent Icons, Segoe MDL2 Assets'; $gl.FontSize = 13
    $gl.Foreground = Brush $(if ($chosen) { '#AEB6C4' } else { 'White' }); $gb.Content = $gl
    $gb.ToolTip = (T 'Idiomas'); [System.Windows.Automation.AutomationProperties]::SetName($gb, (T 'Idiomas'))
    $gb.add_Click({ Show-LanguageDialog })
    if (-not $chosen) {
        $an = New-Object System.Windows.Media.Animation.DoubleAnimation 1.0, 0.35, ([TimeSpan]::FromMilliseconds(750))
        $an.AutoReverse = $true; $an.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
        $gb.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $an)
    }
    $ui.LangTop.Children.Add($gb) | Out-Null
    foreach ($code in @($TopLangs | Where-Object { $_ -ne $script:Lang } | Select-Object -First 3)) {
        $b = New-Object System.Windows.Controls.Button
        $b.Style = $W.FindResource('Ghost'); $b.Content = $Langs[$code]; $b.Tag = $code
        $b.Padding = '10,3'; $b.Margin = '4,0,0,0'; $b.FontSize = 12; $b.ToolTip = $LangEnglish[$code]
        $b.add_Click({ Set-Language $this.Tag })
        $ui.LangTop.Children.Add($b) | Out-Null
    }
    # engrenagem: preferências do Janus num menu simples
    $gear = New-Object System.Windows.Controls.Button; $gear.Style = $W.FindResource('Ghost'); $gear.Padding = '9,3'; $gear.Margin = '8,0,0,0'
    $gt = New-Object System.Windows.Controls.TextBlock; $gt.Text = [string][char]0xE713; $gt.FontFamily = 'Segoe Fluent Icons, Segoe MDL2 Assets'; $gt.FontSize = 14; $gt.Foreground = Brush '#AEB6C4'; $gear.Content = $gt
    $gear.ToolTip = (T 'Configurações do Janus'); [System.Windows.Automation.AutomationProperties]::SetName($gear, (T 'Configurações do Janus'))
    $gear.add_Click({ [void](Show-GearMenu $this) })
    $ui.LangTop.Children.Add($gear) | Out-Null
}
function Show-LanguageDialog {
    $d = New-StyledWindow 'Idiomas' 460
    $root = New-Object System.Windows.Controls.StackPanel; $root.Margin = '26,22,26,22'
    $hr = New-Object System.Windows.Controls.StackPanel; $hr.Orientation = 'Horizontal'
    $ic = Glyph ([string][char]0xE774) 22 '#818CF8'; $ic.Margin = '0,0,12,0'; $ic.VerticalAlignment = 'Center'; $hr.Children.Add($ic) | Out-Null
    $ht = New-Text 'Escolha o idioma' 19 '#E6E9EF' 'SemiBold'; $ht.VerticalAlignment = 'Center'; $hr.Children.Add($ht) | Out-Null
    $root.Children.Add($hr) | Out-Null
    $sub = New-Text 'O Janus inteiro muda na hora, sem reiniciar.' 12.5 '#9AA3B2'; $sub.Margin = '0,8,0,14'; $root.Children.Add($sub) | Out-Null
    foreach ($code in $Langs.Keys) {
        $b = New-Object System.Windows.Controls.Button
        $b.Style = $W.FindResource($(if ($code -eq $script:Lang) { 'Accent' } else { 'Ghost' })); $b.HorizontalContentAlignment = 'Stretch'; $b.Margin = '0,0,0,8'; $b.Padding = '14,9'; $b.Tag = $code
        $g = New-Object System.Windows.Controls.Grid; Grid-Cols $g @('*', 'Auto')
        $n1 = New-Object System.Windows.Controls.TextBlock; $n1.Text = $Langs[$code]; $n1.FontSize = 14; $n1.FontWeight = 'SemiBold'; $n1.Foreground = Brush $(if ($code -eq $script:Lang) { 'White' } else { '#E6E9EF' }); Put $g $n1 0
        $n2 = New-Object System.Windows.Controls.TextBlock; $n2.Text = $(if ($code -eq $script:Lang) { '✓  ' + $LangEnglish[$code] } else { $LangEnglish[$code] }); $n2.FontSize = 12; $n2.Foreground = Brush $(if ($code -eq $script:Lang) { '#DCE7FF' } else { '#9AA3B2' }); $n2.VerticalAlignment = 'Center'; Put $g $n2 1
        $b.Content = $g
        $b.add_Click({ $win = [System.Windows.Window]::GetWindow($this); $win.Tag = $this.Tag; $win.DialogResult = $true })
        $root.Children.Add($b) | Out-Null
    }
    $more = New-Text 'Mais idiomas serão adicionados nas próximas versões.' 11.5 '#6F7889'; $more.Margin = '0,6,0,0'; $root.Children.Add($more) | Out-Null
    $bc = New-Button 'Fechar' 'Ghost'; $bc.HorizontalAlignment = 'Right'; $bc.Margin = '0,14,0,0'; $bc.add_Click({ [System.Windows.Window]::GetWindow($this).DialogResult = $false }); $root.Children.Add($bc) | Out-Null
    $d.Content = $root; $d.Tag = ''
    if ($Teste) { $d.Close(); return }
    $wasBusy = $script:Busy; $script:Busy = $true
    try { [void]$d.ShowDialog() } finally { $script:Busy = $wasBusy }
    # abriu os idiomas: mesmo sem trocar (já estava certo), o globo para de piscar
    if (-not $script:Config.LangChosen) { $script:Config.LangChosen = $true; Save-Config; Build-LangTop }
    if ($d.Tag) { Set-Language ([string]$d.Tag) }
}
function Set-Language([string]$code) {
    if ($code -eq $script:Lang) { return }
    if ($code -ne 'pt' -and -not $script:I18N[$code]) { Show-Toast 'Arquivo de idiomas não encontrado'; return }
    $script:Lang = $code; $script:Config.Lang = $code; Save-Config
    Write-Log ('Idioma: ' + $Langs[$code])
    Apply-StaticTexts; Build-Nav
    if ($script:CurrentPage) { Show-Page $script:CurrentPage $ui.Scroll.VerticalOffset }
    elseif ($script:FirstLoad) { $ui.PageTitle.Text = (T $script:Pages['Inicio'].Title); Set-PageSub 'Inicio' }
    Show-Toast ($Langs[$code])
}
Build-Nav

$ui.Search.add_TextChanged({
    $q = $ui.Search.Text.Trim()
    $ui.SearchHint.Visibility = $(if ($q) { 'Collapsed' } else { 'Visible' })
    foreach ($t in @($script:Tweaks | Where-Object { ($script:CurrentPage -eq 'Otimizacoes' -or $_.Page -eq $script:CurrentPage) -and $_.UI })) {
        $match = (-not $q) -or ($t.Title -like "*$q*") -or ($t.Desc -like "*$q*")
        $t.UI.Card.Visibility = $(if ($match) { 'Visible' } else { 'Collapsed' })
    }
})

# ---------- atualização automática (em segundo plano) ----------
function Set-LiveState([string]$lv) {
    $col = @{ ok = '#22C55E'; busy = '#F59E0B'; err = '#EF4444' }[$lv]
    $ui.LiveDot.Fill = Brush $col; $ui.RefreshIcon.Foreground = Brush $col
    # dica da luz: o que está sendo feito ou o que você deve fazer
    $sec = @($script:Snap.Sec)
    $crit = @($sec | Where-Object { $_ -and $_.Level -eq 'crit' } | ForEach-Object { T $_.Name })
    $warn = @($sec | Where-Object { $_ -and $_.Level -eq 'warn' } | ForEach-Object { T $_.Name })
    $hint = $(switch ($lv) {
        'busy' { T 'Lendo o Windows agora, em segundo plano. A janela continua livre.' }
        'err'  { if ($crit.Count) { (T 'Urgente: {0}. Abra a Visão geral para ver o que fazer.') -f ($crit -join ', ') } else { T 'A última leitura falhou. Veja o Registro de mudanças ou reporte o problema em Manutenção.' } }
        default { if ($warn.Count) { (T 'Lido e em dia. Pedem atenção: {0}. Veja na Visão geral.') -f ($warn -join ', ') } else { T 'Tudo em dia: o Janus lê o Windows em segundo plano e nada precisa de você agora.' } }
    })
    $ui.LiveDot.ToolTip = $hint; $ui.UpdatedText.ToolTip = $hint
    [System.Windows.Controls.ToolTipService]::SetInitialShowDelay($ui.LiveDot, 100)
}
function Update-UpdatedText {
    $iv = Get-Intervals
    $at = $(if ($script:Snap.FastAt -gt [datetime]::MinValue) { $script:Snap.FastAt } else { Get-Date })
    $ui.UpdatedText.Text = ((T 'Lido às {0}') -f $at.ToString('HH:mm:ss'))
    $ui.UpdatedText.ToolTip = ((T 'Ajustes lidos a cada {0} s e segurança a cada {1}, em segundo plano. Para mudar, veja Manutenção > Otimizar o Janus.') -f $iv.Fast, (T $(if ($iv.Full -ge 120) { '{0} min' -f ($iv.Full / 60) } else { '1 min' })))
}
function Get-FastSignature { (@($script:Tweaks | ForEach-Object { [string]$script:Snap.State[$_.Id] + '/' + [string]$script:Snap.Avail[$_.Id] })) -join '|' }
function Get-SlowSignature { (@($script:Snap.Checks | ForEach-Object { [string]$_ }) + @($script:Snap.Sec | ForEach-Object { $_.Name + '=' + $_.Value })) -join '|' }
function Rebuild-Current([bool]$slow = $true) {
    $p = $script:CurrentPage; if (-not $p) { return }
    $hasChecks = @($script:Checks | Where-Object { $_.Page -eq $p }).Count -gt 0
    if ($p -in 'Inicio', 'Sugestoes', 'Ativos', 'Automacao' -or ($slow -and $hasChecks)) { Show-Page $p $ui.Scroll.VerticalOffset }
    else { foreach ($t in @($script:Tweaks | Where-Object { $_.Page -eq $p -and $_.UI })) { if (Is-Available $t) { Refresh-Card $t } }; Update-NavCounts }
}
function Apply-Snapshot($res) {
    $oldFast = Get-FastSignature; $oldSlow = Get-SlowSignature
    $fresh = Merge-Snapshot $res
    if ($res.Full -and $fresh) { $crit = @($script:Snap.Sec | Where-Object { $_.Level -eq 'crit' }).Count; Set-LiveState $(if ($crit) { 'err' } else { 'ok' }); Sync-SecOff }
    if ($script:FirstLoad) { $script:FirstLoad = $false; Show-Page $(if ($Pagina -and $script:Pages.Contains($Pagina) -and (Test-PageInMode $Pagina)) { $Pagina } else { 'Inicio' }); return }
    $fastChanged = (Get-FastSignature) -ne $oldFast
    $slowChanged = $res.Full -and ((Get-SlowSignature) -ne $oldSlow)
    $forced = $script:ToastWhenDone -and $res.Full -and $fresh
    if ($fastChanged -or $slowChanged -or $forced) {
        if ($script:Busy) { $script:PendingRebuild = $true } else { Rebuild-Current ($slowChanged -or $forced) }
    }
    if ($forced) { $script:ToastWhenDone = $false; Show-Toast ('Tudo lido de novo em {0} ms' -f $res.Ms) }
    Update-UpdatedText
}
$script:Poll = New-Object System.Windows.Threading.DispatcherTimer
$script:Poll.Interval = [TimeSpan]::FromMilliseconds(400)
$script:Poll.add_Tick({
    try {
        if (Test-Path -LiteralPath $ShowReq) { Remove-Item -LiteralPath $ShowReq -Force -ErrorAction SilentlyContinue; Show-FromTray }
        if (Test-Path -LiteralPath $CloseReq) { Remove-Item -LiteralPath $CloseReq -Force -ErrorAction SilentlyContinue; $script:CleanExit = $true; $W.Close(); return }
        Receive-BgJobs
        $mi = $MonLevels[$script:Config.MonLevel][1]
        if ($script:CurrentPage -ne 'Inicio') { $mi = $(if (@($script:Config.NotifyItems).Count) { 30 } else { 0 }) }
        if ($mi -gt 0 -and -not $script:BgJobs.ContainsKey('mon') -and ((Get-Date) - $script:MonAt).TotalSeconds -ge $mi -and $W.WindowState -ne 'Minimized') { Start-MonRead }
        if ($script:CurrentPage -eq 'Rede' -and $script:Config.DnsAuto -and $script:DnsTestedAt -and ((Get-Date) - $script:DnsTestedAt).TotalMinutes -ge 5 -and -not $script:BgJobs.ContainsKey('dns')) { Start-DnsTest }
        if (-not $script:Busy) { Invoke-SecReminder }
        Invoke-FoEval
        if ($script:NetJob -and $script:NetJob.Handle.IsCompleted) { Receive-UpdateCheck }
        if ($script:Config.AutoUpdate -and -not $script:NetJob -and -not $script:FirstLoad -and (Get-Date) -ge $script:NextUpdateCheck) { Start-UpdateCheck }
        if ($script:Job) {
            if ($script:Job.Handle.IsCompleted) { $res = Receive-Worker; Apply-Snapshot $res; if ($script:Config.LightMode) { [GC]::Collect() } }
            return
        }
        if ($script:PendingRebuild -and -not $script:Busy) { $script:PendingRebuild = $false; Rebuild-Current }
        if ($script:Config.LightMode -and -not $script:ForceFull -and ($W.WindowState -eq 'Minimized' -or -not $W.IsActive)) { return }
        $iv = Get-Intervals; $now = Get-Date
        if ($script:ForceFull -or ($now - $script:Snap.FullAt).TotalSeconds -ge $iv.Full) { $script:ForceFull = $false; Start-Worker $true }
        elseif (($now - $script:Snap.FastAt).TotalSeconds -ge $iv.Fast) { Start-Worker $false }
    } catch {
        if ($script:Job) { try { $script:Job.PS.Dispose() } catch {}; $script:Job = $null }
        Set-LiveState 'err'
        $m = $_.Exception.Message
        if ($m -ne $script:LastErr) { $script:LastErr = $m; Write-Log ('ERRO na leitura em segundo plano: ' + $m) }
        $script:Snap.FastAt = Get-Date   # espera o próximo ciclo antes de tentar de novo
    }
})

$ui.BtnExplorer.add_Click({ Restart-Explorer; Show-Toast 'Explorer reiniciado' })
$ui.BtnRefresh.add_Click({ $script:ForceFull = $true; Start-MonRead; $script:ToastWhenDone = $true; Set-LiveState 'busy'; Show-Toast 'Lendo tudo de novo em segundo plano...' })
$ui.BtnReboot.add_Click({
    $r = Show-Choice 'Reiniciar' 'Reiniciar o PC agora?' 'Salve o que estiver aberto antes. O PC reinicia em 5 segundos.' @(@('yes', 'Reiniciar', 'Accent'), @('no', 'Agora não', 'Ghost')) 'warn'
    if ($r -eq 'yes') { Write-Log 'Reinício do PC pedido pelo Janus.'; $script:CleanExit = $true; & shutdown.exe /r /t 5 /c "Janus: reiniciando para aplicar as mudanças" }
})
$W.Title = $AppName; try { $W.FindName('BrandText').Text = $AppName } catch {}
$W.add_ContentRendered({
    # depois de atualizar: janela com as novidades (não aparece na primeira vez que o Janus é aberto)
    $prevV = [string]$script:Config.LastVersion; $isUpd = ($script:Config.WarningSeen -and $prevV -ne $AppVersion)
    if ($prevV -ne $AppVersion) { $script:Config.LastVersion = $AppVersion; Save-Config }
    if (-not $script:Config.WarningSeen) { Show-Welcome }
    if ($isUpd) { Show-Changelog $prevV }
    if (-not $script:Config.AiAsked) { [void](Show-AiSetup) }
    if (@(Get-SecOffList).Count -and -not (Test-Dnd)) {
        $names = (@(Get-SecOffList) | ForEach-Object { T $SecInfo[$_.Id].Name }) -join ', '
        $r = Show-Choice 'Segurança' 'Há proteções desligadas' ((T 'Continuam desligadas: {0}. Recomendamos estritamente religar.') -f $names) @(@('go', 'Ir para Segurança', 'Accent'), @('no', 'Agora não', 'Ghost')) 'crit'
        if ($r -eq 'go') { Show-Page 'Seguranca' }
    }
    if ($script:PrevCrashed) {
        $det = ''; if (Test-Path -LiteralPath $CrashFile) { $det = [IO.File]::ReadAllText($CrashFile) }
        Show-ReportDialog 'fechou' $det | Out-Null
        Remove-Item -LiteralPath $CrashFile -Force -ErrorAction SilentlyContinue
    }
})
$W.add_Closing({
    param($s, $e)
    if ($script:CleanExit -or $Teste) { return }
    if ($script:Config.Tray) { $e.Cancel = $true; Hide-ToTray; return }
    if ($script:Config.CloseAsked) { return }
    $r = Show-CloseAsk
    if ($r -eq 'tray') { $e.Cancel = $true; Hide-ToTray } elseif ($r -ne 'close') { $e.Cancel = $true }
})
$W.add_Activated({ if ($script:Config.LightMode -and ((Get-Date) - $script:Snap.FastAt).TotalSeconds -ge 5) { $script:Snap.FastAt = [datetime]::MinValue } })
# Erro não tratado dentro da janela: o Janus não fecha. Guarda o erro e oferece o relatório.
$W.Dispatcher.add_UnhandledException({
    param($s, $e)
    $e.Handled = $true
    $det = Save-CrashInfo $e.Exception 'janela'
    try { Show-ReportDialog 'erro' $det | Out-Null } catch {}
})

Write-Log ('Janus ' + $AppVersion + ' aberto' + $(if ($Teste) { ' (modo teste)' } else { '' }))
Apply-StaticTexts

if ($Teste) {
    $sw = [Diagnostics.Stopwatch]::StartNew(); $r0 = Invoke-WorkerNow $true; Write-Output ("leitura completa em segundo plano: {0} ms (worker {1} ms)" -f $sw.ElapsedMilliseconds, $r0.Ms)
    foreach ($k in $script:Pages.Keys) { $sw.Restart(); Show-Page $k; Write-Output ("pagina {0,-12}: {1,2} elemento(s), montada em {2} ms" -f $k, $ui.Body.Children.Count, $sw.ElapsedMilliseconds) }
    Write-Output ("ativos: " + ((Get-ActiveTweaks | ForEach-Object { $_.Id }) -join ', '))
    # tarefas em segundo plano (monitor, DNS, jogos) e telas novas
    Start-MonRead; Start-DnsTest; Start-GameScan
    $sw.Restart(); while ($script:BgJobs.Count -and $sw.Elapsed.TotalSeconds -lt 90) { Start-Sleep -Milliseconds 300; Receive-BgJobs }
    Write-Output ("monitor: cpu={0}% ram={1}% disco={2}% cheio, gpu={3}% {4}C ventoinha={5}% | ssd={6} | cpu temp={7}" -f $script:Mon.Cpu, $script:Mon.Ram, $script:Mon.DiskUsedPct, $script:Mon.Gpu.Use, $script:Mon.Gpu.Temp, $script:Mon.Gpu.Fan, (@($script:Mon.Ssd | ForEach-Object { '{0} {1}C desgaste {2}%' -f $_.Name, $_.Temp, $_.Wear }) -join '; '), $script:Mon.CpuTemp)
    Write-Output ("dns (ms): " + ((@($script:DnsTimes.Keys | Sort-Object) | ForEach-Object { '{0}={1}' -f $_, $script:DnsTimes[$_] }) -join ' '))
    Write-Output ("jogos: {0} -> {1}" -f @($script:Games).Count, ((@($script:Games) | Select-Object -First 12 | ForEach-Object { $_.Name + ' (' + $_.Source + ')' }) -join ', '))
    Write-Output ("adaptadores: " + ((Get-NetAdapters | ForEach-Object { '{0} v4={1} principal={2} dnsManual={3}' -f $_.Name, $_.V4, $_.Primary, $_.Manual }) -join ' | '))
    foreach ($k in 'Inicio', 'Rede', 'Jogos', 'Otimizacoes', 'Seguranca', 'Automacao') { $sw.Restart(); Show-Page $k; Write-Output ("pagina {0,-12}: {1,2} elemento(s), {2} ms" -f $k, $ui.Body.Children.Count, $sw.ElapsedMilliseconds) }
    foreach ($o in 'alfa', 'cat', 'prio') { $script:Config.OptSort = $o; foreach ($v in 'grade', 'detalhado') { $script:Config.OptView = $v; Show-Page 'Otimizacoes' } }
    $script:Config.NavMode = 'categorias'; Build-Nav; Show-Page 'Rede'; Show-Page 'Entrada'; Write-Output ("modo categorias: abas=" + $ui.Nav.Children.Count); $script:Config.NavMode = 'simples'; Build-Nav
    try { $cm = Show-GearMenu $ui.LangTop; Write-Output ("menu da engrenagem: {0} itens, submenu IA={1}" -f $cm.Items.Count, ($cm.Items | Where-Object { $_.Header -eq 'Inteligência artificial' }).Items.Count); $cm.IsOpen = $false } catch { Write-Output ('menu da engrenagem falhou: ' + $_.Exception.Message) }
    [void](Show-AiSetup); $script:Config.LogView = 'simples'; Show-Page 'Registro'; Write-Output ("registro simples: {0} elemento(s)" -f $ui.Body.Children.Count); $script:Config.LogView = 'detalhado'; Show-Page 'Registro'
    Write-Output ("cor 0/50/100: {0} {1} {2} | numero: {3}" -f (Get-HeatColor 0), (Get-HeatColor 50), (Get-HeatColor 100), (Fmt-Num 15.13))
    Write-Output ("igpu disponivel={0} | exitlag={1}" -f (Is-Available ($script:Tweaks | Where-Object { $_.Id -eq 'igpu-off' })), (Get-PcInfo).HasExitLag)
    # Failover: mede de verdade por cada conexão (sem trocar nada no Windows) e testa a lógica com amostras falsas
    foreach ($ad in @(Get-NetAdapters | Where-Object { $_.V4 })) { $ms = @(1..3 | ForEach-Object { [math]::Round([JanusProbe]::Probe($ad.V4, '1.1.1.1', 900)) }); Write-Output ("failover medida {0}: {1} ms" -f $ad.Name, ($ms -join ' / ')) }
    $q = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList)); $now = Get-Date
    for ($i = 20; $i -ge 1; $i--) { [void]$q.Add(@($now.AddMilliseconds(-500 * $i), $(if ($i % 3 -eq 0) { -1 } else { 40 + ($i % 4) * 30 }))) }
    $script:FoSync.Samples = @{ '99' = $q }
    $stx = Get-FoStats '99' 5; $cfgM = $FoPresets['moderado']; $cfgS = $FoPresets['sensivel']; $cfgQ = $FoPresets['queda']
    Write-Output ("failover logica: perda={0}% media={1}ms variacao={2}ms | ruim? sensivel={3} moderado={4} queda={5}" -f $stx.Loss, $stx.Avg, $stx.Jit, (Test-FoBad $stx $cfgS), (Test-FoBad $stx $cfgM), (Test-FoBad $stx $cfgQ))
    $script:FoSync.Samples = @{}
    Write-Output ("dica 300 ms: " + (Get-FoHint 'Ms' 300)[1] + " | muito solto: " + (Test-FoTooLoose @{ Loss = 30; Ms = 100; Jitter = 20; Secs = 5 }))
    Show-NotifySettings; try { $tm2 = Show-TestMenu $ui.LangTop; Write-Output ("menu de testes: {0} itens" -f $tm2.Items.Count); $tm2.IsOpen = $false } catch { Write-Output ('menu de testes falhou: ' + $_.Exception.Message) }
    $script:Sim['ssdtemp'] = @{ Value = 90; Until = (Get-Date).AddSeconds(30) }; Apply-Sims; Write-Output ("simulacao SSD: {0} C -> nivel {1}" -f @($script:Mon.Ssd)[0].Temp, (Get-MonLevel 'ssdtemp' @($script:Mon.Ssd)[0].Temp)); Check-Alerts -Force; $script:Sim = @{}
    Show-MonMenu; Show-SecurityDisable ($script:Checks | Where-Object { $_.Id -eq 'firewall' }); Show-SecurityDisable ($script:Checks | Where-Object { $_.Id -eq 'av' }); Show-AiAnswer 'Teste' 'resposta'; Write-Output 'dialogos novos: montaram'
    Write-Output ("pergunta de jogo:`n" + (New-GamePrompt @{ Name = 'Marvel Rivals'; Source = 'Steam' }))
    # Variáveis só de teste (não afetam o uso normal): JANUS_REDE = mede a velocidade de verdade;
    # JANUS_FOTOS = pasta para salvar capturas das telas; JANUS_TEMA = força o tema; JANUS_PAGINAS = quais telas capturar
    if ($env:JANUS_REDE) {
        $pa = Get-NetAdapters | Where-Object { $_.Primary } | Select-Object -First 1
        try { $pg = [JanusNet]::Ping('speed.cloudflare.com', $pa.V4, 5); $dl = [JanusNet]::Download($pa.V4, $pa.V6, 3, 2); $ul = [JanusNet]::Upload($pa.V4, $pa.V6, 3, 1); Write-Output ("velocidade ({0}): ping {1:N0} ms, download {2:N0} Mbps, upload {3:N0} Mbps" -f $pa.Name, $pg[0], $dl[0], $ul[0]) } catch { Write-Output ('velocidade falhou: ' + $_.Exception.Message) }
        $wf = Get-NetAdapters | Where-Object { -not $_.Primary } | Select-Object -First 1
        if ($wf) { try { $pg = [JanusNet]::Ping('speed.cloudflare.com', $wf.V4, 5); $dl = [JanusNet]::Download($wf.V4, $wf.V6, 3, 2); Write-Output ("velocidade ({0}, sem trocar de conexão): ping {1:N0} ms, download {2:N0} Mbps" -f $wf.Name, $pg[0], $dl[0]) } catch { Write-Output ('velocidade pela outra conexão falhou: ' + $_.Exception.Message) } }
    }
    Write-Output ("versao: {0} -> '{1}' | 0.1.0 > beta.1: {2} | beta.2 > beta.1: {3} | 0.1.0 = 0.1.0: {4}" -f $AppVersion, (Format-Version $AppVersion), (Compare-AppVersion '0.1.0' '0.1.0-beta.1'), (Compare-AppVersion 'v0.1.0-beta.2' '0.1.0-beta.1'), (Compare-AppVersion '0.1.0' '0.1.0'))
    Show-Welcome; Write-Output 'aviso inicial: montou'
    Write-Output ("relatorio (dialogo): " + (Show-ReportDialog 'erro' 'Erro: teste de relatório'))
    $rp = New-ErrorReport @{ Reason = 'teste'; Detail = "Erro: teste em $env:USERPROFILE\x"; UserText = "estava testando, meu pc é $env:COMPUTERNAME"; IncDetail = $true; IncLog = $true; IncPc = $true; IncState = $true; IncEvents = $true; IncConfig = $true; Anon = $true }
    $rt = [IO.File]::ReadAllText($rp)
    Write-Output ("relatorio: {0} linhas | nome de usuario vazou: {1} | nome do PC vazou: {2}" -f @(Get-Content -LiteralPath $rp).Count, ($rt -match [regex]::Escape($env:USERNAME)), ($rt -match [regex]::Escape($env:COMPUTERNAME)))
    Remove-Item -LiteralPath $rp -Force
    $sig = Test-Signature ([Text.Encoding]::UTF8.GetBytes('x')) 'AAAA'; Write-Output ("assinatura sem chave = {0} (esperado False)" -f $sig)
    $sw.Restart(); Start-UpdateCheck; Receive-UpdateCheck -Wait; Write-Output ("selo: [{0}] {1} | {2} ms" -f $script:Auth.Level, $script:Auth.Title, $sw.ElapsedMilliseconds)
    # cobertura de tradução: cada idioma, todas as páginas, guarda o que ficou sem tradução
    foreach ($lg in 'en', 'zh', 'es') {
        if (-not $script:I18N[$lg]) { Write-Output "idioma ${lg}: arquivo idiomas.json ausente"; continue }
        $script:Lang = $lg; $script:I18NMiss = New-Object 'System.Collections.Generic.HashSet[string]'
        Apply-StaticTexts; Build-Nav
        foreach ($k in $script:Pages.Keys) { Show-Page $k }
        Show-Welcome; Show-LanguageDialog; [void](Show-ReportDialog 'repetido' 'Erro: x'); [void](Show-Choice 'Descartar sugestão' 'x' 'Quer esconder esta sugestão só até fechar o Janus, ou para sempre? As descartadas para sempre podem ser trazidas de volta no fim desta aba.' @(@('forever', 'Para sempre', 'Danger'), @('session', 'Só até fechar o app', 'Ghost')) 'info')
        [void](Show-ChangePreview @($script:Tweaks | Where-Object { $_.Rec -eq $true }) $null 'Ajustes automáticos para este PC')
        if ($env:JANUS_FOTOS) {
            foreach ($pg in @($(if ($env:JANUS_PAGINAS) { $env:JANUS_PAGINAS -split ',' } else { 'Inicio', 'Manutencao', 'Sobre' }))) {
                Show-Page $pg
                $c = $W.Content; $sz = New-Object System.Windows.Size 1260, 840
                $c.Measure($sz); $c.Arrange((New-Object System.Windows.Rect $sz)); $c.UpdateLayout()
                $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap 1260, 840, 96, 96, ([System.Windows.Media.PixelFormats]::Pbgra32)
                $bg = New-Object System.Windows.Media.DrawingVisual; $dc = $bg.RenderOpen(); $dc.DrawRectangle((Brush '#0E1117'), $null, (New-Object System.Windows.Rect $sz)); $dc.Close(); $rtb.Render($bg); $rtb.Render($c)
                $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder; $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
                $fs = [IO.File]::Create((Join-Path $env:JANUS_FOTOS "janus-$lg-$pg.png")); $enc.Save($fs); $fs.Close()
            }
        }
        $miss = @($script:I18NMiss | Sort-Object)
        Write-Output ("idioma {0}: {1} texto(s) sem tradução" -f $lg, $miss.Count)
        [IO.File]::WriteAllLines((Join-Path $env:TEMP "janus-faltando-$lg.txt"), [string[]]$miss, (New-Object Text.UTF8Encoding($false)))
    }
    $gr = & ([scriptblock]::Create($GamesCode)) @{}
    Write-Output ("icones de jogos: {0} de {1} | sem: {2}" -f @($gr.Games | Where-Object { Get-GameIcon $_.Icon }).Count, @($gr.Games).Count, ((@($gr.Games | Where-Object { -not (Get-GameIcon $_.Icon) }) | ForEach-Object { $_.Name }) -join ', '))
    $sw2 = [Diagnostics.Stopwatch]::StartNew(); $fi = @(Get-NetInterference); Write-Output ("interferencias no failover ({0} ms): {1}" -f $sw2.ElapsedMilliseconds, $(if ($fi.Count) { ($fi | ForEach-Object { $_.Name }) -join ' | ' } else { 'nenhuma' }))
    Write-Output ("override faria: " + ((Get-FoOverridePlan $fi) -join ' | '))
    $gb = Save-GameBrief @{ Name = 'Overwatch'; Source = 'Battle.net' }; Write-Output ("ficha do jogo: {0} ({1} caracteres)" -f (Split-Path -Leaf $gb), (Get-Content -LiteralPath $gb -Raw).Length)
    Write-Output ("abrir sem a tela do administrador: {0}" -f (Test-NoUac))
    Write-Output ("rede: icones={0} | ordem: {1}" -f (Get-NetGlyphs).Length, ((Get-NetAdapters | ForEach-Object { $_.Name }) -join ' > '))
    Write-Output ("iniciar com o Windows: {0} | fechar: {1} | novidades: ok" -f (Test-Autostart), (Show-CloseAsk)); Show-Changelog '0.1.0-beta.2'
    $script:Mon = @{ Ram = 97; CpuTemp = $null; Gpu = @{ Temp = 92; Use = 50 }; Ssd = @() }; $script:Config.NotifyItems = @('gputemp', 'ram'); $script:Config.NotifyRepeat = 'uma'
    $cnt = 0; function Send-Notify { $script:cnt++ }; Check-Alerts; Check-Alerts; $script:Mon.Ram = 50; Check-Alerts; Write-Output ("avisos (uma vez, 2 itens, 3 leituras): {0} (esperado 2)" -f $script:cnt)
    $script:Config.NotifyItems = @(); $script:Mon = $null
    $script:Lang = 'pt'
    $W.Close(); $script:Rs.Dispose()
    return
}

# ---------- abertura: travamentos anteriores e modo de segurança ----------
$script:PrevCrashed = $false; $script:CleanExit = $false
# se a sessão anterior ainda está fechando (troca de tema, atualização), espera ela sair em vez de achar que travou
if (Test-Path -LiteralPath $LockFile) {
    $lp = [regex]::Match([string](Get-Content -LiteralPath $LockFile -Raw -ErrorAction SilentlyContinue), 'pid (\d+)').Groups[1].Value
    if ($lp -and [int]$lp -ne $PID -and @(Get-Process -Id ([int]$lp) -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'powershell' }).Count) {
        if (-not $Bandeja) { try { Set-Content -LiteralPath $ShowReq -Value 'x' -Encoding ASCII } catch {} }
        for ($i = 0; $i -lt 40 -and (Test-Path -LiteralPath $LockFile); $i++) {
            Start-Sleep -Milliseconds 250
            if (-not $Bandeja -and -not (Test-Path -LiteralPath $ShowReq)) { return }   # a outra cópia apareceu: esta não precisa abrir
        }
        if (Test-Path -LiteralPath $LockFile) { Remove-Item -LiteralPath $ShowReq -Force -ErrorAction SilentlyContinue; if ($Bandeja) { return } }
        Remove-Item -LiteralPath $ShowReq -Force -ErrorAction SilentlyContinue
    }
}
if (Test-Path -LiteralPath $LockFile) {
    $script:PrevCrashed = $true; $script:Config.CrashCount = [int]$script:Config.CrashCount + 1; Save-Config
    Write-Log ('A última sessão não fechou direito (vez {0} seguida).' -f $script:Config.CrashCount)
}
if ($SoRelatorio -or $script:Config.CrashCount -ge 3) {
    $det = ''; if (Test-Path -LiteralPath $CrashFile) { $det = [IO.File]::ReadAllText($CrashFile) }
    $ch = Show-ReportDialog 'repetido' $det
    if ($ch -notin 'open', 'reset') { Write-Log 'Modo de segurança: fechado sem abrir a janela principal.'; return }
    $script:Config.CrashCount = 0; Save-Config; $script:PrevCrashed = $false
    $script:Config = Load-Config
}
try { Set-Content -LiteralPath $LockFile -Value ("{0} | pid {1}" -f (Get-Date -Format 's'), $PID) -Encoding ASCII } catch {}

# Abre a janela na hora e lê o PC em segundo plano
try {
    Paint-Nav 'Inicio'
    $ui.PageTitle.Text = (T (Get-PageTitle 'Inicio')); Set-PageSub 'Inicio'
    $ui.SearchBox.Visibility = 'Collapsed'
    Add-Body (New-EmptyState ([string][char]0xE895) 'Fazendo a leitura do seu PC...' 'Ajustes, verificações e segurança estão sendo lidos em segundo plano. Leva só alguns segundos.')
    $ui.UpdatedText.Text = (T 'Fazendo a leitura do PC...')
    $script:ForceFull = $true
    $script:NextUpdateCheck = (Get-Date).AddSeconds(8)
    Start-MonRead
    if ((Get-FoCfg).On) {
        [void](Start-Failover)
        # já estava ligado: liga, mas avisa se algo pode interferir
        $fi = @(Get-NetInterference); if ($fi.Count) { Write-Log ('Failover: interferências: ' + (($fi | ForEach-Object { $_.Name }) -join '; ')); Send-Notify 'Failover' ((T 'Algo pode interferir no Failover: {0}. Veja em Internet e DNS.') -f (($fi | ForEach-Object { $_.Name }) -join ', ')) 'warn' }
    }
    $script:Poll.Start()
    $W.add_Closed({ try { if ($script:Tray) { $script:Tray.Visible = $false; $script:Tray.Dispose() } } catch {}; $W.Dispatcher.InvokeShutdown() })
    if ($Bandeja) { $script:TrayTipShown = $true; Hide-ToTray } else { [void]$W.Show(); $W.Topmost = $true; $W.Topmost = $false; [void]$W.Activate() }   # aberto por tarefa agendada: garante que aparece na frente
    [System.Windows.Threading.Dispatcher]::Run()
    $script:CleanExit = $true
} catch {
    Save-CrashInfo $_ 'abertura' | Out-Null
    try { Show-ReportDialog 'erro' (Get-ErrorText $_) | Out-Null } catch {}
} finally {
    $script:Poll.Stop()
    try { if ($script:Job) { $script:Job.PS.Stop() }; $script:Rs.Dispose() } catch {}
    try { if ($script:RsNet) { $script:RsNet.Dispose() } } catch {}
    try { if (-not $script:FoSync.Stop) { Stop-Failover } } catch {}
    if ($script:CleanExit) {
        if ([string](Get-Content -LiteralPath $LockFile -Raw -ErrorAction SilentlyContinue) -match "pid $PID\b") { Remove-Item -LiteralPath $LockFile -Force -ErrorAction SilentlyContinue }
        if ($script:Config.CrashCount) { $script:Config.CrashCount = 0; Save-Config }
    }
    Write-Log 'Janus fechado.'
}
