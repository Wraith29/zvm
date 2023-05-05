zig build;
if ($LASTEXITCODE -ne 0) {
    Write-Output "error: zvm build failed";
} else {
    Write-Output "info: zvm Built Successfully"
    .\zig-out\bin\zvm.exe @args
}