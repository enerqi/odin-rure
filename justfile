set windows-shell := ["nu", "-c"]
set shell := ["bash", "-c"]
set unstable  # [script("python")] feature - https://github.com/casey/just/issues/1479

main_name := "example.exe"

# odinfmt every odin file under this directory or subdirectories
[script("python")]
format:
    import os, subprocess
    for (root, _, files) in os.walk("."):
        for filename in files:
            if filename.endswith(".odin"):
                path = os.path.join(root, filename)
                subprocess.check_call(f"odinfmt -w {path}", shell=True)


# lint checks for style and potential bugs. Accepts extra args like `--show-timings`as needed
lint *args:
    odin check . -vet -strict-style -no-entry-point {{args}}


# ensure the build artifacts top level directory exists
[unix]
@mktarget_dirs:
    -mkdir -p target
    -mkdir -p target/debug
    -mkdir -p target/fastdebug
    -mkdir -p target/release

# ensure the build artifacts top level directory exists
[windows]
@mktarget_dirs:
    -mkdir target
    -mkdir target/debug
    -mkdir target/fastdebug
    -mkdir target/release


run_debug *args: mktarget_dirs
	odin run example -debug -microarch:native -show-timings -out:target/debug/{{main_name}} {{args}}

alias run := run_debug

run_fastdebug *args: mktarget_dirs
    odin run example -debug -o:speed -microarch:native -show-timings -out:target/fastdebug/{{main_name}} {{args}}

run_release *args: mktarget_dirs
    odin run example -o:speed -microarch:native -show-timings -out:target/release/{{main_name}} {{args}}

# run all tests
test *args: mktarget_dirs
    odin test . -debug -file -microarch:native -show-timings -out:target/debug/test-main.exe {{args}}

# run one named test
test1 name *args: mktarget_dirs
    odin test . -debug -file -microarch:native -show-timings -test-name:{{name}} -out:target/debug/test-main.exe {{args}}

# simple delete of all debug databases and executables in the target directory
clean:
    rm -rf target
    just mktarget_dirs
