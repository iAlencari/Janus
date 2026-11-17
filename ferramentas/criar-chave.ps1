#requires -Version 5.1
# Cria a chave de assinatura do Janus. Rode UMA vez, num terminal, você mesmo (a senha é digitada por você e não fica salva).
#  - Chave PRIVADA: arquivo .pfx protegido por senha, FORA do repositório (padrão: Documentos\Janus-chave).
#    Faça backup dela (pendrive e/ou Google Drive). Sem ela não dá para assinar versões novas.
#  - Chave PÚBLICA: gravada dentro do Janus.ps1 ($PublicKeyXml). Ela só confere assinaturas; pode ser pública.
# Uso: powershell -ExecutionPolicy Bypass -File ferramentas\criar-chave.ps1
# -GerarSenha: em vez de perguntar, cria uma senha aleatória forte e grava SÓ no arquivo SENHA-...txt da pasta da chave
#              (não aparece na tela). Passe a senha para um gerenciador de senhas e apague o arquivo.
param([string]$Pasta = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Janus-chave'), [switch]$Substituir, [switch]$GerarSenha)
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$App  = Join-Path $Repo 'Janus.ps1'
$Pfx  = Join-Path $Pasta 'janus-assinatura.pfx'
if ((Test-Path -LiteralPath $Pfx) -and -not $Substituir) {
    Write-Host "Já existe uma chave em $Pfx." -ForegroundColor Yellow
    Write-Host 'Trocar a chave invalida o selo de quem já instalou. Se tem certeza, rode de novo com -Substituir.'
    exit 1
}
Write-Host ''
Write-Host 'Janus: criar chave de assinatura' -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $Pasta | Out-Null
$SenhaFile = Join-Path $Pasta 'SENHA-guarde-num-gerenciador-e-apague.txt'
if ($GerarSenha) {
    # 32 caracteres sorteados pelo gerador criptográfico do Windows (~190 bits): impossível de adivinhar por tentativa
    $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%&*-_=+?'.ToCharArray()
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create(); $buf = New-Object byte[] 1
    $p1 = New-Object Security.SecureString; $plain = New-Object Text.StringBuilder
    while ($plain.Length -lt 32) { $rng.GetBytes($buf); if ($buf[0] -lt (256 - (256 % $chars.Count))) { $c = $chars[$buf[0] % $chars.Count]; [void]$plain.Append($c); $p1.AppendChar($c) } }
    [IO.File]::WriteAllText($SenhaFile, ("Senha da chave do Janus (janus-assinatura.pfx):`r`n`r`n" + $plain.ToString() + "`r`n`r`nPasse para um gerenciador de senhas (ou anote em papel guardado) e APAGUE este arquivo.`r`nNão guarde esta senha junto do backup do .pfx.`r`n"), (New-Object Text.UTF8Encoding($false)))
    $plain = $null
    Write-Host "Senha gerada e gravada só em: $SenhaFile (não aparece aqui)."
} else {
    Write-Host 'Escolha uma senha forte (12+ caracteres). Ela NÃO fica salva em lugar nenhum: guarde num gerenciador de senhas.'
    $p1 = Read-Host 'Senha' -AsSecureString
    $p2 = Read-Host 'Repita a senha' -AsSecureString
    $b1 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p1))
    $b2 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p2))
    if ($b1 -ne $b2) { Write-Host 'As senhas não são iguais.' -ForegroundColor Red; exit 1 }
    if ($b1.Length -lt 12) { Write-Host 'Use pelo menos 12 caracteres.' -ForegroundColor Red; exit 1 }
    $b1 = $null; $b2 = $null
}
$cert = New-SelfSignedCertificate -Subject 'CN=Janus (iAlencari)' -Type CodeSigningCert -KeyAlgorithm RSA -KeyLength 3072 `
    -HashAlgorithm SHA256 -KeyExportPolicy Exportable -CertStoreLocation 'Cert:\CurrentUser\My' -NotAfter (Get-Date).AddYears(15)
try {
    Export-PfxCertificate -Cert $cert -FilePath $Pfx -Password $p1 | Out-Null
    $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($cert)
    $pp = $rsa.ExportParameters($false)
    $xml = '<RSAKeyValue><Modulus>' + [Convert]::ToBase64String($pp.Modulus) + '</Modulus><Exponent>' + [Convert]::ToBase64String($pp.Exponent) + '</Exponent></RSAKeyValue>'
} finally {
    # a chave só fica no .pfx com senha, não no Windows
    Remove-Item -LiteralPath ("Cert:\CurrentUser\My\" + $cert.Thumbprint) -DeleteKey -ErrorAction SilentlyContinue
}
$src = [IO.File]::ReadAllText($App, [Text.Encoding]::UTF8)
$new = [regex]::Replace($src, "(?m)^\`$PublicKeyXml = '.*'\s*$", ("`$PublicKeyXml = '" + $xml + "'"))
if ($new -eq $src -and $src -notmatch [regex]::Escape($xml)) { throw 'Não achei a linha $PublicKeyXml no Janus.ps1' }
[IO.File]::WriteAllText($App, $new, (New-Object Text.UTF8Encoding($true)))
Set-Content -LiteralPath (Join-Path $Pasta 'janus-publica.xml') -Value $xml -Encoding ASCII
$sha = [Security.Cryptography.SHA256]::Create()
$hx = -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($xml)) | Select-Object -First 4 | ForEach-Object { $_.ToString('X2') })
Write-Host ''
Write-Host 'Pronto!' -ForegroundColor Green
Write-Host "Chave privada (com senha): $Pfx"
Write-Host ("Código de autenticidade: JN-{0}-{1}  (publique no README)" -f $hx.Substring(0, 4), $hx.Substring(4, 4))
Write-Host 'A chave pública já foi gravada no Janus.ps1.'
Write-Host 'AGORA: faça backup do .pfx (pendrive e/ou Google Drive). A senha fica só com você.' -ForegroundColor Yellow
