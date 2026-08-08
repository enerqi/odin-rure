# `cmd.exe` for one reason: it starts in ~9ms. just launches a shell per recipe LINE, so shell startup
# is a fixed tax on every recipe. Bare `<shell> exit` under hyperfine: cmd ~9ms, `nu -c` ~41ms (what
# this file used to set), `powershell -NoLogo -NoProfile -Command` ~143ms. cmd is also more portable
# than either: on every Windows and on GitHub's windows runners, no install, and no profile to make a
# recipe unreproducible. The cost is that it is a poor language for a multi-line recipe and does not
# understand POSIX single-quoting - so every recipe below with logic or quoted arguments (the cargo
# ones) uses `[script("python")]`, which builds an argv list and spawns no shell at all.
set windows-shell := ["cmd.exe", "/c"]
set shell := ["bash", "-c"]
set unstable  # [script("python")] feature - https://github.com/casey/just/issues/1479
set lazy

# Set by the newest just feature used below - user-defined functions (1.49), for `target_path`.
# Older features also needed: `join()` 1.37, `set lazy` 1.47. Without this an old just reports a plain
# syntax error at the offending line, which reads like a corrupt justfile rather than an old tool.
set minimum-version := "1.49.0"

main_name := "example.exe"
test_main_name := "test-main.exe"

# `join`, not the `/` operator: `/` always emits a forward slash, and cmd.exe rejects a forward-slash
# path in *command* position ("'target' is not recognized") even quoted. Odin takes either in an
# `-out:` argument, but the `rerun_*` recipes invoke the binary directly, so they need the native
# separator `join` gives. bash needs no `./` prefix - a path containing a slash is already a path.
target_path(dir, name) := join("target", dir, name)

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
# One caution specific to a project like this one, which statically links a Rust `staticlib` built
# with `+crt-static`: sibling project odin-num-format has exactly that arrangement and radlink LINKS
# it without complaint but produces a binary that dies immediately with `0xc000001d`
# (STATUS_ILLEGAL_INSTRUCTION), where `default` and `lld` both work. So if a rure binary ever starts
# failing that way, try `ODIN_LINKER=default` before suspecting your own code - and note that a
# successful link proves nothing, only running it does.
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


# lint checks for style and potential bugs. Accepts extra args like `--show-timings` as needed
lint *args:
	odin check . -vet -vet-cast -strict-style -vet-tabs -no-entry-point {{args}}


# Every `run_*` and `test*` recipe depends on this, so it runs before every build - which makes its
# cost a tax on every iteration. The directories are created all at once rather than one per line
# because just starts a new shell per recipe line and on Windows the shell launch dwarfs the work.
# odin does not create the output directory (the linker fails with LNK1104), so this cannot be dropped.
# ---
# ensure the build artifacts top level directory exists
[unix]
@mktarget_dirs:
	mkdir -p target/debug target/fastdebug target/release

# `if not exist` rather than swallowing md's "already exists" with `2>nul`, so a genuine failure still
# sets a non-zero exit. The loop variable is a single `%d`, NOT the `%%d` a .bat file would use:
# doubling is escaping for batch *files*, and `cmd /c` takes a command *line*.
# ---
# ensure the build artifacts top level directory exists
[windows]
@mktarget_dirs:
	for %d in (debug fastdebug release) do @if not exist target\%d md target\%d || exit /b 1

# run bindgen to update rure.odin
generate:
	bindgen .

# (re)build the Windows rure.lib from a cloned regex/regex-capi checkout with the
# CRT match + performance flags these bindings need (see README "Building the
# rure library"). Pass the path to the regex-capi dir, e.g.
#   just build_rure ../regex/regex-capi
# Flags are passed via `cargo --config`, as an argv list from python rather than a
# shell line: the values are TOML, so `lto="fat"` has to reach cargo WITH its
# double quotes intact, and neither cmd.exe nor a POSIX shell hands them over
# unaltered without per-shell escaping. subprocess spawns no shell, so there is
# nothing to escape against.
#   +crt-static       -> rure links the STATIC CRT (libcmt) to match Odin's host,
#                        instead of the default dynamic msvcrt (avoids LNK4098 /
#                        two-CRT mixing). Flips /defaultlib:msvcrt -> libcmt.
#   target-cpu=v3     -> AVX2/BMI baseline (matches the project's AVX2 stance;
#                        drops pre-2013 CPUs). Use a named level, NOT `native`,
#                        for the shipped prebuilt lib.
#   lto=fat + cu=1    -> cross-crate inlining (memchr/aho-corasick into regex) and
#                        max optimization. Slow build, but the lib is shipped.
# ---
# (re)build Windows rure.lib with CRT-match + perf flags; arg = regex-capi dir
[windows]
[script("python")]
build_rure regex_capi_dir:
	import subprocess, sys
	d = r"{{regex_capi_dir}}"
	rc = subprocess.run([
		"cargo", "build", "--release", "--manifest-path", d + "/Cargo.toml",
		"--config", 'profile.release.lto="fat"',
		"--config", "profile.release.codegen-units=1",
		"--config", 'build.rustflags=["-C","target-feature=+crt-static","-C","target-cpu=x86-64-v3"]',
	]).returncode
	if rc != 0:
		raise SystemExit(rc)
	print("artifact: " + d + "/../target/release/rure.lib  -> copy to ./lib")

