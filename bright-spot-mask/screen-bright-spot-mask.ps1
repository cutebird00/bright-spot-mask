# Fixed click-through screen mask with independent center and edge RGBA controls.
param([switch]$AutoStart)
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms,System.Drawing
Add-Type -Path (Join-Path $PSScriptRoot 'screen-mask-monitor.cs')
Add-Type -Path (Join-Path $PSScriptRoot 'screen-mask-topmost.cs')
Add-Type -Path (Join-Path $PSScriptRoot 'screen-mask-brightness.cs')
Add-Type -Path (Join-Path $PSScriptRoot 'screen-mask-curves.cs') -ReferencedAssemblies ([System.Windows.Media.Color].Assembly.Location),([System.Windows.DependencyObject].Assembly.Location)
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class MaskWindowStyles {
    [DllImport("user32.dll", EntryPoint="GetWindowLongW")]
    public static extern int GetWindowLong(IntPtr hWnd, int index);
    [DllImport("user32.dll", EntryPoint="SetWindowLongW")]
    public static extern int SetWindowLong(IntPtr hWnd, int index, int value);
    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y,
        int width, int height, uint flags);
    [DllImport("shell32.dll", CharSet=CharSet.Unicode)]
    public static extern int SetCurrentProcessExplicitAppUserModelID(string appId);
}
'@
$showEvent=[System.Threading.EventWaitHandle]::new($false,
    [System.Threading.EventResetMode]::AutoReset,'Local\BrightSpotMaskOpen')
$mutex = [System.Threading.Mutex]::new($false, 'Local\BrightSpotMask')
if (-not $mutex.WaitOne(0)) {
    if(-not $AutoStart){[void]$showEvent.Set()}
    $showEvent.Dispose(); $mutex.Dispose()
    exit
}
[void][MaskWindowStyles]::SetCurrentProcessExplicitAppUserModelID('SomeTools.BrightSpotMask')
$iconPath=Join-Path $PSScriptRoot 'mask-icon.ico'
$settingsPath=Join-Path $PSScriptRoot 'mask-settings.json'
function Read-JsonResilient([string]$path){
    foreach($candidate in @($path,($path+'.bak'))){
        if(Test-Path -LiteralPath $candidate){
            try{return (Get-Content -LiteralPath $candidate -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop)}catch{}
        }
    }
    return $null
}
function Write-JsonAtomic([string]$path,$value){
    $temporary=$path+'.tmp'
    [System.IO.File]::WriteAllText($temporary,($value | ConvertTo-Json -Depth 10),[System.Text.UTF8Encoding]::new($true))
    if([System.IO.File]::Exists($path)){[System.IO.File]::Replace($temporary,$path,$path+'.bak',$true)}
    else{[System.IO.File]::Move($temporary,$path)}
}
$languagePath=Join-Path $PSScriptRoot 'mask-language.json'
$savedLanguage=Read-JsonResilient $languagePath
$script:language=if($savedLanguage -and $savedLanguage.language -in @('zh-CN','zh-TW','en')){[string]$savedLanguage.language}else{'zh-CN'}
$script:localizedProperties=[System.Collections.Generic.List[object]]::new()
$script:translations=@{
'总开关'=@('總開關','Master switch');'统一开启或关闭两层遮罩。每层的参数与位置独立保存。'=@('統一開啟或關閉兩層遮罩。每層的參數與位置獨立保存。','Turn both masks on or off. Each layer saves its own settings and position.')
'连接显示器'=@('連接顯示器','Monitor');'选择并记住两层遮罩绑定的显示器。'=@('選擇並記住兩層遮罩綁定的顯示器。','Choose the display used by both mask layers.')
'实时生效 · 自动保存'=@('即時生效 · 自動保存','Live · Auto-save');'随背景亮度'=@('隨背景亮度','Adapt to background');'背景越亮，遮罩越强。白色使用设定强度，黑色强度为 0。两层各自读取背景。'=@('背景越亮，遮罩越強。白色使用設定強度，黑色強度為 0。兩層各自讀取背景。','Brighter backgrounds strengthen the mask. White uses the set strength; black uses 0. Each layer samples independently.')
'第一层遮罩'=@('第一層遮罩','Layer 1');'第二层遮罩'=@('第二層遮罩','Layer 2');'启用第一层'=@('啟用第一層','Enable layer 1');'启用第二层'=@('啟用第二層','Enable layer 2');'第一层预览'=@('第一層預覽','Layer 1 preview');'第二层预览'=@('第二層預覽','Layer 2 preview')
'01  中心'=@('01  中心','01  Center');'02  中间点'=@('02  中間點','02  Midpoint');'03  边缘'=@('03  邊緣','03  Edge');'白色背景'=@('白色背景','White');'浅灰背景'=@('淺灰背景','Light gray');'深色背景'=@('深色背景','Dark');'中心'=@('中心','Center');'中间点'=@('中間點','Midpoint');'边缘'=@('邊緣','Edge');'启用'=@('啟用','Enable')
'亮度'=@('亮度','Brightness');'透明度'=@('透明度','Transparency');'红色'=@('紅色','Red');'绿色'=@('綠色','Green');'蓝色'=@('藍色','Blue');'位置 · 半径百分比'=@('位置 · 半徑百分比','Position · radius %');'渐变起点 · 半径 0%'=@('漸變起點 · 半徑 0%','Gradient start · radius 0%');'渐变终点 · 半径 100%'=@('漸變終點 · 半徑 100%','Gradient end · radius 100%')
'只调这个渐变点：0% 为黑色、100% 为原色、200% 为白色；透明度独立。'=@('只調整此漸變點：0% 為黑色、100% 為原色、200% 為白色；透明度獨立。','Adjust only this gradient point: 0% is black, 100% is original, 200% is white. Transparency is separate.')
'圆圈大小'=@('圓圈大小','Circle size');'圆圈直径'=@('圓圈直徑','Diameter');'屏幕位置'=@('螢幕位置','Screen position');'收起到托盘'=@('收合至系統匣','Hide to tray');'退出'=@('結束','Exit');'亮斑遮罩'=@('亮斑遮罩','Bright Spot Mask')
'原色'=@('原色','Original');'实际颜色 #{0:X2}{1:X2}{2:X2}（已应用该点亮度）'=@('實際顏色 #{0:X2}{1:X2}{2:X2}（已套用該點亮度）','Actual color #{0:X2}{1:X2}{2:X2} (brightness applied)')
'档位 {0} · 自动保存'=@('設定檔 {0} · 自動保存','Profile {0} · Auto-save');'档位 {0}'=@('設定檔 {0}','Profile {0}');'保存失败，请重试'=@('保存失敗，請重試','Save failed. Try again.');'切换失败，已保留原设置'=@('切換失敗，已保留原設定','Switch failed; previous settings kept');'当前档位未能保存，已取消切换。'=@('目前設定檔無法保存，已取消切換。','Could not save the current profile; switching was cancelled.');'当前档位保存失败，显示器绑定未更改。'=@('目前設定檔保存失敗，顯示器綁定未變更。','Could not save the current profile; monitor binding was not changed.');'这台显示器已断开，请刷新列表后重试。'=@('此顯示器已中斷連線，請重新整理清單後再試。','This display is disconnected. Refresh the list and try again.');'方案必须包含两层遮罩。'=@('設定檔必須包含兩層遮罩。','A profile must contain two mask layers.')
'选择绑定的显示器'=@('選擇綁定的顯示器','Choose monitor');'当前绑定：{0}'=@('目前綁定：{0}','Current monitor: {0}');'绑定由三个档位共享；不同显示器的位置分别记忆。'=@('綁定由三個設定檔共用；不同顯示器的位置分別記憶。','The monitor is shared by all profiles; positions are remembered per display.');'没有检测到可用显示器，请连接后刷新。'=@('找不到可用顯示器，請連接後重新整理。','No displays found. Connect one and refresh.');'显示器 {0}  ·  {1}  ·  {2} × {3}'=@('顯示器 {0}  ·  {1}  ·  {2} × {3}','Display {0}  ·  {1}  ·  {2} × {3}');'主显示器'=@('主顯示器','Primary');'刷新'=@('重新整理','Refresh');'取消'=@('取消','Cancel');'绑定所选显示器'=@('綁定所選顯示器','Use selected display');'请先选择一台显示器。'=@('請先選擇一台顯示器。','Select a display first.')
'单击移动 5 像素；长按连续移动并逐渐加速'=@('單擊移動 5 像素；長按連續移動並逐漸加速','Click to move 5 px; hold to move continuously, accelerating');'打开调节窗口'=@('開啟調整視窗','Open settings');'退出遮罩'=@('結束遮罩','Exit mask');'亮斑遮罩 - 双击打开调节窗口'=@('亮斑遮罩 - 雙擊開啟調整視窗','Bright Spot Mask - double-click to open')
'等待 {0} 连接'=@('等待 {0} 連線','Waiting for {0}');'{0} 已连接 · 遮罩已关闭'=@('{0} 已連線 · 遮罩已關閉','{0} connected · Mask off');'{0} · 背景采样暂不可用'=@('{0} · 背景取樣暫不可用','{0} · Background sampling unavailable');'{0} · 当前层强度 {1}%'=@('{0} · 目前圖層強度 {1}%','{0} · Layer strength {1}%');'{0} · 随背景调节'=@('{0} · 隨背景調整','{0} · Adapting to background');'{0} 已连接 · 自动保存'=@('{0} 已連線 · 自動保存','{0} connected · Auto-save')
'自动启动配置失败：{0}'=@('自動啟動設定失敗：{0}','Startup setup failed: {0}');'连接检测文件缺失，请完整解压所有程序文件。'=@('連線偵測檔案遺失，請完整解壓所有程式檔案。','Connection watcher is missing. Extract all program files.');'启动目录存在同名的其他快捷方式，无法自动配置。'=@('啟動資料夾已有同名捷徑，無法自動設定。','A shortcut with the same name exists in Startup; setup failed.')
}
function T([string]$text){
    if($script:language -eq 'zh-CN'){return $text}
    if($script:translations.ContainsKey($text)){if($script:language -eq 'zh-TW'){return $script:translations[$text][0]}return $script:translations[$text][1]}
    if($text -match '^当前绑定：(.*)$'){return ((T '当前绑定：{0}') -f $matches[1])}
    if($text -match '^档位 (\d+) · 自动保存$'){return ((T '档位 {0} · 自动保存') -f $matches[1])}
    if($text -match '^档位 (\d+)$'){return ((T '档位 {0}') -f $matches[1])}
    if($text -match '^实际颜色 #([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})（已应用该点亮度）$'){
        return ((T '实际颜色 #{0:X2}{1:X2}{2:X2}（已应用该点亮度）') -f [Convert]::ToInt32($matches[1],16),[Convert]::ToInt32($matches[2],16),[Convert]::ToInt32($matches[3],16))
    }
    return $text
}
function Set-Loc($object,[string]$property,[string]$source){
    $existing=$null
    foreach($candidate in $script:localizedProperties){if([object]::ReferenceEquals($candidate.Object,$object) -and $candidate.Property -eq $property){$existing=$candidate;break}}
    if($existing){$existing.Source=$source}else{$entry=@{Object=$object;Property=$property;Source=$source};$script:localizedProperties.Add($entry)}
    $object.$property=T $source
}
function Update-LocalizedProperties {
    foreach($entry in $script:localizedProperties){$entry.Object.($entry.Property)=T $entry.Source}
    $font=if($script:language -eq 'en'){[System.Windows.Media.FontFamily]::new('Arial')}else{[System.Windows.Media.FontFamily]::new('Microsoft YaHei UI')}
    if($panel){$panel.FontFamily=$font}
    if($languageSelector){$languageSelector.FontFamily=$font}
    if($menu){$menu.Font=[System.Drawing.Font]::new($(if($script:language -eq 'en'){'Arial'}else{'Microsoft YaHei UI'}),9.0)}
    if($tray){$tray.Text=[string](T '亮斑遮罩 - 双击打开调节窗口');if($tray.Text.Length -gt 63){$tray.Text=$tray.Text.Substring(0,63)}}
}
function Save-Language { Write-JsonAtomic -path $languagePath -value @{language=$script:language} }

