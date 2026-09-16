import { StrokeMark } from '../kit.tsx';

/** A branch: a repo, in the app's strokes. */
export function RepoMark({ size }: { size?: number }) {
  return <StrokeMark d="M6 3v12M18 9a3 3 0 1 0 0-.01M6 21a3 3 0 1 0 0-.01M18 12c0 3-3 4-6 4H9" size={size} />;
}
