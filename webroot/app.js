"use strict";

const MODULE_ID = "persian_font_switcher";
const MODULE_DIR = `/data/adb/modules/${MODULE_ID}`;
const SAFE_ID = /^[a-z0-9][a-z0-9_-]{0,31}$/;
const SCRIPT_NAMES = new Set(["apply-font.sh", "get-status.sh"]);

let manifest;
let selectedId = "system-default";
let operationPending = false;
let callbackSequence = 0;

const elements = {
  currentFont: document.querySelector("#current-font"),
  rebootBadge: document.querySelector("#reboot-badge"),
  notice: document.querySelector("#notice"),
  fontList: document.querySelector("#font-list"),
};

function allOptions() {
  return [manifest.systemDefault, ...manifest.fonts];
}

function optionFor(id) {
  return allOptions().find((font) => font.id === id);
}

function validateManifest(data) {
  if (!data || data.schema !== 1 || !Array.isArray(data.fonts)) {
    throw new Error("Unsupported font manifest.");
  }

  const ids = new Set([data.systemDefault?.id]);
  if (data.systemDefault?.id !== "system-default") {
    throw new Error("System Default is missing from the manifest.");
  }

  for (const font of data.fonts) {
    if (!SAFE_ID.test(font.id) || ids.has(font.id)) {
      throw new Error("The font manifest contains an unsafe or duplicate ID.");
    }
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

function execModuleScript(scriptName, args = []) {
  if (!SCRIPT_NAMES.has(scriptName)) {
    return Promise.reject(new Error("Script is not allowlisted."));
  }
  if (!args.every((arg) => SAFE_ID.test(arg) && optionFor(arg))) {
    return Promise.reject(new Error("Font ID is not allowlisted."));
  }

  const command = [`'${MODULE_DIR}/scripts/${scriptName}'`, ...args.map((arg) => `'${arg}'`)].join(" ");
  const callbackName = `pfsCallback${++callbackSequence}`;

  return new Promise((resolve, reject) => {
    window[callbackName] = (exitCode, stdout, stderr) => {
      delete window[callbackName];
      if (exitCode === 0) {
        resolve(stdout);
      } else {
        reject(new Error(stderr || stdout || `Command failed (${exitCode}).`));
      }
    };

    try {
      window.ksu.exec(command, callbackName);
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
    if (separator > 0) {
      result[line.slice(0, separator)] = line.slice(separator + 1);
    }
  }
  return result;
}

function textElement(className, text, direction) {
  const element = document.createElement("p");
  element.className = className;
  element.textContent = text;
  if (direction) element.dir = direction;
  return element;
}

function mixedElement(className, leading, candidate, trailing, font) {
  const element = document.createElement("p");
  element.className = className;
  element.dir = "auto";
  element.append(document.createTextNode(leading));
  const candidateSpan = document.createElement("span");
  candidateSpan.textContent = candidate;
  if (font.id !== "system-default") {
    candidateSpan.classList.add(`font-${font.id}`);
  }
  element.append(candidateSpan, document.createTextNode(trailing));
  return element;
}

function createFontCard(font) {
  const card = document.createElement("article");
  card.className = "font-card";
  card.dataset.fontId = font.id;

  const header = document.createElement("div");
  header.className = "card-header";
  const titleGroup = document.createElement("div");
  const title = document.createElement("h3");
  title.className = "font-name";
  title.textContent = font.name;
  const meta = document.createElement("div");
  meta.className = "font-meta";
  meta.textContent = font.id === "system-default"
    ? "ROM-provided fallback"
    : `${font.version} · ${font.author} · ${font.license}`;
  const description = document.createElement("p");
  description.className = "font-description";
  description.textContent = font.description;
  titleGroup.append(title, meta, description);
  const selectedMark = document.createElement("span");
  selectedMark.className = "selected-mark";
  selectedMark.textContent = "Selected";
  header.append(titleGroup, selectedMark);

  const previews = document.createElement("div");
  previews.className = "previews";
  previews.lang = "fa";
  if (font.id !== "system-default") {
    previews.classList.add(`font-${font.id}`);
  }
  previews.append(
    textElement("preview-regular", "سلام، حال شما چطور است؟", "rtl"),
    textElement("preview-bold", "این یک متن نمونه برای نمایش فونت فارسی است.", "rtl"),
    textElement("preview-regular", "می‌روم، خانه‌ها، برنامه‌نویسی", "rtl"),
    mixedElement("preview-digits", "", "۱۲۳۴۵۶۷۸۹۰", " · 1234567890", font),
    mixedElement("preview-mixed", "English + ", "فارسی", " mixed text", font),
  );

  const button = document.createElement("button");
  button.className = "select-button";
  button.type = "button";
  button.dataset.fontId = font.id;
  button.addEventListener("click", () => applySelection(font.id));

  card.append(header, previews, button);
  return card;
}

function renderCards() {
  elements.fontList.replaceChildren(...allOptions().map(createFontCard));
  elements.fontList.setAttribute("aria-busy", "false");
  updateSelectionDisplay();
}

function updateSelectionDisplay() {
  const selected = optionFor(selectedId) || manifest.systemDefault;
  elements.currentFont.textContent = selected.name;

  for (const card of elements.fontList.querySelectorAll(".font-card")) {
    const isSelected = card.dataset.fontId === selectedId;
    card.classList.toggle("selected", isSelected);
    const mark = card.querySelector(".selected-mark");
    const button = card.querySelector(".select-button");
    mark.classList.toggle("hidden", !isSelected);
    button.disabled = isSelected || operationPending;
    button.textContent = isSelected ? "Selected" : operationPending ? "Please wait…" : `Use ${card.querySelector(".font-name").textContent}`;
  }
}

function showNotice(message, isError = false) {
  elements.notice.textContent = message;
  elements.notice.classList.toggle("error", isError);
  elements.notice.classList.remove("hidden");
}

async function applySelection(id) {
  if (operationPending || !SAFE_ID.test(id) || !optionFor(id)) return;
  operationPending = true;
  updateSelectionDisplay();

  try {
    const result = parseResult(await execModuleScript("apply-font.sh", [id]));
    if (result.status !== "ok" || result.selected !== id) {
      throw new Error(result.message || "The module rejected the selection.");
    }
    selectedId = id;
    elements.rebootBadge.classList.remove("hidden");
    showNotice(result.message || "Font selected successfully. Reboot required to apply system-wide.");
    if (typeof window.ksu.toast === "function") {
      window.ksu.toast("Font selected. Reboot required.");
    }
  } catch (error) {
    showNotice(error.message || "Could not apply the selected font.", true);
  } finally {
    operationPending = false;
    updateSelectionDisplay();
  }
}

async function initialize() {
  try {
    const response = await fetch("font-manifest.json", { cache: "no-store" });
    if (!response.ok) throw new Error("Could not load the font manifest.");
    manifest = await response.json();
    validateManifest(manifest);
    verifyBridge();
    renderCards();

    const status = parseResult(await execModuleScript("get-status.sh"));
    if (status.status !== "ok") throw new Error("Could not read module status.");
    if (SAFE_ID.test(status.selected) && optionFor(status.selected)) {
      selectedId = status.selected;
    }
    elements.rebootBadge.classList.toggle("hidden", status.reboot_required !== "true");
    if (status.layout !== "valid") {
      showNotice("The saved ROM font layout is invalid. Reinstall the module before changing fonts.", true);
    }
    updateSelectionDisplay();
  } catch (error) {
    elements.fontList.setAttribute("aria-busy", "false");
    elements.currentFont.textContent = "Unavailable";
    showNotice(error.message || "WebUI initialization failed.", true);
  }
}

initialize();
