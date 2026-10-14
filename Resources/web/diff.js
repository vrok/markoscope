// Builds a "rich diff" of two Markdown documents: the new document is rendered as usual,
// with removed blocks re-inserted (class diff-del) and added blocks marked (class diff-ins).
// Every changed element gets data-change = "del" | "ins" | "mod" (a removal paired with
// an addition), which drives the minimap colours.
const MarkDiff = (() => {
  'use strict';

  // Longest-common-subsequence diff of two arrays of strings.
  // Returns ops in order: { t: 'eq', a, b } | { t: 'del', a } | { t: 'ins', b }.
  function diffSeq(a, b) {
    let start = 0;
    while (start < a.length && start < b.length && a[start] === b[start]) start++;
    let endA = a.length, endB = b.length;
    while (endA > start && endB > start && a[endA - 1] === b[endB - 1]) { endA--; endB--; }

    const ops = [];
    for (let i = 0; i < start; i++) ops.push({ t: 'eq', a: i, b: i });

    const n = endA - start, m = endB - start;
    if (n * m > 4e6) {
      // Too big to align precisely: treat the differing middle as replaced wholesale.
      for (let i = 0; i < n; i++) ops.push({ t: 'del', a: start + i });
      for (let j = 0; j < m; j++) ops.push({ t: 'ins', b: start + j });
    } else {
      const w = m + 1;
      const lcs = new Uint32Array((n + 1) * w);
      for (let i = n - 1; i >= 0; i--) {
        for (let j = m - 1; j >= 0; j--) {
          lcs[i * w + j] = a[start + i] === b[start + j]
            ? lcs[(i + 1) * w + j + 1] + 1
            : Math.max(lcs[(i + 1) * w + j], lcs[i * w + j + 1]);
        }
      }
      let i = 0, j = 0;
      while (i < n && j < m) {
        if (a[start + i] === b[start + j]) { ops.push({ t: 'eq', a: start + i, b: start + j }); i++; j++; }
        else if (lcs[(i + 1) * w + j] >= lcs[i * w + j + 1]) { ops.push({ t: 'del', a: start + i }); i++; }
        else { ops.push({ t: 'ins', b: start + j }); j++; }
      }
      for (; i < n; i++) ops.push({ t: 'del', a: start + i });
      for (; j < m; j++) ops.push({ t: 'ins', b: start + j });
    }

    for (let k = 0; k < a.length - endA; k++) ops.push({ t: 'eq', a: endA + k, b: endB + k });
    return ops;
  }

  // Walks the diff of two item lists, calling same(newItem) for unchanged items and
  // change(removedItems, addedItems) once per contiguous run of changes.
  function walk(oldItems, newItems, key, same, change) {
    const ops = diffSeq(oldItems.map(key), newItems.map(key));
    for (let k = 0; k < ops.length;) {
      if (ops[k].t === 'eq') { same(newItems[ops[k].b]); k++; continue; }
      const removed = [], added = [];
      for (; k < ops.length && ops[k].t !== 'eq'; k++) {
        if (ops[k].t === 'del') removed.push(oldItems[ops[k].a]);
        else added.push(newItems[ops[k].b]);
      }
      change(removed, added);
    }
  }

  const kindOf = (removed, added) => (removed.length && added.length ? 'mod' : removed.length ? 'del' : 'ins');

  function mark(el, side, kind) {
    el.classList.add('diff-' + side);
    el.dataset.change = kind;
  }

  // ---- Word-level emphasis inside a modified pair ----

  function wordTokens(root) {
    const tokens = [];
    const walker = root.ownerDocument.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    for (let node; (node = walker.nextNode());) {
      const re = /\S+/g;
      for (let m; (m = re.exec(node.data));) {
        tokens.push({ node, start: m.index, end: m.index + m[0].length, text: m[0] });
      }
    }
    return tokens;
  }

  function wrapTokens(tokens) {
    const byNode = new Map();
    for (const t of tokens) {
      if (!byNode.has(t.node)) byNode.set(t.node, []);
      byNode.get(t.node).push(t);
    }
    for (const [node, list] of byNode) {
      // Merge neighbouring changed words so a changed phrase gets one highlight.
      const ranges = [];
      for (const t of list) {
        const last = ranges[ranges.length - 1];
        if (last && /^\s*$/.test(node.data.slice(last.end, t.start))) last.end = t.end;
        else ranges.push({ start: t.start, end: t.end });
      }
      for (let i = ranges.length - 1; i >= 0; i--) {
        const range = node.ownerDocument.createRange();
        range.setStart(node, ranges[i].start);
        range.setEnd(node, ranges[i].end);
        const span = node.ownerDocument.createElement('span');
        span.className = 'diff-word';
        range.surroundContents(span);
      }
    }
  }

  function emphasizeWords(oldEl, newEl) {
    const a = wordTokens(oldEl), b = wordTokens(newEl);
    if (!a.length || !b.length) return;
    const ops = diffSeq(a.map(t => t.text), b.map(t => t.text));
    const removed = ops.filter(o => o.t === 'del').map(o => a[o.a]);
    const added = ops.filter(o => o.t === 'ins').map(o => b[o.b]);
    // Mostly rewritten: the block colours already say it all.
    if ((removed.length + added.length) / (a.length + b.length) > 0.6) return;
    wrapTokens(removed);
    wrapTokens(added);
  }

  // ---- Item-level diff for lists and table rows ----

  function itemContainer(el) {
    if (el.tagName !== 'TABLE') return el;
    if (!el.tBodies.length) el.appendChild(el.ownerDocument.createElement('tbody'));
    return el.tBodies[0];
  }

  // Returns the merged element, or null if the two blocks can't be compared item by item.
  function diffItems(oldTok, newTok, renderToken) {
    const comparable =
      (oldTok.type === 'list' && newTok.type === 'list' && oldTok.ordered === newTok.ordered) ||
      (oldTok.type === 'table' && newTok.type === 'table');
    if (!comparable) return null;

    const oldRoot = renderToken(oldTok).find(n => n.nodeType === Node.ELEMENT_NODE);
    const newRoot = renderToken(newTok).find(n => n.nodeType === Node.ELEMENT_NODE);
    if (!oldRoot || !newRoot || oldRoot.tagName !== newRoot.tagName) return null;
    if (newRoot.tagName === 'TABLE' && oldRoot.tHead?.outerHTML !== newRoot.tHead?.outerHTML) return null;

    const oldItems = [...itemContainer(oldRoot).children];
    const newItems = [...itemContainer(newRoot).children];
    const target = itemContainer(newRoot);
    target.replaceChildren();
    walk(oldItems, newItems, el => el.outerHTML,
      el => target.append(el),
      (removed, added) => {
        const kind = kindOf(removed, added);
        removed.forEach(el => { mark(el, 'del', kind); target.append(el); });
        added.forEach(el => { mark(el, 'ins', kind); target.append(el); });
        if (removed.length === added.length) removed.forEach((el, i) => emphasizeWords(el, added[i]));
      });

    // Removed items shouldn't shift the numbering: each one shows the number of the item it precedes.
    if (newRoot.tagName === 'OL') {
      let number = newRoot.start || 1;
      for (const li of target.children) li.value = li.classList.contains('diff-del') ? number : number++;
    }
    return newRoot;
  }

  // ---- Top level ----

  // Blocks of the same kind can be compared with each other (a paragraph with a paragraph...).
  const blockKind = tok =>
    tok.type + (tok.type === 'heading' ? tok.depth : tok.type === 'list' ? (tok.ordered ? 'o' : 'u') : '');

  /**
   * oldTokens/newTokens: top-level marked tokens. renderToken(token) returns an array of
   * sanitized DOM nodes owned by `doc`. Returns a container element holding the diff.
   */
  function build(oldTokens, newTokens, renderToken, doc) {
    const out = doc.createElement('div');
    const wrap = (tok, side, kind) => {
      const block = doc.createElement('div');
      block.className = 'diff-block';
      block.append(...renderToken(tok));
      mark(block, side, kind);
      return block;
    };

    walk(oldTokens, newTokens, tok => tok.raw.trim(),
      tok => out.append(...renderToken(tok)),
      (removed, added) => {
        // Within a run of changes, pair up blocks of the same kind as modifications;
        // the rest are plain removals and additions.
        for (const op of diffSeq(removed.map(blockKind), added.map(blockKind))) {
          if (op.t === 'del') { out.append(wrap(removed[op.a], 'del', 'del')); continue; }
          if (op.t === 'ins') { out.append(wrap(added[op.b], 'ins', 'ins')); continue; }
          const merged = diffItems(removed[op.a], added[op.b], renderToken);
          if (merged) { out.append(merged); continue; }
          const oldBlock = wrap(removed[op.a], 'del', 'mod');
          const newBlock = wrap(added[op.b], 'ins', 'mod');
          out.append(oldBlock, newBlock);
          emphasizeWords(oldBlock, newBlock);
        }
      });
    return out;
  }

  return { build };
})();
