import os
import shutil

ALL_SHADERS = [
    {"path": "assets/shaders/triangle.slang", "kind": "graphics"},
]
ILA_SHADERS = [
    {"path": "assets/shaders/triangle.slang", "kind": "graphics"},
]


# check for a slang binary
def check_slang_binary():
    slang_binary = "slangc"
    found = shutil.which(slang_binary)
    if not found:
        print(f"Error: {slang_binary} not found in PATH.")
        return None
    return found


nice_name_map = {
    "fragment": "frag",
    "vertex": "vert",
    "compute": "comp",
    "geometry": "geom",
}


def compile_shader(source, entrypoint, profile, target, destination):
    # destination should look like destination/stem.entrypoint.target
    nice_name_entrypoint = nice_name_map.get(entrypoint, entrypoint)
    dest = f"{destination}/{os.path.splitext(os.path.basename(source))[0]}.{nice_name_entrypoint}.{target}"
    command = (
        f"slangc -o {dest} -target {target} -profile {profile} {source} "
        + f"-fvk-use-entrypoint-name -entry {entrypoint} "
        + "-fvk-b-shift 0 all -fvk-t-shift 0 all -fvk-s-shift 0 all -fvk-u-shift 0 all"
    )
    result = os.system(command)
    if result != 0:
        print(f"Error: Failed to compile shader {source}.")
        return False
    return True


def compile_folder(destination, shaders):
    if not os.path.exists(destination):
        os.makedirs(destination)

    for shader in shaders:
        for target_and_profile in [
            ["spirv", "glsl_450"],
            ["dxil", "sm_6_0"],
            ["metal", "sm_6_0"],
        ]:
            target, profile = target_and_profile
            kind = shader["kind"]
            if kind == "graphics":
                if not compile_shader(
                    shader["path"], "vertex", profile, target, destination
                ):
                    return False
                if not compile_shader(
                    shader["path"], "fragment", profile, target, destination
                ):
                    return False
            elif kind == "compute":
                if not compile_shader(
                    shader["path"], "compute", profile, target, destination
                ):
                    return False
    return True


def build():
    binary = check_slang_binary()
    if not binary:
        return False

    if compile_folder("sandbox/compiled_shaders", ALL_SHADERS) == False:
        return False

    if compile_folder("src/compiled_shaders", ILA_SHADERS) == False:
        return False


if __name__ == "__main__":
    if build() == False:
        print("Shader compilation failed.")
        os._exit(1)
    print("Shader compilation complete.")