function Copy-ProfileSnapshot($value){
    return ($value | ConvertTo-Json -Depth 10 | ConvertFrom-Json -ErrorAction Stop)
}
function Copy-NormalizedProfile($snapshot){
    $copy=Copy-ProfileSnapshot $snapshot
    if(@($copy.layers).Count -ne 2){throw (T '方案必须包含两层遮罩。')}
    $result=@{}
    foreach($property in $copy.PSObject.Properties){if($property.Name -ne 'layers'){$result[$property.Name]=$property.Value}}
    $result.schemaVersion=9
    $result.maskEnabled=[bool]$result.maskEnabled;$result.adaptiveEnabled=[bool]$result.adaptiveEnabled
    $result.activeLayer=[Math]::Max(0,[Math]::Min(1,[int]$result.activeLayer))
    if(-not $result.targetHardwareId){$result.targetHardwareId=''}
    if(-not $result.targetMonitorName){$result.targetMonitorName='Select a display'}
    if(-not $result.targetInstanceKey){$result.targetInstanceKey=''}
    $result.layers=@()
    for($index=0;$index -lt 2;$index++){
        $values=New-LayerSettings
        foreach($key in $layerKeys){if($null -ne $copy.layers[$index].$key){$values[$key]=$copy.layers[$index].$key}}
        $values.enabled=[bool]$values.enabled;$values.middleEnabled=[bool]$values.middleEnabled
        foreach($key in @('monitorX','monitorY','x','y')){$values[$key]=[int]$values[$key]}
        $values.radiusPx=[Math]::Max(15,[Math]::Min(150,[int]$values.radiusPx))
        $values.feather=100
        $values.middlePosition=[Math]::Max(1,[Math]::Min(99,[int]$values.middlePosition))
        foreach($prefix in @('center','middle','edge')){
            foreach($channel in @('Red','Green','Blue')){
                $key=$prefix+$channel;$values[$key]=[Math]::Max(0,[Math]::Min(255,[int]$values[$key]))
            }
            $key=$prefix+'Transparency';$values[$key]=[Math]::Max(0,[Math]::Min(100,[int]$values[$key]))
            $key=$prefix+'Brightness';$values[$key]=[Math]::Max(0,[Math]::Min(200,[int]$values[$key]))
        }
        $result.layers+=$values
    }
    return $result
}

$layerKeys=@('enabled','x','y','monitorX','monitorY','radiusPx','feather','middlePosition','middleEnabled',
    'centerRed','centerGreen','centerBlue','centerTransparency','centerBrightness',
    'middleRed','middleGreen','middleBlue','middleTransparency','middleBrightness',
    'edgeRed','edgeGreen','edgeBlue','edgeTransparency','edgeBrightness')
