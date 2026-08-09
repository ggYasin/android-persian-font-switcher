"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const root = path.resolve(__dirname, "..");

function arrayBuffer(buffer) {
  return buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength);
}

// Deliberately satisfies the lightweight directory/cmap/weight checks while
// giving the shaping/name tables only one byte. Browser font sanitizers reject
// this shape, so importing it must depend on FontFace.load(), not the parser
// result alone.
function malformedSfnt(weight) {
  const font = Buffer.alloc(698);
  font.writeUInt32BE(0x00010000, 0);
  font.writeUInt16BE(6, 4);
  const tables = [
    ["cmap", 128, 40],
    ["OS/2", 168, 6],
    ["GDEF", 174, 1],
    ["GPOS", 175, 1],
    ["GSUB", 176, 1],
    ["name", 177, 1],
  ];
  tables.forEach(([tag, offset, length], index) => {
    const record = 12 + index * 16;
    font.write(tag, record, 4, "ascii");
    font.writeUInt32BE(offset, record + 8);
    font.writeUInt32BE(length, record + 12);
  });

  // cmap format 12: one broad group covers every required Persian codepoint.
  font.writeUInt16BE(1, 130);
  font.writeUInt16BE(3, 132);
  font.writeUInt16BE(10, 134);
  font.writeUInt32BE(12, 136);
  font.writeUInt16BE(12, 140);
  font.writeUInt32BE(28, 144);
  font.writeUInt32BE(1, 152);
  font.writeUInt32BE(0x0621, 156);
  font.writeUInt32BE(0x06f9, 160);
  font.writeUInt32BE(1, 164);
  font.writeUInt16BE(weight, 172);
  return font;
}

function fakeElement() {
  return {
    addEventListener() {},
    classList: { add() {}, remove() {}, toggle() {}, contains() { return false; } },
    files: [],
    querySelector() { return null; },
    querySelectorAll() { return []; },
    setAttribute() {},
    style: {},
    textContent: "",
    value: "",
  };
}

const elements = new Map();
const revoked = [];
let objectUrlSequence = 0;
class RejectingFontFace {
  load() {
    const error = new Error("Malformed font");
    error.name = "NetworkError";
    return Promise.reject(error);
  }
}

const context = vm.createContext({
  assert,
  console,
  clearTimeout,
  setTimeout,
  TextDecoder,
  TextEncoder,
  FontFace: RejectingFontFace,
  URL: {
    createObjectURL() { return `blob:test-${++objectUrlSequence}`; },
    revokeObjectURL(url) { revoked.push(url); },
  },
  document: {
    fonts: { add() {}, delete() {} },
    querySelector(selector) {
      if (!elements.has(selector)) elements.set(selector, fakeElement());
      return elements.get(selector);
    },
  },
});
context.window = context;
context.globalThis = context;
context.window.requestAnimationFrame = (callback) => callback();

vm.runInContext(fs.readFileSync(path.join(root, "webroot/font-validator.js"), "utf8"), context, {
  filename: "font-validator.js",
});
const appSource = fs.readFileSync(path.join(root, "webroot/app.js"), "utf8")
  .replace(/\ninitialize\(\);\s*$/, "\n");
vm.runInContext(appSource, context, { filename: "app.js" });

async function main() {
  const regular = malformedSfnt(400);
  const bold = malformedSfnt(700);
  assert.doesNotThrow(() => context.PfsFontValidator.validate(arrayBuffer(regular), "regular"));
  assert.doesNotThrow(() => context.PfsFontValidator.validate(arrayBuffer(bold), "bold"));

  const regularFile = { size: regular.length, arrayBuffer: async () => arrayBuffer(regular) };
  const boldFile = { size: bold.length, arrayBuffer: async () => arrayBuffer(bold) };
  await assert.rejects(
    context.validateRenderableFontPair(regularFile, boldFile),
    /could not be parsed by Android WebView as usable fonts/,
  );
  assert.strictEqual(objectUrlSequence, 2, "renderability gate was not reached");
  assert.deepStrictEqual(revoked, ["blob:test-1", "blob:test-2"]);
  assert.match(
    context.importCustomFont.toString(),
    /validateRenderableFontPair\(regularFile, boldFile\)/,
    "import must repeat the renderability gate for its captured pair",
  );
  console.log("WebUI malformed-font import gate test passed");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
