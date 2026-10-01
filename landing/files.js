/*
 * The workspace on the home page (index.html, "Your files"): a tap on a file in the tree shows what is in it, from the
 * <template> of the same name beside the tree. The first file is shown when the page opens; with no script the tree
 * still says what each file is.
 */
(() => {
  const box = document.querySelector('[data-files]');
  if (!box) return;
  const path = box.querySelector('[data-file-path]');
  const body = box.querySelector('[data-file-body]');
  const files = [...box.querySelectorAll('[data-file]')];
  const show = (button) => {
    const template = document.getElementById(`file-${button.dataset.file}`);
    if (!template) return;
    for (const each of files) each.setAttribute('aria-pressed', String(each === button));
    path.textContent = template.dataset.path;
    body.replaceChildren(template.content.cloneNode(true));
  };
  const shown = box.querySelector('.file');
  for (const button of files) {
    button.addEventListener('click', () => {
      show(button);
      // On a phone the file is under the tree: brought up, so the tap visibly did something.
      const { top, bottom } = shown.getBoundingClientRect();
      if (top > innerHeight - 80 || bottom < 80) shown.scrollIntoView({ block: 'start', behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth' });
    });
  }
  show(files.find((button) => button.dataset.file === 'f1') ?? files[0]);
})();
