import { SegmentedControl } from '@glacier/react';
import type { ReadMode } from './readMode.ts';

/** Read | Markdown, the kit's segmented control (readMode.ts says what each is). */
export function ReadToggle({ mode, onChange, className }: { mode: ReadMode; onChange: (mode: ReadMode) => void; className?: string }) {
  return (
    <SegmentedControl
      aria-label="Read or Markdown"
      size="sm"
      className={className}
      options={[
        { value: 'read', label: 'Read' },
        { value: 'markdown', label: 'Markdown' },
      ]}
      value={mode}
      onValueChange={(value) => onChange(value === 'markdown' ? 'markdown' : 'read')}
    />
  );
}
