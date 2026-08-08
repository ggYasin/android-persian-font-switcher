"use strict";

const MODULE_ID = "persian_font_switcher";
const MODULE_DIR = `/data/adb/modules/${MODULE_ID}`;
const DATA_DIR = "/data/adb/persian_font_switcher";
const SAFE_ID = /^[a-z0-9][a-z0-9_-]{0,31}$/;
const SAFE_TOKEN = /^[0-9a-f]{32}$/;
const SCRIPT_NAMES = new Set([
  "apply-font.sh",
  "get-status.sh",
  "import-font.sh",
  "list-custom-fonts.sh",
  "reboot-device.sh",
]);
const MAX_FONT_SIZE = 16 * 1024 * 1024;

let manifest;
let customFonts = [];
let activeId = "unknown";
let selectedId = "system-default";
let chosenId = "system-default";
let operationPending = false;
let callbackSequence = 0;
const loadedFamilies = new Set();
let importPreviewFaces = [];

const elements = {
  activeFont: document.querySelector("#active-font"),
  selectedFont: document.querySelector("#selected-font"),
  chosenFont: document.querySelector("#chosen-font"),
  fontloaderStatus: document.querySelector("#fontloader-status"),
  fontloaderGuidance: document.querySelector("#fontloader-guidance"),
  restartBadge: document.querySelector("#restart-badge"),
  restartPanel: document.querySelector("#restart-panel"),
  notice: document.querySelector("#notice"),
  fontList: document.querySelector("#font-list"),
  search: document.querySelector("#font-search"),
  applyButton: document.querySelector("#apply-button"),
  rebootButton: document.querySelector("#reboot-button"),
  laterButton: document.querySelector("#later-button"),
  customName: document.querySelector("#custom-name"),
  customRegular: document.querySelector("#custom-regular"),
  customBold: document.querySelector("#custom-bold"),
  customPreview: document.querySelector("#custom-preview"),
  importButton: document.querySelector("#import-button"),
  importSupport: document.querySelector("#import-support"),
};

function allOptions() {
  return [manifest.systemDefault, ...manifest.fonts, ...customFonts];
}

function optionFor(id) {
  return allOptions().find((font) => font.id === id);
}

function optionName(id) {
  if (id === "unknown") return "System default or unrecognized";
  return optionFor(id)?.name || id;
}

function validateManifest(data) {
  if (!data || data.schema !== 2 || !Array.isArray(data.fonts) || data.fonts.length < 10) {
    throw new Error("Unsupported font manifest.");
  }
  const ids = new Set([data.systemDefault?.id]);
  if (data.systemDefault?.id !== "system-default") throw new Error("System Default is missing.");
  for (const font of data.fonts) {
    if (!SAFE_ID.test(font.id) || ids.has(font.id)) throw new Error("Unsafe or duplicate font ID.");
    if (font.regular !== `assets/fonts/${font.id}/regular.ttf` || font.bold !== `assets/fonts/${font.id}/bold.ttf`) {
      throw new Error(`Unsafe asset path for ${font.id}.`);
    }
    if (font.previewRegular !== `fonts/${font.id}/regular.ttf` || font.previewBold !== `fonts/${font.id}/bold.ttf`) {
      throw new Error(`Unsafe preview path for ${font.id}.`);
    }
    ids.add(font.id);
  }
}

function verifyBridge() {
  if (!window.ksu || typeof window.ksu.exec !== "function" || typeof window.ksu.moduleInfo !== "function") {
    throw new Error("KernelSU Next WebUI bridge is unavailable.");
  }
  const info = JSON.parse(window.ksu.moduleInfo());
  if (info.moduleDir !== MODULE_DIR || (info.id && info.id !== MODULE_ID)) {
    throw new Error("Unexpected module directory. Refusing privileged operations.");
  }
}

function validateScriptArgs(scriptName, args) {
  if (!SCRIPT_NAMES.has(scriptName)) return false;
  if (scriptName === "apply-font.sh") return args.length === 1 && SAFE_ID.test(args[0]) && Boolean(optionFor(args[0]));
  if (scriptName === "import-font.sh") {
    return args.length === 2 && new Set(["begin", "finish", "cancel"]).has(args[0]) && SAFE_TOKEN.test(args[1]);
  }
  return args.length === 0;
}

