import { chipPhase, partialCommand } from './chip.ts';
import type { RouteView } from './takeHost.ts';
import styles from './CaptureScreen.module.css';

/**
 * The chip just above the recorder's buttons: where the words are going while a command is heard, and what came of
 * it. Outlined with dots while a note is being named or a command worked out, filled with a tick once something has
 * landed, dashed when a name matched no note, filled with an Undo when the last thing said was taken back
 * (CaptureScreen.module.css `.route`). What it says is the live reader's and the recorder's (capture/takeHost.ts
 * `RouteView`); which look it takes, and how long a settled one stays, are chip.ts.
 */

/**
 * The chip for `route`, with `itemWords` - what of a command is being heard - where the chip shows it, and `onUndo`
 * for a take-back that can still be put back: the recorder withholds it once Done is writing.
 */
export function RouteChip({ route, itemWords, onUndo }: { route: Exclude<RouteView, null>; itemWords: string; onUndo?: () => void }) {
  return (
    <p className={styles.route} data-phase={chipPhase(route)} role="status">
      {route.phase === 'tookBack' ? (
        <>
          <span className={styles.routeText}>
            {route.outcome === 'gone' ? (
              <>Took back “{route.said}”</>
            ) : 'sent' in route.outcome ? (
              <>
                Sent “{route.said}” to <strong>{route.outcome.sent}</strong>
              </>
            ) : 'placed' in route.outcome ? (
              <>
                Put “{route.said}” {route.outcome.placed}
              </>
            ) : 'replaced' in route.outcome ? (
              <>
                Replaced “{route.said}” with “{route.outcome.replaced}”
              </>
            ) : (
              <>
                Changed “{route.said}” to “{route.outcome.changed}”
              </>
            )}
          </span>
          {onUndo ? (
            <button type="button" className={`app-word ${styles.routeUndo}`} onClick={onUndo}>
              Undo
            </button>
          ) : null}
        </>
      ) : route.phase === 'hearing' ? (
        <>
          <span className={styles.routeDots} aria-hidden="true" />
          Looking for “{route.name}”
        </>
      ) : route.phase === 'waiting' ? (
        itemWords ? (
          <>
            <strong>{route.title}:</strong> {itemWords}
          </>
        ) : (
          <>
            <span className={styles.routeDots} aria-hidden="true" />
            Say the note for <strong>{route.title}</strong>
          </>
        )
      ) : route.phase === 'command' ? (
        <>
          <span className={styles.routeDots} aria-hidden="true" />
          <span>
            <strong>Hey Ghost</strong>
            {route.words || partialCommand(itemWords) ? `: ${[route.words, partialCommand(itemWords)].filter(Boolean).join(' ')}` : ', listening for a command'}
          </span>
        </>
      ) : route.phase === 'said' ? (
        <>{route.text}</>
      ) : route.phase === 'done' ? (
        <>
          <span className={styles.routeTick} aria-hidden="true" />
          {route.text}
        </>
      ) : route.phase === 'added' ? (
        <>
          <span className={styles.routeTick} aria-hidden="true" />
          {route.added.length === 1 ? 'Added to' : `${route.added.length} added to`} <strong>{route.title}</strong>
        </>
      ) : route.phase === 'moved' ? (
        <>
          <span className={styles.routeTick} aria-hidden="true" />
          {route.title === 'New note' ? (
            'New note'
          ) : (
            // Its own box, so a long title ends in an ellipsis inside the chip rather than at its edge.
            <span className={styles.routeText}>
              Now on <strong>{route.title}</strong>
              {route.spot ? ` · ${route.spot}` : null}
            </span>
          )}
        </>
      ) : (
        <>No note called “{route.title}”, so it stays here</>
      )}
    </p>
  );
}
