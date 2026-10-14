// Renders Markdown into #content. The native app drives it through window.MV:
//   MV.load({ markdown, previous, baseURL, scrollToChange })   MV.setTheme(name)   MV.setFontSize(px)
//   MV.scrollToHeading(id)
// and the page reports back through the "markoscope" message handler:
//   { type: 'outline', headings: [{ id, title, level }] }   { type: 'activeHeading', id }
// When `previous` is given, the changes from it to `markdown` are highlighted (see diff.js).
(() => {
  'use strict';

  const MERMAID_THEMES = { reader: 'neutral', clean: 'default', sepia: 'neutral', night: 'dark' };
  // DOMPurify's default list plus file: (local images/links) and data: (inline images).
  const ALLOWED_URI = /^(?:(?:https?|mailto|tel|file|data):|[^a-z]|[a-z+.\-]+(?:[^a-z+.\-:]|$))/i;

  const content = document.getElementById('content');
  const minimap = document.getElementById('minimap');
  // Rendering happens in an inert document so images don't load before their URLs are resolved.
  const scratch = document.implementation.createHTMLDocument('');
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
      if (h.closest('.diff-del')) return; // removed headings shouldn't steal anchors
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

  const sanitize = html => DOMPurify.sanitize(html, { ALLOWED_URI_REGEXP: ALLOWED_URI });

  function parseHTML(html) {
    const div = scratch.createElement('div');
    div.innerHTML = html;
    return div;
  }

  function renderPlain(markdown) {
    return parseHTML(sanitize(marked.parse(stripFrontMatter(markdown), { gfm: true })));
  }

  function renderDiff(previous, markdown) {
    const lex = md => marked.lexer(stripFrontMatter(md), { gfm: true }).filter(t => t.type !== 'space');
    const renderToken = tok => [...parseHTML(sanitize(marked.parser([tok], { gfm: true }))).childNodes];
    return MarkDiff.build(lex(previous), lex(markdown), renderToken, scratch);
  }

  async function load({ markdown, previous = null, baseURL: base, scrollToChange = false }) {
    baseURL = base || '';
    const scrollY = window.scrollY;
    const root = previous == null ? renderPlain(markdown) : renderDiff(previous, markdown);
    enhance(root);
    content.replaceChildren(...root.childNodes);
    window.scrollTo(0, scrollY);
    postOutline();
    updateMinimap();
    await renderDiagrams();
    // Diagrams change the layout height: keep the reader's place, or jump to the first change.
    const firstChange = scrollToChange && content.querySelector('[data-change]');
    if (firstChange) firstChange.scrollIntoView({ block: 'center' });
    else window.scrollTo(0, scrollY);
    updateMinimap();
    updateActiveHeading();
  }

  // ---- Outline: headings for the native sidebar, and which section is in view ----

  const post = message => window.webkit?.messageHandlers?.markoscope?.postMessage(message);
  const headings = () => [...content.querySelectorAll('h1[id], h2[id], h3[id], h4[id], h5[id], h6[id]')];
  let activeHeading;

  function postOutline() {
    activeHeading = undefined;
    post({
      type: 'outline',
      headings: headings().map(h => ({ id: h.id, title: h.textContent.trim(), level: Number(h.tagName[1]) })),
    });
  }

  // The active heading is the last one above the top quarter of the window.
  function updateActiveHeading() {
    const line = window.innerHeight / 4;
    let id = null;
    for (const h of headings()) {
      if (h.getBoundingClientRect().top > line) break;
      id = h.id;
    }
    if (window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 2) {
      id = headings().at(-1)?.id ?? id; // scrolled to the bottom: the last section is the one in view
    }
    if (id === activeHeading) return;
    activeHeading = id;
    post({ type: 'activeHeading', id });
  }

  let headingFrame = 0;
  window.addEventListener('scroll', () => {
    cancelAnimationFrame(headingFrame);
    headingFrame = requestAnimationFrame(updateActiveHeading);
  }, { passive: true });

  function scrollToHeading(id) {
    document.getElementById(id)?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }

  // ---- Change minimap: marks along the right edge, positioned like the scrollbar ----

  const MARK_TITLES = { del: 'Removed', ins: 'Added', mod: 'Changed' };

  function reveal(el) {
    el.scrollIntoView({ behavior: 'smooth', block: 'center' });
    el.classList.remove('flash');
    void el.offsetWidth; // restart the animation
    el.classList.add('flash');
  }

  function updateMinimap() {
    const changed = content.querySelectorAll('[data-change]');
    minimap.replaceChildren();
    minimap.hidden = changed.length === 0;
    if (!changed.length) return;

    const docHeight = document.documentElement.scrollHeight;
    const track = minimap.clientHeight;
    let last = null;
    for (const el of changed) {
      const rect = el.getBoundingClientRect();
      const top = ((rect.top + window.scrollY) / docHeight) * track;
      const height = Math.max(4, (rect.height / docHeight) * track);
      const kind = el.dataset.change;
      if (last && last.kind === kind && top <= last.top + last.height + 1) {
        last.height = Math.max(last.height, top + height - last.top);
        last.mark.style.height = last.height + 'px';
        continue;
      }
      const mark = document.createElement('div');
      mark.className = 'mark ' + kind;
      mark.title = MARK_TITLES[kind];
      mark.style.top = top + 'px';
      mark.style.height = height + 'px';
      mark.addEventListener('click', () => reveal(el));
      minimap.append(mark);
      last = { mark, top, height, kind };
    }
  }

  let minimapFrame = 0;
  const scheduleMinimap = () => {
    cancelAnimationFrame(minimapFrame);
    minimapFrame = requestAnimationFrame(updateMinimap);
  };
  new ResizeObserver(scheduleMinimap).observe(content);
  window.addEventListener('resize', scheduleMinimap);

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
  window.MV = { load, setTheme, setFontSize, scrollToHeading };
})();