function execModuleScript(scriptName, args = []) {
  if (!validateScriptArgs(scriptName, args)) return Promise.reject(new Error("Rejected unsafe script arguments."));
  const command = [`'${MODULE_DIR}/scripts/${scriptName}'`, ...args.map((arg) => `'${arg}'`)].join(" ");
  const callbackName = `pfsCallback${++callbackSequence}`;
  const options = JSON.stringify({ cwd: MODULE_DIR, env: { KSU_MODULE: MODULE_ID } });
  return new Promise((resolve, reject) => {
    window[callbackName] = (exitCode, stdout, stderr) => {
      delete window[callbackName];
      if (exitCode === 0) resolve(stdout);
      else reject(new Error(stderr || stdout || `Command failed (${exitCode}).`));
    };
    try {
      window.ksu.exec(command, options, callbackName);
    } catch (error) {
      delete window[callbackName];
      reject(error);
    }
  });
}

function parseResult(output) {
  const result = {};
  for (const line of output.split(/\r?\n/)) {
    const separator = line.indexOf("=");
    if (separator > 0) result[line.slice(0, separator)] = line.slice(separator + 1);
  }
  return result;
}

function decodeBase64Utf8(value) {
  const bytes = Uint8Array.from(atob(value), (character) => character.charCodeAt(0));
  return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
}

async function loadCustomFonts() {
  const output = await execModuleScript("list-custom-fonts.sh");
  const next = [];
  for (const line of output.split(/\r?\n/)) {
    if (!line.startsWith("custom=")) continue;
    const [id, nameBase64, regularHash, boldHash] = line.slice(7).split("|");
    if (!SAFE_ID.test(id) || !id.startsWith("custom-") || !/^[0-9a-f]{64}$/.test(regularHash) || !/^[0-9a-f]{64}$/.test(boldHash)) continue;
    try {
      const name = decodeBase64Utf8(nameBase64);
      if (!name || name.length > 60 || /[\u0000-\u001f\u007f]/.test(name)) continue;
      next.push({
        id, name, version: "Custom", variant: "User import", author: "User supplied",
        license: "User responsibility", description: "Persisted custom Regular/Bold family.", custom: true,
        previewRegular: `custom-fonts/${id}/regular.ttf`, previewBold: `custom-fonts/${id}/bold.ttf`,
        sha256Regular: regularHash, sha256Bold: boldHash,
      });
    } catch (_) {
      // Ignore corrupt persistent metadata rather than exposing it to the UI.
    }
  }
  customFonts = next;
}

async function ensurePreviewFont(font) {
  if (font.id === "system-default" || loadedFamilies.has(font.id)) return;
  const family = `pfs-${font.id}`;
  const regular = new FontFace(family, `url("${font.previewRegular}")`, { weight: "400" });
  const bold = new FontFace(family, `url("${font.previewBold}")`, { weight: "700" });
  await Promise.all([regular.load(), bold.load()]);
  document.fonts.add(regular);
  document.fonts.add(bold);
  loadedFamilies.add(font.id);
}

function previewLine(className, text, direction) {
  const line = document.createElement("p");
  line.className = className;
  line.textContent = text;
  line.dir = direction;
  return line;
}

function createFontCard(font) {
  const card = document.createElement("article");
  card.className = "font-card";
  card.dataset.fontId = font.id;
  card.tabIndex = 0;
  card.setAttribute("role", "radio");
  card.addEventListener("click", () => chooseFont(font.id));
  card.addEventListener("keydown", (event) => {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      chooseFont(font.id);
    }
  });

  const header = document.createElement("div");
  header.className = "card-header";
  const titleGroup = document.createElement("div");
  const title = document.createElement("h3");
  title.className = "font-name";
  title.textContent = font.name;
  const meta = document.createElement("div");
  meta.className = "font-meta";
  meta.textContent = font.id === "system-default" ? "ROM-provided fallback" : `${font.version} · ${font.author} · ${font.license}`;
  const description = document.createElement("p");
  description.className = "font-description";
  description.textContent = font.description;
  const marks = document.createElement("div");
  marks.className = "card-marks";
  titleGroup.append(title, meta, description);
  header.append(titleGroup, marks);

  const previews = document.createElement("div");
  previews.className = "previews";
  previews.lang = "fa";
  if (font.id !== "system-default") previews.style.fontFamily = `"pfs-${font.id}", sans-serif`;
  previews.append(
    previewLine("preview-regular", "سلام، حال شما چطور است؟", "rtl"),
    previewLine("preview-bold", "این یک متن نمونه برای نمایش فونت فارسی است.", "rtl"),
    previewLine("preview-regular", "می‌روم، خانه‌ها، برنامه‌نویسی", "rtl"),
    previewLine("preview-digits", "۱۲۳۴۵۶۷۸۹۰ · 1234567890 · English + فارسی", "auto"),
  );

  const choose = document.createElement("button");
  choose.type = "button";
  choose.className = "select-button";
  choose.textContent = "Choose";
  choose.addEventListener("click", (event) => {
    event.stopPropagation();
    chooseFont(font.id);
  });
  card.append(header, previews, choose);
  ensurePreviewFont(font).catch(() => card.classList.add("preview-error"));
  return card;
}

