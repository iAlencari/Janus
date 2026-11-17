#requires -Version 5.1
# Desinstalador do Janus. Fica dentro da pasta instalada.
# -Teste: sem perguntas, sem mexer em atalhos públicos nem no registro.
param([switch]$Teste)
$ErrorActionPreference = 'Stop'
$Pasta = Split-Path -Parent $PSCommandPath
$Ed = $null; $edf = Join-Path $Pasta 'edicao.json'
if (Test-Path -LiteralPath $edf) { try { $Ed = Get-Content -LiteralPath $edf -Raw -Encoding UTF8 | ConvertFrom-Json } catch {} }
$Nome = $(if ($Ed -and $Ed.Nome) { [string]$Ed.Nome } else { 'Janus' })
$Chave = $(if ($Ed -and $Ed.Pasta) { ([string]$Ed.Pasta -replace '[^A-Za-z0-9]', '') } else { 'Janus' })

$adm = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $adm -and -not $Teste) {
    try { Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"") } catch {}
    exit
}
Add-Type -AssemblyName System.Windows.Forms
$dados = Join-Path $env:LOCALAPPDATA 'Janus'
$lang = $(switch -Wildcard ([Globalization.CultureInfo]::CurrentUICulture.Name) { 'pt*' { 'pt' } 'es*' { 'es' } 'zh*' { 'zh' } default { 'en' } })
$S = @{
  pt = @{ ask = "Desinstalar o Janus?`n`nAtenção: os ajustes que estiverem ativos continuam no Windows. Para voltar tudo ao padrão antes, abra o app e use a aba Ativos > Desfazer todos.`n`nSeu registro de mudanças e os backups ficam guardados em:`n{0}"; done = 'O Janus foi desinstalado.'; title = 'Desinstalar o Janus' }
  en = @{ ask = "Uninstall Janus?`n`nNote: tweaks that are active stay in Windows. To put everything back to default first, open the app and use the Active tab > Undo all.`n`nYour change log and backups are kept in:`n{0}"; done = 'Janus was uninstalled.'; title = 'Uninstall Janus' }
  es = @{ ask = "¿Desinstalar Janus?`n`nAtención: los ajustes activos permanecen en Windows. Para volver todo a la configuración predeterminada antes, abre la app y usa la pestaña Activos > Deshacer todos.`n`nTu registro de cambios y las copias de seguridad se guardan en:`n{0}"; done = 'Janus fue desinstalado.'; title = 'Desinstalar Janus' }
  zh = @{ ask = "卸载 Janus？`n`n注意：已启用的调整会保留在 Windows 中。如需先全部恢复默认，请打开应用，在「已启用」页点击「全部撤销」。`n`n更改记录和备份保存在：`n{0}"; done = 'Janus 已卸载。'; title = '卸载 Janus' }
}[$(if ($Ed -and $Ed.Idioma) { [string]$Ed.Idioma } else { $lang })]
foreach ($kk in @($S.Keys)) { $S[$kk] = $S[$kk].Replace('Janus', $Nome) }
if (-not $Teste) {
    $r = [System.Windows.Forms.MessageBox]::Show(($S.ask -f $dados), $S.title, 'YesNo', 'Warning')
    if ([string]$r -ne 'Yes') { exit 2 }
}
Set-Location -LiteralPath $env:TEMP
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -like "*$Pasta*Janus.ps1*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
if ($Teste) { $lnks = @((Join-Path $Pasta "atalhos-teste\$Nome.lnk")) }
else {
    $lnks = @(foreach ($d in 'CommonDesktopDirectory', 'CommonPrograms', 'Desktop', 'Programs') { Join-Path ([Environment]::GetFolderPath($d)) "$Nome.lnk" })
    Remove-Item -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$Chave" -Recurse -Force -ErrorAction SilentlyContinue
    # tarefa "Iniciar com o Windows" (as tarefas de religar a segurança ficam: elas só religam o que foi desligado)
    Unregister-ScheduledTask -TaskPath '\Janus\' -TaskName 'Iniciar com o Windows' -Confirm:$false -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskPath '\Janus\' -TaskName 'Abrir o Janus' -Confirm:$false -ErrorAction SilentlyContinue
}
foreach ($l in $lnks) { Remove-Item -LiteralPath $l -Force -ErrorAction SilentlyContinue }
Remove-Item -LiteralPath $Pasta -Recurse -Force -ErrorAction SilentlyContinue
if ($Teste) { Write-Output ("desinstalado: pasta existe=" + (Test-Path -LiteralPath $Pasta)); exit 0 }
[void][System.Windows.Forms.MessageBox]::Show($S.done, $Nome, 'OK', 'Information')
