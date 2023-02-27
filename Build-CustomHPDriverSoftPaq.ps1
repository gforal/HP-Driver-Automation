<#
    Author: Graham Foral
    Date:   02/26/2023

.SYNOPSIS

    To allow system administrators to build complete and up-to-date driver packs for HP computers. The HP Client Management Solutions Script Library must be installed for the 
    system prior to use: https://www.hp.com/us-en/solutions/client-management-solutions/download.html

.NOTES

    - When '-Compress' is used, DriverPack.zip is created in $TargetDir

.EXAMPLE

This command will download, extract, and then compress the driver packages into a single ZIP file, but will not install them
.\Build-CustomHPDriverSoftPaq.ps1 -Platform 8760 -TargetDir C:\DriverPackage -Extract:$True -Compress:$True -Install:$False

.PARAMETER Platform
    Required: Used to tell the HP PowerShell Commandlets that system family you want drivers for. The "Platform" is actually just the system's baseboard, which is found using the following command 
    (Get-CimInstance -ClassName Win32_Baseboard).Product

.PARAMETER TargetDir
    Required: To let the script know where to put the SoftPaqs.
.PARAMETER Extract
    Optional: To let the script know if you want to extract all of the SoftPaqs after download.
.PARAMETER Install
    Optional: To let the script know if you want to install all of the SoftPaqs after download. This is done by executing the SoftPaq.
.PARAMETER Compress
    Optional, but is the main purpose of the script. This let's the script know that you want to ZIP-up the directories containing the extracted SoftPaqs. If you use this argument, you must also add -Extract:$True
#>

param(
    $Platform, 
    $TargetDir,
    $Extract,
    $Install,
    $Compress
)

$ExecDir = $MyInvocation.MyCommand.Path
$SoftPaqs = $NULL


Function Get-DriverPackSoftPaqs {
    $TempFileLog = Join-Path -Path $TargetDir -ChildPath "Available Driver Packs.log" 
    Start-Transcript -Path $TempFileLog -Force
    New-HPDriverPack -Platform $Platform -Os win11 -OSVer 22h2 -WhatIf 
    Stop-Transcript

    $SoftPaqs = Get-Content -Path $TempFileLog | Select-String -pattern "sp[0-9]....." | ForEach { $_.Matches } | Select Value 

    ForEach ($SoftPaq in $SoftPaqs) {
    
        Write-Host "Information (Get-DriverPackSoftPaqs): " -ForegroundColor Green -NoNewline
        Write-Host "Gathering SoftPaq Information: $($SoftPaq.Value)"
    
        $SoftPaq = $SoftPaq.Value -Replace (" ", "")
        $SoftPaqMeta = Get-SoftpaqMetadata -Number $SoftPaq 
    
        Write-Host "Information (Get-DriverPackSoftPaqs): " -ForegroundColor Green -NoNewline
        Write-Host "Parsing Metadata for: $SoftPaq"
   
        $SoftPaqName = ($SoftPaqMeta."Software Title".US).ToString() 
        $SoftPaqDate = [datetime]::ParseExact(($SoftPaqMeta.'CVA File Information'.CVATimeStamp).Split("T")[0], 'yyyyMMdd', $NULL) | Get-Date -Format 'MMM dd, yyyy'
        $SoftPaqVersion = ($SoftPaqMeta.General.Version).ToString()
        $OutFileName = Join-Path -Path $TargetDir -ChildPath ($SoftPaqName + " - " + $SoftPaqVersion + " (" + $SoftPaqDate + ").exe")
        
        Write-Host "Information (Get-DriverPackSoftPaqs): " -ForegroundColor Green -NoNewline
        Write-Host "Downloading $SoftPaq and saving as $OutFileName"

        Get-Softpaq -Number $SoftPaq -SaveAs $OutFileName -KeepInvalidSigned -ErrorAction Continue
    }
}

Function Extract-SoftPaqs {
    
    $SoftPaqEXEs = Get-ChildItem -Path $TargetDir -Filter *.exe
    
    ForEach ($SoftPaqEXE in $SoftPaqEXEs) {
        $Destination = Join-Path -Path $TargetDir -ChildPath $SoftPaqEXE.Name.Replace(".exe", "") 
        $Destination = "`"" + $Destination + "`""
        $ExtractOnlyParams = "-e -f $Destination -s"

        Write-Host "Information (Extract-SoftPaqs): " -ForegroundColor Green -NoNewline
        Write-Host "$($SoftPaqEXE.Name) => $Destination"
        
        Start-Process -FilePath ("`"" + $SoftPaqEXE.FullName + "`"") -ArgumentList $ExtractOnlyParams -Wait -NoNewWindow   
    }
}

Function Install-SoftPaqs {
    
    $SoftPaqEXEs = Get-ChildItem -Path $TargetDir -Filter *.exe
    
    ForEach ($SoftPaqEXE in $SoftPaqEXEs) {
        $Destination = Join-Path -Path $TargetDir -ChildPath $SoftPaqEXE.Name.Replace(".exe", "") 
        $Destination = "`"" + $Destination + "`""
        $InstallOnlyParams = "-s"

        Write-Host "Information (Install-SoftPaqs): " -ForegroundColor Green -NoNewline
        Write-Host "Installing: $($SoftPaqEXE.Name)"
        
        Start-Process -FilePath ("`"" + $SoftPaqEXE.FullName + "`"") -ArgumentList $InstallOnlyParams -Wait -NoNewWindow   
    }

}

# General Logic #

Get-DriverPackSoftPaqs


If ((Test-Path -Path $TargetDir -PathType Container) -and (Get-ChildItem -Path $TargetDir).count -gt 0 ) {
    Write-Host "Information: " -ForegroundColor Green -NoNewline
    Write-Host "$TargetDir exists..."

}
Else {
    Write-Host "Warning: " -ForegroundColor Green -NoNewline
    Write-Host "$TargetDir did not exist and will be created"
    New-Item -Path $TargetDir -Force -ItemType Directory | Out-Null
}

$SystemFamily = (Get-HPDeviceDetails -Platform $Platform).Name

Write-Host "System family requested: " 
ForEach ($SystemModel in $SystemFamily) {
    Write-Host " - $SystemModel"
}




If ($Extract -eq $True) {
    Extract-SoftPaqs
}
Else {
    Write-Host "Information: " -ForegroundColor Green -NoNewline
    Write-Host "SoftPaq extraction was not requsted."
}

If (($Compress -eq $True) -and ($Extract -eq $True)) {
    $TargetDir
    Write-Host "Information: " -ForegroundColor Green -NoNewline
    Write-Host "Creating Driver Package."
    
    $ExtractedSoftPaqs = Get-ChildItem -Path $TargetDir -Directory
    Compress-Archive -Path $ExtractedSoftPaqs.FullName -DestinationPath (Join-Path -Path $TargetDir -ChildPath "DriverPack.zip") -CompressionLevel Optimal

}
Else {
    Write-Host "Warning: " -ForegroundColor Yellow -NoNewline
    Write-Host "The -Compress and -Extract parameters MUST both be set to `$True to create a ZIP driver package."
}

If ($Install -eq $True) {
    Install-SoftPaqs
}