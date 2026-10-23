// Videos play only while on screen (and never if the visitor prefers reduced motion).
const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
const vids = document.querySelectorAll('video');
if ('IntersectionObserver' in window) {
  const io = new IntersectionObserver((entries) => {
    for (const e of entries) {
      const v = e.target;
      if (e.isIntersecting && !reduce) { v.preload = 'auto'; v.play().catch(() => {}); } else v.pause();
    }
  }, { threshold: 0.45 });
  vids.forEach((v) => io.observe(v));
}
if (reduce) vids.forEach((v) => { v.controls = true; });

// If a screenshot or clip isn't present, show a quiet placeholder instead of a broken image.
function markMissing(el) {
  const fig = el.closest('figure');
  if (!fig || fig.classList.contains('missing')) return;
  fig.classList.add('missing');
  fig.replaceChildren(Object.assign(document.createElement('span'), { textContent: 'Media coming soon' }));
}
document.querySelectorAll('figure img').forEach((img) => {
  img.addEventListener('error', () => markMissing(img));
  if (img.complete && img.naturalWidth === 0 && img.currentSrc) markMissing(img);
});
document.querySelectorAll('figure video').forEach((v) => {
  const src = v.querySelector('source');
  if (src) src.addEventListener('error', () => markMissing(v));
});

// Copy buttons for the install commands.
document.querySelectorAll('[data-copy]').forEach((b) => b.addEventListener('click', async () => {
  try { await navigator.clipboard.writeText(b.dataset.copy); b.textContent = 'Copied'; }
  catch { b.textContent = 'Press ⌘C'; }
  setTimeout(() => (b.textContent = 'Copy'), 1500);
}));
