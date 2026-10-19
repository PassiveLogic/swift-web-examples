#ifndef CDISPATCH_HOST_H
#define CDISPATCH_HOST_H

#include <stdbool.h>
#include <stdint.h>

// The host event loop SPI of libdispatch for single-threaded WASI. It is
// private, so libdispatch does not install a header for it. These are the
// same declarations as in private/private.h of libdispatch.
typedef void (*dispatch_wasi_event_loop_schedule_t)(void *context);
void _dispatch_wasi_event_loop_set_scheduler(
		dispatch_wasi_event_loop_schedule_t schedule, void *context);
bool _dispatch_wasi_event_loop_perform(unsigned long max_steps,
		bool consumes_scheduled_turn);
int64_t _dispatch_wasi_event_loop_next_timer_delay(void);

// Queue a block with the C API (dispatch_async_f) on the default global
// queue. The block calls work(context).
void c_async_on_default_queue(void (*work)(void *), void *context);

#endif
