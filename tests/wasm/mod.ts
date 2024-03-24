// SPDX-FileCopyrightText: 2024 Shota FUJI <pockawoooh@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0

export class File {
	name: string;
	contents: Uint8Array;

	constructor(name: string, contents: string | Uint8Array) {
		this.name = name;
		this.contents = typeof contents === "string"
			? new TextEncoder().encode(contents)
			: contents;
	}
}

export class Dir {
	constructor(public name: string, public children: (File | Dir)[]) {}
}

export class VirtualFS {
	#root: Dir;

	constructor(entries: (File | Dir)[]) {
		this.#root = new Dir("root", entries);
	}

	#getInternal(path: readonly string[], entry: File | Dir): File | Dir | null {
		if (path.length === 0) {
			return null;
		}

		const [head, ...tail] = path;

		if (entry.name !== head) {
			return null;
		}

		if (entry instanceof File) {
			if (tail.length > 0) {
				// file as dir
				return null;
			}

			return entry;
		}

		if (tail.length === 0) {
			return entry;
		}

		for (const child of entry.children) {
			const found = this.#getInternal(tail, child);
			if (found) {
				return found;
			}
		}

		return null;
	}

	get(path: string): File | Dir | null {
		return this.#getInternal(path.split("/").filter((s) => !!s), this.#root);
	}
}

const wasm = await Deno.readFile(
	new URL("../../zig-out/lib/tpl.wasm", import.meta.url),
);

const mod = new WebAssembly.Module(wasm);

const ARENA = Symbol("Arena");
type Arena = number & { [ARENA]: 0 };

const ALLOCATOR = Symbol("Allocator");
type Allocator = number & { [ALLOCATOR]: 0 };

const STRING_PTR = Symbol("StringPtr");
type StringPtr = number & { [STRING_PTR]: 0 };

const CSTRING_PTR = Symbol("CstringPtr");
type CstringPtr = number & { [CSTRING_PTR]: 0 };

const POINTER = Symbol("ptr");
type Pointer = number & { [POINTER]: 0 };

const SCANNER = Symbol("SCANNER");
type Scanner = number & { [SCANNER]: 0 };

interface WasmExports {
	memory: WebAssembly.Memory;

	create_scanner(allocator: Allocator): Scanner;
	set_scanner_package_root(
		scanner: Scanner,
		pathPtr: number,
		pathLen: number,
	): void;
	set_scanner_file(scanner: Scanner, pathPtr: number, pathLen: number): void;
	set_scanner_root(scanner: Scanner, pathPtr: number, pathLen: number): void;
	scan_file(allocator: Allocator, scanner: Scanner): CstringPtr;

	init_arena(): Arena;
	deinit_arena(arena: Arena): void;
	get_arena_allocator(arena: Arena): Allocator;
	allocate_u8(allocator: Allocator, len: number): StringPtr;
	get_cstring_len(ptr: CstringPtr): number;
	add_file_to_dir_entry_context(
		ctx: Pointer,
		pathPtr: number,
		pathLen: number,
	): void;
}

type ScanResult =
	| { error: string }
	| { project: unknown; licenses: unknown[]; copyrights: unknown[] };

export class WasmApi {
	#instance: WebAssembly.Instance;

	#arena: Arena;
	#allocator: Allocator;

	constructor(vfs?: VirtualFS) {
		this.#instance = new WebAssembly.Instance(mod, {
			fs: {
				read_text_file: (
					_allocator: Allocator,
					path_ptr: number,
					path_len: number,
				) => {
					const pathBuffer = new Uint8Array(
						this.#exports.memory.buffer,
						path_ptr,
						path_len,
					);

					const path = new TextDecoder().decode(pathBuffer);

					if (vfs) {
						const found = vfs.get(path);
						if (!found) {
							throw new Error(`File not found: ${path}`);
						}

						if (found instanceof Dir) {
							throw new Error(`Attempt to read directory: ${path}`);
						}

						return this.#makeString(found.contents);
					}

					const file = Deno.readFileSync(path);

					return this.#makeString(file);
				},
				list_dir: (
					_allocator: Allocator,
					path_ptr: number,
					path_len: number,
					ctx: Pointer,
				) => {
					const path = new TextDecoder().decode(
						new Uint8Array(this.#exports.memory.buffer, path_ptr, path_len),
					);

					if (vfs) {
						const url = new URL(path + "/", "file:///");
						const found = vfs.get(path);
						if (!found) {
							throw new Error(`Directory not found: ${path}`);
						}

						if (found instanceof File) {
							throw new Error(`Attempt to list file: ${path}`);
						}

						for (const child of found.children) {
							if (child instanceof File) {
								const childPath = this.#makeString(
									new URL(`./${child.name}`, url).pathname,
								);

								this.#exports.add_file_to_dir_entry_context(
									ctx,
									childPath.ptr,
									childPath.len,
								);
							}
						}
						return;
					}

					const pathUrl = new URL(path, new URL(Deno.cwd() + "/", "file://"));
					const entries = Deno.readDirSync(path);

					for (const entry of entries) {
						if (entry.isFile) {
							const entryPath = new URL(`./${entry.name}`, pathUrl).pathname;
							const entryPathStr = this.#makeString(entryPath);

							this.#exports.add_file_to_dir_entry_context(
								ctx,
								entryPathStr.ptr,
								entryPathStr.len,
							);
						}
					}
				},
			},
		});

		this.#arena = this.#exports.init_arena();
		this.#allocator = this.#exports.get_arena_allocator(this.#arena);
	}

	get #exports(): WasmExports {
		// @ts-expect-error: Deno (or TS) ships shitty type definition for WebAssembly.Instance
		return this.#instance.exports;
	}

	#makeString(str: string | Uint8Array) {
		const bytes = typeof str === "string" ? new TextEncoder().encode(str) : str;

		const ptr = this.#exports.allocate_u8(this.#allocator, bytes.length);

		const view = new Uint8Array(this.#exports.memory.buffer, ptr, bytes.length);

		view.set(bytes);

		return { ptr, len: bytes.length };
	}

	#readCString(ptr: CstringPtr): Uint8Array {
		const len = this.#exports.get_cstring_len(ptr);

		return new Uint8Array(this.#exports.memory.buffer, ptr, len);
	}

	scan(
		params: { file: string; projectRoot: string; root: string },
	): ScanResult {
		const scanner = this.#exports.create_scanner(this.#allocator);

		const file = this.#makeString(params.file);
		this.#exports.set_scanner_file(scanner, file.ptr, file.len);

		const projectRoot = this.#makeString(params.projectRoot);
		this.#exports.set_scanner_package_root(
			scanner,
			projectRoot.ptr,
			projectRoot.len,
		);

		const root = this.#makeString(params.root);
		this.#exports.set_scanner_root(scanner, root.ptr, root.len);

		const resultPtr = this.#exports.scan_file(this.#allocator, scanner);
		const result = JSON.parse(
			new TextDecoder().decode(this.#readCString(resultPtr)),
		);

		this.#exports.deinit_arena(this.#arena);

		return result;
	}
}
