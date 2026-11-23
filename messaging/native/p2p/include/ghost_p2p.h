/*
 * The direct network's core (native/p2p; docs/OPEN_NETWORK.md, section 2): the whole C interface.
 *
 * A node is a number. Commands go in as bytes, events come out as bytes through the callback the node was made
 * with; README.md beside this folder lays out both. lib/net/p2p/node_ffi.dart is the one caller.
 *
 * Nothing here waits on the network, and every function may be called from any thread.
 */
#ifndef GHOST_P2P_H
#define GHOST_P2P_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* What ghost_p2p_abi() answers in this version of the interface. A caller that finds another number uses nothing. */
#define GHOST_P2P_ABI 1

/* What ghost_p2p_command() answers. */
#define GHOST_P2P_OK 0
#define GHOST_P2P_NO_NODE (-1)   /* There is no such node. */
#define GHOST_P2P_MALFORMED (-2) /* The command could not be read. */
#define GHOST_P2P_NO_STREAM (-3) /* SEND: there is no such stream (it has closed). */
#define GHOST_P2P_OVERFLOW (-4)  /* SEND: the stream's queue was full, and the stream is now closed. */
#define GHOST_P2P_TOO_LONG (-5)  /* SEND: the frame is longer than a stream carries (1 MiB). */
#define GHOST_P2P_PANICKED (-6)  /* A bug in the library was caught. */

/*
 * Called with a node's events, one at a time and in order, from the library's own threads. `event` is `len` bytes,
 * the receiver's from then on: it gives them back with ghost_p2p_buffer_free(event, len), from any thread.
 */
typedef void (*ghost_p2p_event_cb)(uint64_t node, uint8_t *event, size_t len);

/* The number of this interface: GHOST_P2P_ABI. */
uint32_t ghost_p2p_abi(void);

/*
 * The node id a node key makes, with nothing started. `secret` is 32 bytes; `out` is room for 32.
 * Answers GHOST_P2P_OK, or GHOST_P2P_MALFORMED where either is null.
 */
int32_t ghost_p2p_node_id(const uint8_t *secret, uint8_t *out);

/*
 * Makes a node, not started, whose events go to `callback`. Answers its number, or 0 where it could not be made.
 * `owner` is a number of the caller's own choosing that says who made it (the Dart side gives its Flutter engine's),
 * for ghost_p2p_drop_owned.
 */
uint64_t ghost_p2p_new(uint64_t owner, ghost_p2p_event_cb callback);

/*
 * Gives a node a command: `len` bytes, read before this returns and not kept. Answers one of the numbers above.
 * What the command comes to is said in events.
 */
int32_t ghost_p2p_command(uint64_t node, const uint8_t *command, size_t len);

/* Gives back a buffer the callback was handed, with the length it was handed with. */
void ghost_p2p_buffer_free(uint8_t *buffer, size_t len);

/*
 * Stops a node and forgets it. Once this has returned its callback is not called again; its links and sockets
 * close in the background, within a few seconds.
 */
void ghost_p2p_drop(uint64_t node);

/*
 * The same for every node `owner` made: called as the library is first opened, for nodes that an earlier life of the
 * same owner left behind (a hot restart ends an isolate without a word). Another owner's nodes are left alone.
 */
void ghost_p2p_drop_owned(uint64_t owner);

#ifdef __cplusplus
}
#endif

#endif