function renderCards() {
  elements.fontList.replaceChildren(...allOptions().map(createFontCard));
  elements.fontList.setAttribute("aria-busy", "false");
  filterCards();
  updateDisplay();
}

function chooseFont(id) {
  if (operationPending || !optionFor(id)) return;
  chosenId = id;
  updateDisplay();
}

function updateDisplay() {
  elements.activeFont.textContent = optionName(activeId);
  elements.selectedFont.textContent = optionName(selectedId);
  elements.chosenFont.textContent = optionName(chosenId);
  for (const card of elements.fontList.querySelectorAll(".font-card")) {
    const id = card.dataset.fontId;
    const chosen = id === chosenId;
    card.classList.toggle("chosen", chosen);
    card.setAttribute("aria-checked", String(chosen));
    const marks = card.querySelector(".card-marks");
    marks.replaceChildren();
    if (id === activeId) marks.append(makeMark("Active", "active-mark"));
    if (id === selectedId) marks.append(makeMark("Selected", "selected-mark"));
    const button = card.querySelector(".select-button");
    button.disabled = chosen || operationPending;
    button.textContent = chosen ? "Chosen" : "Choose";
  }
  elements.applyButton.disabled = operationPending || chosenId === selectedId;
}

function makeMark(text, className) {
  const mark = document.createElement("span");
  mark.className = className;
  mark.textContent = text;
  return mark;
}

function filterCards() {
  const query = elements.search.value.trim().toLocaleLowerCase();
  for (const card of elements.fontList.querySelectorAll(".font-card")) {
    const font = optionFor(card.dataset.fontId);
    const haystack = `${font.name} ${font.author || ""} ${font.variant || ""}`.toLocaleLowerCase();
    card.classList.toggle("filtered", Boolean(query) && !haystack.includes(query));
  }
}

function showNotice(message, isError = false) {
  elements.notice.textContent = message;
  elements.notice.classList.toggle("error", isError);
  elements.notice.classList.remove("hidden");
}

function updateRestartUi(required) {
  elements.restartBadge.textContent = "Restart required";
  elements.restartBadge.classList.toggle("hidden", !required);
  elements.restartPanel.classList.toggle("hidden", !required);
}

async function applyChosen() {
  if (operationPending || chosenId === selectedId || !optionFor(chosenId)) return;
  operationPending = true;
  updateDisplay();
  try {
    const result = parseResult(await execModuleScript("apply-font.sh", [chosenId]));
    if (result.status !== "ok" || result.selected !== chosenId) throw new Error(result.message || "Selection rejected.");
    selectedId = chosenId;
    const restartRequired = activeId !== selectedId;
    updateRestartUi(restartRequired);
    showNotice(restartRequired
      ? "Font selected successfully. Reboot is required to rebuild overlays and process font maps."
      : "Selection now matches the active font. No restart is required.");
    if (typeof window.ksu.toast === "function") window.ksu.toast(restartRequired ? "Font selected. Reboot required." : "Selection matches the active font.");
  } catch (error) {
    showNotice(error.message || "Could not apply the selected font.", true);
  } finally {
    operationPending = false;
    updateDisplay();
  }
}

