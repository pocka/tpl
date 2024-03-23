// SPDX-FileCopyrightText: 2024 Shota FUJI <pockawoooh@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0

import { assertObjectMatch } from "./deps.ts";

import { File, VirtualFS, WasmApi } from "./mod.ts";

Deno.test("Return an error object if license was not found", () => {
	const api = new WasmApi(
		new VirtualFS([
			new File("foo.txt", ""),
		]),
	);

	const result = api.scan({
		file: "/root/foo.txt",
		projectRoot: "/root",
		root: "/root",
	});

	assertObjectMatch(result, { error: "LicenseOrCopyrightNotFound" });
});

Deno.test("Find LICENSE file", () => {
	const api = new WasmApi(
		new VirtualFS([
			new File("foo.txt", ""),
			new File("LICENSE", ""),
		]),
	);

	const result = api.scan({
		file: "/root/foo.txt",
		projectRoot: "/root",
		root: "/root",
	});

	assertObjectMatch(result, {
		licenses: [{
			files: [{ path: "foo.txt" }],
			license: { type: "arbitrary", includes: [{ path: "LICENSE" }] },
		}],
	});
});

Deno.test("Find British one, too", () => {
	const api = new WasmApi(
		new VirtualFS([
			new File("foo.txt", ""),
			new File("LICENCE", ""),
		]),
	);

	const result = api.scan({
		file: "/root/foo.txt",
		projectRoot: "/root",
		root: "/root",
	});

	assertObjectMatch(result, {
		licenses: [{
			files: [{ path: "foo.txt" }],
			license: { type: "arbitrary", includes: [{ path: "LICENCE" }] },
		}],
	});
});

Deno.test("Ignore filename case", () => {
	const api = new WasmApi(
		new VirtualFS([
			new File("foo.txt", ""),
			new File("liCEnSE", ""),
		]),
	);

	const result = api.scan({
		file: "/root/foo.txt",
		projectRoot: "/root",
		root: "/root",
	});

	assertObjectMatch(result, {
		licenses: [{
			files: [{ path: "foo.txt" }],
			license: { type: "arbitrary", includes: [{ path: "liCEnSE" }] },
		}],
	});
});

Deno.test("Find LICENSE file even with file extension", () => {
	const api = new WasmApi(
		new VirtualFS([
			new File("foo.txt", ""),
			new File("LICENSE.txt", ""),
		]),
	);

	const result = api.scan({
		file: "/root/foo.txt",
		projectRoot: "/root",
		root: "/root",
	});

	assertObjectMatch(result, {
		licenses: [{
			files: [{ path: "foo.txt" }],
			license: { type: "arbitrary", includes: [{ path: "LICENSE.txt" }] },
		}],
	});
});
