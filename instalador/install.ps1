#requires -Version 5.1
# Instalador do Janus (janela própria). Roda de dentro do Janus-Setup.exe, que já pediu administrador UMA vez.
# Padrão: "C:\Program Files\Janus". A pessoa pode escolher outra pasta; fora de Arquivos de Programas
# o instalador protege a pasta (só administradores alteram), igual à Program Files.
# -Teste: instala em -Destino sem janela, sem atalhos públicos e sem registro.
# -Captura <pasta>: salva fotos das telas do instalador (para conferir o visual) e sai.
param([switch]$Teste, [string]$Destino, [string]$Captura)
$ErrorActionPreference = 'Stop'
$Origem = Split-Path -Parent $PSCommandPath
$Versao = [regex]::Match([IO.File]::ReadAllText((Join-Path $Origem 'Janus.ps1')), "\`$AppVersion = '([^']+)'").Groups[1].Value
$VersaoTxt = $(if ($Versao -match '^(\d+\.\d+\.\d+)-beta\.(\d+)$') { '{0} - beta {1}' -f $Matches[1], $Matches[2] } else { $Versao })
# edição especial (opcional): nome do app, pasta e atalhos só para quem instala
$Ed = $null; $edf = Join-Path $Origem 'edicao.json'
if (Test-Path -LiteralPath $edf) { try { $Ed = Get-Content -LiteralPath $edf -Raw -Encoding UTF8 | ConvertFrom-Json } catch {} }
$Nome = $(if ($Ed -and $Ed.Nome) { [string]$Ed.Nome } else { 'Janus' })
$PastaNome = $(if ($Ed -and $Ed.Pasta) { [string]$Ed.Pasta } else { 'Janus' })
$Chave = ($PastaNome -replace '[^A-Za-z0-9]', '')
$SoEu = [bool]($Ed -and $Ed.SoEsteUsuario)

# PowerShell 64 bits (um PowerShell de 32 enxerga outra Program Files e outro registro)
$fwd = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', "`"$PSCommandPath`"")
if ($Teste) { $fwd += '-Teste' }
if ($Destino) { $fwd += @('-Destino', "`"$Destino`"") }
if ($Captura) { $fwd += @('-Captura', "`"$Captura`"") }
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $p = Start-Process "$env:windir\sysnative\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $fwd -Wait -PassThru -WindowStyle Hidden
    exit $p.ExitCode
}
# administrador: o Setup.exe já pede; isto só vale se alguém rodar o install.ps1 direto
$adm = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $adm -and -not $Teste -and -not $Captura) {
    try { $p = Start-Process powershell.exe -Verb RunAs -ArgumentList $fwd -Wait -PassThru -WindowStyle Hidden; exit $p.ExitCode } catch { exit 1 }
}