async function validateFontFile(file, expectedWeight) {
  if (!file || file.size < 256 || file.size > MAX_FONT_SIZE) throw new Error("Each font must be between 256 bytes and 16 MiB.");
  const buffer = await file.arrayBuffer();
  window.PfsFontValidator.validate(buffer, expectedWeight);
  return buffer;
}

function bytesToBase64(bytes) {
  let binary = "";
  for (let offset = 0; offset < bytes.length; offset += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
  }
  return btoa(binary);
}

function randomToken() {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  return Array.from(bytes, (value) => value.toString(16).padStart(2, "0")).join("");
}

async function sha256Hex(buffer) {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", buffer));
  return Array.from(digest, (value) => value.toString(16).padStart(2, "0")).join("");
}

function writeBuffer(stream, path, buffer) {
  const id = stream.open(path, false);
  if (!id) throw new Error("Could not open privileged import staging.");
  try {
    const bytes = new Uint8Array(buffer);
    for (let offset = 0; offset < bytes.length; offset += 192 * 1024) {
      if (!stream.write(id, bytesToBase64(bytes.subarray(offset, offset + 192 * 1024)))) throw new Error("Custom font transfer failed.");
    }
    if (!stream.flush(id)) throw new Error("Custom font transfer could not be flushed.");
  } finally {
    stream.close(id);
  }
}

async function importCustomFont() {
  if (operationPending) return;
  if (typeof window.ksu.fileOutputStream !== "function") {
    showNotice("Custom import requires KernelSU Next Manager v3.1.0 or newer.", true);
    return;
  }
  const name = elements.customName.value.trim();
  const nameBytes = new TextEncoder().encode(name);
  if (!name || nameBytes.length > 80 || /[\u0000-\u001f\u007f]/.test(name)) {
    showNotice("Enter a display name of at most 80 UTF-8 bytes without control characters.", true);
    return;
  }

  operationPending = true;
  elements.importButton.disabled = true;
  let token;
  try {
    const regularFile = elements.customRegular.files[0];
    const boldFile = elements.customBold.files[0];
    const [regularBuffer, boldBuffer] = await Promise.all([
      validateFontFile(regularFile, "regular"), validateFontFile(boldFile, "bold"),
    ]);
    const [regularHash, boldHash] = await Promise.all([sha256Hex(regularBuffer), sha256Hex(boldBuffer)]);
    token = randomToken();
    await execModuleScript("import-font.sh", ["begin", token]);
    const stream = window.ksu.fileOutputStream();
    const importRoot = `${DATA_DIR}/staging/${token}`;
    writeBuffer(stream, `${importRoot}/regular.ttf`, regularBuffer);
    writeBuffer(stream, `${importRoot}/bold.ttf`, boldBuffer);
    const encodedName = bytesToBase64(nameBytes);
    writeBuffer(stream, `${importRoot}/name.b64`, new TextEncoder().encode(encodedName).buffer);
    writeBuffer(stream, `${importRoot}/regular.expected.sha256`, new TextEncoder().encode(`${regularHash}\n`).buffer);
    writeBuffer(stream, `${importRoot}/bold.expected.sha256`, new TextEncoder().encode(`${boldHash}\n`).buffer);
    const result = parseResult(await execModuleScript("import-font.sh", ["finish", token]));
    if (result.status !== "ok" || !SAFE_ID.test(result.id)) throw new Error(result.message || "Custom import was rejected.");
    await loadCustomFonts();
    renderCards();
    chosenId = result.id;
    updateDisplay();
    showNotice("Custom font imported. Review its preview, then apply the selection.");
  } catch (error) {
    if (token && SAFE_TOKEN.test(token)) execModuleScript("import-font.sh", ["cancel", token]).catch(() => {});
    showNotice(error.message || "Custom font import failed.", true);
  } finally {
    operationPending = false;
    elements.importButton.disabled = false;
    updateDisplay();
  }
}

