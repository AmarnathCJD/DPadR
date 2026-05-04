const deviceSel = document.getElementById('device');
const displaySel = document.getElementById('display');
const displayBar = document.getElementById('displayBar');
const refreshBtn = document.getElementById('refresh');
const themeBtn = document.getElementById('themeToggle');
const toast = document.getElementById('toast');
const numpadPanel = document.getElementById('numpad');
const numpadToggle = document.getElementById('toggleNumpad');
let toastTimer = null;

function setToast(msg, kind) {
  toast.textContent = msg;
  toast.className = 'toast' + (kind ? ' ' + kind : '');
  if (toastTimer) clearTimeout(toastTimer);
  if (msg) toastTimer = setTimeout(() => { toast.textContent = ''; toast.className = 'toast'; }, 2000);
}

themeBtn.addEventListener('click', () => {
  const cur = document.documentElement.getAttribute('data-theme') || 'light';
  const next = cur === 'dark' ? 'light' : 'dark';
  document.documentElement.setAttribute('data-theme', next);
  localStorage.setItem('theme', next);
});

async function loadDevices() {
  try {
    const r = await fetch('/api/devices');
    const data = await r.json();
    if (!r.ok) throw new Error(data.error || 'failed');

    deviceSel.innerHTML = '';
    if (!data.length) {
      const o = document.createElement('option');
      o.textContent = 'no devices connected';
      o.value = '';
      deviceSel.appendChild(o);
      setToast('no devices found — run `adb devices`', 'error');
      return;
    }
    for (const d of data) {
      const o = document.createElement('option');
      o.value = d.serial;
      o.textContent = `${d.serial} (${d.state})`;
      if (d.state !== 'device') o.disabled = true;
      deviceSel.appendChild(o);
    }
    setToast(`${data.length} device(s)`, 'ok');
    loadDisplays();
  } catch (e) {
    setToast('error: ' + e.message, 'error');
  }
}

async function loadDisplays() {
  const serial = deviceSel.value;
  displaySel.innerHTML = '';
  displayBar.hidden = true;
  if (!serial) return;

  try {
    const r = await fetch('/api/displays?serial=' + encodeURIComponent(serial));
    const data = await r.json();
    if (!r.ok) throw new Error(data.error || 'failed');

    if (!data.length) return;

    const def = document.createElement('option');
    def.value = '';
    def.textContent = 'Default display';
    displaySel.appendChild(def);

    for (const d of data) {
      const o = document.createElement('option');
      o.value = String(d.id);
      o.textContent = `${d.name} (id ${d.id})`;
      displaySel.appendChild(o);
    }

    if (data.length > 1) displayBar.hidden = false;
  } catch (e) {
    setToast('display list error: ' + e.message, 'error');
  }
}

async function sendKey(key, btn) {
  const serial = deviceSel.value;
  if (!serial) { setToast('select a device first', 'error'); return; }

  const body = { serial, key };
  if (displaySel.value !== '') body.display = parseInt(displaySel.value, 10);

  if (btn) {
    btn.classList.add('pressed');
    setTimeout(() => btn.classList.remove('pressed'), 120);
  }

  try {
    const r = await fetch('/api/keyevent', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    const data = await r.json();
    if (!r.ok) throw new Error(data.error || 'failed');
    setToast(key, 'ok');
  } catch (e) {
    setToast('error: ' + e.message, 'error');
  }
}

document.querySelectorAll('.key').forEach(btn => {
  btn.addEventListener('click', () => sendKey(btn.dataset.key, btn));
});

refreshBtn.addEventListener('click', loadDevices);
deviceSel.addEventListener('change', loadDisplays);

const keyboardMap = {
  ArrowUp: 'UP',
  ArrowDown: 'DOWN',
  ArrowLeft: 'LEFT',
  ArrowRight: 'RIGHT',
  Enter: 'OK',
  ' ': 'OK',
  Escape: 'BACK',
  Backspace: 'BACK',
  h: 'HOME',
  H: 'HOME',
  r: 'RECENTS',
  R: 'RECENTS',
};

document.addEventListener('keydown', (ev) => {
  if (ev.target.tagName === 'SELECT' || ev.target.tagName === 'INPUT') return;
  const k = keyboardMap[ev.key];
  if (!k) return;
  if (ev.repeat) return;
  ev.preventDefault();
  const btn = document.querySelector(`.key[data-key="${k}"]`);
  sendKey(k, btn);
});

numpadToggle.addEventListener('click', () => {
  const open = numpadPanel.hidden;
  numpadPanel.hidden = !open;
  numpadToggle.setAttribute('aria-pressed', open ? 'true' : 'false');
});

loadDevices();
