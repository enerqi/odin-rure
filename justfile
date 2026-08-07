set windows-shell := ["nu", "-c"]
set shell := ["bash", "-c"]
set unstable  # [script("python")] feature - https://github.com/casey/just/issues/1479

main_name := "example.exe"

# Which linker Odin hands the object files to. `-linker:` takes exactly four values: `default` (Odin
# picks - MSVC `link.exe` on Windows), `lld` (Windows and Linux; NOT on a stock macOS, where Odin
# links through Apple's clang and clang ships no lld), `radlink` (Windows only, and bundled with the
# Odin toolchain so it needs no install - which is why it is the Windows default here) and `mold`
# (Linux only, and not bundled - `apt install mold` first). Odin has no build cache and relinks on
# every `just run`, so the link step is a cost paid on each iteration.
#
# Override for a single command without editing this file. It is an env var rather than a recipe
# argument because `odin` errors on a repeated flag, so a `-linker:` passed through a recipe's *args
# would collide with the one the recipe already adds:
#
#     ODIN_LINKER=lld just run -lto:thin   # -lto on Windows *requires* -linker:lld
#
# See the odin-lang-skeleton justfile for the full per-value notes.
linker := env_var_or_default("ODIN_LINKER", if os() == "windows" { "radlink" } else { "default" })

# Deliberately NOT `odinfmt -w .`, which is what the other Odin projects here use: inputs/prelude.odin
# is an incomplete bindgen fragment with no package line, and odinfmt exits non-zero on it. So the two
# real sources are named instead - the same approach odin-dds takes for its own prelude. `odinfmt -w
# example` formats the directory. This replaces a python os.walk that skipped `inputs` for this reason.
# ---
# odinfmt the generated bindings + the example (inputs/ holds an unparseable bindgen fragment)
format:
    odinfmt -w rure.odin
    odinfmt -w example


# lint checks for style and potential bugs. Accepts extra args like `--show-timings`as needed
lint *args:
    odin check . -vet -vet-cast -strict-style -vet-tabs -no-entry-point {{args}}


# ensure the build artifacts top level directory exists
[unix]
@mktarget_dirs:
    mkdir -p target/debug target/fastdebug target/release

# ensure the build artifacts top level directory exists
[windows]
@mktarget_dirs:
    mkdir target/debug target/fastdebug target/release

# run bindgen to update rure.odin
generate:
	bindgen .

# (re)build the Windows rure.lib from a cloned regex/regex-capi checkout with the
# CRT match + performance flags these bindings need (see README "Building the
# rure library"). Pass the path to the regex-capi dir, e.g.
#   just build_rure ../regex/regex-capi
# Flags are passed via `cargo --config` so this works in both shells without
# per-shell env-var syntax:
#   +crt-static       -> rure links the STATIC CRT (libcmt) to match Odin's host,
#                        instead of the default dynamic msvcrt (avoids LNK4098 /
#                        two-CRT mixing). Flips /defaultlib:msvcrt -> libcmt.
#   target-cpu=v3     -> AVX2/BMI baseline (matches the project's AVX2 stance;
#                        drops pre-2013 CPUs). Use a named level, NOT `native`,
#                        for the shipped prebuilt lib.
#   lto=fat + cu=1    -> cross-crate inlining (memchr/aho-corasick into regex) and
#                        max optimization. Slow build, but the lib is shipped.
# (re)build Windows rure.lib with CRT-match + perf flags; arg = regex-capi dir
[windows]
build_rure regex_capi_dir:
	cargo build --release --manifest-path {{regex_capi_dir}}/Cargo.toml \
		--config 'profile.release.lto="fat"' \
		--config 'profile.release.codegen-units=1' \
		--config 'build.rustflags=["-C","target-feature=+crt-static","-C","target-cpu=x86-64-v3"]'
	@echo "artifact: {{regex_capi_dir}}/../target/release/rure.lib  -> copy to ./lib"

# print the native static libs to link against the built rure.lib. Re-run this
# after changing CRT flags: with +crt-static the directive becomes
# /defaultlib:libcmt and legacy_stdio_definitions.lib drops out, so the
# `foreign import` list in inputs/prelude.odin must be updated to match.
# print native static libs to link against rure.lib; arg = regex-capi dir
[windows]
rure_native_libs regex_capi_dir:
	cargo rustc --release --manifest-path {{regex_capi_dir}}/Cargo.toml \
		--config 'build.rustflags=["-C","target-feature=+crt-static"]' \
		-q -- --print=native-static-libs

# Linux build of librure.a. Same name as the Windows recipe (just dispatches on
# the host OS), so `just build_rure ../regex/regex-capi` works on both.
# NOTE: no +crt-static here. On Linux there is no static/dynamic CRT split to
# match - Odin and librure.a both link the system glibc dynamically (the
# -lgcc_s -lutil -lrt -lpthread -lm -ldl -lc deps). +crt-static would try to
# statically link glibc, which breaks dlopen/NSS (getaddrinfo, user/host lookups)
# and gains nothing here. Only the toolchain-agnostic perf flags carry over.
# target-cpu=v3 assumes an x86_64 Linux lib; drop/replace it for other arches.
# (re)build Linux librure.a with perf flags; arg = regex-capi dir
[linux]
build_rure regex_capi_dir:
	cargo build --release --manifest-path {{regex_capi_dir}}/Cargo.toml \
		--config 'profile.release.lto="fat"' \
		--config 'profile.release.codegen-units=1' \
		--config 'build.rustflags=["-C","target-cpu=x86-64-v3"]'
	@echo "artifact: {{regex_capi_dir}}/../target/release/librure.a  -> copy to ./lib"

# print native static libs to link against librure.a; arg = regex-capi dir
[linux]
rure_native_libs regex_capi_dir:
	cargo rustc --release --manifest-path {{regex_capi_dir}}/Cargo.toml \
		-q -- --print=native-static-libs

# run example code
run_debug *args: mktarget_dirs
	odin run example -debug -microarch:native -show-timings -linker:{{linker}} -out:target/debug/{{main_name}} {{args}}

alias run := run_debug

# run fast debug example code
run_fastdebug *args: mktarget_dirs
    odin run example -debug -o:speed -microarch:native -show-timings -linker:{{linker}} -out:target/fastdebug/{{main_name}} {{args}}

# run release example code
run_release *args: mktarget_dirs
    odin run example -o:speed -microarch:native -show-timings -linker:{{linker}} -out:target/release/{{main_name}} {{args}}

# run all tests
test *args: mktarget_dirs
    odin test . -debug -file -microarch:native -show-timings -linker:{{linker}} -out:target/debug/test-main.exe {{args}}

# run one named test
test1 name *args: mktarget_dirs
    odin test . -debug -file -microarch:native -show-timings -test-name:{{name}} -linker:{{linker}} -out:target/debug/test-main.exe {{args}}

# simple delete of all debug databases and executables in the target directory
clean:
    rm -rf target
    just mktarget_dirs
