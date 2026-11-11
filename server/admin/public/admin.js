// Console behaviour. Inline scripts are blocked by the CSP, so everything lives here.
(() => {
  // Destructive actions ask first (forms with data-confirm).
  document.addEventListener('submit', (event) => {
    const text = event.target.dataset && event.target.dataset.confirm;
    if (text && !window.confirm(text)) event.preventDefault();
  });

  // HEIC in any browser: decoded here with libheif (WebAssembly, served from /vendor) into PNGs.
  // The Worker never converts anything, so no server CPU is used.
  let ready;
  function lib() {
    // This libheif build compiles its wasm synchronously, so the binary is fetched first and
    // handed over; initialisation may then finish before the factory even returns.
    ready ??= (async () => {
      if (typeof libheif !== 'function') throw new Error('decoder not loaded');
      const res = await fetch('/vendor/libheif.wasm', { credentials: 'same-origin' });
      if (!res.ok) throw new Error('decoder HTTP ' + res.status);
      const wasmBinary = new Uint8Array(await res.arrayBuffer());
      return await new Promise((resolve) => {
        let module = null, initialised = false;
        module = libheif({ wasmBinary, onRuntimeInitialized: () => { initialised = true; if (module) resolve(module); } });
        if (initialised) resolve(module);
      });
    })();
    return ready;
  }

  async function decode(url) {
    const [m, bytes] = await Promise.all([
      lib(),
      fetch(url, { credentials: 'same-origin' }).then((r) => {
        if (!r.ok) throw new Error('HTTP ' + r.status);
        return r.arrayBuffer();
      }),
    ]);
    const images = new m.HeifDecoder().decode(new Uint8Array(bytes));
    if (!images.length) throw new Error('not a HEIC image');
    const image = images[0];
    const w = image.get_width(), h = image.get_height();
    const canvas = document.createElement('canvas');
    canvas.width = w;
    canvas.height = h;
    const ctx = canvas.getContext('2d');
    const pixels = ctx.createImageData(w, h);
    await new Promise((ok, fail) => image.display(pixels, (d) => (d ? ok() : fail(new Error('decode failed')))));
    ctx.putImageData(pixels, 0, 0);
    if (image.free) image.free();
    const blob = await new Promise((ok) => canvas.toBlob(ok, 'image/png'));
    return URL.createObjectURL(blob);
  }

  function failed(img) {
    const note = document.createElement('div');
    note.className = 'noheic';
    note.textContent = '图片解码失败';
    img.replaceWith(note);
  }

  // Thumbnails, two at a time.
  async function thumbnails() {
    const queue = [...document.querySelectorAll('img[data-heic]')];
    const worker = async () => {
      for (let img; (img = queue.shift()); ) {
        try { img.src = await decode(img.dataset.heic); } catch (e) { console.error(e); failed(img); }
      }
    };
    await Promise.all([worker(), worker()]);
  }

  // Full size in an overlay.
  document.addEventListener('click', async (event) => {
    const link = event.target.closest('a[data-heic-full]');
    if (!link) return;
    event.preventDefault();
    const overlay = document.createElement('div');
    overlay.className = 'overlay';
    overlay.textContent = '解码中…';
    overlay.addEventListener('click', () => overlay.remove());
    document.body.append(overlay);
    try {
      const img = new Image();
      img.src = await decode(link.getAttribute('href'));
      overlay.textContent = '';
      overlay.append(img);
    } catch (e) {
      console.error(e);
      overlay.textContent = '图片解码失败';
    }
  });

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', thumbnails);
  else thumbnails();
})();
