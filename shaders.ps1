Push-Location $dir
if (!(Test-Path -Path "./src/compiled_shaders")) {
    New-Item -ItemType Directory -Path "./src/compiled_shaders"
}

shadercross "./assets/shaders/triangle.hlsl" -e "vertex" -o "./src/compiled_shaders/triangle.vert.dxil" -t vertex -I "./assets/shaders/"
shadercross "./assets/shaders/triangle.hlsl" -e "pixel" -o "./src/compiled_shaders/triangle.frag.dxil" -t fragment -I "./assets/shaders/"
Pop-Location