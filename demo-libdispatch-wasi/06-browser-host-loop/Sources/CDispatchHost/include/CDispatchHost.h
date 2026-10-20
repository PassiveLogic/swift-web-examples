#ifndef CDISPATCH_HOST_H
#define CDISPATCH_HOST_H

#include <stdbool.h>
#include <stdint.h>

// The host event loop SPI of libdispatch for single-threaded WASI. It is
// private, so libdispatch does not install a header for it. These are the
// same declarations as in private/private.h of libdispatch. Each browser
// example has its own copy, so each example builds on its own.
//
// Dispatch calls the scheduler when it records new work. The scheduler must
// arrange a later call to _dispatch_wasi_event_loop_perform() and return
// without running Dispatch.
typedef void (*dispatch_wasi_event_loop_schedule_t)(void *context);
void _dispatch_wasi_event_loop_set_scheduler(
		dispatch_wasi_event_loop_schedule_t schedule, void *context);
// Runs at most max_steps drain steps. Returns true when more work remains.
bool _dispatch_wasi_event_loop_perform(unsigned long max_steps,
		bool consumes_scheduled_turn);
// Returns -1 with no armed timer, 0 when a timer is due, or else the delay
// in nanoseconds until the next timer.
int64_t _dispatch_wasi_event_loop_next_timer_delay(void);

// Work queued with the C API: count the primes below limit on a global
// queue, then call done(primes, context) on the main queue.
typedef void (*c_primes_done_t)(int primes, void *context);
void c_count_primes_async(int limit, c_primes_done_t done, void *context);

#endif
