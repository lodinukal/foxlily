# L(ila)c

My experiment creating a raylib-like library in zig. You need shadercross installed to compile the shaders (see shaders.ps1). Very early stage, only the d3d12 backend for gpu is implemented.

## TODO:
- [x] replace gpu object pool with taking in allocators
- [x] zigify the gpu api
- [x] write a 2d ui renderer
- [] write a 3d renderer
- [ ] utility library (loading textures, fonts, etc.)
    - [x] transfer pool
    - [x] image loading
    - [x] font loading
    - [x] text rendering
    - [ ] wrap sdl windows in a nicer way
- [ ] add examples for gpu
- [x] replace shadercross (or at least call it from build.zig)
    - [ ] replaced but need to invoke slang, might replace again as slang is very slow
- [ ] vulkan backend
- [ ] metal backend