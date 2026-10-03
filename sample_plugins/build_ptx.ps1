# 遍历 sample_plugins 目录下的所有插件目录并打包为 .ptx (zip)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$plugins = Get-ChildItem -Path $scriptDir -Directory

foreach ($plugin in $plugins) {
    $pluginDir = $plugin.FullName
    $manifestPath = Join-Path $pluginDir "plugin.json"
    
    if (Test-Path $manifestPath) {
        $ptxName = "$($plugin.Name).ptx"
        $outPtx = Join-Path $scriptDir $ptxName
        if (Test-Path $outPtx) { Remove-Item -Force $outPtx }

        Write-Host "Packaging $($plugin.Name) -> $ptxName ..."
        
        # 将目录内容压缩为 zip，改名为 .ptx
        $tempZip = Join-Path $scriptDir "$($plugin.Name).zip"
        if (Test-Path $tempZip) { Remove-Item -Force $tempZip }
        Compress-Archive -Path "$pluginDir\*" -DestinationPath $tempZip
        Move-Item -Force $tempZip $outPtx
        Write-Host "Success: $outPtx" -ForegroundColor Green
    }
}
