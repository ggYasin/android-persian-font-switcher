"use strict";

const fs = require("fs");
const path = require("path");
const vm = require("vm");

const root = path.resolve(__dirname, "..");
vm.runInThisContext(fs.readFileSync(path.join(root, "webroot/font-validator.js"), "utf8"), {
  filename: "font-validator.js",
});

const manifest = JSON.parse(fs.readFileSync(path.join(root, "webroot/font-manifest.json"), "utf8"));

function arrayBuffer(buffer) {
  return buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength);
}

function expectFailure(buffer, label) {
  let failed = false;
  try {
    PfsFontValidator.validate(arrayBuffer(buffer), "regular");
  } catch (_) {
    failed = true;
  }
  if (!failed) throw new Error(`Corrupt font accepted: ${label}`);
}

for (const font of manifest.fonts) {
  const regular = fs.readFileSync(path.join(root, font.regular));
  const bold = fs.readFileSync(path.join(root, font.bold));
  PfsFontValidator.validate(arrayBuffer(regular), "regular");
  PfsFontValidator.validate(arrayBuffer(bold), font.boldStrategy === "duplicate-regular" ? "regular" : "bold");
}

const sample = fs.readFileSync(path.join(root, manifest.fonts[0].regular));
expectFailure(sample.subarray(0, 10), "truncated header");

const badSignature = Buffer.from(sample);
badSignature.writeUInt32BE(0xdeadbeef, 0);
expectFailure(badSignature, "invalid signature");

const badTableBounds = Buffer.from(sample);
badTableBounds.writeUInt32BE(0xffffffff, 20);
expectFailure(badTableBounds, "out-of-bounds table");

const missingCmap = Buffer.from(sample);
const tableCount = missingCmap.readUInt16BE(4);
for (let index = 0; index < tableCount; index += 1) {
  const offset = 12 + index * 16;
  if (missingCmap.toString("ascii", offset, offset + 4) === "cmap") {
    missingCmap.write("xxxx", offset, 4, "ascii");
    break;
  }
}
expectFailure(missingCmap, "missing cmap");

console.log(`WebUI font-validator tests passed for ${manifest.fonts.length} bundled families`);
