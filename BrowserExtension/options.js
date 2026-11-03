import { usesNativeApp, savedFolder, saveFolder, cookbooksIn } from './cookbooks.js';

const $ = (id) => document.getElementById(id);

function showCookbooks(folderName, cookbooks) {
  $('status').textContent = `Saving into “${folderName}”, with ${cookbooks.length === 1 ? 'this cookbook' : 'these cookbooks'}:`;
  $('status').classList.remove('muted');
  $('cookbooks').replaceChildren(...cookbooks.map(({ name }) => Object.assign(document.createElement('li'), { textContent: name })));
  $('cookbooks').hidden = false;
  $('choose').textContent = 'Choose a Different Folder…';
  $('choose').classList.add('secondary');
}

async function choose() {
  $('error').hidden = true;
  let folder;
  try {
    folder = await showDirectoryPicker({ id: 'cookbo', mode: 'readwrite' });
  } catch {
    return; // Cancelled
  }

  const cookbooks = await cookbooksIn(folder);
  if (!cookbooks.length) {
    $('error').hidden = false;
    $('error').textContent = `“${folder.name}” doesn’t hold any Cookbo cookbooks. Choose iCloud Drive › Cookbo (open the app once if it isn’t there).`;
    return;
  }
  showCookbooks(folder.name, await saveFolder(folder));
}

async function start() {
  if (usesNativeApp) {
    $('native').hidden = false;
    return;
  }
  $('picker').hidden = false;

  // A folder chosen before needs permission again after Chrome restarts
  let folder = await savedFolder();
  if (folder && (await folder.queryPermission({ mode: 'readwrite' })) === 'granted') {
    showCookbooks(folder.name, await cookbooksIn(folder));
    folder = null;
  } else if (folder) {
    $('status').textContent = `Chrome needs permission for “${folder.name}” again.`;
    $('choose').textContent = 'Allow Again';
  }

  $('choose').addEventListener('click', async () => {
    if (folder && (await folder.requestPermission({ mode: 'readwrite' })) === 'granted') {
      showCookbooks(folder.name, await saveFolder(folder));
    } else {
      await choose();
    }
    folder = null;
  });
}

start();
