/*
 * The formatting reference's Copy buttons (reference.html): each puts its example on the clipboard, as typed, and
 * says so for a moment.
 */
document.addEventListener('click', async (event) => {
  const button = event.target instanceof Element ? event.target.closest('[data-copy-text]') : null;
  if (!button) return;
  try {
    await navigator.clipboard.writeText(button.getAttribute('data-copy-text') ?? '');
    const words = button.querySelector('span') ?? button;
    words.textContent = 'Copied';
    button.setAttribute('data-copied', '');
    setTimeout(() => {
      words.textContent = 'Copy';
      button.removeAttribute('data-copied');
    }, 1600);
  } catch {
    (button.querySelector('span') ?? button).textContent = 'Select it';
  }
});
