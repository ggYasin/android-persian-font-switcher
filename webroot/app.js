"use strict";

const MODULE_ID = "persian_font_switcher";
const MODULE_DIR = `/data/adb/modules/${MODULE_ID}`;
const DATA_DIR = "/data/adb/persian_font_switcher";
const SAFE_ID = /^[a-z0-9][a-z0-9_-]{0,31}$/;
const SAFE_TOKEN = /^[0-9a-f]{32}$/;
const SCRIPT_NAMES = new Set([
  "apply-font.sh",
  "delete-custom-font.sh",
  "get-status.sh",
  "import-font.sh",
  "list-custom-fonts.sh",
  "reboot-device.sh",
]);
const MAX_FONT_SIZE = 16 * 1024 * 1024;
/* KernelSU's Java bridge call itself is synchronous. This timer starts only
 * after that call returns, so it detects a missing/late callback without
 * racing a legitimate long-running root operation. It cannot preempt a root
 * command that blocks inside the bridge. */
const CALLBACK_DELIVERY_WATCHDOG_MS = 15000;

let manifest;
let customFonts = [];
let activeId = "unknown";
let selectedId = "system-default";
let chosenId = "system-default";
let restartState = "unknown";
let operationPending = false;
let initialized = false;
let coreReady = false;
let layoutValid = false;
let importSupported = false;
let customRegistryReady = false;
let callbackSequence = 0;
let previewSequence = 0;
let transientFontSequence = 0;
const loadedFamilies = new Map();
const loadingFamilies = new Map();
let importPreviewFaces = [];
let validatedImportPair = null;
let previewObserver;