function New-LayerSettings {
    $bounds=[System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $centerX=[int]($bounds.Width/2.0);$centerY=[int]($bounds.Height/2.0)
    return @{enabled=$true;monitorX=$centerX;monitorY=$centerY;x=$centerX;y=$centerY;radiusPx=40;feather=100;middlePosition=50;middleEnabled=$false
        centerBrightness=100;centerRed=0;centerGreen=0;centerBlue=0;centerTransparency=90
        middleBrightness=100;middleRed=0;middleGreen=0;middleBlue=0;middleTransparency=95
        edgeBrightness=100;edgeRed=0;edgeGreen=0;edgeBlue=0;edgeTransparency=100}
}

$config=@{schemaVersion=9;targetInstanceKey='';maskEnabled=$true;adaptiveEnabled=$false;targetHardwareId='';targetMonitorName='Select a display';activeLayer=0;layers=@()}
$saved=$null
$saved=Read-JsonResilient $settingsPath
if($saved){
    foreach($key in @('maskEnabled','adaptiveEnabled','targetHardwareId','targetInstanceKey','targetMonitorName','activeLayer')){
        if($null -ne $saved.$key){$config[$key]=$saved.$key}
    }
}
$first=New-LayerSettings
if($saved -and $saved.schemaVersion -ge 5 -and @($saved.layers).Count -ge 2){
    foreach($key in $layerKeys){if($null -ne $saved.layers[0].$key){$first[$key]=$saved.layers[0].$key}}
    $second=New-LayerSettings
    foreach($key in $layerKeys){if($null -ne $saved.layers[1].$key){$second[$key]=$saved.layers[1].$key}}
} else {
    if($saved){foreach($key in $layerKeys){if($null -ne $saved.$key){$first[$key]=$saved.$key}}}
    $second=$first.Clone();$second.enabled=$false
}
$config.layers=@($first,$second)
$config.maskEnabled=[bool]$config.maskEnabled
$config.adaptiveEnabled=[bool]$config.adaptiveEnabled
$config.activeLayer=[Math]::Max(0,[Math]::Min(1,[int]$config.activeLayer))
foreach($values in $config.layers){
    $values.enabled=[bool]$values.enabled;$values.middleEnabled=[bool]$values.middleEnabled
    $values.monitorX=[int]$values.monitorX;$values.monitorY=[int]$values.monitorY
    $values.radiusPx=[Math]::Max(15,[Math]::Min(150,[int]$values.radiusPx))
    $values.feather=100
    $values.middlePosition=[Math]::Max(1,[Math]::Min(99,[int]$values.middlePosition))
    foreach($prefix in @('center','middle','edge')){
        foreach($channel in @('Red','Green','Blue')){
            $key=$prefix+$channel;$values[$key]=[Math]::Max(0,[Math]::Min(255,[int]$values[$key]))
        }
        $brightnessKey=$prefix+'Brightness';$values[$brightnessKey]=[Math]::Max(0,[Math]::Min(200,[int]$values[$brightnessKey]))
        $key=$prefix+'Transparency';$values[$key]=[Math]::Max(0,[Math]::Min(100,[int]$values[$key]))
    }
}
$presetsPath=Join-Path $PSScriptRoot 'mask-presets.json'
$savedPresets=Read-JsonResilient $presetsPath
$presets=@{schemaVersion=1;activeSlot=0;slots=@()}
if($savedPresets){$presets.activeSlot=[Math]::Max(0,[Math]::Min(2,[int]$savedPresets.activeSlot))}
for($index=0;$index -lt 3;$index++){
    $snapshot=Copy-ProfileSnapshot $config
    if($savedPresets -and @($savedPresets.slots).Count -eq 3){
        try{$snapshot=Copy-ProfileSnapshot (Copy-NormalizedProfile $savedPresets.slots[$index])}catch{}
    }
    $presets.slots+=$snapshot
}
# The preset store is authoritative; the settings file is a convenient current-settings copy.
$script:config=Copy-NormalizedProfile $presets.slots[$presets.activeSlot]
$script:lastSaveSucceeded=$true
function Save-Settings {
    try{
        foreach($values in $config.layers){$values.feather=100}
        $presets.slots[$presets.activeSlot]=Copy-ProfileSnapshot $config
        Write-JsonAtomic -path $presetsPath -value $presets
        $script:lastSaveSucceeded=$true
        try{Write-JsonAtomic -path $settingsPath -value $config}catch{}
        if($presetStatus){$presetStatus.Text=(T ('档位 {0} · 自动保存' -f ($presets.activeSlot+1)));$presetStatus.Foreground=UI-Brush '#237D68'}
    }catch{
        $script:lastSaveSucceeded=$false
        if($presetStatus){$presetStatus.Text=T '保存失败，请重试';$presetStatus.Foreground=UI-Brush '#C25A54'}
    }
}

$bindingPath=Join-Path $PSScriptRoot 'mask-display-binding.json'
$savedBinding=Read-JsonResilient $bindingPath
$monitorBinding=@{hardwareId=$config.targetHardwareId;instanceKey=$config.targetInstanceKey;monitorName=$config.targetMonitorName;positions=@{}}
if($savedBinding -and $savedBinding.hardwareId){
    $monitorBinding.hardwareId=[string]$savedBinding.hardwareId
    $monitorBinding.instanceKey=[string]$savedBinding.instanceKey
    $monitorBinding.monitorName=[string]$savedBinding.monitorName
    if($savedBinding.positions){foreach($property in $savedBinding.positions.PSObject.Properties){$monitorBinding.positions[$property.Name]=$property.Value}}
}
function Get-BindingKey([string]$hardwareId,[string]$instanceKey){
    if([string]::IsNullOrEmpty($instanceKey)){return $hardwareId}
    return $hardwareId+'|'+$instanceKey
}
function Capture-MonitorPositions($display){
    $slots=@()
    for($slot=0;$slot -lt 3;$slot++){
        $positions=@()
        foreach($layer in $presets.slots[$slot].layers){$positions+=@{x=[int]$layer.monitorX;y=[int]$layer.monitorY}}
        $slots+=,$positions
    }
    return @{slots=$slots;width=$(if($display){$display.Width}else{0});height=$(if($display){$display.Height}else{0})}
}
function Apply-BindingFields {
    foreach($entry in @(@{key='targetHardwareId';value=$monitorBinding.hardwareId},@{key='targetInstanceKey';value=$monitorBinding.instanceKey},@{key='targetMonitorName';value=$monitorBinding.monitorName})){
        $config[$entry.key]=$entry.value
        foreach($snapshot in $presets.slots){$snapshot | Add-Member -NotePropertyName $entry.key -NotePropertyValue $entry.value -Force}
    }
}
function Restore-MonitorPositions($pack,$display){
    for($slot=0;$slot -lt 3;$slot++){
        $profile=Copy-NormalizedProfile $presets.slots[$slot]
        for($index=0;$index -lt 2;$index++){
            if($pack -and @($pack.slots).Count -eq 3){
                $x=[double]$pack.slots[$slot][$index].x;$y=[double]$pack.slots[$slot][$index].y
                if($display -and $pack.width -gt 0 -and $pack.height -gt 0){$x=$x*$display.Width/$pack.width;$y=$y*$display.Height/$pack.height}
            }elseif($display){$x=$display.Width/2.0;$y=$display.Height/2.0}
            else{$x=$profile.layers[$index].monitorX;$y=$profile.layers[$index].monitorY}
            if($display){$x=[Math]::Max(0.0,[Math]::Min($display.Width-1.0,$x));$y=[Math]::Max(0.0,[Math]::Min($display.Height-1.0,$y))}
            $profile.layers[$index].monitorX=[int][Math]::Round($x);$profile.layers[$index].monitorY=[int][Math]::Round($y)
        }
        $presets.slots[$slot]=Copy-ProfileSnapshot $profile
    }
    $script:config=Copy-NormalizedProfile $presets.slots[$presets.activeSlot]
}
if($savedBinding -and $savedBinding.hardwareId){
    $changed=$config.targetHardwareId -ne $monitorBinding.hardwareId -or $config.targetInstanceKey -ne $monitorBinding.instanceKey
    if($changed){
        $key=Get-BindingKey $monitorBinding.hardwareId $monitorBinding.instanceKey
        $display=[MaskMonitor]::FindBound($monitorBinding.hardwareId,$monitorBinding.instanceKey)
        Restore-MonitorPositions $monitorBinding.positions[$key] $display
    }
}
Apply-BindingFields

# Connection detection is always enabled; no separate preference or UI switch.
$startupFolder=[Environment]::GetFolderPath('Startup')
$watcherPath=Join-Path $PSScriptRoot 'watch-display.ps1'
function Test-OwnedStartupShortcut($shell,[string]$path){
    if(-not [System.IO.File]::Exists($path)){return $false}
    $shortcut=$shell.CreateShortcut($path)
    return [System.IO.Path]::GetFileName($shortcut.TargetPath) -ieq 'powershell.exe' -and $shortcut.Arguments -match '(?i)-File\s+"[^"\r\n]*[\\/]watch-(?:display|xg27qa)\.ps1"'
}
function Ensure-ConnectionStartup {
    $shell=New-Object -ComObject WScript.Shell
    try{
        $path=Join-Path $startupFolder '亮斑遮罩 - 显示器连接自动启动.lnk'
        $legacyPath=Join-Path $startupFolder '亮斑遮罩 - XG27QA 自动启动.lnk'
            if(-not (Test-Path -LiteralPath $watcherPath)){throw (T '连接检测文件缺失，请完整解压所有程序文件。')}
            if([System.IO.File]::Exists($path) -and -not (Test-OwnedStartupShortcut $shell $path)){throw (T '启动目录存在同名的其他快捷方式，无法自动配置。')}
            $shortcut=$shell.CreateShortcut($path)
            $shortcut.TargetPath=Join-Path ([Environment]::GetFolderPath('System')) 'WindowsPowerShell\v1.0\powershell.exe'
            $shortcut.Arguments='-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$watcherPath+'"'
            $shortcut.WorkingDirectory=$PSScriptRoot;$shortcut.WindowStyle=7
            $shortcut.Description='登录后静默检测绑定的显示器，连接时启动亮斑遮罩。'
            if(Test-Path -LiteralPath $iconPath){$shortcut.IconLocation=$iconPath+',0'}
            $shortcut.Save()
            if(Test-OwnedStartupShortcut $shell $legacyPath){[System.IO.File]::Delete($legacyPath)}
    }finally{if($shell){[void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)}}
}
function Start-ConnectionWatcher {
    $engine=Join-Path ([Environment]::GetFolderPath('System')) 'WindowsPowerShell\v1.0\powershell.exe'
    Start-Process -FilePath $engine -WindowStyle Hidden -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',('"'+$watcherPath+'"'))
}
function Initialize-ConnectionAutoStart {
    try{
        Ensure-ConnectionStartup
        if(-not $AutoStart){Start-ConnectionWatcher}
    }catch{
        [void][System.Windows.MessageBox]::Show(((T '自动启动配置失败：{0}') -f $_.Exception.Message),(T '亮斑遮罩'))
    }
}

$script:settings=$config.layers[$config.activeLayer]
$script:targetDisplay=[MaskMonitor]::FindBound($config.targetHardwareId,$config.targetInstanceKey)
$layerMasks=@()
foreach($values in $config.layers){
    $window=[System.Windows.Window]::new()
    $window.WindowStyle='None';$window.ResizeMode='NoResize';$window.AllowsTransparency=$true
    $window.Background=[System.Windows.Media.Brushes]::Transparent
    $window.ShowInTaskbar=$false;$window.ShowActivated=$false;$window.Focusable=$false;$window.Topmost=$true
    $window.Opacity=0.0;$window.Left=0;$window.Top=0;$window.Width=88;$window.Height=88
    $layerBrush=[System.Windows.Media.RadialGradientBrush]::new()
    $layerBrush.Center=[System.Windows.Point]::new(0.5,0.5)
    $layerBrush.GradientOrigin=[System.Windows.Point]::new(0.5,0.5)
    $layerBrush.RadiusX=0.5;$layerBrush.RadiusY=0.5;$layerBrush.ColorInterpolationMode='SRgbLinearInterpolation'
    $layerEllipse=[System.Windows.Shapes.Ellipse]::new();$layerEllipse.Fill=$layerBrush;$layerEllipse.IsHitTestVisible=$false
    $window.Content=$layerEllipse
    $runtime=@{Settings=$values;Window=$window;Brush=$layerBrush;Handle=[IntPtr]::Zero;Signature='';Strength=1.0;CaptureExcluded=$false}
    $window.Tag=$runtime
    $window.Add_SourceInitialized({
        param($sender,$e)
        $runtime=$sender.Tag
        $runtime.Handle=([System.Windows.Interop.WindowInteropHelper]::new($sender)).Handle
        $style=[MaskWindowStyles]::GetWindowLong($runtime.Handle,-20)
        [void][MaskWindowStyles]::SetWindowLong($runtime.Handle,-20,($style -bor 0x20 -bor 0x80 -bor 0x08000000))
        Update-Mask
    })
    $layerMasks+=$runtime
}
$mask=$layerMasks[0].Window
$script:brush=$layerMasks[$config.activeLayer].Brush
function Get-AdjustedChannel([int]$channel,[int]$brightness){
    $factor=$brightness/100.0
    $result=if($factor -le 1.0){$channel*$factor}else{$channel+(255.0-$channel)*($factor-1.0)}
    return [byte][Math]::Round([Math]::Max(0.0,[Math]::Min(255.0,$result)))
}
function Get-EndpointColor([string]$prefix,[hashtable]$values=$settings){
    $alpha=[byte][Math]::Round(255.0*(1.0-$values[$prefix+'Transparency']/100.0))
    $brightness=[int]$values[$prefix+'Brightness']
    $red=Get-AdjustedChannel -channel $values[$prefix+'Red'] -brightness $brightness
    $green=Get-AdjustedChannel -channel $values[$prefix+'Green'] -brightness $brightness
    $blue=Get-AdjustedChannel -channel $values[$prefix+'Blue'] -brightness $brightness
    return [System.Windows.Media.Color]::FromArgb($alpha,$red,$green,$blue)
}

function Update-Gradient($runtime) {
    $values=$runtime.Settings
    $parts=@($values.middleEnabled,$values.middlePosition,$values.feather)
    foreach($prefix in @('center','middle','edge')) {
        foreach($channel in @('Red','Green','Blue','Transparency','Brightness')) {$parts+=$values[$prefix+$channel]}
    }
    $signature=$parts -join '|'
    if($signature -eq $runtime.Signature){return}
    $center=Get-EndpointColor -prefix 'center' -values $values
    $middle=Get-EndpointColor -prefix 'middle' -values $values
    $edge=Get-EndpointColor -prefix 'edge' -values $values
    $runtime.Brush.GradientStops=[MaskCurves]::Build($center,$middle,$edge,
        $values.middlePosition/100.0,1.0,[bool]$values.middleEnabled)
    $runtime.Signature=$signature
}

function Sync-CaptureExclusion {
    $changed=$false
    foreach($runtime in $layerMasks){
        if($runtime.Handle -eq [IntPtr]::Zero){continue}
        $wanted=[bool]$config.adaptiveEnabled
        if($runtime.CaptureExcluded -ne $wanted){
            if([MaskBrightness]::ExcludeWindow($runtime.Handle,$wanted)){
                $runtime.CaptureExcluded=$wanted;$changed=$true
            }
        }
    }
    if($changed){[void][MaskBrightness]::DwmFlush()}
}
function Read-BackgroundBrightness($runtime){
    $values=$runtime.Settings
    return [MaskBrightness]::Sample($values.x,$values.y,$script:targetDisplay.X,$script:targetDisplay.Y,
        $script:targetDisplay.Width,$script:targetDisplay.Height)
}
function Update-AdaptiveStrength([switch]$Immediate){
    if(-not $config.adaptiveEnabled){
        foreach($runtime in $layerMasks){$runtime.Strength=1.0}
        Apply-MaskVisibility
        return
    }
    if(-not $config.maskEnabled -or -not $script:targetDisplay){Apply-MaskVisibility;return}
    Sync-CaptureExclusion
    $script:adaptiveCaptureUnavailable=$false
    foreach($runtime in $layerMasks){
        if(-not $runtime.Settings.enabled){$runtime.Strength=1.0;continue}
        if(-not $runtime.CaptureExcluded){$script:adaptiveCaptureUnavailable=$true;continue}
        $brightness=Read-BackgroundBrightness $runtime
        if([double]::IsNaN($brightness)){$script:adaptiveCaptureUnavailable=$true;continue}
        $target=[Math]::Max(0.0,[Math]::Min(1.0,[double]$brightness))
        if($target -le 0.01){$target=0.0}
        elseif($target -ge 0.99){$target=1.0}
        if($Immediate -or $target -eq 0.0 -or $target -eq 1.0){$runtime.Strength=$target}
        else {
            $runtime.Strength=[double]$runtime.Strength+0.45*($target-[double]$runtime.Strength)
            if([Math]::Abs($target-[double]$runtime.Strength) -lt 0.01){$runtime.Strength=$target}
        }
        $runtime.Window.Opacity=$runtime.Strength
    }
    Apply-MaskVisibility
}

function Update-MaskZOrder {
    $targets=[System.Collections.Generic.List[System.IntPtr]]::new()
    foreach($runtime in $layerMasks){
        if($runtime.Handle -ne [IntPtr]::Zero -and $runtime.Window.IsVisible){$targets.Add($runtime.Handle)}
    }
    [MaskTopmost]::SetTargets($targets.ToArray())
}

$script:maskVisibilityBusy=$false
function Apply-MaskVisibility {
    if($script:maskVisibilityBusy){return}
    $script:maskVisibilityBusy=$true
    try{
        foreach($runtime in $layerMasks){
            $active=$config.maskEnabled -and $runtime.Settings.enabled -and $null -ne $script:targetDisplay
            $runtime.Window.Opacity=if($active){[double]$runtime.Strength}else{0.0}
            if($script:initialLoadDone){
                if($active -and -not $runtime.Window.IsVisible){$runtime.Window.Show()}
                elseif(-not $active -and $runtime.Window.IsVisible){$runtime.Window.Hide()}
            }
        }
        Update-MaskZOrder
        foreach($circle in $previewCircles){$circle.Opacity=if($config.adaptiveEnabled){[double]$circle.Tag}else{1.0}}
        if($maskSwitch){$maskSwitch.Content=T '总开关'}
        if($badgeText){
            $badgeText.Text=if(-not $script:targetDisplay){"○  "+((T '等待 {0} 连接') -f $config.targetMonitorName)}
                elseif(-not $config.maskEnabled){"○  "+((T '{0} 已连接 · 遮罩已关闭') -f $config.targetMonitorName)}
                elseif($config.adaptiveEnabled -and $script:adaptiveCaptureUnavailable){"○  "+((T '{0} · 背景采样暂不可用') -f $config.targetMonitorName)}
                elseif($config.adaptiveEnabled -and $settings.enabled){"●  "+((T '{0} · 当前层强度 {1}%') -f $config.targetMonitorName,[int][Math]::Round($layerMasks[$config.activeLayer].Strength*100.0))}
                elseif($config.adaptiveEnabled){"●  "+((T '{0} · 随背景调节') -f $config.targetMonitorName)}
                elseif($config.maskEnabled){"●  "+((T '{0} 已连接 · 自动保存') -f $config.targetMonitorName)}
                else{"○  "+((T '{0} 已连接 · 遮罩已关闭') -f $config.targetMonitorName)}
        }
    }finally{$script:maskVisibilityBusy=$false}
}
function Update-Mask {
    foreach($runtime in $layerMasks){
        $values=$runtime.Settings
        if($script:targetDisplay){
            $values.x=$script:targetDisplay.X+$values.monitorX
            $values.y=$script:targetDisplay.Y+$values.monitorY
            if($runtime.Handle -ne [IntPtr]::Zero){
                [MaskMonitor]::PlacePhysical($runtime.Handle,$values.x-$values.radiusPx,$values.y-$values.radiusPx,2*$values.radiusPx,2*$values.radiusPx)
            }
        }
        Update-Gradient $runtime
    }
    if($positionLabel){$positionLabel.Text="X $($settings.monitorX)  ·  Y $($settings.monitorY)"}
    Sync-CaptureExclusion
    Update-AdaptiveStrength -Immediate
}

$panel=[System.Windows.Window]::new()
if(Test-Path -LiteralPath $iconPath) { $panel.Icon=[System.Windows.Media.Imaging.BitmapFrame]::Create([uri]$iconPath) }
Set-Loc $panel 'Title' '亮斑遮罩'; $panel.Width=1020; $panel.Height=930
$panel.ResizeMode='CanResize'; $panel.MinWidth=900; $panel.MinHeight=650; $panel.WindowStartupLocation='Manual'; $panel.Topmost=$false
$panel.FontFamily=[System.Windows.Media.FontFamily]::new($(if($script:language -eq 'en'){'Arial'}else{'Microsoft YaHei UI'})); $panel.FontSize=12
function UI-Brush($hex) { return [System.Windows.Media.BrushConverter]::new().ConvertFromString($hex) }
$panel.Background=UI-Brush '#F3F6F8'
$theme=@'
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <Style x:Key="LanguageItemStyle" TargetType="ComboBoxItem">
    <Setter Property="Foreground" Value="#425669"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
    <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ComboBoxItem">
      <Border x:Name="ItemSurface" Background="Transparent" CornerRadius="6" Padding="12,8" Margin="0,1">
        <ContentPresenter VerticalAlignment="Center"/>
      </Border>
      <ControlTemplate.Triggers>
        <Trigger Property="IsHighlighted" Value="True"><Setter TargetName="ItemSurface" Property="Background" Value="#F3F6F8"/></Trigger>
        <Trigger Property="IsSelected" Value="True"><Setter TargetName="ItemSurface" Property="Background" Value="#E2F3EE"/><Setter Property="Foreground" Value="#15847C"/><Setter Property="FontWeight" Value="SemiBold"/></Trigger>
      </ControlTemplate.Triggers>
    </ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style x:Key="LanguageSelectorStyle" TargetType="ComboBox">
    <Setter Property="Background" Value="White"/>
    <Setter Property="Foreground" Value="#425669"/>
    <Setter Property="BorderBrush" Value="#DFE7ED"/>
    <Setter Property="BorderThickness" Value="1"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
    <Setter Property="ScrollViewer.HorizontalScrollBarVisibility" Value="Disabled"/>
    <Setter Property="ItemContainerStyle" Value="{StaticResource LanguageItemStyle}"/>
    <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ComboBox">
      <Grid>
        <Border x:Name="LanguageSurface" CornerRadius="8" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}"/>
        <ToggleButton Focusable="False" ClickMode="Press" IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">
          <ToggleButton.Template><ControlTemplate TargetType="ToggleButton"><Border Background="Transparent" CornerRadius="8"/></ControlTemplate></ToggleButton.Template>
        </ToggleButton>
        <ContentPresenter Content="{TemplateBinding SelectionBoxItem}" ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}" ContentTemplateSelector="{TemplateBinding ItemTemplateSelector}" Margin="13,0,30,0" VerticalAlignment="Center" IsHitTestVisible="False"/>
        <Path x:Name="Chevron" Data="M 0,0 L 4,4 L 8,0" Stroke="#607586" StrokeThickness="1.5" StrokeStartLineCap="Round" StrokeEndLineCap="Round" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,12,0" IsHitTestVisible="False"/>
        <Popup x:Name="PART_Popup" Placement="Bottom" IsOpen="{TemplateBinding IsDropDownOpen}" AllowsTransparency="True" Focusable="False" PopupAnimation="Fade">
          <Border Background="White" BorderBrush="#DFE7ED" BorderThickness="1" CornerRadius="8" Padding="4" Margin="0,5,0,10" MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}">
            <Border.Effect><DropShadowEffect Color="#263544" BlurRadius="12" ShadowDepth="3" Opacity="0.12"/></Border.Effect>
            <ScrollViewer MaxHeight="200" CanContentScroll="True" HorizontalScrollBarVisibility="Disabled" VerticalScrollBarVisibility="Auto"><ItemsPresenter KeyboardNavigation.DirectionalNavigation="Contained"/></ScrollViewer>
          </Border>
        </Popup>
      </Grid>
      <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="LanguageSurface" Property="Background" Value="#F5FBFA"/><Setter TargetName="LanguageSurface" Property="BorderBrush" Value="#9DCAC5"/></Trigger>
        <Trigger Property="IsKeyboardFocusWithin" Value="True"><Setter TargetName="LanguageSurface" Property="BorderBrush" Value="#15847C"/></Trigger>
        <Trigger Property="IsDropDownOpen" Value="True"><Setter TargetName="LanguageSurface" Property="BorderBrush" Value="#15847C"/><Setter TargetName="Chevron" Property="Data" Value="M 0,4 L 4,0 L 8,4"/></Trigger>
        <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger>
      </ControlTemplate.Triggers>
    </ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style x:Key="MaskSwitchStyle" TargetType="CheckBox">
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="CheckBox">
          <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
            <ContentPresenter VerticalAlignment="Center" Margin="0,0,9,0"/>
            <Grid Width="38" Height="22">
              <Border x:Name="SwitchTrack" Background="#CBD5DF" CornerRadius="11"/>
              <Ellipse x:Name="SwitchThumb" Width="16" Height="16" Fill="White" HorizontalAlignment="Left" Margin="3,0,3,0"/>
            </Grid>
          </StackPanel>
          <ControlTemplate.Triggers>
            <Trigger Property="IsChecked" Value="True">
              <Setter TargetName="SwitchTrack" Property="Background" Value="#15847C"/>
              <Setter TargetName="SwitchThumb" Property="HorizontalAlignment" Value="Right"/>
            </Trigger>
            <Trigger Property="IsMouseOver" Value="True"><Setter Property="Opacity" Value="0.8"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style x:Key="LayerTabStyle" TargetType="RadioButton">
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Foreground" Value="#607586"/>
    <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="RadioButton">
      <Border x:Name="TabSurface" CornerRadius="8" Background="Transparent" Padding="16,8">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Border>
      <ControlTemplate.Triggers>
        <Trigger Property="IsChecked" Value="True"><Setter TargetName="TabSurface" Property="Background" Value="#15847C"/><Setter Property="Foreground" Value="White"/></Trigger>
        <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="TabSurface" Property="Opacity" Value="0.8"/></Trigger>
      </ControlTemplate.Triggers>
    </ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style TargetType="Slider">
    <Setter Property="Foreground" Value="#15847C"/>
    <Setter Property="Background" Value="#E8EEF2"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Slider">
          <Grid Height="24" Margin="8,0">
            <Track x:Name="PART_Track" Minimum="{TemplateBinding Minimum}" Maximum="{TemplateBinding Maximum}" Value="{TemplateBinding Value}" IsDirectionReversed="{TemplateBinding IsDirectionReversed}" VerticalAlignment="Center">
              <Track.DecreaseRepeatButton>
                <RepeatButton Command="{x:Static Slider.DecreaseLarge}" Focusable="False">
                  <RepeatButton.Template><ControlTemplate TargetType="RepeatButton"><Border Height="4" CornerRadius="2" Background="{Binding Foreground, RelativeSource={RelativeSource AncestorType=Slider}}"/></ControlTemplate></RepeatButton.Template>
                </RepeatButton>
              </Track.DecreaseRepeatButton>
              <Track.IncreaseRepeatButton>
                <RepeatButton Command="{x:Static Slider.IncreaseLarge}" Focusable="False">
                  <RepeatButton.Template><ControlTemplate TargetType="RepeatButton"><Border Height="4" CornerRadius="2" Background="{Binding Background, RelativeSource={RelativeSource AncestorType=Slider}}"/></ControlTemplate></RepeatButton.Template>
                </RepeatButton>
              </Track.IncreaseRepeatButton>
              <Track.Thumb>
                <Thumb Width="16" Height="16">
                  <Thumb.Template>
                    <ControlTemplate TargetType="Thumb">
                      <Ellipse x:Name="Dot" Fill="White" StrokeThickness="2" Stroke="{Binding Foreground, RelativeSource={RelativeSource AncestorType=Slider}}">
                        <Ellipse.Effect><DropShadowEffect BlurRadius="4" ShadowDepth="1" Opacity="0.12"/></Ellipse.Effect>
                      </Ellipse>
                      <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Dot" Property="StrokeThickness" Value="3"/></Trigger></ControlTemplate.Triggers>
                    </ControlTemplate>
                  </Thumb.Template>
                </Thumb>
              </Track.Thumb>
            </Track>
          </Grid>
          <ControlTemplate.Triggers><Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger></ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style TargetType="Button">
    <Setter Property="Background" Value="White"/>
    <Setter Property="Foreground" Value="#425669"/>
    <Setter Property="BorderBrush" Value="#DFE7ED"/>
    <Setter Property="BorderThickness" Value="1"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="ButtonSurface" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8" Padding="{TemplateBinding Padding}">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="ButtonSurface" Property="Opacity" Value="0.8"/></Trigger>
            <Trigger Property="IsPressed" Value="True"><Setter TargetName="ButtonSurface" Property="Opacity" Value="0.6"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style TargetType="RepeatButton">
    <Setter Property="Background" Value="White"/>
    <Setter Property="Foreground" Value="#425669"/>
    <Setter Property="BorderBrush" Value="#DFE7ED"/>
    <Setter Property="BorderThickness" Value="1"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="RepeatButton">
          <Border x:Name="ButtonSurface" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8" Padding="{TemplateBinding Padding}">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="ButtonSurface" Property="Opacity" Value="0.8"/></Trigger>
            <Trigger Property="IsPressed" Value="True"><Setter TargetName="ButtonSurface" Property="Opacity" Value="0.6"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
