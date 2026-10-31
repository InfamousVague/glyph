import type { ReactNode } from 'react';
import type { Canvas, CanvasNode } from '../../src/app/canvas/jsonCanvas.ts';
import type { Page } from './library.ts';
import type { Resolver } from './links.ts';
import styles from './site.module.css';

/**
 * A canvas drawn still (docs/MARKDOWN_FIRST.md §7, "Canvas"; the app's CanvasView.tsx pans, zooms and edits, and
 * wants a browser): JSON Canvas 1.0 as one SVG, every card a box where it sits, its first words in it, groups behind
 * their cards with their labels, and each edge a line with the arrow the spec gives it; then the cards as a list under
 * it, so what a card says is read in full and found by the search. A file card links to its page where the site has
 * one, a link card to its address. Six preset colours are the spec's; a hex colour is drawn as it is.
 */

const PRESETS: Record<string, string> = { '1': '#e05252', '2': '#e0a052', '3': '#e0d052', '4': '#52b86a', '5': '#52a0e0', '6': '#a052e0' };
const PAD = 40;
const LINE = 22;
const CHARS_PER_PX = 0.12;

function colourOf(node: CanvasNode): string | null {
  if (!node.color) return null;
  return PRESETS[node.color] ?? node.color;
}

/** The card's words, one line of its text at a time, as many as fit. */
function linesOf(node: CanvasNode, resolve: (file: string) => Page | null): string[] {
  const words = node.type === 'text' ? node.text : node.type === 'file' ? (resolve(node.file)?.title ?? node.file.replace(/\.md$/, '')) : node.type === 'link' ? node.url : (node.label ?? '');
  const width = Math.max(1, Math.floor((node.width - 24) * CHARS_PER_PX));
  const most = Math.max(1, Math.floor((node.height - 16) / LINE));
  const out: string[] = [];
  for (const line of words.split('\n')) {
    const plain = line.replace(/^#+\s*/, '').replace(/[*_`]/g, '').trim();
    if (!plain && out.length) continue;
    let rest = plain;
    while (rest.length > width && out.length < most) {
      const cut = rest.lastIndexOf(' ', width);
      out.push(rest.slice(0, cut > width / 2 ? cut : width));
      rest = rest.slice(cut > width / 2 ? cut + 1 : width);
    }
    if (out.length >= most) break;
    out.push(rest);
  }
  if (out.length >= most && words.length > out.join(' ').length) out[most - 1] = `${out[most - 1]!.slice(0, Math.max(0, width - 1))}…`;
  return out.slice(0, most);
}

function sidePoint(node: CanvasNode, side: 'top' | 'right' | 'bottom' | 'left'): [number, number] {
  switch (side) {
    case 'top':
      return [node.x + node.width / 2, node.y];
    case 'bottom':
      return [node.x + node.width / 2, node.y + node.height];
    case 'left':
      return [node.x, node.y + node.height / 2];
    case 'right':
      return [node.x + node.width, node.y + node.height / 2];
  }
}

/** The side of `from` that faces `to`, for an edge that does not say. */
function facing(from: CanvasNode, to: CanvasNode): 'top' | 'right' | 'bottom' | 'left' {
  const dx = to.x + to.width / 2 - (from.x + from.width / 2);
  const dy = to.y + to.height / 2 - (from.y + from.height / 2);
  return Math.abs(dx) > Math.abs(dy) ? (dx > 0 ? 'right' : 'left') : dy > 0 ? 'bottom' : 'top';
}

export function CanvasStill({ canvas, page, resolver }: { canvas: Canvas; page: Page; resolver: Resolver }) {
  const resolve = (file: string) => resolver.pageOf(page, file.replace(/\.md$/, '').split('/').pop() ?? file) ?? resolver.pageOf(page, file.replace(/\.md$/, ''));
  if (!canvas.nodes.length) return <p className={styles.quiet}>An empty canvas.</p>;
  const minX = Math.min(...canvas.nodes.map((n) => n.x)) - PAD;
  const minY = Math.min(...canvas.nodes.map((n) => n.y)) - PAD;
  const maxX = Math.max(...canvas.nodes.map((n) => n.x + n.width)) + PAD;
  const maxY = Math.max(...canvas.nodes.map((n) => n.y + n.height)) + PAD;
  const byId = new Map(canvas.nodes.map((n) => [n.id, n] as const));
  // Groups first, so the cards draw over them.
  const ordered = [...canvas.nodes].sort((a, b) => Number(b.type === 'group') - Number(a.type === 'group'));
  const cards: ReactNode[] = ordered.map((node) => {
    const colour = colourOf(node);
    const lines = linesOf(node, resolve);
    const href = node.type === 'file' ? (resolve(node.file) ? resolver.hrefOf(page, resolve(node.file)!.title, null) : null) : node.type === 'link' ? node.url : null;
    const box = (
      <g key={node.id} data-card={node.type} transform={`translate(${node.x} ${node.y})`}>
        <rect width={node.width} height={node.height} rx={node.type === 'group' ? 12 : 8} className={node.type === 'group' ? styles.canvasGroup : styles.canvasCard} style={colour ? { stroke: colour, fill: node.type === 'group' ? `${colour}22` : undefined } : undefined} />
        {node.type === 'group' && node.label ? (
          <text x={12} y={-8} className={styles.canvasLabel}>
            {node.label}
          </text>
        ) : (
          lines.map((line, i) => (
            <text key={i} x={12} y={20 + i * LINE} className={styles.canvasText}>
              {line}
            </text>
          ))
        )}
      </g>
    );
    return href && /^(https?:|[^:]*$)/i.test(href) ? (
      <a key={node.id} href={href} target={node.type === 'link' ? '_blank' : undefined} rel={node.type === 'link' ? 'noopener noreferrer' : undefined}>
        {box}
      </a>
    ) : (
      box
    );
  });
  const edges = canvas.edges.map((edge) => {
    const from = byId.get(edge.fromNode);
    const to = byId.get(edge.toNode);
    if (!from || !to) return null;
    const [x1, y1] = sidePoint(from, edge.fromSide ?? facing(from, to));
    const [x2, y2] = sidePoint(to, edge.toSide ?? facing(to, from));
    const mx = (x1 + x2) / 2;
    const my = (y1 + y2) / 2;
    return (
      <g key={edge.id} data-edge="">
        <path d={`M ${x1} ${y1} L ${x2} ${y2}`} className={styles.canvasEdge} style={edge.color ? { stroke: PRESETS[edge.color] ?? edge.color } : undefined} markerEnd={(edge.toEnd ?? 'arrow') === 'arrow' ? 'url(#canvas-arrow)' : undefined} markerStart={edge.fromEnd === 'arrow' ? 'url(#canvas-arrow-back)' : undefined} />
        {edge.label ? (
          <text x={mx} y={my - 6} textAnchor="middle" className={styles.canvasLabel}>
            {edge.label}
          </text>
        ) : null}
      </g>
    );
  });
  return (
    <>
      <figure className={styles.canvasFigure}>
        <svg viewBox={`${minX} ${minY} ${maxX - minX} ${maxY - minY}`} role="img" aria-label={`Canvas: ${page.title}`} className={styles.canvasSvg}>
          <defs>
            <marker id="canvas-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto-start-reverse">
              <path d="M 0 0 L 10 5 L 0 10 z" fill="currentColor" />
            </marker>
            <marker id="canvas-arrow-back" viewBox="0 0 10 10" refX="1" refY="5" markerWidth="8" markerHeight="8" orient="auto">
              <path d="M 10 0 L 0 5 L 10 10 z" fill="currentColor" />
            </marker>
          </defs>
          {edges}
          {cards}
        </svg>
      </figure>
      <details className={styles.fenceDetails} data-canvas-cards="">
        <summary>
          {canvas.nodes.length} {canvas.nodes.length === 1 ? 'card' : 'cards'}
        </summary>
        <ul>
          {canvas.nodes.map((node) => (
            <li key={node.id} data-card={node.type}>
              {node.type === 'text' ? node.text : node.type === 'file' ? `Note: ${resolve(node.file)?.title ?? node.file}` : node.type === 'link' ? node.url : `Group: ${node.label ?? ''}`}
            </li>
          ))}
        </ul>
      </details>
    </>
  );
}
