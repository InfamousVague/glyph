import { chipPhase, partialCommand } from './chip.ts';
import type { RouteView } from './takeHost.ts';
import styles from './CaptureScreen.module.css';

/**
 * The chip just above the recorder's buttons: where the words are going while a command is heard, and what came of
 * it. Outlined with dots while a note is being named or a command worked out, filled with a tick once something has
 * landed, dashed when a name matched no note (CaptureScreen.module.css `.route`). What it says is the take's
 * (capture/takeHost.ts `RouteView`); which look it takes, and how long a settled one stays, are chip.ts.
 */

/** The chip for `route`, with `itemWords` - what of a command is being heard - where the chip shows it. */
export function RouteChip({ route, itemWords }: { route: Exclude<RouteView, null>; itemWords: string }) {
  return (
    <p className={styles.route} data-phase={chipPhase(route)} role="status">
      {route.phase === 'hearing' ? (
        <>
          <span className={styles.routeDots} aria-hidden="true" />
          {route.guess ? (
            <>
              {route.lead} <strong>{route.guess}</strong>
            </>
          ) : (
            <>Looking for “{route.name}”</>
          )}
        </>
      ) : route.phase === 'waiting' ? (
        itemWords ? (
          <>
            <strong>{route.title}:</strong> {itemWords}
          </>
        ) : (
          <>
            <span className={styles.routeDots} aria-hidden="true" />
            {route.leave ? 'Say the note for' : route.many ? 'Say the items for' : 'Say the item for'} <strong>{route.title}</strong>
          </>
        )
      ) : route.phase === 'plugin' ? (
        route.state === 'failed' ? (
          <>{route.title}</>
        ) : (
          <>
            <span className={route.state === 'working' ? styles.routeDots : styles.routeTick} aria-hidden="true" />
            {route.lead ? `${route.lead} ` : null}
            <strong>{route.title}</strong>
          </>
        )
      ) : route.phase === 'command' ? (
        <>
          <span className={styles.routeDots} aria-hidden="true" />
          <span>
            <strong>Hey Ghost</strong>
            {route.words || partialCommand(itemWords) ? `: ${[route.words, partialCommand(itemWords)].filter(Boolean).join(' ')}` : ', listening for a command'}
            {route.thinking ? <span className={styles.routeThinking}> · working it out</span> : null}
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
            <>
              Now on <strong>{route.title}</strong>
            </>
          )}
        </>
      ) : (
        <>No note called “{route.title}”, so it stays here</>
      )}
    </p>
  );
}
