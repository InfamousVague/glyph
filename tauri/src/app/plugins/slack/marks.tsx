import { StrokeMark } from '../kit.tsx';

/** A hash, the way a Slack channel is written: the plugin's mark on a note's More sheet, in the app's strokes. */
export function SlackMark({ size }: { size?: number }) {
  return <StrokeMark d="M4 9h16M4 15h16M10 3 8 21M16 3l-2 18" size={size} />;
}