</ResourceDictionary>
'@
$panel.Resources=[System.Windows.Markup.XamlReader]::Parse($theme)
$primaryWorkArea=[System.Windows.SystemParameters]::WorkArea
$panel.Width=[Math]::Min($panel.Width,$primaryWorkArea.Width-40.0)
$panel.Height=[Math]::Min($panel.Height,$primaryWorkArea.Height-40.0)
$panelTargetLeft=[int](($primaryWorkArea.Width-$panel.Width)/2+$primaryWorkArea.Left)
$panelTargetTop=[int](($primaryWorkArea.Height-$panel.Height)/2+$primaryWorkArea.Top)
$panel.Left=$panelTargetLeft; $panel.Top=$panelTargetTop
$scroll=[System.Windows.Controls.ScrollViewer]::new(); $scroll.VerticalScrollBarVisibility='Auto'
$root=[System.Windows.Controls.StackPanel]::new(); $root.Margin=[System.Windows.Thickness]::new(24,16,24,16)
$scroll.Content=$root; $panel.Content=$scroll
function Add-Text($parent,$text,$size=12,$color='#667C8B',$bold=$false) {
    $label=[System.Windows.Controls.TextBlock]::new(); Set-Loc $label 'Text' ([string]$text); $label.TextWrapping='Wrap'
    $label.FontSize=$size; $label.Foreground=UI-Brush $color
    if($bold){$label.FontWeight='SemiBold'}
    [void]$parent.Children.Add($label); return $label
}
function New-Surface($parent,$background='White',$padding=16) {
    $border=[System.Windows.Controls.Border]::new(); $border.Background=UI-Brush $background
    $border.CornerRadius=[System.Windows.CornerRadius]::new(14)
    $border.BorderBrush=UI-Brush '#E1E9EE'; $border.BorderThickness=[System.Windows.Thickness]::new(1)
    $border.Padding=[System.Windows.Thickness]::new($padding); [void]$parent.Children.Add($border)
    return $border
}
$header=[System.Windows.Controls.DockPanel]::new(); $header.Margin=[System.Windows.Thickness]::new(0,0,0,18)
[void]$root.Children.Add($header)
$maskSwitch=[System.Windows.Controls.CheckBox]::new()
$maskSwitch.Style=$panel.Resources['MaskSwitchStyle']; $maskSwitch.IsChecked=$config.maskEnabled
Set-Loc $maskSwitch 'Content' '总开关'
$maskSwitch.FontSize=12; $maskSwitch.FontWeight='SemiBold'; $maskSwitch.Foreground=UI-Brush '#244B55'
$maskSwitch.VerticalAlignment='Center'; $maskSwitch.Margin=[System.Windows.Thickness]::new(18,0,0,0)
Set-Loc $maskSwitch 'ToolTip' '统一开启或关闭两层遮罩。每层的参数与位置独立保存。'
[System.Windows.Controls.DockPanel]::SetDock($maskSwitch,'Right'); [void]$header.Children.Add($maskSwitch)
$languageSelector=[System.Windows.Controls.ComboBox]::new();$languageSelector.Style=$panel.Resources['LanguageSelectorStyle'];$languageSelector.Width=112;$languageSelector.Height=32;$languageSelector.Margin=[System.Windows.Thickness]::new(8,0,0,0);$languageSelector.VerticalAlignment='Center';$languageSelector.FontSize=12
[void]$languageSelector.Items.Add('简体中文');[void]$languageSelector.Items.Add('繁體中文');[void]$languageSelector.Items.Add('English')
$languageSelector.SelectedIndex=switch($script:language){'zh-TW'{1} 'en'{2} default{0}}
[System.Windows.Controls.DockPanel]::SetDock($languageSelector,'Right');[void]$header.Children.Add($languageSelector)
$monitorButton=[System.Windows.Controls.Button]::new();Set-Loc $monitorButton 'Content' '连接显示器'
$monitorButton.Padding=[System.Windows.Thickness]::new(12,7,12,7);$monitorButton.FontSize=12;$monitorButton.VerticalAlignment='Center'
$monitorButton.Margin=[System.Windows.Thickness]::new(12,0,0,0);Set-Loc $monitorButton 'ToolTip' '选择并记住两层遮罩绑定的显示器。'
[System.Windows.Controls.DockPanel]::SetDock($monitorButton,'Right');[void]$header.Children.Add($monitorButton)
$badge=[System.Windows.Controls.Border]::new(); $badge.Background=UI-Brush '#E2F3EE'; $badge.CornerRadius=[System.Windows.CornerRadius]::new(14)
$badge.Padding=[System.Windows.Thickness]::new(12,6,12,6); $badge.VerticalAlignment='Center'
$badgeText=[System.Windows.Controls.TextBlock]::new(); Set-Loc $badgeText 'Text' '实时生效 · 自动保存'; $badgeText.Foreground=UI-Brush '#237D68'; $badgeText.FontSize=11
$badge.Child=$badgeText; [System.Windows.Controls.DockPanel]::SetDock($badge,'Right'); [void]$header.Children.Add($badge)
$logo=[System.Windows.Controls.Image]::new(); $logo.Width=44; $logo.Height=44; $logo.Margin=[System.Windows.Thickness]::new(0,0,12,0)
$logoPath=Join-Path $PSScriptRoot 'mask-icon.png'
if(Test-Path -LiteralPath $logoPath){$logo.Source=[System.Windows.Media.Imaging.BitmapFrame]::Create([uri]$logoPath)}
[System.Windows.Controls.DockPanel]::SetDock($logo,'Left'); [void]$header.Children.Add($logo)
$heading=[System.Windows.Controls.StackPanel]::new(); $heading.VerticalAlignment='Center'; [void]$header.Children.Add($heading)
$null=Add-Text $heading '亮斑遮罩' 23 '#173D47' $true

