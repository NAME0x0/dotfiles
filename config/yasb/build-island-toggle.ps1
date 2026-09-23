# Compiles island_toggle.cs into island_toggle.exe next to it.
# A Windows (not console) application, so a click never flashes a console window.
$src = Join-Path $PSScriptRoot 'island_toggle.cs'
$exe = Join-Path $PSScriptRoot 'island_toggle.exe'

if (Test-Path $exe) { Remove-Item $exe -Force }
# -Encoding UTF8: Windows PowerShell otherwise reads a BOM-less source as ANSI and
# compiles any non-ASCII literal into mojibake.
Add-Type -TypeDefinition (Get-Content $src -Raw -Encoding UTF8) -OutputAssembly $exe -OutputType WindowsApplication
if (Test-Path $exe) { "built $exe ({0} KB)" -f [math]::Round((Get-Item $exe).Length / 1KB, 1) }
else { throw "island_toggle.exe was not produced" }
