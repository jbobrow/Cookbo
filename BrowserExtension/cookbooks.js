// Where recipes go: each cookbook's folder in iCloud Drive › Cookbo › Cookbooks,
// the same files the app reads (see CookbookFolders.swift).
//
// Chrome writes there itself, through a folder picked once on the options page
// (the File System Access API). Safari has no such API, so it hands the files
// to the extension's native half inside the Cookbo app, which writes them into
// Cookbo's iCloud container (SafariExtension/SafariWebExtensionHandler.swift).

export const api = globalThis.browser ?? globalThis.chrome;

export const usesNativeApp = !('showDirectoryPicker' in globalThis);

/** Thrown when Chrome has no folder yet, or has lost permission to it. */
export class NeedsFolder extends Error {}

/** The cookbooks to choose from, as `{id, name}`, newest first. */
export async function listCookbooks() {
  if (usesNativeApp) {
    const reply = await native({ action: 'cookbooks' });
    return reply.cookbooks;
  }

  const folder = await savedFolder();
  if (!folder) throw new NeedsFolder();
  // Opening the popup isn't a click, so permission can't be asked for here.
  // Show the cookbooks found last time; Save asks again if it needs to.
  if ((await folder.queryPermission({ mode: 'readwrite' })) !== 'granted') {
    const { cookbooks } = await api.storage.local.get('cookbooks');
    if (cookbooks?.length) return cookbooks;
    throw new NeedsFolder();
  }
  return remember(await cookbooksIn(folder));
}

/**
 * Saves a recipe's Markdown, and its photo if it has one, into a cookbook.
 * Call it straight from a click: Chrome may need to ask for the folder again.
 */
export async function saveRecipe({ cookbookID, fileName, markdown, imageName, imageURL }) {
  if (usesNativeApp) {
    await native({ action: 'save', cookbookID, fileName, markdown, imageName, imageURL });
    return;
  }

  const folder = await savedFolder();
  if (!folder || (await folder.requestPermission({ mode: 'readwrite' })) !== 'granted') {
    throw new NeedsFolder();
  }
  const cookbook = (await cookbooksIn(folder)).find((c) => c.id === cookbookID);
  if (!cookbook) throw new Error('That cookbook isn’t in the Cookbo folder anymore.');

  // The photo goes first, so the app never finds the recipe before its picture
  if (imageName && imageURL) {
    const jpeg = await jpegFrom(imageURL).catch(() => null);
    if (jpeg) {
      await writeFile(await cookbook.handle.getDirectoryHandle('Images', { create: true }), imageName, jpeg);
    } else {
      markdown = markdown.replace(`\nimageName: ${imageName}\n`, '\n');
    }
  }
  await writeFile(await cookbook.handle.getDirectoryHandle('Recipes', { create: true }), fileName, markdown);
}

// MARK: - Safari

async function native(message) {
  // Safari ignores the application id and always talks to the containing app
  const reply = await api.runtime.sendNativeMessage('com.jonbobrow.Cookbook', message);
  if (!reply || reply.error) throw new Error(reply?.error ?? 'Cookbo didn’t answer.');
  return reply;
}

// MARK: - Chrome

/**
 * The cookbooks in a folder someone picked. Accepts the Cookbo folder itself,
 * its Cookbooks folder, or a single cookbook's folder.
 */
export async function cookbooksIn(folder) {
  const own = await readCookbook(folder);
  if (own) return [own];

  let base = folder;
  try {
    base = await folder.getDirectoryHandle('Cookbooks');
  } catch {
    // Already inside Cookbooks
  }

  const found = [];
  for await (const entry of base.values()) {
    if (entry.kind !== 'directory') continue;
    const cookbook = await readCookbook(entry);
    if (cookbook) found.push(cookbook);
  }
  return found.sort((a, b) => b.dateModified - a.dateModified);
}

async function readCookbook(folder) {
  try {
    const file = await (await folder.getFileHandle('cookbook.json')).getFile();
    const { id, name, dateModified = 0 } = JSON.parse(await file.text());
    return typeof id === 'string' && typeof name === 'string' ? { id, name, dateModified, handle: folder } : null;
  } catch {
    return null;
  }
}

/** Keeps the list for next time the popup opens without permission. */
async function remember(cookbooks) {
  await api.storage.local.set({ cookbooks: cookbooks.map(({ id, name }) => ({ id, name })) });
  return cookbooks;
}

async function writeFile(folder, name, contents) {
  const writable = await (await folder.getFileHandle(name, { create: true })).createWritable();
  await writable.write(contents);
  await writable.close();
}

/** The recipe's photo as a JPEG, as the app stores it, no bigger than it needs to be. */
async function jpegFrom(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`Photo: ${response.status}`);
  const bitmap = await createImageBitmap(await response.blob());
  const scale = Math.min(1, 2000 / Math.max(bitmap.width, bitmap.height));
  const canvas = new OffscreenCanvas(Math.round(bitmap.width * scale), Math.round(bitmap.height * scale));
  canvas.getContext('2d').drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  return canvas.convertToBlob({ type: 'image/jpeg', quality: 0.85 });
}

// The picked folder outlives the browser in IndexedDB, the only place a handle can be kept.

function handles(mode, use) {
  return new Promise((resolve, reject) => {
    const open = indexedDB.open('cookbo', 1);
    open.onupgradeneeded = () => open.result.createObjectStore('handles');
    open.onerror = () => reject(open.error);
    open.onsuccess = () => {
      const request = use(open.result.transaction('handles', mode).objectStore('handles'));
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    };
  });
}

export function savedFolder() {
  return handles('readonly', (store) => store.get('folder'));
}

export async function saveFolder(folder) {
  await handles('readwrite', (store) => store.put(folder, 'folder'));
  return remember(await cookbooksIn(folder));
}
