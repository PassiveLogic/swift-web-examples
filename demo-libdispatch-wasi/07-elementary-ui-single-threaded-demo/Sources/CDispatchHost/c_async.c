#include "CDispatchHost.h"

#include <dispatch/dispatch.h>

void c_async_on_default_queue(void (*work)(void *), void *context) {
	dispatch_async_f(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
			context, work);
}