$presetBar=[System.Windows.Controls.DockPanel]::new();$presetBar.Margin=[System.Windows.Thickness]::new(0,0,0,12)
[void]$root.Children.Add($presetBar)
$presetStatus=[System.Windows.Controls.TextBlock]::new();Set-Loc $presetStatus 'Text' ('档位 {0} · 自动保存' -f ($presets.activeSlot+1))
$presetStatus.Foreground=UI-Brush '#237D68';$presetStatus.FontSize=11;$presetStatus.VerticalAlignment='Center'
$presetStatus.Margin=[System.Windows.Thickness]::new(12,0,14,0)
[System.Windows.Controls.DockPanel]::SetDock($presetStatus,'Right');[void]$presetBar.Children.Add($presetStatus)
$presetSurface=[System.Windows.Controls.Border]::new();$presetSurface.Background=UI-Brush '#E5ECEF';$presetSurface.CornerRadius=[System.Windows.CornerRadius]::new(10)
$presetSurface.Padding=[System.Windows.Thickness]::new(3);$presetSurface.HorizontalAlignment='Left'
$presetRow=[System.Windows.Controls.StackPanel]::new();$presetRow.Orientation='Horizontal';$presetSurface.Child=$presetRow
[void]$presetBar.Children.Add($presetSurface)
$presetTabs=@()
for($index=0;$index -lt 3;$index++){
    $tab=[System.Windows.Controls.RadioButton]::new();$tab.Style=$panel.Resources['LayerTabStyle'];$tab.GroupName='MaskPresetSelector'
    Set-Loc $tab 'Content' ('档位 {0}' -f ($index+1));$tab.FontSize=12;$tab.FontWeight='SemiBold';$tab.Tag=[int]$index
    $tab.IsChecked=$index -eq $presets.activeSlot
    [void]$presetRow.Children.Add($tab);$presetTabs+=$tab
}

$layerBar=[System.Windows.Controls.DockPanel]::new();$layerBar.Margin=[System.Windows.Thickness]::new(0,0,0,12)
[void]$root.Children.Add($layerBar)
$adaptiveSwitch=[System.Windows.Controls.CheckBox]::new();$adaptiveSwitch.Style=$panel.Resources['MaskSwitchStyle']
$adaptiveSwitch.IsChecked=$config.adaptiveEnabled;Set-Loc $adaptiveSwitch 'Content' '随背景亮度'
$adaptiveSwitch.FontSize=12;$adaptiveSwitch.Foreground=UI-Brush '#244B55';$adaptiveSwitch.VerticalAlignment='Center'
$adaptiveSwitch.Margin=[System.Windows.Thickness]::new(18,0,0,0)
Set-Loc $adaptiveSwitch 'ToolTip' '背景越亮，遮罩越强。白色使用设定强度，黑色强度为 0。两层各自读取背景。'
[System.Windows.Controls.DockPanel]::SetDock($adaptiveSwitch,'Right');[void]$layerBar.Children.Add($adaptiveSwitch)
$layerSwitch=[System.Windows.Controls.CheckBox]::new();$layerSwitch.Style=$panel.Resources['MaskSwitchStyle']
$layerSwitch.IsChecked=$settings.enabled;Set-Loc $layerSwitch 'Content' $(if($config.activeLayer -eq 0){'启用第一层'}else{'启用第二层'})
$layerSwitch.FontSize=12;$layerSwitch.Foreground=UI-Brush '#244B55';$layerSwitch.VerticalAlignment='Center'
[System.Windows.Controls.DockPanel]::SetDock($layerSwitch,'Right');[void]$layerBar.Children.Add($layerSwitch)
$tabSurface=[System.Windows.Controls.Border]::new();$tabSurface.Background=UI-Brush '#E5ECEF';$tabSurface.CornerRadius=[System.Windows.CornerRadius]::new(10)
$tabSurface.Padding=[System.Windows.Thickness]::new(3);$tabSurface.HorizontalAlignment='Left'
$tabRow=[System.Windows.Controls.StackPanel]::new();$tabRow.Orientation='Horizontal';$tabSurface.Child=$tabRow
[void]$layerBar.Children.Add($tabSurface)
$layerTabs=@()
for($index=0;$index -lt 2;$index++){
    $tab=[System.Windows.Controls.RadioButton]::new();$tab.Style=$panel.Resources['LayerTabStyle'];$tab.GroupName='MaskLayerSelector'
    Set-Loc $tab 'Content' $(if($index -eq 0){'第一层遮罩'}else{'第二层遮罩'});$tab.FontSize=12;$tab.FontWeight='SemiBold';$tab.Tag=[int]$index
    $tab.IsChecked=$index -eq $config.activeLayer
    [void]$tabRow.Children.Add($tab);$layerTabs+=$tab
}