# ---------- textos ----------
$lang = $(if ($Ed -and $Ed.Idioma) { [string]$Ed.Idioma } elseif ([Globalization.CultureInfo]::CurrentUICulture.Name -like 'pt*') { 'pt' } else { 'en' })
$S = @{
  pt = @{ title = 'Instalar o {0}'; sub = 'Versão {0}'
          intro = 'O {0} ajusta o Windows para jogos e desempenho. Ele roda como administrador, cria ponto de restauração e backup antes de cada mudança, e tudo pode ser desfeito pelo próprio app.'
          folder = 'Pasta de instalação'; browse = 'Procurar...'; pick = 'Escolha onde instalar o {0}. Uma pasta "{1}" será criada dentro dela.'
          outside = 'Fora de "Arquivos de Programas": o instalador protege a pasta para que só administradores possam alterar o {0}.'
          upd = 'O {0} já está instalado nesta pasta: ele será atualizado. Suas preferências e o registro de mudanças continuam.'
          desk = 'Criar atalho na área de trabalho'; start = 'Criar atalho no menu Iniciar'; open = 'Abrir o {0} ao terminar'
          cancel = 'Cancelar'; install = 'Instalar'; update = 'Atualizar'; working = 'Instalando o {0}...'
          s1 = 'Fechando o {0}, se estiver aberto...'; s2 = 'Copiando arquivos...'; s3 = 'Protegendo a pasta...'; s4 = 'Criando atalhos...'; s5 = 'Registrando em Aplicativos instalados...'; s6 = 'Concluído.'
          done = 'Pronto!'; doneText = 'O {0} {1} foi instalado em:'; hint = 'Para desinstalar: Configurações > Aplicativos > Aplicativos instalados.'; finish = 'Concluir'
          fail = 'A instalação não terminou'; failText = 'Motivo:'; close = 'Fechar'; bad = 'Escolha uma pasta válida, por exemplo C:\Program Files\{0}.' }
  en = @{ title = 'Install {0}'; sub = 'Version {0}'
          intro = '{0} tunes Windows for gaming and performance. It runs as administrator, creates a restore point and a backup before every change, and everything can be undone from the app itself.'
          folder = 'Install folder'; browse = 'Browse...'; pick = 'Choose where to install {0}. A "{1}" folder will be created inside it.'
          outside = 'Outside "Program Files": the installer protects the folder so only administrators can change {0}.'
          upd = '{0} is already installed in this folder: it will be updated. Your settings and change log are kept.'
          desk = 'Create a desktop shortcut'; start = 'Create a Start menu shortcut'; open = 'Open {0} when done'
          cancel = 'Cancel'; install = 'Install'; update = 'Update'; working = 'Installing {0}...'
          s1 = 'Closing {0} if it is open...'; s2 = 'Copying files...'; s3 = 'Protecting the folder...'; s4 = 'Creating shortcuts...'; s5 = 'Registering in Installed apps...'; s6 = 'Done.'
          done = 'All set!'; doneText = '{0} {1} was installed in:'; hint = 'To uninstall: Settings > Apps > Installed apps.'; finish = 'Finish'
          fail = 'Setup did not finish'; failText = 'Reason:'; close = 'Close'; bad = 'Choose a valid folder, for example C:\Program Files\{0}.' }
}[$lang]

