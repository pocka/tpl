<!--
SPDX-FileCopyrightText: 2024 Shota FUJI <pockawoooh@gmail.com>

SPDX-License-Identifier: CC0-1.0
-->

# Development document

This document describes commands and tips for developing TPL. Without specific
instruction, commands described here assume to be invoked at project root
(repository root directory).

## Build

In order to build, run:

```
$ zig build
```

Here is the list of build outpus:

| Path from project root             | Description           |
| ---------------------------------- | --------------------- |
| `zig-out/bin/tpl-generic-scanners` | CLI executable binary |
| `zig-out/lib/tpl-wasm.wasm`        | WebAssembly module    |

## Test

### Unit tests

In order to run unit tests, run:

```
$ zig build test --summary all
```

Without `--summary all`, the command does not print tests summary if all tests
passed.

### E2E tests (WASM)

In order to run end-to-end tests for WebAssembly module, run:

```
$ deno test --allow-read=.
```

This command requires WebAssembly module to be already built by the build
command above.

The `--allow-read=.` permission is for loading WebAssembly module. If you want
more strict permission, you can minimize the scope by:

```
$ deno test --allow-read=zig-out/lib/tpl-wasm.wasm
```

## Source code

### Common rules

This project has EditorConfig config file. Use an editor or an editor plugin
that supports EditorConfig.

### Code formatter

In order to format Zig source code, run:

```
$ zig fmt .
```

In order to other files, run:

```
$ deno fmt
```

### License

This project aims to comply with [REUSE](https://reuse.software/). Each file
MUST have either copyright/license header or `<filename with ext>.license` file.

Do not forget to put a license text file under `LICENSES/` before using a new
license.
