# Foxlily

My experiment creating a raylib-like library in zig. You need shadercross installed to compile the shaders (see shaders.ps1). Very early stage, only the d3d12 backend for gpu is implemented.

## TODO:
- [ ] replace gpu object pool with taking in allocators
- [ ] zigify the gpu api
- [ ] write a proper renderer
- [ ] utility library (loading textures, fonts, etc.)
    - [ ] transfer pool
    - [ ] image loading
    - [ ] font loading
    - [ ] wrap sdl windows in a nicer way
- [ ] add examples for gpu
- [ ] replace shadercross (or at least call it from build.zig)
- [ ] vulkan backend
- [ ] metal backend