# ---------- instalação ----------
$Pf = $(if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles })
function Get-Existing { try { [string](Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$Chave" -ErrorAction Stop).InstallLocation } catch { '' } }
function Test-InProgramFiles([string]$p) {
    foreach ($b in @($env:ProgramW6432, $env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }) { if ($p.TrimEnd('\') -like ($b.TrimEnd('\') + '\*')) { return $true } }
    return $false
}
function Resolve-Target([string]$p) {
    $p = [IO.Path]::GetFullPath($p.Trim().Trim('"')).TrimEnd('\')
    # pasta com outras coisas dentro (e sem Janus): instala numa subpasta, para nunca misturar nem trancar arquivos da pessoa
    if ((Test-Path -LiteralPath $p) -and @(Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue).Count -and -not (Test-Path -LiteralPath (Join-Path $p 'Janus.ps1'))) { $p = Join-Path $p $PastaNome }
    return $p
}
function Invoke-Install([string]$dest, [bool]$desk, [bool]$startm, [scriptblock]$step) {
    & $step 8 ($S.s1 -f $Nome)
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -like "*$dest*Janus.ps1*" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    & $step 25 $S.s2
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    foreach ($f in 'Janus.ps1', 'idiomas.json', 'Janus.ico', 'uninstall.ps1', 'LICENSE', 'LEIA-ME.txt', 'edicao.json') {
        $src = Join-Path $Origem $f
        if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $dest $f) -Force }
    }
    # marca de "instalado": o Janus guarda preferências e registro em %LOCALAPPDATA%, não na pasta do programa
    Set-Content -LiteralPath (Join-Path $dest 'instalado.txt') -Value 'Instalado pelo instalador. O Janus guarda seus dados em %LOCALAPPDATA%\Janus.' -Encoding UTF8
    Get-ChildItem -LiteralPath $dest -File | Unblock-File -ErrorAction SilentlyContinue
    if (-not (Test-InProgramFiles $dest) -and -not $Teste) {
        # o Janus roda como administrador: a pasta dele não pode ser alterável por programas comuns
        & $step 45 $S.s3
        $null = & icacls.exe $dest /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' /T /Q
        if ($LASTEXITCODE -ne 0) { throw "icacls ($LASTEXITCODE)" }
    }
    & $step 65 $S.s4
    $ps = Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $app = Join-Path $dest 'Janus.ps1'; $ico = Join-Path $dest 'Janus.ico'
    if ($Teste) { $dirs = @(, @((Join-Path $dest 'atalhos-teste'), $true)) }
    elseif ($SoEu) { $dirs = @(@([Environment]::GetFolderPath('Desktop'), $desk), @([Environment]::GetFolderPath('Programs'), $startm)) }
    else { $dirs = @(@([Environment]::GetFolderPath('CommonDesktopDirectory'), $desk), @([Environment]::GetFolderPath('CommonPrograms'), $startm)) }
    $sh = New-Object -ComObject WScript.Shell
    foreach ($d in $dirs) {
        $lnk = Join-Path $d[0] "$Nome.lnk"
        if (-not $d[1]) { Remove-Item -LiteralPath $lnk -Force -ErrorAction SilentlyContinue; continue }
        New-Item -ItemType Directory -Force -Path $d[0] | Out-Null
        $l = $sh.CreateShortcut($lnk)
        $l.TargetPath = $ps; $l.Arguments = '-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "' + $app + '"'; $l.WorkingDirectory = $dest
        $l.IconLocation = "$ico,0"; $l.Description = $Nome; $l.WindowStyle = 7; $l.Save()
    }
    if (-not $Teste) {
        & $step 85 $S.s5
        $k = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$Chave"
        New-Item -Path $k -Force | Out-Null
        $vals = @{
            DisplayName = $Nome; DisplayVersion = $Versao; Publisher = 'iAlencari'
            DisplayIcon = $ico; InstallLocation = $dest; URLInfoAbout = 'https://github.com/iAlencari/Janus'
            UninstallString = "`"$ps`" -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $dest 'uninstall.ps1')`""
            InstallDate = (Get-Date -Format 'yyyyMMdd')
        }
        foreach ($n in $vals.Keys) { New-ItemProperty -Path $k -Name $n -Value $vals[$n] -PropertyType String -Force | Out-Null }
        foreach ($n in 'NoModify', 'NoRepair') { New-ItemProperty -Path $k -Name $n -Value 1 -PropertyType DWord -Force | Out-Null }
        $size = [int]((Get-ChildItem -LiteralPath $dest -File | Measure-Object Length -Sum).Sum / 1KB)
        New-ItemProperty -Path $k -Name 'EstimatedSize' -Value $size -PropertyType DWord -Force | Out-Null
    }
    & $step 100 $S.s6
}

if ($Teste) {
    try { $d = Resolve-Target $Destino; Invoke-Install $d $true $true { param($p, $t) }; Write-Output "instalado em $d (versão $Versao)"; exit 0 }
    catch { Write-Output ('falhou: ' + $_.Exception.Message); exit 1 }
}

# ---------- janela ----------
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms
Add-Type -Namespace JanusSetup -Name Dwm -MemberDefinition '[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int a, ref int v, int s);'
[xml]$x = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="620" SizeToContent="Height" ResizeMode="NoResize" WindowStartupLocation="CenterScreen"
        Background="#0E1117" Foreground="#E6E9EF" FontFamily="Segoe UI Variable Text, Segoe UI, Microsoft YaHei UI" FontSize="13">
  <Window.Resources>
    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Foreground" Value="#E6E9EF"/><Setter Property="Background" Value="#1F2633"/><Setter Property="Padding" Value="18,8"/>
      <Setter Property="FontSize" Value="13"/><Setter Property="Cursor" Value="Hand"/><Setter Property="MinWidth" Value="96"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
        <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}">
          <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.85"/></Trigger>
          <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.4"/></Trigger>
        </ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="Accent" TargetType="Button" BasedOn="{StaticResource Btn}"><Setter Property="Background" Value="#3B82F6"/><Setter Property="Foreground" Value="White"/><Setter Property="FontWeight" Value="SemiBold"/></Style>
    <Style TargetType="CheckBox"><Setter Property="Foreground" Value="#D6DCE8"/><Setter Property="Margin" Value="0,10,0,0"/><Setter Property="Cursor" Value="Hand"/></Style>
  </Window.Resources>
  <Border x:Name="Root" Background="#0E1117" Padding="34,30,34,28" TextElement.Foreground="#E6E9EF" TextElement.FontSize="13" TextElement.FontFamily="Segoe UI Variable Text, Segoe UI, Microsoft YaHei UI">
    <StackPanel>
      <StackPanel Orientation="Horizontal">
        <Image x:Name="Logo" Width="52" Height="52"/>
        <StackPanel Margin="16,0,0,0" VerticalAlignment="Center">
          <TextBlock x:Name="Head" FontSize="23" FontWeight="SemiBold"/>
          <TextBlock x:Name="Sub" FontSize="12.5" Foreground="#8B94A5" Margin="0,2,0,0"/>
        </StackPanel>
      </StackPanel>
      <StackPanel x:Name="P1">
        <TextBlock x:Name="Intro" TextWrapping="Wrap" Foreground="#AEB6C4" LineHeight="19" Margin="0,20,0,0"/>
        <TextBlock x:Name="FolderLbl" FontWeight="SemiBold" Margin="0,22,0,8"/>
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
          <TextBox x:Name="PathBox" Background="#171C26" Foreground="#E6E9EF" BorderBrush="#2A3242" BorderThickness="1" Padding="10,7" FontSize="13" CaretBrush="#E6E9EF" VerticalContentAlignment="Center"/>
          <Button x:Name="Browse" Grid.Column="1" Style="{StaticResource Btn}" Margin="8,0,0,0"/>
        </Grid>
        <TextBlock x:Name="Upd" TextWrapping="Wrap" Foreground="#60A5FA" FontSize="12" Margin="0,8,0,0" Visibility="Collapsed"/>
        <TextBlock x:Name="Outside" TextWrapping="Wrap" Foreground="#F59E0B" FontSize="12" Margin="0,8,0,0" Visibility="Collapsed"/>
        <TextBlock x:Name="Bad" TextWrapping="Wrap" Foreground="#EF4444" FontSize="12" Margin="0,8,0,0" Visibility="Collapsed"/>
        <CheckBox x:Name="Desk" IsChecked="True" Margin="0,18,0,0" Foreground="#D6DCE8" Cursor="Hand"/>
        <CheckBox x:Name="StartM" IsChecked="True" Margin="0,10,0,0" Foreground="#D6DCE8" Cursor="Hand"/>
        <CheckBox x:Name="OpenIt" IsChecked="True" Margin="0,10,0,0" Foreground="#D6DCE8" Cursor="Hand"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,26,0,0">
          <Button x:Name="Cancel" Style="{StaticResource Btn}"/>
          <Button x:Name="Go" Style="{StaticResource Accent}" Margin="10,0,0,0"/>
        </StackPanel>
      </StackPanel>
      <StackPanel x:Name="P2" Visibility="Collapsed">
        <TextBlock x:Name="Working" FontSize="16" FontWeight="SemiBold" Margin="0,26,0,0"/>
        <ProgressBar x:Name="Bar" Height="8" Margin="0,16,0,0" Minimum="0" Maximum="100" Foreground="#3B82F6" Background="#171C26" BorderThickness="0"/>
        <TextBlock x:Name="Status" Foreground="#8B94A5" FontSize="12" Margin="0,10,0,8"/>
      </StackPanel>
      <StackPanel x:Name="P3" Visibility="Collapsed">
        <StackPanel Orientation="Horizontal" Margin="0,26,0,0">
          <TextBlock x:Name="DoneIcon" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="22" VerticalAlignment="Center" Margin="0,0,12,0"/>
          <TextBlock x:Name="DoneHead" FontSize="18" FontWeight="SemiBold" VerticalAlignment="Center"/>
        </StackPanel>
        <TextBlock x:Name="DoneText" TextWrapping="Wrap" Foreground="#AEB6C4" Margin="0,12,0,0"/>
        <TextBlock x:Name="DonePath" TextWrapping="Wrap" Foreground="#E6E9EF" FontFamily="Cascadia Mono, Consolas" FontSize="12.5" Margin="0,6,0,0"/>
        <TextBlock x:Name="Hint" TextWrapping="Wrap" Foreground="#6F7889" FontSize="12" Margin="0,14,0,0"/>
        <Button x:Name="Finish" Style="{StaticResource Accent}" HorizontalAlignment="Right" Margin="0,24,0,0"/>
      </StackPanel>
    </StackPanel>
  </Border>
</Window>
'@
$W = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $x))
$u = @{}; foreach ($n in 'Root', 'Logo', 'Head', 'Sub', 'P1', 'P2', 'P3', 'Intro', 'FolderLbl', 'PathBox', 'Browse', 'Upd', 'Outside', 'Bad', 'Desk', 'StartM', 'OpenIt', 'Cancel', 'Go', 'Working', 'Bar', 'Status', 'DoneIcon', 'DoneHead', 'DoneText', 'DonePath', 'Hint', 'Finish') { $u[$n] = $W.FindName($n) }
$W.Title = ($S.title -f $Nome)
try {
    $png = Join-Path $Origem 'janus-icone.png'
    if (Test-Path -LiteralPath $png) { $u.Logo.Source = [System.Windows.Media.Imaging.BitmapFrame]::Create([Uri]$png) }
    $W.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create([Uri](Join-Path $Origem 'Janus.ico'))
} catch {}
$u.Head.Text = ($S.title -f $Nome); $u.Sub.Text = ($S.sub -f $VersaoTxt); $u.Intro.Text = ($S.intro -f $Nome)
$u.FolderLbl.Text = $S.folder; $u.Browse.Content = $S.browse; $u.Cancel.Content = $S.cancel
$u.Desk.Content = $S.desk; $u.StartM.Content = $S.start; $u.OpenIt.Content = ($S.open -f $Nome)
$u.Working.Text = ($S.working -f $Nome); $u.Hint.Text = $S.hint
$ex = Get-Existing
$u.PathBox.Text = $(if ($ex) { $ex } else { Join-Path $Pf $PastaNome })
function Update-PathInfo {
    $p = $u.PathBox.Text.Trim().Trim('"')
    $ok = $p -and ($p -match '^[A-Za-z]:\\.+')
    $u.Bad.Visibility = $(if ($ok) { 'Collapsed' } else { 'Visible' }); $u.Bad.Text = ($S.bad -f $PastaNome); $u.Go.IsEnabled = $ok
    $isUpd = $ok -and (Test-Path -LiteralPath (Join-Path $p 'Janus.ps1'))
    $u.Upd.Visibility = $(if ($isUpd) { 'Visible' } else { 'Collapsed' }); $u.Upd.Text = ($S.upd -f $Nome)
    $u.Go.Content = $(if ($isUpd) { $S.update } else { $S.install })
    $u.Outside.Visibility = $(if ($ok -and -not (Test-InProgramFiles $p)) { 'Visible' } else { 'Collapsed' }); $u.Outside.Text = ($S.outside -f $Nome)
}
Update-PathInfo
$u.PathBox.add_TextChanged({ Update-PathInfo })
$u.Browse.add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = ($S.pick -f $Nome, $PastaNome); $dlg.ShowNewFolderButton = $true
    $cur = $u.PathBox.Text.Trim(); $par = $(try { Split-Path -Parent $cur } catch { '' })
    if ($par -and (Test-Path -LiteralPath $par)) { $dlg.SelectedPath = $par }
    if ($dlg.ShowDialog() -eq 'OK') {
        $p = $dlg.SelectedPath.TrimEnd('\')
        if ((Split-Path -Leaf $p) -ne $PastaNome -and -not (Test-Path -LiteralPath (Join-Path $p 'Janus.ps1'))) { $p = Join-Path $p $PastaNome }
        $u.PathBox.Text = $p
    }
})
$script:Result = 2; $script:Dest = ''; $script:Busy = $false
$u.Cancel.add_Click({ $W.Close() })
$W.add_Closing({ param($s, $e) if ($script:Busy) { $e.Cancel = $true } })
$step = { param($pct, $txt) $u.Bar.Value = $pct; if ($txt) { $u.Status.Text = $txt }; $W.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background); Start-Sleep -Milliseconds 120 }
$u.Go.add_Click({
    $script:Dest = Resolve-Target $u.PathBox.Text
    $u.P1.Visibility = 'Collapsed'; $u.P2.Visibility = 'Visible'; $script:Busy = $true
    try {
        Invoke-Install $script:Dest ([bool]$u.Desk.IsChecked) ([bool]$u.StartM.IsChecked) $step
        $script:Result = 0
        $u.DoneIcon.Text = [string][char]0xE73E; $u.DoneIcon.Foreground = '#22C55E'; $u.DoneHead.Text = $S.done
        $u.DoneText.Text = ($S.doneText -f $Nome, $VersaoTxt); $u.DonePath.Text = $script:Dest; $u.Finish.Content = $S.finish
    } catch {
        $script:Result = 1
        $u.DoneIcon.Text = [string][char]0xEA39; $u.DoneIcon.Foreground = '#EF4444'; $u.DoneHead.Text = $S.fail
        $u.DoneText.Text = $S.failText; $u.DonePath.Text = $_.Exception.Message; $u.Hint.Text = ''; $u.Finish.Content = $S.close
    } finally { $script:Busy = $false }
    $u.P2.Visibility = 'Collapsed'; $u.P3.Visibility = 'Visible'
})
$u.Finish.add_Click({
    if ($script:Result -eq 0 -and $u.OpenIt.IsChecked) {
        # este processo já é administrador: o Janus abre sem pedir de novo
        Start-Process (Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe') -WorkingDirectory $script:Dest -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', ('"' + (Join-Path $script:Dest 'Janus.ps1') + '"'))
    }
    $W.Close()
})
$W.add_SourceInitialized({ try { $h = (New-Object System.Windows.Interop.WindowInteropHelper $W).Handle; $one = 1; [void][JanusSetup.Dwm]::DwmSetWindowAttribute($h, 20, [ref]$one, 4) } catch {} })