const elements = {
  activeFont: document.querySelector("#active-font"),
  selectedFont: document.querySelector("#selected-font"),
  chosenFont: document.querySelector("#chosen-font"),
  fontloaderStatus: document.querySelector("#fontloader-status"),
  fontloaderGuidance: document.querySelector("#fontloader-guidance"),
  layoutStatus: document.querySelector("#layout-status"),
  restartBadge: document.querySelector("#restart-badge"),
  restartPanel: document.querySelector("#restart-panel"),
  notice: document.querySelector("#notice"),
  errorNotice: document.querySelector("#error-notice"),
  fontList: document.querySelector("#font-list"),
  search: document.querySelector("#font-search"),
  resultCount: document.querySelector("#result-count"),
  emptyState: document.querySelector("#empty-state"),
  refreshButton: document.querySelector("#refresh-button"),
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

function supportsCustomImport() {
  return typeof window.ksu?.fileOutputStream === "function"
    && typeof window.crypto?.getRandomValues === "function"
    && typeof window.crypto?.subtle?.digest === "function"
    && typeof File !== "undefined"
    && typeof File.prototype.arrayBuffer === "function"
    && typeof URL !== "undefined"
    && typeof URL.createObjectURL === "function"
    && typeof URL.revokeObjectURL === "function"
    && typeof TextEncoder === "function"
    && typeof TextDecoder === "function"
    && typeof FontFace === "function"
    && Boolean(document.fonts)
    && typeof window.PfsFontValidator?.validate === "function";
}

function validateScriptArgs(scriptName, args) {
  if (!SCRIPT_NAMES.has(scriptName)) return false;
  if (scriptName === "apply-font.sh") {
    const font = args.length === 1 && SAFE_ID.test(args[0]) ? optionFor(args[0]) : null;
    return Boolean(font && (!font.custom || customRegistryReady));
  }
  if (scriptName === "delete-custom-font.sh") {
    const font = args.length === 1 && SAFE_ID.test(args[0]) ? optionFor(args[0]) : null;
    return Boolean(customRegistryReady && font?.custom);
  }
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
    let settled = false;
    let timeout;
    const finish = (handler, value) => {
      if (settled) return;
      settled = true;
      if (timeout !== undefined) clearTimeout(timeout);
      delete window[callbackName];
      handler(value);
    };
    window[callbackName] = (exitCode, stdout, stderr) => {
      if (exitCode === 0) finish(resolve, stdout);
      else {
        const result = parseResult(stdout || "");
        const error = new Error(result.message || stderr || stdout || `Command failed (${exitCode}).`);
        error.code = result.code || "command-failed";
        finish(reject, error);
      }
    };
    /* Give disabled controls and progress text one frame to paint before the
     * synchronous Java bridge blocks the WebView on the root command. */
    window.requestAnimationFrame(() => {
      try {
        window.ksu.exec(command, options, callbackName);
        if (!settled) {
          timeout = setTimeout(() => {
            const error = new Error("The root command returned, but KernelSU did not deliver its callback. The outcome is unknown; refresh status before retrying.");
            error.code = "bridge-timeout";
            finish(reject, error);
          }, CALLBACK_DELIVERY_WATCHDOG_MS);
        }
      } catch (error) {
        finish(reject, error);
      }
    });
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
  customRegistryReady = false;
  try {
    const output = await execModuleScript("list-custom-fonts.sh");
    if (parseResult(output).status !== "ok") throw new Error("Custom-font registry returned an invalid response.");
    const next = [];
    for (const line of output.split(/\r?\n/)) {
      if (!line.startsWith("custom=")) continue;
      const [id, nameBase64, regularHash, boldHash] = line.slice(7).split("|");
      if (!SAFE_ID.test(id) || !id.startsWith("custom-") || !/^[0-9a-f]{64}$/.test(regularHash) || !/^[0-9a-f]{64}$/.test(boldHash)) continue;
      try {
        const name = decodeBase64Utf8(nameBase64);
        if (!name || new TextEncoder().encode(name).length > 80 || /[\u0000-\u001f\u007f]/.test(name)) continue;
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
    customRegistryReady = true;
    return next;
  } catch (error) {
    // Never leave entries from a prior successful read actionable after the
    // persistent registry becomes unavailable.
    customFonts = [];
    throw error;
  }
}

async function ensurePreviewFont(font) {
  if (font.id === "system-default" || loadedFamilies.has(font.id)) return;
  if (loadingFamilies.has(font.id)) return loadingFamilies.get(font.id);
  if (typeof FontFace !== "function" || !document.fonts) throw new Error("Font previews are unsupported by this WebView.");
  const family = `pfs-${font.id}`;
  const regular = new FontFace(family, `url("${font.previewRegular}")`, { weight: "400" });
  const bold = new FontFace(family, `url("${font.previewBold}")`, { weight: "700" });
  const loading = Promise.all([regular.load(), bold.load()])
    .then(() => {
      document.fonts.add(regular);
      document.fonts.add(bold);
      loadedFamilies.set(font.id, [regular, bold]);
    })
    .finally(() => loadingFamilies.delete(font.id));
  loadingFamilies.set(font.id, loading);
  return loading;
}

function previewLine(className, text, direction, font) {
  const line = document.createElement("p");
  line.className = className;
  line.textContent = text;
  line.dir = direction;
  if (font?.id && font.id !== "system-default") line.style.fontFamily = `"pfs-${font.id}", sans-serif`;
  return line;
}

function mixedPreviewLine(font) {
  const line = document.createElement("p");
  line.className = "preview-digits";
  line.dir = "auto";
  const persian = document.createElement("span");
  persian.textContent = "۱۲۳۴۵۶۷۸۹۰ · فارسی";
  if (font.id !== "system-default") persian.style.fontFamily = `"pfs-${font.id}", sans-serif`;
  const latin = document.createElement("span");
  latin.className = "system-latin";
  latin.textContent = " · 1234567890 · English";
  line.append(persian, latin);
  return line;
}

function handleChoiceKey(event) {
  const choice = event.currentTarget;
  if (event.key === "Enter" || event.key === " ") {
    event.preventDefault();
    chooseFont(choice.dataset.fontId);
    return;
  }
  const choices = [...elements.fontList.querySelectorAll(".card-choice")]
    .filter((candidate) => !candidate.closest(".font-card").classList.contains("filtered"));
  if (!choices.length) return;
  const current = choices.indexOf(choice);
  let next = -1;
  if (event.key === "ArrowDown" || event.key === "ArrowRight") next = (current + 1) % choices.length;
  if (event.key === "ArrowUp" || event.key === "ArrowLeft") next = (current - 1 + choices.length) % choices.length;
  if (event.key === "Home") next = 0;
  if (event.key === "End") next = choices.length - 1;
  if (next >= 0) {
    event.preventDefault();
    chooseFont(choices[next].dataset.fontId);
    choices[next].focus();
  }
}

function observePreview(card, font) {
  if (font.id === "system-default") return;
  const load = () => ensurePreviewFont(font).catch(() => card.classList.add("preview-error"));
  if (typeof IntersectionObserver !== "function") {
    load();
    return;
  }
  if (!previewObserver) {
    const observer = new IntersectionObserver((entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue;
        observer.unobserve(entry.target);
        const observedFont = optionFor(entry.target.dataset.fontId);
        if (observedFont) ensurePreviewFont(observedFont).catch(() => entry.target.classList.add("preview-error"));
      }
    }, { rootMargin: "320px 0px" });
    previewObserver = observer;
  }
  previewObserver.observe(card);
}

function createFontCard(font) {
  const card = document.createElement("article");
  card.className = "font-card";
  card.dataset.fontId = font.id;
  const choice = document.createElement("div");
  choice.className = "card-choice";
  choice.dataset.fontId = font.id;
  choice.tabIndex = -1;
  choice.setAttribute("role", "radio");
  choice.addEventListener("click", () => chooseFont(font.id));
  choice.addEventListener("keydown", handleChoiceKey);

  const header = document.createElement("div");
  header.className = "card-header";
  const titleGroup = document.createElement("div");
  const title = document.createElement("h3");
  title.className = "font-name";
  title.id = `font-title-${font.id}`;
  title.textContent = font.name;
  choice.setAttribute("aria-labelledby", title.id);
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
  previews.append(
    previewLine("preview-regular", "سلام، حال شما چطور است؟", "rtl", font),
    previewLine("preview-bold", "این یک متن نمونه برای نمایش فونت فارسی است.", "rtl", font),
    previewLine("preview-regular", "می‌روم، خانه‌ها، برنامه‌نویسی", "rtl", font),
    mixedPreviewLine(font),
  );
  if (font.id === "system-default") {
    const note = document.createElement("small");
    note.className = "preview-note";
    note.textContent = "Rendered by the current WebView; the ROM fallback is restored after reboot.";
    previews.append(note);
  }

  const choose = document.createElement("span");
  choose.className = "select-action";
  choose.textContent = "Choose";
  choice.append(header, previews, choose);
  card.append(choice);
  if (font.custom) {
    const remove = document.createElement("button");
    remove.type = "button";
    remove.className = "remove-font-button";
    remove.textContent = "Remove custom font";
    remove.setAttribute("aria-label", `Remove custom font ${font.name}`);
    remove.addEventListener("click", () => removeCustomFont(font));
    card.append(remove);
  }
  observePreview(card, font);
  return card;
}

function renderCards() {
  if (previewObserver) previewObserver.disconnect();
  previewObserver = undefined;
  elements.fontList.replaceChildren(...allOptions().map(createFontCard));
  elements.fontList.setAttribute("aria-busy", "false");
  filterCards();
  updateDisplay();
}

function chooseFont(id) {
  const font = optionFor(id);
  if (operationPending || !initialized || !layoutValid || !font || (font.custom && !customRegistryReady)) return;
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
    const choice = card.querySelector(".card-choice");
    choice.setAttribute("aria-checked", String(chosen));
    choice.setAttribute("aria-disabled", String(operationPending || !initialized || !layoutValid));
    const marks = card.querySelector(".card-marks");
    marks.replaceChildren();
    if (id === activeId) marks.append(makeMark("Active", "active-mark"));
    if (id === selectedId) marks.append(makeMark("Selected", "selected-mark"));
    const action = card.querySelector(".select-action");
    action.textContent = chosen ? "Chosen" : "Choose";
    const remove = card.querySelector(".remove-font-button");
    if (remove) {
      const removalUnverified = activeId === "unknown" || restartState !== "false";
      const registryUnavailable = !customRegistryReady;
      remove.disabled = operationPending || !initialized || registryUnavailable || removalUnverified || id === selectedId || id === activeId;
      remove.title = registryUnavailable
        ? "Custom-font registry unavailable; refresh before removing a font."
        : removalUnverified || id === selectedId || id === activeId
          ? "Switch away, reboot, and refresh until Active and Selected match before removing this font."
          : "";
    }
  }
  updateRovingTabindex();
  syncControls();
}

function makeMark(text, className) {
  const mark = document.createElement("span");
  mark.className = className;
  mark.textContent = text;
  return mark;
}

function filterCards() {
  const query = elements.search.value.trim().toLocaleLowerCase();
  let visible = 0;
  for (const card of elements.fontList.querySelectorAll(".font-card")) {
    const font = optionFor(card.dataset.fontId);
    const haystack = `${font.name} ${font.author || ""} ${font.variant || ""}`.toLocaleLowerCase();
    const filtered = Boolean(query) && !haystack.includes(query);
    card.classList.toggle("filtered", filtered);
    if (!filtered) visible += 1;
  }
  elements.resultCount.textContent = `${visible} font${visible === 1 ? "" : "s"}`;
  elements.emptyState.classList.toggle("hidden", visible !== 0);
  updateRovingTabindex();
}

function updateRovingTabindex() {
  const visible = [...elements.fontList.querySelectorAll(".font-card:not(.filtered) .card-choice")];
  const preferred = visible.find((choice) => choice.dataset.fontId === chosenId) || visible[0];
  for (const choice of elements.fontList.querySelectorAll(".card-choice")) {
    choice.tabIndex = choice === preferred ? 0 : -1;
  }
}

function syncControls() {
  const mutationsAllowed = initialized && layoutValid && !operationPending;
  const chosen = coreReady ? optionFor(chosenId) : null;
  const customChoiceReady = !chosen?.custom || customRegistryReady;
  const currentPairValidated = Boolean(
    validatedImportPair
    && validatedImportPair.regularFile === elements.customRegular.files[0]
    && validatedImportPair.boldFile === elements.customBold.files[0]
  );
  elements.applyButton.disabled = !mutationsAllowed || !chosen || !customChoiceReady || chosenId === selectedId;
  elements.importButton.disabled = !mutationsAllowed || !importSupported || !customRegistryReady || !currentPairValidated;
  elements.refreshButton.disabled = operationPending;
  elements.rebootButton.disabled = operationPending || !initialized;
  const customInputsDisabled = operationPending || !importSupported || !customRegistryReady;
  elements.customName.disabled = customInputsDisabled;
  elements.customRegular.disabled = customInputsDisabled;
  elements.customBold.disabled = customInputsDisabled;
  elements.fontList.setAttribute("aria-busy", String(operationPending));
}

function showNotice(message, isError = false) {
  const target = isError ? elements.errorNotice : elements.notice;
  const other = isError ? elements.notice : elements.errorNotice;
  other.textContent = "";
  other.classList.add("hidden");
  target.textContent = message;
  target.classList.remove("hidden");
}

function updateRestartUi(required) {
  elements.restartBadge.textContent = "Restart required";
  elements.restartBadge.classList.toggle("hidden", !required);
  elements.restartPanel.classList.toggle("hidden", !required);
}

async function applyChosen() {
  const chosen = optionFor(chosenId);
  if (operationPending || chosenId === selectedId || !chosen || (chosen.custom && !customRegistryReady)) return;
  operationPending = true;
  updateDisplay();
  elements.applyButton.textContent = "Applying…";
  let applyError;
  try {
    const result = parseResult(await execModuleScript("apply-font.sh", [chosenId]));
    if (result.status !== "ok" || result.selected !== chosenId) throw new Error(result.message || "Selection rejected.");
  } catch (error) {
    applyError = error;
  }
  try {
    await refreshStatus({ preserveChoice: true });
    if (selectedId === chosenId) {
      if (restartState === "true") {
        showNotice("Font selected successfully. Reboot is required to rebuild overlays and process font maps.");
        if (typeof window.ksu.toast === "function") window.ksu.toast("Font selected. Reboot required.");
      } else if (restartState === "false") {
        showNotice("Selection now matches the active font. No restart is required.");
        if (typeof window.ksu.toast === "function") window.ksu.toast("Selection matches the active font.");
      } else {
        showNotice("Font selected, but the active system mount could not be verified. Reboot before relying on the change, then refresh status.");
        if (typeof window.ksu.toast === "function") window.ksu.toast("Font selected; active state is unverified.");
      }
    } else if (applyError) {
      showNotice(applyError.message || "Could not apply the selected font.", true);
    } else {
      showNotice("The operation returned, but the authoritative selected state did not change. Refresh and retry.", true);
    }
  } catch (statusError) {
    const message = applyError?.message || "The selection command returned, but status could not be verified.";
    showNotice(`${message} Use Refresh status before retrying.`, true);
  } finally {
    operationPending = false;
    elements.applyButton.textContent = "Apply selection";
    updateDisplay();
  }
}

async function validateFontFile(file, expectedWeight) {
  if (!file || file.size < 256 || file.size > MAX_FONT_SIZE) throw new Error("Each font must be between 256 bytes and 16 MiB.");
  const buffer = await file.arrayBuffer();
  window.PfsFontValidator.validate(buffer, expectedWeight);
  return buffer;
}

async function loadRenderableFontPair(regularFile, boldFile) {
  const family = `pfs-import-${Date.now()}-${++transientFontSequence}`;
  const urls = [];
  try {
    const regularUrl = URL.createObjectURL(regularFile);
    urls.push(regularUrl);
    const boldUrl = URL.createObjectURL(boldFile);
    urls.push(boldUrl);
    const regularFace = new FontFace(family, `url("${regularUrl}")`, { weight: "400" });
    const boldFace = new FontFace(family, `url("${boldUrl}")`, { weight: "700" });
    await Promise.all([regularFace.load(), boldFace.load()]);
    return { family, faces: [regularFace, boldFace] };
  } catch (_) {
    throw new Error("The selected files could not be parsed by Android WebView as usable fonts.");
  } finally {
    for (const url of urls) URL.revokeObjectURL(url);
  }
}

async function validateRenderableFontPair(regularFile, boldFile) {
  const [regularBuffer, boldBuffer] = await Promise.all([
    validateFontFile(regularFile, "regular"),
    validateFontFile(boldFile, "bold"),
  ]);
  const rendered = await loadRenderableFontPair(regularFile, boldFile);
  return { regularBuffer, boldBuffer, ...rendered };
}

function customFontMatchesExpected(font, expected) {
  return Boolean(
    font?.custom
    && font.id === expected.id
    && font.name === expected.name
    && font.sha256Regular === expected.regularHash
    && font.sha256Bold === expected.boldHash
  );
}

function bytesToBase64(bytes) {
  let binary = "";
  for (let offset = 0; offset < bytes.length; offset += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
  }
  return btoa(binary);
}

function randomToken() {
  const bytes = window.crypto.getRandomValues(new Uint8Array(16));
  return Array.from(bytes, (value) => value.toString(16).padStart(2, "0")).join("");
}

async function sha256Hex(buffer) {
  const digest = new Uint8Array(await window.crypto.subtle.digest("SHA-256", buffer));
  return Array.from(digest, (value) => value.toString(16).padStart(2, "0")).join("");
}

async function writeBuffer(stream, path, buffer) {
  const id = stream.open(path, false);
  if (!id) throw new Error("Could not open privileged import staging.");
  try {
    const bytes = new Uint8Array(buffer);
    for (let offset = 0; offset < bytes.length; offset += 192 * 1024) {
      if (!stream.write(id, bytesToBase64(bytes.subarray(offset, offset + 192 * 1024)))) throw new Error("Custom font transfer failed.");
      if (offset > 0 && offset % (1536 * 1024) === 0) {
        await new Promise((resolve) => setTimeout(resolve, 0));
      }
    }
    if (!stream.flush(id)) throw new Error("Custom font transfer could not be flushed.");
  } finally {
    stream.close(id);
  }
}

async function importCustomFont() {
  if (operationPending) return;
  if (!importSupported) {
    showNotice("Custom import requires KernelSU Next Manager v3.1.0 or newer.", true);
    return;
  }
  if (!customRegistryReady) {
    showNotice("Refresh the custom-font registry before importing a font.", true);
    return;
  }
  const regularFile = elements.customRegular.files[0];
  const boldFile = elements.customBold.files[0];
  if (!validatedImportPair
      || validatedImportPair.regularFile !== regularFile
      || validatedImportPair.boldFile !== boldFile) {
    showNotice("Wait for both selected files to pass local parsing and renderability checks before importing.", true);
    return;
  }
  const name = elements.customName.value.trim().normalize("NFC");
  const nameBytes = new TextEncoder().encode(name);
  if (!name || nameBytes.length > 80 || /[\u0000-\u001f\u007f]/.test(name)) {
    showNotice("Enter a display name of at most 80 UTF-8 bytes without control characters.", true);
    return;
  }

  operationPending = true;
  syncControls();
  elements.importButton.textContent = "Validating and importing…";
  let token;
  let expected;
  let finishAttempted = false;
  let finishReportedSuccess = false;
  let matchedBefore = false;
  try {
    // Repeat both checks on the exact captured File objects. Preview state is a
    // UI gate, not authorization for a stale or programmatically changed pair.
    const { regularBuffer, boldBuffer } = await validateRenderableFontPair(regularFile, boldFile);
    const [regularHash, boldHash] = await Promise.all([sha256Hex(regularBuffer), sha256Hex(boldBuffer)]);
    expected = {
      id: `custom-${regularHash.slice(0, 12)}${boldHash.slice(0, 12)}`,
      name,
      regularHash,
      boldHash,
    };
    matchedBefore = customFontMatchesExpected(optionFor(expected.id), expected);
    token = randomToken();
    await execModuleScript("import-font.sh", ["begin", token]);
    const stream = window.ksu.fileOutputStream();
    if (!stream || ["open", "write", "flush", "close"].some((method) => typeof stream[method] !== "function")) {
      throw new Error("KernelSU returned an incompatible binary file stream.");
    }
    const importRoot = `${DATA_DIR}/staging/${token}`;
    elements.importButton.textContent = "Transferring Regular…";
    await writeBuffer(stream, `${importRoot}/regular.ttf`, regularBuffer);
    elements.importButton.textContent = "Transferring Bold…";
    await writeBuffer(stream, `${importRoot}/bold.ttf`, boldBuffer);
    const encodedName = bytesToBase64(nameBytes);
    await writeBuffer(stream, `${importRoot}/name.b64`, new TextEncoder().encode(encodedName).buffer);
    await writeBuffer(stream, `${importRoot}/regular.expected.sha256`, new TextEncoder().encode(`${regularHash}\n`).buffer);
    await writeBuffer(stream, `${importRoot}/bold.expected.sha256`, new TextEncoder().encode(`${boldHash}\n`).buffer);
    elements.importButton.textContent = "Persisting…";
    finishAttempted = true;
    const result = parseResult(await execModuleScript("import-font.sh", ["finish", token]));
    if (result.status !== "ok"
        || result.id !== expected.id
        || result.regular_sha256 !== expected.regularHash
        || result.bold_sha256 !== expected.boldHash) {
      throw new Error(result.message || "Custom import returned an invalid result.");
    }
    finishReportedSuccess = true;
    await loadCustomFonts();
    if (!customFontMatchesExpected(optionFor(expected.id), expected)) {
      const error = new Error("The custom-font registry does not match the requested name and file hashes.");
      error.code = "registry-postcondition";
      throw error;
    }
    renderCards();
    chosenId = expected.id;
    clearImportForm();
    updateDisplay();
    showNotice(result.import_result === "updated-existing"
      ? "The existing custom font was verified and its display name was updated. Review it, then apply the selection."
      : "Custom font imported. Review its preview, then apply the selection.");
  } catch (error) {
    if (token && SAFE_TOKEN.test(token) && !finishReportedSuccess && error.code !== "bridge-timeout") {
      try {
        await execModuleScript("import-font.sh", ["cancel", token]);
      } catch (_) {
        // The original error remains authoritative; stale stages are pruned by
        // a later begin operation.
      }
    }
    let handled = false;
    if (error.code === "bridge-timeout" && expected && finishAttempted) {
      try {
        await loadCustomFonts();
        renderCards();
        if (customFontMatchesExpected(optionFor(expected.id), expected)) {
          chosenId = expected.id;
          clearImportForm();
          handled = true;
          showNotice(matchedBefore
            ? "The callback was late; the requested custom font was already present and remains verified."
            : "The callback was late, but the requested name and both file hashes are present in the registry. Review the font, then apply it.");
        }
      } catch (_) {
        renderCards();
      }
    }
    if (!handled && finishReportedSuccess) {
      renderCards();
      const message = error.code === "registry-postcondition"
        ? error.message
        : "The font was persisted, but the custom-font registry could not be refreshed.";
      showNotice(`${message} Refresh and verify the exact name and hashes before retrying.`, true);
      handled = true;
    }
    if (!handled) showNotice(error.message || "Custom font import failed.", true);
  } finally {
    operationPending = false;
    elements.importButton.textContent = "Validate and import";
    updateDisplay();
  }
}

function clearImportForm() {
  previewSequence += 1;
  validatedImportPair = null;
  elements.customName.value = "";
  elements.customRegular.value = "";
  elements.customBold.value = "";
  elements.customPreview.classList.add("hidden");
  for (const previous of importPreviewFaces) document.fonts.delete(previous);
  importPreviewFaces = [];
}

async function removeCustomFont(font) {
  if (operationPending || !customRegistryReady || !font?.custom) return;
  if (activeId === "unknown" || restartState !== "false" || font.id === selectedId || font.id === activeId) {
    showNotice("Switch away, reboot, and refresh until Active and Selected match before removing this custom font.", true);
    return;
  }
  if (!window.confirm(`Remove “${font.name}” from persistent custom-font storage? The original cannot be restored by this WebUI; module-local preview cleanup is best-effort.`)) return;
  operationPending = true;
  updateDisplay();
  let commandError;
  try {
    const result = parseResult(await execModuleScript("delete-custom-font.sh", [font.id]));
    if (result.status !== "ok" || result.removed !== font.id) throw new Error(result.message || "Custom font removal was rejected.");
  } catch (error) {
    commandError = error;
  }

  try {
    await loadCustomFonts();
    if (!optionFor(font.id)) {
      for (const face of loadedFamilies.get(font.id) || []) document.fonts.delete(face);
      loadedFamilies.delete(font.id);
      loadingFamilies.delete(font.id);
      if (chosenId === font.id) chosenId = selectedId;
      renderCards();
      showNotice(commandError
        ? "The command result was late or unsuccessful, but a fresh registry read confirms the persistent custom font is absent. Module-local preview cleanup is best-effort and will be retried on refresh or update."
        : "Persistent custom font removed. Module-local preview cleanup is best-effort and will be retried on refresh or update if needed.");
    } else {
      renderCards();
      showNotice(commandError?.message || "The removal command returned, but the custom font remains in the authoritative registry.", true);
    }
  } catch (registryError) {
    if (!optionFor(chosenId)) chosenId = selectedId;
    renderCards();
    const commandMessage = commandError?.message || "The removal command returned.";
    showNotice(`${commandMessage} The custom-font registry could not verify the outcome; refresh before retrying.`, true);
  } finally {
    operationPending = false;
    updateDisplay();
  }
}

async function previewImport() {
  const sequence = ++previewSequence;
  const regularFile = elements.customRegular.files[0];
  const boldFile = elements.customBold.files[0];
  validatedImportPair = null;
  for (const previous of importPreviewFaces) document.fonts.delete(previous);
  importPreviewFaces = [];
  elements.customPreview.classList.add("hidden");
  syncControls();
  if (!regularFile || !boldFile) {
    elements.importSupport.textContent = "Choose both Regular and Bold files to validate their structure and renderability.";
    return;
  }
  elements.importSupport.textContent = "Validating the exact selected file pair…";
  try {
    const { family, faces } = await validateRenderableFontPair(regularFile, boldFile);
    if (sequence !== previewSequence
        || elements.customRegular.files[0] !== regularFile
        || elements.customBold.files[0] !== boldFile) return;
    importPreviewFaces = faces;
    for (const face of importPreviewFaces) document.fonts.add(face);
    validatedImportPair = { regularFile, boldFile };
    elements.customPreview.style.fontFamily = `"${family}", sans-serif`;
    elements.customPreview.classList.remove("hidden");
    elements.importSupport.textContent = "Regular and Bold passed local SFNT, shaping-table, weight, Persian coverage, and WebView renderability checks.";
    syncControls();
  } catch (error) {
    if (sequence !== previewSequence) return;
    validatedImportPair = null;
    elements.importSupport.textContent = error.message;
    syncControls();
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
  if (operationPending || !initialized) return;
  if (!window.confirm("Reboot now to rebuild font mounts and Android font maps?")) return;
  operationPending = true;
  updateDisplay();
  showNotice("Reboot requested…");
  try {
    await execModuleScript("reboot-device.sh");
  } catch (error) {
    showNotice(error.message || "Reboot request failed.", true);
  } finally {
    operationPending = false;
    updateDisplay();
  }
}

async function refreshStatus({ preserveChoice = true, announce = false } = {}) {
  const status = parseResult(await execModuleScript("get-status.sh"));
  if (status.status !== "ok") throw new Error("Could not read module status.");
  if (status.active === "unknown" || SAFE_ID.test(status.active)) activeId = status.active;
  if (SAFE_ID.test(status.selected)) selectedId = status.selected;
  if (!preserveChoice || !optionFor(chosenId)) chosenId = selectedId;
  restartState = new Set(["true", "false", "unknown"]).has(status.restart_required)
    ? status.restart_required : "unknown";
  layoutValid = status.layout === "valid";
  elements.layoutStatus.textContent = layoutValid ? "Verified four-file AOSP layout" : "Invalid — reinstall required";
  elements.fontloaderStatus.textContent = fontLoaderLabel(status.fontloader);
  elements.fontloaderGuidance.textContent = status.fontloader === "enabled"
    ? "FontLoader is active. It remains an external module and helps apps that later lose module-font access through mount-namespace hiding."
    : "On Android 12+, external FontLoader may be needed when hidden apps still see stock Noto fonts because fonts load lazily after their module mounts disappear.";
  if (restartState === "unknown") {
    elements.restartBadge.textContent = "Active verification unavailable";
    elements.restartBadge.classList.remove("hidden");
    elements.restartPanel.classList.add("hidden");
  } else {
    updateRestartUi(restartState === "true");
  }
  const warnings = [];
  if (!layoutValid) warnings.push("Saved ROM font layout is invalid. Reinstall before changing fonts.");
  if (status.active_scope === "unavailable") warnings.push("The active system font could not be verified from Android's global mount namespace; selected state is shown separately.");
  if (announce) showNotice(warnings.length ? warnings.join(" ") : "Status refreshed from the effective system mount.", !layoutValid);
  updateDisplay();
  return { status, warnings };
}

async function refreshFromUi() {
  if (operationPending) return;
  await initialize({ preserveChoice: true, announce: true });
}

async function initialize({ preserveChoice = false, announce = false } = {}) {
  if (operationPending) return;
  operationPending = true;
  elements.refreshButton.textContent = announce ? "Refreshing…" : "Loading…";
  syncControls();
  try {
    verifyBridge();
    if (!coreReady) {
      const response = await fetch("font-manifest.json", { cache: "no-store" });
      if (!response.ok) throw new Error("Could not load the font manifest.");
      manifest = await response.json();
      validateManifest(manifest);
      coreReady = true;
    }

    let customWarning = "";
    try {
      await loadCustomFonts();
    } catch (error) {
      customWarning = `Custom-font registry unavailable (${error.message || "temporary error"}); bundled fonts remain usable.`;
    }
    renderCards();
    const { warnings } = await refreshStatus({ preserveChoice });
    if (!preserveChoice || !optionFor(chosenId)) chosenId = selectedId;
    importSupported = supportsCustomImport();
    elements.importSupport.textContent = importSupported
      ? "KernelSU binary file import is available. Files never leave the device."
      : "Custom import needs KernelSU Next Manager v3.1.0+ and a current Android System WebView.";
    initialized = true;
    const combinedWarnings = [...warnings];
    if (customWarning) combinedWarnings.push(customWarning);
    if (combinedWarnings.length) showNotice(combinedWarnings.join(" "), !layoutValid);
    else if (announce) showNotice("Status and custom-font registry refreshed.");
    updateDisplay();
  } catch (error) {
    initialized = false;
    layoutValid = false;
    elements.fontList.setAttribute("aria-busy", "false");
    elements.layoutStatus.textContent = "Verification unavailable";
    if (!coreReady) {
      elements.activeFont.textContent = "Unavailable";
      elements.selectedFont.textContent = "Unavailable";
    }
    showNotice(error.message || "WebUI initialization failed.", true);
  } finally {
    operationPending = false;
    elements.refreshButton.textContent = "Refresh status";
    syncControls();
  }
}

elements.search.addEventListener("input", filterCards);
elements.applyButton.addEventListener("click", applyChosen);
elements.refreshButton.addEventListener("click", refreshFromUi);
elements.rebootButton.addEventListener("click", rebootNow);
elements.laterButton.addEventListener("click", () => elements.restartPanel.classList.add("hidden"));
elements.importButton.addEventListener("click", importCustomFont);
elements.customRegular.addEventListener("change", previewImport);
elements.customBold.addEventListener("change", previewImport);

initialize();
