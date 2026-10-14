// Renders Markdown into #content. The native app drives it through window.MV:
//   MV.load({ markdown, baseURL })   MV.setTheme(name)   MV.setFontSize(px)
(() => {
  'use strict';

  const MERMAID_THEMES = { reader: 'neutral', clean: 'default', sepia: 'neutral', night: 'dark' };
  // DOMPurify's default list plus file: (local images/links) and data: (inline images).
  const ALLOWED_URI = /^(?:(?:https?|mailto|tel|file|data):|[^a-z]|[a-z+.\-]+(?:[^a-z+.\-:]|$))/i;

  const content = document.getElementById('content');
  let theme = document.documentElement.dataset.theme;
  let baseURL = '';
  let renderSeq = 0;

  function configureMermaid() {
    mermaid.initialize({
      startOnLoad: false,
      securityLevel: 'strict',
      theme: MERMAID_THEMES[theme] || 'default',
      fontFamily: '-apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif',
    });
  }

  function stripFrontMatter(md) {
    return md.replace(/^﻿/, '').replace(/^---\r?\n[\s\S]*?\r?\n(?:---|\.\.\.)[ \t]*(?:\r?\n|$)/, '');
  }

  function slugify(text) {
    return text.trim().toLowerCase().replace(/[^\p{L}\p{N}\s_-]/gu, '').replace(/\s+/g, '-') || 'section';
  }

  function resolve(url) {
    if (!baseURL || !url || url.startsWith('#')) return url;
    try { return new URL(url, baseURL).href; } catch { return url; }
  }

  function enhance(root) {
    // GitHub-style heading anchors so [links](#some-heading) work.
    const seen = new Map();
    root.querySelectorAll('h1, h2, h3, h4, h5, h6').forEach(h => {
      const slug = slugify(h.textContent);
      const count = seen.get(slug) || 0;
      seen.set(slug, count + 1);
      h.id = count ? `${slug}-${count}` : slug;
    });

    // Relative paths are relative to the Markdown file, not to this page.
    root.querySelectorAll('img[src]').forEach(el => el.setAttribute('src', resolve(el.getAttribute('src'))));
    root.querySelectorAll('a[href]').forEach(el => el.setAttribute('href', resolve(el.getAttribute('href'))));

    root.querySelectorAll('pre > code').forEach(code => {
      const langClass = [...code.classList].find(c => c.startsWith('language-'));
      const lang = langClass ? langClass.slice('language-'.length).toLowerCase() : '';
      if (lang === 'mermaid') {
        const figure = document.createElement('figure');
        figure.className = 'mermaid-block';
        figure.dataset.source = code.textContent;
        code.parentElement.replaceWith(figure);
      } else if (lang && hljs.getLanguage(lang)) {
        hljs.highlightElement(code);
      }
    });

    root.querySelectorAll('table').forEach(table => {
      const wrap = document.createElement('div');
      wrap.className = 'table-wrap';
      table.replaceWith(wrap);
      wrap.appendChild(table);
    });
  }

  async function renderDiagrams() {
    const seq = ++renderSeq;
    const blocks = content.querySelectorAll('.mermaid-block');
    for (let i = 0; i < blocks.length; i++) {
      const block = blocks[i];
      const id = `mermaid-${seq}-${i}`;
      try {
        const { svg } = await mermaid.render(id, block.dataset.source);
        if (seq !== renderSeq) return;
        block.classList.remove('error');
        block.innerHTML = svg;
      } catch (err) {
        // Mermaid can leave its scratch element behind on failure.
        document.getElementById('d' + id)?.remove();
        if (seq !== renderSeq) return;
        const message = document.createElement('div');
        message.className = 'mermaid-error';
        message.textContent = 'Mermaid diagram error: ' + (err?.message || err);
        const source = document.createElement('pre');
        source.textContent = block.dataset.source;
        block.classList.add('error');
        block.replaceChildren(message, source);
      }
    }
  }

  async function load({ markdown, baseURL: base }) {
    baseURL = base || '';
    const scrollY = window.scrollY;
    const html = DOMPurify.sanitize(marked.parse(stripFrontMatter(markdown), { gfm: true }), {
      ALLOWED_URI_REGEXP: ALLOWED_URI,
    });
    const template = document.createElement('template');
    template.innerHTML = html;
    enhance(template.content);
    content.replaceChildren(template.content);
    window.scrollTo(0, scrollY);
    await renderDiagrams();
    window.scrollTo(0, scrollY); // diagrams change the layout height; keep the reader's place on reload
  }

  function setTheme(name) {
    if (name === theme) return;
    theme = name;
    document.documentElement.dataset.theme = name;
    configureMermaid();
    renderDiagrams();
  }

  function setFontSize(px) {
    document.documentElement.style.setProperty('--base-size', px + 'px');
  }

  // In-page anchors: scroll instead of navigating (the native side handles all other links).
  document.addEventListener('click', event => {
    const link = event.target.closest('a[href^="#"]');
    if (!link) return;
    event.preventDefault();
    const target = document.getElementById(decodeURIComponent(link.getAttribute('href').slice(1)));
    target?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  });

  configureMermaid();
  window.MV = { load, setTheme, setFontSize };
})();
