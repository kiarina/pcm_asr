# Windows counterpart of fetch_whisper_cpp.sh: downloads the pinned whisper.cpp
# release, verifies its sha256 and extracts it into third_party/whisper.cpp.
#   powershell -ExecutionPolicy Bypass -File tool\fetch_whisper_cpp.ps1
$ErrorActionPreference = 'Stop'
$tag = 'v1.9.5'
$sha = 'ff1a9053feb509ff9d7729703355541ae9690073a6b1c40eb692c962e0dc1720'
$url = "https://github.com/ggml-org/whisper.cpp/archive/refs/tags/$tag.tar.gz"
$pkg = Split-Path -Parent $PSScriptRoot
$dest = Join-Path $pkg 'third_party\whisper.cpp'
$stamp = Join-Path $dest ".fetched-$tag"
if (Test-Path $stamp) { Write-Host "whisper.cpp $tag already present"; exit 0 }
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("whisper-cpp-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $tmp | Out-Null
$archive = Join-Path $tmp 'whisper.cpp.tar.gz'
Write-Host "Downloading $url"
Invoke-WebRequest -Uri $url -OutFile $archive
$got = (Get-FileHash -Algorithm SHA256 $archive).Hash.ToLower()
if ($got -ne $sha) { throw "sha256 mismatch: expected $sha, got $got" }
$x = Join-Path $tmp 'x'
New-Item -ItemType Directory -Path $x | Out-Null
tar -xzf $archive -C $x
$src = Get-ChildItem -Directory $x | Select-Object -First 1
if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
Move-Item $src.FullName $dest
New-Item -ItemType File -Path $stamp | Out-Null
Remove-Item -Recurse -Force $tmp
Write-Host "Extracted whisper.cpp $tag to third_party\whisper.cpp"