$previewSurface=New-Surface $root '#EAF4F3' 12; $previewSurface.Margin=[System.Windows.Thickness]::new(0,0,0,14)
$previewGrid=[System.Windows.Controls.Grid]::new(); $previewSurface.Child=$previewGrid
$introColumn=[System.Windows.Controls.ColumnDefinition]::new(); $introColumn.Width=[System.Windows.GridLength]::new(170)
[void]$previewGrid.ColumnDefinitions.Add($introColumn)
foreach($unused in 1..3){[void]$previewGrid.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]::new())}
$previewIntro=[System.Windows.Controls.StackPanel]::new(); $previewIntro.VerticalAlignment='Center'; $previewIntro.Margin=[System.Windows.Thickness]::new(6,0,16,0)
[void]$previewGrid.Children.Add($previewIntro)
$previewTitle=Add-Text $previewIntro $(if($config.activeLayer -eq 0){'第一层预览'}else{'第二层预览'}) 16 '#254F54' $true
$previewCircles=@()
$previewIndex=1
foreach($preview in @(@{Bg='#FFFFFF';Text='白色背景';Fg='#7E909F'},@{Bg='#E4E9EE';Text='浅灰背景';Fg='#72838F'},@{Bg='#263544';Text='深色背景';Fg='#A8BAC8'})) {
    $tile=[System.Windows.Controls.Border]::new(); $tile.Background=UI-Brush $preview.Bg; $tile.CornerRadius=[System.Windows.CornerRadius]::new(10)
    $tile.Margin=[System.Windows.Thickness]::new(5,0,5,0); $tile.Height=88
    [System.Windows.Controls.Grid]::SetColumn($tile,$previewIndex); [void]$previewGrid.Children.Add($tile)
    $tileGrid=[System.Windows.Controls.Grid]::new(); $tile.Child=$tileGrid
    $previewCircle=[System.Windows.Shapes.Ellipse]::new(); $previewCircle.Width=62; $previewCircle.Height=62
    $previewColor=[System.Windows.Media.ColorConverter]::ConvertFromString($preview.Bg)
    $previewCircle.Tag=([double]$previewColor.R*0.2126+[double]$previewColor.G*0.7152+[double]$previewColor.B*0.0722)/255.0
    $previewCircle.Fill=$brush; $previewCircle.VerticalAlignment='Top'; $previewCircle.Margin=[System.Windows.Thickness]::new(0,3,0,0)
    [void]$tileGrid.Children.Add($previewCircle);$previewCircles+=$previewCircle
    $tileLabel=[System.Windows.Controls.TextBlock]::new(); Set-Loc $tileLabel 'Text' $preview.Text; $tileLabel.FontSize=10
    $tileLabel.Foreground=UI-Brush $preview.Fg; $tileLabel.HorizontalAlignment='Center'; $tileLabel.VerticalAlignment='Bottom'; $tileLabel.Margin=[System.Windows.Thickness]::new(0,0,0,8)
    [void]$tileGrid.Children.Add($tileLabel); $previewIndex++
}

$modulesGrid=[System.Windows.Controls.Grid]::new(); $modulesGrid.Margin=[System.Windows.Thickness]::new(0,0,0,14)
foreach($unused in 1..3){[void]$modulesGrid.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]::new())}
[void]$root.Children.Add($modulesGrid)
function New-SliderRow($parent,$caption,$minimum,$maximum,$step,$value) {
    $row=[System.Windows.Controls.StackPanel]::new(); $row.Margin=[System.Windows.Thickness]::new(0,0,0,4); [void]$parent.Children.Add($row)
    $rowHeader=[System.Windows.Controls.DockPanel]::new(); [void]$row.Children.Add($rowHeader)
    $label=[System.Windows.Controls.TextBlock]::new(); $label.FontSize=11; $label.FontWeight='SemiBold'; $label.Foreground=UI-Brush '#26786F'
    [System.Windows.Controls.DockPanel]::SetDock($label,'Right'); [void]$rowHeader.Children.Add($label)
    $captionLabel=[System.Windows.Controls.TextBlock]::new(); Set-Loc $captionLabel 'Text' ([string]$caption); $captionLabel.FontSize=11; $captionLabel.Foreground=UI-Brush '#536A7A'
    [void]$rowHeader.Children.Add($captionLabel)
    $slider=[System.Windows.Controls.Slider]::new(); $slider.Minimum=$minimum; $slider.Maximum=$maximum; $slider.TickFrequency=$step
    $slider.IsSnapToTickEnabled=$true; $slider.AutoToolTipPlacement='TopLeft'; $slider.Value=$value; $slider.Height=25; $slider.Margin=[System.Windows.Thickness]::new(-8,3,-8,0)
    $slider.Foreground=UI-Brush $(switch($caption){'红色'{'#D27977'} '绿色'{'#56A384'} '蓝色'{'#6B96C3'} '亮度'{'#8193A4'} default{'#15847C'}})
    [void]$row.Children.Add($slider)
    return @{Slider=$slider;Label=$label;Caption=$captionLabel}
}
$modules=@{}
foreach($prefix in @('center','middle','edge')) {
    $column=switch($prefix){'center'{0} 'middle'{1} 'edge'{2}}
    $card=New-Surface $modulesGrid 'White' 17
    $card.Margin=[System.Windows.Thickness]::new(0,0,$(if($prefix -eq 'edge'){0}else{12}),0)
    [System.Windows.Controls.Grid]::SetColumn($card,$column)
    $content=[System.Windows.Controls.StackPanel]::new(); $card.Child=$content
    $cardHeader=[System.Windows.Controls.DockPanel]::new(); $cardHeader.Margin=[System.Windows.Thickness]::new(0,0,0,12); [void]$content.Children.Add($cardHeader)
    $swatch=[System.Windows.Controls.Border]::new(); $swatch.Width=34; $swatch.Height=34; $swatch.CornerRadius=[System.Windows.CornerRadius]::new(10)
    $swatch.Margin=[System.Windows.Thickness]::new(0,0,11,0); [System.Windows.Controls.DockPanel]::SetDock($swatch,'Left'); [void]$cardHeader.Children.Add($swatch)
    $cardHeading=[System.Windows.Controls.StackPanel]::new(); [void]$cardHeader.Children.Add($cardHeading)
    $title=switch($prefix){'center'{'01  中心'} 'middle'{'02  中间点'} 'edge'{'03  边缘'}}
    $null=Add-Text $cardHeading $title 14 '#244B55' $true
    $colorCode=Add-Text $cardHeading '' 10 '#8C9CAA'
    $fields=[System.Windows.Controls.StackPanel]::new(); [void]$content.Children.Add($fields)
    $module=@{Swatch=$swatch;Code=$colorCode;Fields=$fields}
    if($prefix -eq 'middle') {
        $middleCheck=[System.Windows.Controls.CheckBox]::new(); Set-Loc $middleCheck 'Content' '启用'
        $middleCheck.IsChecked=$settings.middleEnabled; $middleCheck.Foreground=UI-Brush '#15847C'
        $middleCheck.VerticalAlignment='Center'; $middleCheck.Margin=[System.Windows.Thickness]::new(4,0,0,0)
        [System.Windows.Controls.DockPanel]::SetDock($middleCheck,'Right')
        $cardHeader.Children.Insert(0,$middleCheck)
        $module.CheckBox=$middleCheck
        $fields.IsEnabled=$settings.middleEnabled
        $fields.Opacity=if($settings.middleEnabled){1.0}else{0.4}
    }
    $module.Transparency=New-SliderRow $fields '透明度' 0 100 1 $settings[$prefix+'Transparency']
    $module.Brightness=New-SliderRow $fields '亮度' 0 200 1 $settings[$prefix+'Brightness']
    Set-Loc $module.Brightness.Slider 'ToolTip' '只调这个渐变点：0% 为黑色、100% 为原色、200% 为白色；透明度独立。'
    foreach($channel in @('Red','Green','Blue')) {
        $caption=switch($channel){'Red'{'红色'} 'Green'{'绿色'} 'Blue'{'蓝色'}}
        $module[$channel]=New-SliderRow $fields $caption 0 255 1 $settings[$prefix+$channel]
    }
    if($prefix -eq 'middle') {
        $module.Position=New-SliderRow $fields '位置 · 半径百分比' 1 99 1 $settings.middlePosition
    } else {
        $pointNote=Add-Text $content $(if($prefix -eq 'center'){'渐变起点 · 半径 0%'}else{'渐变终点 · 半径 100%'}) 10 '#9BAAB5'
        $pointNote.Margin=[System.Windows.Thickness]::new(0,13,0,0)
    }
    $modules[$prefix]=$module
}

$geometry=New-Surface $root 'White' 16; $geometry.Margin=[System.Windows.Thickness]::new(0,0,0,15)
$geometryContent=[System.Windows.Controls.StackPanel]::new(); $geometry.Child=$geometryContent
$geometryTitle=Add-Text $geometryContent '圆圈大小' 13 '#244B55' $true; $geometryTitle.Margin=[System.Windows.Thickness]::new(0,0,0,10)
$geometryGrid=[System.Windows.Controls.Grid]::new(); [void]$geometryContent.Children.Add($geometryGrid)
[void]$geometryGrid.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]::new())
$diameterContent=[System.Windows.Controls.StackPanel]::new(); $diameterContent.Margin=[System.Windows.Thickness]::new(0); [void]$geometryGrid.Children.Add($diameterContent)
$diameterRow=New-SliderRow $diameterContent '圆圈直径' 30 300 2 (2*$settings.radiusPx)

$footer=[System.Windows.Controls.DockPanel]::new(); $footer.LastChildFill=$true; [void]$root.Children.Add($footer)
$actionButtons=[System.Windows.Controls.StackPanel]::new(); $actionButtons.Orientation='Horizontal'; $actionButtons.VerticalAlignment='Center'
[System.Windows.Controls.DockPanel]::SetDock($actionButtons,'Right'); [void]$footer.Children.Add($actionButtons)
$positionArea=[System.Windows.Controls.StackPanel]::new(); $positionArea.Orientation='Horizontal'; $positionArea.VerticalAlignment='Center'; [void]$footer.Children.Add($positionArea)
$positionInfo=[System.Windows.Controls.StackPanel]::new(); $positionInfo.Margin=[System.Windows.Thickness]::new(0,0,15,0); [void]$positionArea.Children.Add($positionInfo)
$null=Add-Text $positionInfo '屏幕位置' 11 '#536A7A'
$positionLabel=Add-Text $positionInfo '' 10 '#92A1AE'
$positionButtons=[System.Windows.Controls.StackPanel]::new(); $positionButtons.Orientation='Horizontal'; $positionButtons.VerticalAlignment='Center'; [void]$positionArea.Children.Add($positionButtons)
function New-Button($parent,$text,$action,$primary=$false) {
    $button=[System.Windows.Controls.Button]::new(); Set-Loc $button 'Content' ([string]$text); $button.FontSize=12
    $button.Padding=[System.Windows.Thickness]::new(13,9,13,9); $button.Margin=[System.Windows.Thickness]::new(0,0,7,0)
    if($primary){$button.Background=UI-Brush '#15847C'; $button.Foreground=[System.Windows.Media.Brushes]::White; $button.BorderBrush=UI-Brush '#15847C'; $button.FontWeight='SemiBold'}
    if($text.Length -eq 1){$button.Padding=[System.Windows.Thickness]::new(0);$button.Width=32;$button.Height=32}
    $button.Add_Click($action); [void]$parent.Children.Add($button)
}

