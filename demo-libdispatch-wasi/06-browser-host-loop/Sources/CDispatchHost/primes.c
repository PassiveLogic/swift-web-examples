#include "CDispatchHost.h"

#include <dispatch/dispatch.h>
#include <stdlib.h>

struct primes_job {
	int limit;
	int primes;
	c_primes_done_t done;
	void *context;
};

// Runs on the main queue, after the count is done.
static void report(void *ctx) {
	struct primes_job *job = ctx;
	job->done(job->primes, job->context);
	free(job);
}

// Runs on a global queue.
static void count(void *ctx) {
	struct primes_job *job = ctx;
	for (int n = 2; n < job->limit; n++) {
		int prime = 1;
		for (int d = 2; d * d <= n; d++) {
			if (n % d == 0) { prime = 0; break; }
		}
		job->primes += prime;
	}
	dispatch_async_f(dispatch_get_main_queue(), job, report);
}

void c_count_primes_async(int limit, c_primes_done_t done, void *context) {
	struct primes_job *job = calloc(1, sizeof(*job));
	if (!job) abort();
	job->limit = limit;
	job->done = done;
	job->context = context;
	dispatch_async_f(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), job, count);
}
