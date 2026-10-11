import { StrokeMark } from '../kit.tsx';

/** A page with an N on it: Notion's mark, in the app's strokes. */
export function NotionMark({ size }: { size?: number }) {
  return <StrokeMark d="M5 4h10l4 4v12H5zM9 16V9l6 7V9" size={size} />;
}
