"use strict";

(function exposeFontValidator(root) {
  const requiredPersian = [
    0x0621, 0x0622, 0x0624, 0x0626, 0x0627, 0x0628,
    0x067e, 0x062a, 0x062b, 0x062c, 0x0686, 0x062d, 0x062e,
    0x062f, 0x0630, 0x0631, 0x0632, 0x0698, 0x0633, 0x0634,
    0x0635, 0x0636, 0x0637, 0x0638, 0x0639, 0x063a, 0x0641,
    0x0642, 0x06a9, 0x06af, 0x0644, 0x0645, 0x0646, 0x0648,
    0x0647, 0x06cc,
    0x06f0, 0x06f1, 0x06f2, 0x06f3, 0x06f4,
    0x06f5, 0x06f6, 0x06f7, 0x06f8, 0x06f9,
  ];

  function tableDirectory(buffer) {
    const view = new DataView(buffer);
    if (buffer.byteLength < 12) throw new Error("Font header is truncated.");
    const signature = view.getUint32(0);
    if (signature !== 0x00010000 && signature !== 0x4f54544f) throw new Error("Only TrueType/OpenType SFNT fonts are supported.");
    const count = view.getUint16(4);
    if (!count || 12 + count * 16 > buffer.byteLength) throw new Error("Font table directory is invalid.");
    const tables = new Map();
    for (let index = 0; index < count; index += 1) {
      const offset = 12 + index * 16;
      const tag = String.fromCharCode(view.getUint8(offset), view.getUint8(offset + 1), view.getUint8(offset + 2), view.getUint8(offset + 3));
      const tableOffset = view.getUint32(offset + 8);
      const length = view.getUint32(offset + 12);
      if (tableOffset > buffer.byteLength || length > buffer.byteLength - tableOffset) throw new Error(`Font table ${tag} is out of bounds.`);
      tables.set(tag, { offset: tableOffset, length });
    }
    return { view, tables };
  }

  function cmapSupports(view, table, codepoint) {
    const base = table.offset;
    if (table.length < 4) return false;
    const count = view.getUint16(base + 2);
    for (let index = 0; index < count; index += 1) {
      const record = base + 4 + index * 8;
      if (record + 8 > base + table.length) return false;
      const subtable = base + view.getUint32(record + 4);
      if (subtable + 2 > base + table.length) continue;
      const format = view.getUint16(subtable);
      if (format === 12 && subtable + 16 <= base + table.length) {
        const groups = view.getUint32(subtable + 12);
        for (let group = 0; group < groups; group += 1) {
          const position = subtable + 16 + group * 12;
          if (position + 12 > base + table.length) break;
          const start = view.getUint32(position);
          const end = view.getUint32(position + 4);
          if (codepoint >= start && codepoint <= end) {
            return view.getUint32(position + 8) + codepoint - start !== 0;
          }
        }
      }
      if (format === 4 && codepoint <= 0xffff && subtable + 16 <= base + table.length) {
        const segCount = view.getUint16(subtable + 6) / 2;
        const endCodes = subtable + 14;
        const startCodes = endCodes + segCount * 2 + 2;
        const deltas = startCodes + segCount * 2;
        const rangeOffsets = deltas + segCount * 2;
        if (rangeOffsets + segCount * 2 > base + table.length) continue;
        for (let segment = 0; segment < segCount; segment += 1) {
          const end = view.getUint16(endCodes + segment * 2);
          const start = view.getUint16(startCodes + segment * 2);
          if (codepoint < start || codepoint > end) continue;
          const delta = view.getInt16(deltas + segment * 2);
          const rangePosition = rangeOffsets + segment * 2;
          const rangeOffset = view.getUint16(rangePosition);
          if (rangeOffset === 0) return ((codepoint + delta) & 0xffff) !== 0;
          const glyphPosition = rangePosition + rangeOffset + (codepoint - start) * 2;
          if (glyphPosition + 2 > base + table.length) return false;
          const glyph = view.getUint16(glyphPosition);
          return glyph !== 0 && ((glyph + delta) & 0xffff) !== 0;
        }
      }
    }
    return false;
  }

  function validate(buffer, expectedWeight) {
    const { view, tables } = tableDirectory(buffer);
    for (const tag of ["cmap", "GDEF", "GPOS", "GSUB", "OS/2", "name"]) {
      if (!tables.has(tag)) throw new Error(`Font is missing required ${tag} data.`);
    }
    for (const codepoint of requiredPersian) {
      if (!cmapSupports(view, tables.get("cmap"), codepoint)) {
        throw new Error(`Font lacks required Persian character U+${codepoint.toString(16).toUpperCase()}.`);
      }
    }
    const os2 = tables.get("OS/2");
    if (os2.length < 6) throw new Error("Font OS/2 table is truncated.");
    const weight = view.getUint16(os2.offset + 4);
    if (expectedWeight === "regular" && (weight < 250 || weight > 550)) throw new Error(`Regular file reports weight ${weight}.`);
    if (expectedWeight === "bold" && weight < 600) throw new Error(`Bold file reports weight ${weight}.`);
    return { weight };
  }

  root.PfsFontValidator = Object.freeze({ validate, requiredPersian: Object.freeze(requiredPersian) });
})(typeof globalThis === "object" ? globalThis : window);
