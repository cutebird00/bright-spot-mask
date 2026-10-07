# Runs quietly after Windows sign-in; launches the mask on connection transitions.
$mutex=[System.Threading.Mutex]::new($false,'Local\BrightSpotMaskDisplayWatcher')
if(-not $mutex.WaitOne(0)){$mutex.Dispose();exit}
Add-Type -Path (Join-Path $PSScriptRoot 'screen-mask-monitor.cs')
$app=Join-Path $PSScriptRoot 'screen-bright-spot-mask.ps1'
$engine=Join-Path ([Environment]::GetFolderPath('System')) 'WindowsPowerShell\v1.0\powershell.exe'
$wasConnected=$false
function Read-WatcherJson([string]$path){
    foreach($candidate in @($path,($path+'.bak'))){
        try{if(Test-Path -LiteralPath $candidate){return (Get-Content -LiteralPath $candidate -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop)}}catch{}
    }
    return $null
}
function Get-WatchedBinding {
    $binding=Read-WatcherJson (Join-Path $PSScriptRoot 'mask-display-binding.json')
    if($binding -and $binding.hardwareId){return @{hardwareId=[string]$binding.hardwareId;instanceKey=[string]$binding.instanceKey}}
    $store=Read-WatcherJson (Join-Path $PSScriptRoot 'mask-presets.json')
    $settings=if($store -and @($store.slots).Count -eq 3){$store.slots[[Math]::Max(0,[Math]::Min(2,[int]$store.activeSlot))]}else{Read-WatcherJson (Join-Path $PSScriptRoot 'mask-settings.json')}
    if($settings -and $settings.targetHardwareId){return @{hardwareId=[string]$settings.targetHardwareId;instanceKey=[string]$settings.targetInstanceKey}}
    return @{hardwareId='';instanceKey=''}
}
$previousBinding=''
try {
    while($true) {
        try {
            $binding=Get-WatchedBinding
            $identity=$binding.hardwareId+'|'+$binding.instanceKey
            if($identity -ne $previousBinding){$wasConnected=$false;$previousBinding=$identity}
            $connected=$null -ne [MaskMonitor]::FindBound($binding.hardwareId,$binding.instanceKey)
            if($connected -and -not $wasConnected) {
                Start-Process -FilePath $engine -WindowStyle Hidden -ArgumentList @('-NoProfile','-STA','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',('"'+$app+'"'),'-AutoStart')
            }
            $wasConnected=$connected
        } catch { }
        Start-Sleep -Seconds 5
    }
} finally { $mutex.ReleaseMutex(); $mutex.Dispose() }
