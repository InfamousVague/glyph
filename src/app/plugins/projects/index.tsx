import { GitBranch } from '@glacier/icons';
import type { GlyphPlugin } from '../types.ts';
import { manifest } from './manifest.ts';
import { RepoMark } from './marks.tsx';
import { ProjectPicker } from './ProjectPicker.tsx';
import { ProjectsPane } from './ProjectsPane.tsx';
import { projectContextFor, projectContextVersion, projectFor, projects } from './projects.ts';

/**
 * The Projects plugin, standard in Glyph: a note linked to a GitHub repo is
 * formatted with a briefing of that repo, written by the model on the phone.
 *
 * - On a note's cog: "Project" under Linked to (ProjectPicker).
 * - In the formatter: the briefing, as the note's context (formatContext).
 * - In Settings: the repos read, and the token (ProjectsPane).
 */
export const projectsPlugin: GlyphPlugin = {
  manifest,
  icon: GitBranch,
  settings: {
    Pane: ProjectsPane,
    summary: () => {
      const count = projects().length;
      return count ? `${count} ${count === 1 ? 'repo' : 'repos'}` : 'GitHub repos for context';
    },
  },
  noteLinks: [
    {
      id: 'project',
      label: 'Project',
      icon: RepoMark,
      hint(noteId) {
        const project = projectFor(noteId);
        return project ? `${project.owner}/${project.repo}. The AI reads it when formatting this note.` : 'A GitHub repo the AI reads for context when formatting this note.';
      },
      Picker: ProjectPicker,
      linked(noteId) {
        const project = projectFor(noteId);
        return project ? `${project.owner}/${project.repo}` : null;
      },
    },
  ],
  formatContext: { for: projectContextFor, version: projectContextVersion },
};
