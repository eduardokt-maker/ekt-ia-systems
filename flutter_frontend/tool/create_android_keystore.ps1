$ErrorActionPreference = "Stop"

$keytool = "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe"
$keystoreDirectory = Join-Path $PSScriptRoot "..\android\keystore"
$keystorePath = Join-Path $keystoreDirectory "ekt-ia-systems-upload.jks"
$propertiesPath = Join-Path $PSScriptRoot "..\android\key.properties"

if (-not (Test-Path -LiteralPath $keytool)) {
    throw "keytool nao encontrado no Android Studio."
}

if (Test-Path -LiteralPath $keystorePath) {
    throw "A chave ja existe. Nao a substitua: $keystorePath"
}

New-Item -ItemType Directory -Force -Path $keystoreDirectory | Out-Null

$password = Read-Host "Digite uma senha forte para a chave" -AsSecureString
$confirmation = Read-Host "Repita a mesma senha" -AsSecureString
$passwordText = [System.Net.NetworkCredential]::new("", $password).Password
$confirmationText = [System.Net.NetworkCredential]::new("", $confirmation).Password

if ($passwordText.Length -lt 12) {
    throw "Use uma senha com pelo menos 12 caracteres."
}
if ($passwordText -cne $confirmationText) {
    throw "As senhas nao conferem."
}

try {
    $env:EKT_KEYSTORE_PASSWORD = $passwordText
    & $keytool -genkeypair -v `
        -keystore $keystorePath `
        -storepass:env EKT_KEYSTORE_PASSWORD `
        -keypass:env EKT_KEYSTORE_PASSWORD `
        -alias "ekt-ia-systems" `
        -keyalg RSA `
        -keysize 4096 `
        -validity 10000 `
        -dname "CN=EKT IA Systems, OU=Software, O=EKT IA Systems, L=Fortaleza, ST=Ceara, C=BR"

    if ($LASTEXITCODE -ne 0) {
        throw "O keytool nao conseguiu criar a chave."
    }

    @"
storePassword=$passwordText
keyPassword=$passwordText
keyAlias=ekt-ia-systems
storeFile=keystore/ekt-ia-systems-upload.jks
"@ | Set-Content -LiteralPath $propertiesPath -Encoding UTF8
}
finally {
    Remove-Item Env:EKT_KEYSTORE_PASSWORD -ErrorAction SilentlyContinue
    $passwordText = $null
    $confirmationText = $null
}

Write-Host "Chave criada em: $keystorePath"
Write-Host "Configuracao local criada em: $propertiesPath"
Write-Host "Guarde uma copia segura da chave e das senhas."
