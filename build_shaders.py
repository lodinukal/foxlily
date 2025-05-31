import os
import shutil
import subprocess
import sys

TRIANGLE_SHADER = {"path": "assets/shaders/triangle.slang", "kind": "graphics"}

ALL_SHADERS = [TRIANGLE_SHADER]
ILA_SHADERS = [TRIANGLE_SHADER]


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
    """Compile a shader using slangc compiler.

    Args:
        source: Path to source shader file
        entrypoint: Shader entry point name
        profile: Target profile (e.g., 'glsl_450', 'sm_6_0')
        target: Target platform (e.g., 'spirv', 'dxil', 'metal')
        destination: Output directory path

    Returns:
        bool: True if compilation succeeded, False otherwise
    """
    # Validate inputs
    if not os.path.exists(source):
        print(f"Error: Source file {source} does not exist.")
        return False

    # destination should look like destination/stem.entrypoint.target
    nice_name_entrypoint = nice_name_map.get(entrypoint, entrypoint)
    dest = f"{destination}/{os.path.splitext(os.path.basename(source))[0]}.{nice_name_entrypoint}.{target}"

    cmd_args = [
        "slangc",
        "-o",
        dest,
        "-target",
        target,
        "-profile",
        profile,
        source,
        "-fvk-use-entrypoint-name",
        "-entry",
        entrypoint,
        "-fvk-b-shift",
        "0",
        "all",
        "-fvk-t-shift",
        "0",
        "all",
        "-fvk-s-shift",
        "0",
        "all",
        "-fvk-u-shift",
        "0",
        "all",
    ]

    try:
        result = subprocess.run(cmd_args, check=True, capture_output=True, text=True)
        return True
    except subprocess.CalledProcessError as e:
        print(f"Error: Failed to compile shader {source}: {e.stderr}")
        return False
    except FileNotFoundError:
        print("Error: slangc command not found.")
        return False


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
    if not build():
        print("Shader compilation failed.")
        sys.exit(1)
    print("Shader compilation complete.")
