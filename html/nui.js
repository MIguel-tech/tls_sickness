window.addEventListener('message', (e) => {
  const data = e.data || {};
  if (data.action === 'play' && data.file) {
    try {
      const a = new Audio(data.file);
      a.volume = Math.max(0, Math.min(1, data.volume ?? 1));
      a.play().catch(() => {});
    } catch (err) {}
  }
});