# print the native static libs to link against the built rure.lib. Re-run this
# after changing CRT flags: with +crt-static the directive becomes
# /defaultlib:libcmt and legacy_stdio_definitions.lib drops out, so the
# `foreign import` list in inputs/prelude.odin must be updated to match.
# ---
# print native static libs to link against rure.lib; arg = regex-capi dir
[windows]
[script("python")]
rure_native_libs regex_capi_dir:
	import subprocess
	d = r"{{regex_capi_dir}}"
	raise SystemExit(subprocess.run([
		"cargo", "rustc", "--release", "--manifest-path", d + "/Cargo.toml",
		"--config", 'build.rustflags=["-C","target-feature=+crt-static"]',
		"-q", "--", "--print=native-static-libs",
	]).returncode)

# Linux build of librure.a. Same name as the Windows recipe (just dispatches on
# the host OS), so `just build_rure ../regex/regex-capi` works on both.
# NOTE: no +crt-static here. On Linux there is no static/dynamic CRT split to
# match - Odin and librure.a both link the system glibc dynamically (the
# -lgcc_s -lutil -lrt -lpthread -lm -ldl -lc deps). +crt-static would try to
# statically link glibc, which breaks dlopen/NSS (getaddrinfo, user/host lookups)
# and gains nothing here. Only the toolchain-agnostic perf flags carry over.
# target-cpu=v3 assumes an x86_64 Linux lib; drop/replace it for other arches.
# ---
# (re)build Linux librure.a with perf flags; arg = regex-capi dir
[linux]
[script("python")]
build_rure regex_capi_dir:
	import subprocess
	d = r"{{regex_capi_dir}}"
	rc = subprocess.run([
		"cargo", "build", "--release", "--manifest-path", d + "/Cargo.toml",
		"--config", 'profile.release.lto="fat"',
		"--config", "profile.release.codegen-units=1",
		"--config", 'build.rustflags=["-C","target-cpu=x86-64-v3"]',
	]).returncode
	if rc != 0:
		raise SystemExit(rc)
	print("artifact: " + d + "/../target/release/librure.a  -> copy to ./lib")

# print native static libs to link against librure.a; arg = regex-capi dir
[linux]
[script("python")]
rure_native_libs regex_capi_dir:
	import subprocess
	raise SystemExit(subprocess.run([
		"cargo", "rustc", "--release", "--manifest-path", r"{{regex_capi_dir}}" + "/Cargo.toml",
		"-q", "--", "--print=native-static-libs",
	]).returncode)

# `-keep-executable` leaves the binary in place (odin run deletes it by default) so `rerun_debug` can
# execute it again - Odin has no build cache, so a plain `just run` always recompiles and relinks.
# ---
# run example code
run_debug *args: mktarget_dirs
	odin run example -debug -microarch:native -show-timings -keep-executable -linker:{{linker}} -out:{{ target_path("debug", main_name) }} {{args}}

alias run := run_debug

# run fast debug example code
run_fastdebug *args: mktarget_dirs
	odin run example -debug -o:speed -microarch:native -show-timings -keep-executable -linker:{{linker}} -out:{{ target_path("fastdebug", main_name) }} {{args}}

# run release example code
run_release *args: mktarget_dirs
	odin run example -o:speed -microarch:native -show-timings -keep-executable -linker:{{linker}} -out:{{ target_path("release", main_name) }} {{args}}

# re-run the last debug example binary WITHOUT recompiling. Requires a prior `run_debug`/`run`.
rerun_debug *args:
	{{ target_path("debug", main_name) }} {{args}}

alias rerun := rerun_debug

# re-run the last fastdebug example binary without recompiling. Requires a prior `run_fastdebug`.
rerun_fastdebug *args:
	{{ target_path("fastdebug", main_name) }} {{args}}

# re-run the last release example binary without recompiling. Requires a prior `run_release`.
rerun_release *args:
	{{ target_path("release", main_name) }} {{args}}

# run all tests
test *args: mktarget_dirs
	odin test . -debug -file -microarch:native -show-timings -linker:{{linker}} -out:{{ target_path("debug", test_main_name) }} {{args}}

# Filtering is a `core:testing` define rather than a compiler flag - there is no `-test-name:`, and the
# stale spelling this recipe used to carry failed with `Unknown flag: 'test-name'` before anything
# built, so `just test1` could never have worked. NAME takes a comma-separated list and the package
# prefix is optional, so `rure.my_test`, `my_test` and `one,two` all work.
# ---
# run one named test (comma-separated for several)
test1 name *args: mktarget_dirs
	odin test . -debug -file -microarch:native -show-timings -define:ODIN_TEST_NAMES={{name}} -linker:{{linker}} -out:{{ target_path("debug", test_main_name) }} {{args}}

# simple delete of all debug databases and executables in the target directory
[unix]
clean:
	rm -rf target
	just mktarget_dirs

# cmd's equivalent of `rm -rf` is `rmdir /s /q`. Guarded by `if exist` because rmdir prints "The system
# cannot find the file specified" and exits non-zero on a missing path, which would fail the recipe on
# an already-clean tree. (The old single `rm -rf target` recipe was nu-only and had no Windows path.)
# ---
# simple delete of all debug databases and executables in the target directory
[windows]
clean:
	if exist target rmdir /s /q target
	just mktarget_dirs