$saveTimer=[System.Windows.Threading.DispatcherTimer]::new()
$saveTimer.Interval=[TimeSpan]::FromMilliseconds(350)
$saveTimer.Add_Tick({ $saveTimer.Stop(); Save-Settings })
function Schedule-Save { $saveTimer.Stop(); $saveTimer.Start() }
function Update-Labels {
    foreach($prefix in @('center','middle','edge')) {
        $module=$modules[$prefix]
        $module.Transparency.Label.Text="$($settings[$prefix+'Transparency'])%"
        $module.Brightness.Label.Text="$($settings[$prefix+'Brightness'])%"
        $module.Red.Label.Text="$($settings[$prefix+'Red'])"
        $module.Green.Label.Text="$($settings[$prefix+'Green'])"
        $module.Blue.Label.Text="$($settings[$prefix+'Blue'])"
        $module.Code.Text=(''+(T '原色')+' #{0:X2}{1:X2}{2:X2}' -f [int]$settings[$prefix+'Red'],[int]$settings[$prefix+'Green'],[int]$settings[$prefix+'Blue'])
        $effective=Get-EndpointColor -prefix $prefix -values $settings
        $module.Swatch.Background=[System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.Color]::FromRgb($effective.R,$effective.G,$effective.B))
        $module.Swatch.ToolTip=((T '实际颜色 #{0:X2}{1:X2}{2:X2}（已应用该点亮度）') -f $effective.R,$effective.G,$effective.B)
    }
    $diameterRow.Label.Text="$(2*$settings.radiusPx) px"
    $modules.middle.Position.Label.Text="$($settings.middlePosition)%"
}
$script:syncing=$false; $script:controlsReady=$false
function Apply-Controls($source) {
    if (-not $script:controlsReady -or $script:syncing) { return }
    foreach ($prefix in @('center','middle','edge')) {
        $module=$modules[$prefix]
        foreach ($channel in @('Red','Green','Blue')) { $settings[$prefix+$channel]=[int]$module[$channel].Slider.Value }
        $settings[$prefix+'Transparency']=[int]$module.Transparency.Slider.Value
        $settings[$prefix+'Brightness']=[int]$module.Brightness.Slider.Value
    }
    $settings.radiusPx=[int]($diameterRow.Slider.Value/2.0)
    $settings.middlePosition=[int]$modules.middle.Position.Slider.Value
    Update-Mask; Update-Labels; Schedule-Save
}
foreach ($prefix in @('center','middle','edge')) {
    foreach ($name in @('Transparency','Brightness','Red','Green','Blue')) {
        $modules[$prefix][$name].Slider.Add_ValueChanged({ param($sender,$e) Apply-Controls $sender })
    }
}
foreach ($row in @($diameterRow,$modules.middle.Position)) {
    $row.Slider.Add_ValueChanged({ param($sender,$e) Apply-Controls $sender })
}
$panel.Add_ContentRendered({ $script:controlsReady=$true })
function Apply-MiddleToggle {
    if(-not $script:controlsReady -or $script:syncing){return}
    $settings.middleEnabled=[bool]$modules.middle.CheckBox.IsChecked
    $modules.middle.Fields.IsEnabled=$settings.middleEnabled
    $modules.middle.Fields.Opacity=if($settings.middleEnabled){1.0}else{0.4}
    Update-Mask; Schedule-Save
}
$modules.middle.CheckBox.Add_Checked({Apply-MiddleToggle})
$modules.middle.CheckBox.Add_Unchecked({Apply-MiddleToggle})
function Apply-MaskToggle {
    if(-not $script:controlsReady -or $script:syncing){return}
    $config.maskEnabled=[bool]$maskSwitch.IsChecked
    Apply-MaskVisibility;Update-AdaptiveStrength -Immediate;Schedule-Save
}
$maskSwitch.Add_Checked({Apply-MaskToggle})
$maskSwitch.Add_Unchecked({Apply-MaskToggle})
function Set-UiLanguage([string]$language){
    if($language -notin @('zh-CN','zh-TW','en')){throw 'Unsupported UI language.'}
    $script:language=$language
    Save-Language
    Update-LocalizedProperties
    if($maskSwitch){$maskSwitch.Content=T '总开关'}
    if($adaptiveSwitch){$adaptiveSwitch.Content=T '随背景亮度'}
    if($layerSwitch){Set-Loc $layerSwitch 'Content' $(if($config.activeLayer -eq 0){'启用第一层'}else{'启用第二层'})}
    if($presetStatus){$presetStatus.Text=T ('档位 {0} · 自动保存' -f ($presets.activeSlot+1))}
    if($previewTitle){$previewTitle.Text=T $(if($config.activeLayer -eq 0){'第一层预览'}else{'第二层预览'})}
    if($script:controlsReady){Update-Labels}
    if($languageSelector){$languageSelector.SelectedIndex=switch($language){'zh-TW'{1} 'en'{2} default{0}}}
    Apply-MaskVisibility
}
$languageSelector.Add_SelectionChanged({if($languageSelector.SelectedIndex -ge 0){$code=@('zh-CN','zh-TW','en')[$languageSelector.SelectedIndex];if($code -ne $script:language){Set-UiLanguage $code}}})
function Apply-AdaptiveToggle {
    if(-not $script:controlsReady -or $script:syncing){return}
    $config.adaptiveEnabled=[bool]$adaptiveSwitch.IsChecked
    Sync-CaptureExclusion;Update-AdaptiveStrength -Immediate;Schedule-Save
}
$adaptiveSwitch.Add_Checked({Apply-AdaptiveToggle});$adaptiveSwitch.Add_Unchecked({Apply-AdaptiveToggle})
function Bind-CurrentLayer {
    $script:syncing=$true
    try{
        $script:settings=$config.layers[$config.activeLayer]
        $script:brush=$layerMasks[$config.activeLayer].Brush
        foreach($prefix in @('center','middle','edge')){
            $module=$modules[$prefix]
            foreach($channel in @('Red','Green','Blue')){$module[$channel].Slider.Value=$settings[$prefix+$channel]}
            $module.Transparency.Slider.Value=$settings[$prefix+'Transparency']
            $module.Brightness.Slider.Value=$settings[$prefix+'Brightness']
        }
        $modules.middle.CheckBox.IsChecked=$settings.middleEnabled
        $modules.middle.Fields.IsEnabled=$settings.middleEnabled
        $modules.middle.Fields.Opacity=if($settings.middleEnabled){1.0}else{0.4}
        $modules.middle.Position.Slider.Value=$settings.middlePosition
        $diameterRow.Slider.Value=2*$settings.radiusPx
        $layerSwitch.IsChecked=$settings.enabled
        Set-Loc $layerSwitch 'Content' $(if($config.activeLayer -eq 0){'启用第一层'}else{'启用第二层'})
        Set-Loc $previewTitle 'Text' $(if($config.activeLayer -eq 0){'第一层预览'}else{'第二层预览'})
        foreach($circle in $previewCircles){$circle.Fill=$brush}
    }finally{$script:syncing=$false}
    Update-Mask;Update-Labels
}
function Switch-Layer([int]$index){
    if($script:syncing){return}
    if($index -lt 0 -or $index -gt 1){return}
    $config.activeLayer=$index
    Bind-CurrentLayer;Schedule-Save
}
function Apply-LayerToggle {
    if(-not $script:controlsReady -or $script:syncing){return}
    $settings.enabled=[bool]$layerSwitch.IsChecked
    Apply-MaskVisibility;Update-AdaptiveStrength -Immediate;Schedule-Save
}
$layerSwitch.Add_Checked({Apply-LayerToggle});$layerSwitch.Add_Unchecked({Apply-LayerToggle})
foreach($tab in $layerTabs){$tab.Add_Checked({param($sender,$e) Switch-Layer -index ([int]$sender.Tag)})}

$script:presetBusy=$false
function Sync-ProfileControls {
    $script:syncing=$true
    try{
        $maskSwitch.IsChecked=$config.maskEnabled;$adaptiveSwitch.IsChecked=$config.adaptiveEnabled
        for($index=0;$index -lt 2;$index++){
            $layerMasks[$index].Settings=$config.layers[$index]
            $layerMasks[$index].Signature=''
            $layerMasks[$index].Strength=1.0
            $layerTabs[$index].IsChecked=$index -eq $config.activeLayer
        }
    }finally{$script:syncing=$false}
    $script:targetDisplay=[MaskMonitor]::FindBound($config.targetHardwareId,$config.targetInstanceKey)
    Bind-CurrentLayer
}
function Switch-Preset([int]$index){
    if($script:presetBusy -or $index -lt 0 -or $index -gt 2 -or $index -eq $presets.activeSlot){return}
    $script:presetBusy=$true
    $oldConfig=$config;$oldIndex=$presets.activeSlot
    try{
        $next=Copy-NormalizedProfile $presets.slots[$index]
        Save-Settings
        if(-not $script:lastSaveSucceeded){throw (T '当前档位未能保存，已取消切换。')}
        $presets.activeSlot=$index
        $script:config=$next
        Sync-ProfileControls
        Save-Settings
    }catch{
        $presets.activeSlot=$oldIndex;$script:config=$oldConfig
        Sync-ProfileControls
        $presetTabs[$oldIndex].IsChecked=$true
        Set-Loc $presetStatus 'Text' '切换失败，已保留原设置';$presetStatus.Foreground=UI-Brush '#C25A54'
    }finally{$script:presetBusy=$false}
}
foreach($tab in $presetTabs){$tab.Add_Checked({param($sender,$e) Switch-Preset -index ([int]$sender.Tag)})}

