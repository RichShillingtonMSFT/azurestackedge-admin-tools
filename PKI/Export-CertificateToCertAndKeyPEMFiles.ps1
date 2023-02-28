Function Export-CertificateToCertAndKeyPEMFiles
{
    Param 
    (
        [Parameter(Mandatory=$true, HelpMessage="Certificate ThumbPrint")]
        [string]$CertificateThumbPrint,

        [Parameter(Mandatory=$true, HelpMessage="PFX Password as a Secure String")]
        [SecureString]$pfxPassword,

        [Parameter(Mandatory=$true, HelpMessage="File path for certificate PEM export. Example C:\certs\cert.pem")]
        [string]$CertFileOutputPath,

        [Parameter(Mandatory=$true, HelpMessage="Path to your private key PEM export. Example: C:\certs\key.pem")]
        [string]$KeyFileOutputPath
    )

    $Cert = Get-ChildItem Cert:\ -Recurse | ? {$_.Thumbprint -eq $CertificateThumbPrint}
    $TempPFXFile = $Cert | Export-PfxCertificate -FilePath "$Env:TEMP\temp.pfx" -Password $pfxPassword -Force

    $pfxAsCertificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($TempPFXFile, $pfxPassword, "Exportable")

    $pfx = [System.Security.Cryptography.X509Certificates.X509Certificate2]$pfxAsCertificate
    
    $base64CertText = [System.Convert]::ToBase64String($pfx.RawData, "InsertLineBreaks")

    $out = New-Object String[] -ArgumentList 3

    $out[0] = "-----BEGIN CERTIFICATE-----"
    $out[1] = $base64CertText
    $out[2] = "-----END CERTIFICATE-----"

    [System.IO.File]::WriteAllLines($CertFileOutputPath, $out)

    $RSACng = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($Cert)

    $KeyBytes = $RSACng.Key.Export([System.Security.Cryptography.CngKeyBlobFormat]::Pkcs8PrivateBlob)

    $KeyBase64 = [System.Convert]::ToBase64String($KeyBytes, [System.Base64FormattingOptions]::InsertLineBreaks)

    $KeyPem = @"
    -----BEGIN PRIVATE KEY-----
    $KeyBase64
    -----END PRIVATE KEY-----
"@

    [System.IO.File]::WriteAllLines($KeyFileOutputPath,$KeyPem)

}

$PFXPass = ConvertTo-SecureString -String 'MyString' -AsPlainText -Force
Export-CertificateToCertAndKeyPEMFiles -CertificateThumbPrint '1212432341241345132453245' -pfxPassword $PFXPass -CertFileOutputPath C:\certs\cert.pem -KeyFileOutputPath C:\certs\key.pem

