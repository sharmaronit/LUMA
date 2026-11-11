(() => {
  if (!['localhost', '127.0.0.1'].includes(location.hostname)) return;
  let revision;
  async function checkBuild() {
    try {
      if (document.visibilityState !== 'hidden') {
        const response = await fetch('/__luma_preview_revision', {cache: 'no-store'});
        if (response.ok && response.headers.get('content-type')?.includes('application/json')) {
          const next = (await response.json()).revision;
          if (next && revision && next !== revision) {
            location.reload();
            return;
          }
          if (next) revision = next;
          document.documentElement.dataset.previewRevision = revision ?? '';
        }
      }
    } catch (_) {
      // A build or server restart can temporarily make the preview unavailable.
    }
    setTimeout(checkBuild, 3000);
  }
  checkBuild();
})();