function Set-DisplayBinding($choice){
    $selected=[MaskMonitor]::FindBound($choice.HardwareId,$choice.InstanceKey)
    if(-not $selected){throw (T '这台显示器已断开，请刷新列表后重试。')}
    Save-Settings
    if(-not $script:lastSaveSucceeded){throw (T '当前档位保存失败，显示器绑定未更改。')}
    $oldDisplay=[MaskMonitor]::FindBound($monitorBinding.hardwareId,$monitorBinding.instanceKey)
    $oldKey=Get-BindingKey $monitorBinding.hardwareId $monitorBinding.instanceKey
    $monitorBinding.positions[$oldKey]=Capture-MonitorPositions $oldDisplay
    $newKey=Get-BindingKey $selected.HardwareId $selected.InstanceKey
    $pack=$monitorBinding.positions[$newKey]
    if($oldDisplay -and $oldDisplay.DeviceName -eq $selected.DeviceName){$pack=$monitorBinding.positions[$oldKey]}
    if(-not $pack -and $monitorBinding.positions.ContainsKey($selected.HardwareId)){$pack=$monitorBinding.positions[$selected.HardwareId]}
    Restore-MonitorPositions $pack $selected
    $monitorBinding.hardwareId=$selected.HardwareId;$monitorBinding.instanceKey=$selected.InstanceKey;$monitorBinding.monitorName=$selected.Model
    Apply-BindingFields
    $monitorBinding.positions[$newKey]=Capture-MonitorPositions $selected
    Write-JsonAtomic -path $bindingPath -value $monitorBinding
    Sync-ProfileControls
    Save-Settings
}
function Show-MonitorPicker {
    $dialog=[System.Windows.Window]::new();Set-Loc $dialog 'Title' '选择绑定的显示器';$dialog.Width=640;$dialog.Height=390
    $dialog.Owner=$panel;$dialog.WindowStartupLocation='CenterOwner';$dialog.ResizeMode='NoResize';$dialog.Topmost=$false
    $dialog.FontFamily=$panel.FontFamily;$dialog.FontSize=13;$dialog.Background=UI-Brush '#F3F6F8';$dialog.Resources=$panel.Resources
    $content=[System.Windows.Controls.StackPanel]::new();$content.Margin=[System.Windows.Thickness]::new(20);$dialog.Content=$content
    $current=Add-Text $content ((T '当前绑定：{0}') -f $config.targetMonitorName) 16 '#244B55' $true
    $current.Margin=[System.Windows.Thickness]::new(0,0,0,12)
    $list=[System.Windows.Controls.ListBox]::new();$list.Height=190;$list.DisplayMemberPath='Label';$list.Padding=[System.Windows.Thickness]::new(10)
    $list.Background=[System.Windows.Media.Brushes]::White;$list.BorderBrush=UI-Brush '#DFE7ED';$list.Foreground=UI-Brush '#244B55'
    [void]$content.Children.Add($list)
    $message=Add-Text $content '绑定由三个档位共享；不同显示器的位置分别记忆。' 11 '#728391'
    $message.Margin=[System.Windows.Thickness]::new(0,10,0,12)
    $buttons=[System.Windows.Controls.StackPanel]::new();$buttons.Orientation='Horizontal';$buttons.HorizontalAlignment='Right';[void]$content.Children.Add($buttons)
    $picker=@{List=$list;Message=$message;Dialog=$dialog}
    function Refresh-Picker($picker){
        $picker.List.Items.Clear()
        $bound=[MaskMonitor]::FindBound($config.targetHardwareId,$config.targetInstanceKey)
        foreach($display in [MaskMonitor]::ActiveDisplays()){
            $number=$display.DeviceName -replace '.*DISPLAY',''
            $label=(T '显示器 {0}  ·  {1}  ·  {2} × {3}') -f $number,$display.Model,$display.Width,$display.Height
            if($display.IsPrimary){$label+=('  ·  '+(T '主显示器'))}
            $item=[pscustomobject]@{Label=$label;Display=$display};[void]$picker.List.Items.Add($item)
            if($bound -and $display.InstanceKey -eq $bound.InstanceKey){$picker.List.SelectedItem=$item}
        }
        if(-not $picker.List.SelectedItem -and $picker.List.Items.Count -gt 0){$picker.List.SelectedIndex=0}
        if($picker.List.Items.Count -eq 0){$picker.Message.Text=T '没有检测到可用显示器，请连接后刷新。'}
        else{$picker.Message.Text=T '绑定由三个档位共享；不同显示器的位置分别记忆。';$picker.Message.Foreground=UI-Brush '#728391'}
    }
    $refresh=[System.Windows.Controls.Button]::new();Set-Loc $refresh 'Content' '刷新';$refresh.Padding=[System.Windows.Thickness]::new(14,8,14,8);$refresh.Margin=[System.Windows.Thickness]::new(0,0,8,0);$refresh.Tag=$picker
    $refresh.Add_Click({param($sender,$e) Refresh-Picker $sender.Tag});[void]$buttons.Children.Add($refresh)
    $cancel=[System.Windows.Controls.Button]::new();Set-Loc $cancel 'Content' '取消';$cancel.Padding=[System.Windows.Thickness]::new(14,8,14,8);$cancel.Margin=[System.Windows.Thickness]::new(0,0,8,0);$cancel.Tag=$picker
    $cancel.Add_Click({param($sender,$e) $sender.Tag.Dialog.DialogResult=$false});[void]$buttons.Children.Add($cancel)
    $confirm=[System.Windows.Controls.Button]::new();Set-Loc $confirm 'Content' '绑定所选显示器';$confirm.Padding=[System.Windows.Thickness]::new(14,8,14,8);$confirm.Background=UI-Brush '#15847C';$confirm.Foreground=[System.Windows.Media.Brushes]::White;$confirm.Tag=$picker
    $confirm.Add_Click({param($sender,$e)
        $picker=$sender.Tag
        if(-not $picker.List.SelectedItem){$picker.Message.Text=T '请先选择一台显示器。';return}
        try{Set-DisplayBinding $picker.List.SelectedItem.Display;$picker.Dialog.DialogResult=$true}
        catch{$picker.Message.Text=$_.Exception.Message;$picker.Message.Foreground=UI-Brush '#C25A54'}
    });[void]$buttons.Children.Add($confirm)
    Refresh-Picker $picker
    [void]$dialog.ShowDialog()
}
$monitorButton.Add_Click({Show-MonitorPicker})

function Nudge([int]$dx,[int]$dy) {
    $settings.monitorX=[int]$settings.monitorX+$dx
    $settings.monitorY=[int]$settings.monitorY+$dy
    if($script:targetDisplay) {
        $settings.monitorX=[Math]::Max(0,[Math]::Min($script:targetDisplay.Width-1,$settings.monitorX))
        $settings.monitorY=[Math]::Max(0,[Math]::Min($script:targetDisplay.Height-1,$settings.monitorY))
    }
    Update-Mask; Schedule-Save
}
function Get-MoveProfile([double]$seconds) {
    return @{Step=[int][Math]::Min(25.0,5.0+[Math]::Floor([Math]::Max(0.0,$seconds-0.6)*3.0));
        Interval=[int][Math]::Max(35.0,120.0-$seconds*16.0)}
}
function New-MoveButton([string]$text,[int]$dx,[int]$dy) {
    $button=[System.Windows.Controls.Primitives.RepeatButton]::new()
    $button.Content=$text; $button.Width=32; $button.Height=32; $button.Margin=[System.Windows.Thickness]::new(0,0,7,0)
    $button.Delay=350; $button.Interval=120; Set-Loc $button 'ToolTip' '单击移动 5 像素；长按连续移动并逐渐加速'
    $button.Tag=@{Dx=$dx;Dy=$dy;Watch=[System.Diagnostics.Stopwatch]::new()}
    $button.Add_PreviewMouseLeftButtonDown({param($sender,$e) $sender.Tag.Watch.Restart(); $sender.Interval=120})
    $button.Add_Click({
        param($sender,$e)
        $profile=Get-MoveProfile $sender.Tag.Watch.Elapsed.TotalSeconds
        $moveX=[int]$sender.Tag.Dx*[int]$profile.Step
        $moveY=[int]$sender.Tag.Dy*[int]$profile.Step
        Nudge -dx $moveX -dy $moveY
        $sender.Interval=$profile.Interval
    })
    $button.Add_PreviewMouseLeftButtonUp({param($sender,$e) $sender.Tag.Watch.Reset(); $sender.Interval=120; Save-Settings})
    $button.Add_LostMouseCapture({param($sender,$e) $sender.Tag.Watch.Reset(); $sender.Interval=120; Save-Settings})
    [void]$positionButtons.Children.Add($button)
}
New-MoveButton '←' -1 0
New-MoveButton '→' 1 0
New-MoveButton '↑' 0 -1
New-MoveButton '↓' 0 1
New-Button $actionButtons '收起到托盘' { $panel.Hide(); Save-Settings } $true
$script:exiting=$false
New-Button $actionButtons '退出' { $script:exiting=$true; $mask.Close() }
$panel.Add_Closing({ param($sender,$e) if(-not $script:exiting){$e.Cancel=$true; $panel.Hide(); Save-Settings} })

$menu=[System.Windows.Forms.ContextMenuStrip]::new()
$openItem=[System.Windows.Forms.ToolStripMenuItem]::new();Set-Loc $openItem 'Text' '打开调节窗口';[void]$menu.Items.Add($openItem); $openItem.Add_Click({ $panel.Show(); [void]$panel.Activate() })
$exitItem=[System.Windows.Forms.ToolStripMenuItem]::new();Set-Loc $exitItem 'Text' '退出遮罩';[void]$menu.Items.Add($exitItem); $exitItem.Add_Click({ $script:exiting=$true; $mask.Close() })
$trayMenu=$menu
$tray=[System.Windows.Forms.NotifyIcon]::new()
$customIcon=$null
if(Test-Path -LiteralPath $iconPath) {
    $customIcon=[System.Drawing.Icon]::new($iconPath)
    $tray.Icon=$customIcon
} else { $tray.Icon=[System.Drawing.SystemIcons]::Application }
Set-Loc $tray 'Text' '亮斑遮罩 - 双击打开调节窗口'; $tray.ContextMenuStrip=$menu; $tray.Visible=$true
$tray.Add_DoubleClick({ $panel.Show(); [void]$panel.Activate() })
$tray.Text=([string](T '亮斑遮罩 - 双击打开调节窗口'));if($tray.Text.Length -gt 63){$tray.Text=$tray.Text.Substring(0,63)}
Update-LocalizedProperties
$uiSignalTimer=[System.Windows.Threading.DispatcherTimer]::new()
$uiSignalTimer.Interval=[TimeSpan]::FromMilliseconds(250)
$uiSignalTimer.Add_Tick({
    if($showEvent.WaitOne(0)) { $panel.Show(); [void]$panel.Activate() }
})
$script:initialLoadDone=$false
$mask.Add_Loaded({
    if(-not $script:initialLoadDone) {
        $script:initialLoadDone=$true
        if(-not $AutoStart) {
            $panel.Show(); [void]$panel.Activate()
            $hWnd=([System.Windows.Interop.WindowInteropHelper]::new($panel)).Handle
            [void][MaskWindowStyles]::SetWindowPos($hWnd,[IntPtr](-2),$panelTargetLeft,$panelTargetTop,0,0,0x0041)
        }
    }
    Apply-MaskVisibility
})
function Refresh-TargetDisplay {
    $script:targetDisplay=[MaskMonitor]::FindBound($config.targetHardwareId,$config.targetInstanceKey)
    Update-Mask
}
$displayTimer=[System.Windows.Threading.DispatcherTimer]::new()
$displayTimer.Interval=[TimeSpan]::FromSeconds(2)
$displayTimer.Add_Tick({Refresh-TargetDisplay})
$adaptiveTimer=[System.Windows.Threading.DispatcherTimer]::new()
$adaptiveTimer.Interval=[TimeSpan]::FromMilliseconds(120)
$adaptiveTimer.Add_Tick({if($config.adaptiveEnabled){Update-AdaptiveStrength}})
$topmostTimer=[System.Windows.Threading.DispatcherTimer]::new()
$topmostTimer.Interval=[TimeSpan]::FromMilliseconds(100)
$topmostTimer.Add_Tick({[MaskTopmost]::Raise()})
try {
    Initialize-ConnectionAutoStart
    Update-Mask; Update-Labels; Save-Settings
    [MaskTopmost]::Start()
    $uiSignalTimer.Start();$displayTimer.Start();$adaptiveTimer.Start();$topmostTimer.Start()
    $mask.Add_ContentRendered({Refresh-TargetDisplay})
    $app=[System.Windows.Application]::new(); $app.ShutdownMode='OnMainWindowClose'
    [void]$app.Run($mask)
} finally {
    $saveTimer.Stop();$uiSignalTimer.Stop();$displayTimer.Stop();$adaptiveTimer.Stop();$topmostTimer.Stop();[MaskTopmost]::Dispose();Save-Settings
    [MaskBrightness]::Dispose()
    $tray.Visible=$false; $tray.Dispose(); $menu.Dispose()
    if($customIcon){$customIcon.Dispose()}
    $showEvent.Dispose()
    $mutex.ReleaseMutex(); $mutex.Dispose()
}