async function previewImport() {
  const regularFile = elements.customRegular.files[0];
  const boldFile = elements.customBold.files[0];
  if (!regularFile || !boldFile) return;
  try {
    await Promise.all([validateFontFile(regularFile, "regular"), validateFontFile(boldFile, "bold")]);
    const family = `pfs-import-${Date.now()}`;
    const regularUrl = URL.createObjectURL(regularFile);
    const boldUrl = URL.createObjectURL(boldFile);
    const regular = new FontFace(family, `url("${regularUrl}")`, { weight: "400" });
    const bold = new FontFace(family, `url("${boldUrl}")`, { weight: "700" });
    try {
      await Promise.all([regular.load(), bold.load()]);
    } finally {
      URL.revokeObjectURL(regularUrl);
      URL.revokeObjectURL(boldUrl);
    }
    for (const previous of importPreviewFaces) document.fonts.delete(previous);
    importPreviewFaces = [regular, bold];
    for (const face of importPreviewFaces) document.fonts.add(face);
    elements.customPreview.style.fontFamily = `"${family}", sans-serif`;
    elements.customPreview.classList.remove("hidden");
    elements.importSupport.textContent = "Regular and Bold passed local SFNT, shaping-table, weight, and Persian coverage checks.";
  } catch (error) {
    elements.customPreview.classList.add("hidden");
    elements.importSupport.textContent = error.message;
  }
}

function fontLoaderLabel(status) {
  return ({
    enabled: "Detected and enabled",
    disabled: "Installed but disabled",
    "pending-install": "Pending install/reboot",
    "pending-install-or-update": "Pending install/update and reboot",
    "pending-removal": "Pending removal/reboot",
    "not-detected": "Not detected — external/optional for hidden apps",
  })[status] || "Unknown";
}

async function rebootNow() {
  if (!window.confirm("Reboot now to rebuild font mounts and Android font maps?")) return;
  showNotice("Reboot requested…");
  elements.rebootButton.disabled = true;
  try {
    await execModuleScript("reboot-device.sh");
  } catch (error) {
    showNotice(error.message || "Reboot request failed.", true);
    elements.rebootButton.disabled = false;
  }
}

async function initialize() {
  try {
    const response = await fetch("font-manifest.json", { cache: "no-store" });
    if (!response.ok) throw new Error("Could not load the font manifest.");
    manifest = await response.json();
    validateManifest(manifest);
    verifyBridge();
    await loadCustomFonts();
    renderCards();
    const status = parseResult(await execModuleScript("get-status.sh"));
    if (status.status !== "ok") throw new Error("Could not read module status.");
    if (status.active === "unknown" || optionFor(status.active)) activeId = status.active;
    if (SAFE_ID.test(status.selected) && optionFor(status.selected)) selectedId = status.selected;
    chosenId = selectedId;
    elements.fontloaderStatus.textContent = fontLoaderLabel(status.fontloader);
    elements.fontloaderGuidance.textContent = status.fontloader === "enabled"
      ? "FontLoader is active. It remains an external module and helps apps that later lose module-font access through mount-namespace hiding."
      : "On Android 12+, external FontLoader may be needed when hidden apps still see stock Noto fonts because fonts load lazily after their module mounts disappear.";
    if (status.restart_required === "unknown") {
      elements.restartBadge.textContent = "Active verification unavailable";
      elements.restartBadge.classList.remove("hidden");
      elements.restartPanel.classList.add("hidden");
    } else {
      updateRestartUi(status.restart_required === "true");
    }
    if (status.layout !== "valid") showNotice("Saved ROM font layout is invalid. Reinstall before changing fonts.", true);
    if (status.active_scope === "unavailable") showNotice("The active system font could not be verified from Android's global mount namespace. The saved selection is still shown separately.");
    const importSupported = typeof window.ksu.fileOutputStream === "function";
    elements.importButton.disabled = !importSupported;
    elements.importSupport.textContent = importSupported
      ? "KernelSU binary file import is available. Files never leave the device."
      : "Custom import needs KernelSU Next Manager v3.1.0+ file-stream support.";
    updateDisplay();
  } catch (error) {
    elements.fontList.setAttribute("aria-busy", "false");
    elements.activeFont.textContent = "Unavailable";
    elements.selectedFont.textContent = "Unavailable";
    showNotice(error.message || "WebUI initialization failed.", true);
  }
}

elements.search.addEventListener("input", filterCards);
elements.applyButton.addEventListener("click", applyChosen);
elements.rebootButton.addEventListener("click", rebootNow);
elements.laterButton.addEventListener("click", () => elements.restartPanel.classList.add("hidden"));
elements.importButton.addEventListener("click", importCustomFont);
elements.customRegular.addEventListener("change", previewImport);
elements.customBold.addEventListener("change", previewImport);

initialize();
