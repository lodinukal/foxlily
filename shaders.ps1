if (-not (Get-Command slangc -ErrorAction SilentlyContinue)) {
    Write-Error "slangc compiler not found. Please install Slang (https://github.com/shader-slang/slang) and add it to PATH."
    exit 1
}

Push-Location $dir
if (!(Test-Path -Path "./sandbox/compiled_shaders")) {
    New-Item -ItemType Directory -Path "./sandbox/compiled_shaders"
}

# function to add a shader
function Add-Shader {
    param (
        [string]$outputPath
    )
    # split the outputPath to get a triple, name, stage, target
    $outputPathParts = $outputPath -split "\."
    $name = $outputPathParts[-3]
    $stage = $outputPathParts[-2]
    $target = $outputPathParts[-1]

    # make shader path by adding .hlsl to the name
    $shaderPath = "./assets/shaders/$name.slang"

    # adapt stage from "vert" to "vertex" and "frag" to "fragment"
    if ($stage -eq "vert") {
        $stage = "vertex"
        $profile = "vs_6_0"
    } elseif ($stage -eq "frag") {
        $stage = "fragment"
        $profile = "ps_6_0"
    }

    if ($target -eq "dxil") {
        $target = "dxil"
    } elseif ($target -eq "spv") {
        $target = "spirv"
    } elseif ($target -eq "msl") {
        $target = "metal"
    }

    slangc "$shaderPath" -entry "$stage" -o "./sandbox/compiled_shaders/$outputPath" -profile $profile -target $target -I "./assets/shaders/"
}

Add-Shader "triangle.vert.dxil"
Add-Shader "triangle.frag.dxil"
Add-Shader "triangle.vert.spv"
Add-Shader "triangle.frag.spv"
Add-Shader "triangle.vert.msl"
Add-Shader "triangle.frag.msl"

Pop-Location