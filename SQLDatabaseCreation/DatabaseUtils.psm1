function Convert-SizeToInt {
    param([string]$SizeString)
    if ($SizeString -match '^(\d+)(MB|GB|TB)$') {
        $size = [int]$matches[1]
        $unit = $matches[2]
        switch ($unit) {
            'MB' { return $size }
            'GB' { return $size * 1024 }
            'TB' { return $size * 1024 * 1024 }
            default { return $size }
        }
    }
    return $SizeString
}

function Write-Log {
    param(
        $Message,
        [ValidateSet("Info", "Warning", "Error", "Success")]$Level = "Info",
        $LogFile
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Write-Host $logEntry -ForegroundColor @{"Info"="White";"Warning"="Yellow";"Error"="Red";"Success"="Green"}[$Level]
    Add-Content -Path $LogFile -Value $logEntry -Encoding UTF8
}

function Initialize-Directories {
    param(
        $DataDrive,
        $LogDrive,
        $ServerInstanceName
    )

    $paths = @(
        "$DataDrive:\$ServerInstanceName\data",
        "$LogDrive:\$ServerInstanceName\log"
    )

    foreach ($path in $paths) {
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
            Write-Log -Message "Created directory: $path" -Level Info -LogFile $LogFile
        }
    }
}

function Enable-QueryStore {
    param(
        $SqlInstance,
        $Database
    )

    $queryStoreConfig = @{
        SqlInstance = $SqlInstance
        Database = $Database
        State = 'ReadWrite'
        StaleQueryThreshold = [timespan]::FromDays(31).Days
        CaptureMode = 'Auto'
        MaxSize = 100
        FlushInterval = [timespan]::FromSeconds(900).TotalSeconds
        CleanupMode = 'Auto'
        MaxPlansPerQuery = 100
    }

    Set-DbaDbQueryStoreOption @queryStoreConfig
}
