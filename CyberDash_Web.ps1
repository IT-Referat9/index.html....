$port = 8080
$url = "http://localhost:$port/"
$htmlPath = Join-Path $PSScriptRoot "index.html"

# Function to get system stats as a hashtable
function Get-SystemStats {
    try {
        $cpu = (Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'").PercentProcessorTime
        
        $mem = Get-CimInstance Win32_OperatingSystem
        $memPercent = (($mem.TotalVisibleMemorySize - $mem.FreePhysicalMemory) / $mem.TotalVisibleMemorySize) * 100
        
        $disks = Get-PSDrive -PSProvider FileSystem | Select-Object Name, @{N = "Free"; E = { [math]::Round($_.Free / 1GB, 1) } }
        $diskStrings = $disks | ForEach-Object { "$($_.Name): $($_.Free)GB" }
        
        $services = Get-Service | Where-Object { $_.Status -eq 'Running' } | Select-Object Name, Status -First 15
        
        return @{
            cpu      = $cpu
            mem      = $memPercent
            disks    = $diskStrings
            services = $services
        }
    }
    catch {
        return @{ error = $_.Exception.Message }
    }
}

# Start HTTP Listener
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($url)
$listener.Prefixes.Add("http://localhost:$port/api/stats/")
$listener.Start()

Write-Host ">>> CYBERDASH SERVER ACTIVE AT $url" -ForegroundColor Cyan
Write-Host ">>> PRESS CTRL+C TO TERMINATE NEURAL LINK" -ForegroundColor Magenta

# Launch Browser
Start-Process $url

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        $path = $request.Url.LocalPath
        
        if ($path -eq "/") {
            $content = [System.IO.File]::ReadAllBytes($htmlPath)
            $response.ContentType = "text/html"
            $response.ContentLength64 = $content.Length
            $response.OutputStream.Write($content, 0, $content.Length)
        }
        elseif ($path -eq "/api/stats") {
            $stats = Get-SystemStats
            $json = $stats | ConvertTo-Json
            $content = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.ContentType = "application/json"
            $response.ContentLength64 = $content.Length
            $response.OutputStream.Write($content, 0, $content.Length)
        }
        else {
            $response.StatusCode = 404
        }
        
        $response.Close()
    }
}
finally {
    $listener.Stop()
}