if ($Captura) {
    # fotos das três telas, sem mostrar a janela
    New-Item -ItemType Directory -Force -Path $Captura | Out-Null
    $W.Content = $null   # desenha o conteúdo sozinho, sem abrir a janela
    $shots = @(
        @('1-escolha', { }),
        @('2-instalando', { $u.P1.Visibility = 'Collapsed'; $u.P2.Visibility = 'Visible'; $u.Bar.Value = 60; $u.Status.Text = $S.s4 }),
        @('3-pronto', { $u.P2.Visibility = 'Collapsed'; $u.P3.Visibility = 'Visible'; $u.DoneIcon.Text = [string][char]0xE73E; $u.DoneIcon.Foreground = '#22C55E'; $u.DoneHead.Text = $S.done; $u.DoneText.Text = ($S.doneText -f $Nome, $VersaoTxt); $u.DonePath.Text = $u.PathBox.Text; $u.Finish.Content = $S.finish }))
    foreach ($sh in $shots) {
        & $sh[1]
        $r = $u.Root; $sz = New-Object System.Windows.Size 620, ([double]::PositiveInfinity)
        $r.Measure($sz); $r.Arrange((New-Object System.Windows.Rect 0, 0, 620, $r.DesiredSize.Height)); $r.UpdateLayout()
        $bmp = New-Object System.Windows.Media.Imaging.RenderTargetBitmap 620, ([int]$r.DesiredSize.Height), 96, 96, ([System.Windows.Media.PixelFormats]::Pbgra32); $bmp.Render($r)
        $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder; $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bmp))
        $fs = [IO.File]::Create((Join-Path $Captura ($sh[0] + '.png'))); $enc.Save($fs); $fs.Close()
    }
    exit 0
}
[void]$W.ShowDialog()
exit $script:Result
