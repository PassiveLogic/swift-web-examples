// The smallest libdispatch program for WASI, in C.
//
// It queues three blocks on a serial queue. When they are done, a block on
// the main queue prints a summary and ends the program.
#include <dispatch/dispatch.h>
#include <stdio.h>
#include <stdlib.h>

int main(void) {
	dispatch_queue_t queue = dispatch_queue_create("hello", DISPATCH_QUEUE_SERIAL);
	dispatch_group_t group = dispatch_group_create();

	for (int i = 1; i <= 3; i++) {
		dispatch_group_async(group, queue, ^{
			printf("block %d ran on the serial queue\n", i);
		});
	}

	// dispatch_async never runs a block before it returns. So this line
	// prints first.
	printf("main() queued 3 blocks\n");

	dispatch_group_notify(group, dispatch_get_main_queue(), ^{
		printf("all blocks are done\n");
		exit(0);
	});

	// WASI has one thread. dispatch_main() runs the queued work on it.
	// It never returns. The notify block above ends the program.
	dispatch_main();
}
