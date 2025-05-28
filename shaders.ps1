Push-Location $dir
if (!(Test-Path -Path "./src/compiled_shaders")) {
    New-Item -ItemType Directory -Path "./src/compiled_shaders"
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
    $shaderPath = "./assets/shaders/$name.hlsl"

    # adapt stage from "vert" to "vertex" and "frag" to "fragment"
    if ($stage -eq "vert") {
        $stage = "vertex"
    } elseif ($stage -eq "frag") {
        $stage = "fragment"
    }

    shadercross "$shaderPath" -e "$stage" -o "./sandbox/compiled_shaders/$outputPath" -t $stage -I "./assets/shaders/"
}

Add-Shader "triangle.vert.dxil"
Add-Shader "triangle.frag.dxil"
Add-Shader "triangle.vert.spv"
Add-Shader "triangle.frag.spv"
Add-Shader "triangle.vert.msl"
Add-Shader "triangle.frag.msl"

Pop-Location