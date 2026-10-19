// A tour of basic Dispatch (libdispatch) features on single-threaded WASI.
//
// Each check prints one line that starts with "PASS [name]" or "FAIL [name]".
// The last line is a summary. The program exits with 0 only if every check
// passes. demo.command looks for each PASS line in the output.
//
// One rule explains most of this file. WASI gives the program one thread.
// So dispatch_async never runs a block before it returns. Queued work runs
// later, at a "pump point":
//   - a blocking Dispatch wait at top level (semaphore, group, or a
//     dispatch_sync that must wait for earlier work)
//   - dispatch_main()
// Because of this rule, every wait in this file happens in main(), never
// inside a block that Dispatch runs.

#include <dispatch/dispatch.h>

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define NSEC_PER_MSEC_I64 ((int64_t)NSEC_PER_MSEC)

static int checks_run;
static int checks_failed;

static void report(bool ok, const char *name, const char *detail)
{
	checks_run++;
	if (!ok) {
		checks_failed++;
	}
	printf("%s [%s] %s\n", ok ? "PASS" : "FAIL", name, detail);
}

// Milliseconds on the monotonic clock. We use it to check timer delays.
static int64_t now_ms(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

// A deadline some milliseconds from now, for timed waits and timers.
static dispatch_time_t in_ms(int64_t ms)
{
	return dispatch_time(DISPATCH_TIME_NOW, ms * NSEC_PER_MSEC_I64);
}

// 1. dispatch_async to a global queue.
//    The block must not run before dispatch_async returns.
//    A semaphore wait at top level lets the block run.
static void check_async(void)
{
	__block bool ran = false;
	dispatch_semaphore_t done = dispatch_semaphore_create(0);
	dispatch_queue_t global = dispatch_get_global_queue(
			DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

	dispatch_async(global, ^{
		ran = true;
		dispatch_semaphore_signal(done);
	});
	bool ran_too_early = ran;

	long timed_out = dispatch_semaphore_wait(done, in_ms(2000));
	report(!ran_too_early && ran && timed_out == 0, "async",
			"global-queue block ran later, not inside dispatch_async");
}

// 2. A serial queue runs blocks one at a time, in FIFO order.
static void check_serial_fifo(void)
{
	enum { COUNT = 8 };
	// Blocks cannot capture C arrays, so the block writes through a pointer.
	int order_storage[COUNT];
	int *order = order_storage;
	__block int next = 0;
	dispatch_queue_t serial = dispatch_queue_create("demo.serial", NULL);
	dispatch_group_t group = dispatch_group_create();

	for (int i = 0; i < COUNT; i++) {
		dispatch_group_async(group, serial, ^{
			order[next++] = i;
		});
	}
	long timed_out = dispatch_group_wait(group, in_ms(2000));

	bool in_order = (timed_out == 0 && next == COUNT);
	for (int i = 0; in_order && i < COUNT; i++) {
		in_order = (order[i] == i);
	}
	report(in_order, "serial-fifo", "8 blocks on a serial queue ran in order");
	dispatch_release(group);
	dispatch_release(serial);
}

// 3. dispatch_sync runs the block before it returns.
//    When earlier async work is still queued, dispatch_sync waits for it.
//    That wait is a pump point.
static void check_sync(void)
{
	dispatch_queue_t serial = dispatch_queue_create("demo.sync", NULL);
	__block int value = 0;

	dispatch_sync(serial, ^{
		value = 1;
	});
	bool idle_ok = (value == 1);

	dispatch_async(serial, ^{
		value = 2;
	});
	__block int seen = 0;
	dispatch_sync(serial, ^{
		seen = value;
	});

	report(idle_ok && seen == 2, "sync",
			"dispatch_sync ran inline, then waited for earlier async work");
	dispatch_release(serial);
}

// 4. A group tracks several blocks. dispatch_group_wait blocks until all of
//    them finish. dispatch_group_notify runs a block after that.
static void check_group(void)
{
	dispatch_group_t group = dispatch_group_create();
	dispatch_queue_t global = dispatch_get_global_queue(
			DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_semaphore_t notified = dispatch_semaphore_create(0);
	__block int finished = 0;
	__block int finished_at_notify = -1;

	for (int i = 0; i < 4; i++) {
		dispatch_group_async(group, global, ^{
			finished++;
		});
	}
	dispatch_group_notify(group, global, ^{
		finished_at_notify = finished;
		dispatch_semaphore_signal(notified);
	});

	long wait_result = dispatch_group_wait(group, in_ms(2000));
	long notify_result = dispatch_semaphore_wait(notified, in_ms(2000));

	report(wait_result == 0 && notify_result == 0 && finished == 4 &&
			finished_at_notify == 4, "group",
			"group wait saw 4 blocks finish, then notify ran");
	dispatch_release(notified);
	dispatch_release(group);
}

// 5. Semaphores: a signal lets one wait go through at once.
//    A timed wait with no signal returns nonzero after its deadline.
static void check_semaphore(void)
{
	dispatch_semaphore_t sema = dispatch_semaphore_create(0);

	dispatch_semaphore_signal(sema);
	long first = dispatch_semaphore_wait(sema, DISPATCH_TIME_NOW);

	int64_t start = now_ms();
	long second = dispatch_semaphore_wait(sema, in_ms(50));
	int64_t waited = now_ms() - start;

	char detail[128];
	snprintf(detail, sizeof(detail),
			"signal then wait returned 0, timed wait timed out after %lld ms",
			(long long)waited);
	report(first == 0 && second != 0 && waited >= 50, "semaphore", detail);
	dispatch_release(sema);
}

// 6. dispatch_after runs a block no earlier than its deadline.
static void check_after(void)
{
	dispatch_semaphore_t done = dispatch_semaphore_create(0);
	dispatch_queue_t global = dispatch_get_global_queue(
			DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	__block int64_t fired_at = 0;
	int64_t start = now_ms();

	dispatch_after(in_ms(100), global, ^{
		fired_at = now_ms();
		dispatch_semaphore_signal(done);
	});
	long timed_out = dispatch_semaphore_wait(done, in_ms(5000));

	int64_t delay = fired_at - start;
	char detail[128];
	snprintf(detail, sizeof(detail),
			"block asked for 100 ms, ran after %lld ms", (long long)delay);
	report(timed_out == 0 && delay >= 100, "after", detail);
	dispatch_release(done);
}

// 7. A repeating timer source fires every 20 ms.
//    After 5 fires it cancels itself. The cancel handler then runs.
static void check_timer(void)
{
	dispatch_queue_t queue = dispatch_queue_create("demo.timer", NULL);
	dispatch_semaphore_t cancelled = dispatch_semaphore_create(0);
	dispatch_source_t timer = dispatch_source_create(
			DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
	__block int fires = 0;
	int64_t start = now_ms();

	dispatch_source_set_timer(timer, in_ms(20), 20 * NSEC_PER_MSEC, 0);
	dispatch_source_set_event_handler(timer, ^{
		fires++;
		if (fires == 5) {
			dispatch_source_cancel(timer);
		}
	});
	dispatch_source_set_cancel_handler(timer, ^{
		dispatch_semaphore_signal(cancelled);
	});
	dispatch_resume(timer);

	long timed_out = dispatch_semaphore_wait(cancelled, in_ms(5000));
	int64_t elapsed = now_ms() - start;

	char detail[128];
	snprintf(detail, sizeof(detail),
			"timer fired %d times in %lld ms, then cancelled itself",
			fires, (long long)elapsed);
	report(timed_out == 0 && fires == 5 && elapsed >= 100, "timer", detail);
	dispatch_release(timer);
	dispatch_release(cancelled);
	dispatch_release(queue);
}

// 8. dispatch_apply runs a block once per index and returns when all are done.
static void check_apply(void)
{
	enum { COUNT = 10 };
	int seen_storage[COUNT] = { 0 };
	int *seen = seen_storage;
	__block int sum = 0;
	dispatch_queue_t global = dispatch_get_global_queue(
			DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

	dispatch_apply(COUNT, global, ^(size_t i) {
		seen[i]++;
		sum += (int)i;
	});

	bool each_once = true;
	for (int i = 0; i < COUNT; i++) {
		each_once = each_once && (seen[i] == 1);
	}
	report(each_once && sum == 45, "apply",
			"10 iterations each ran once, index sum is 45");
}

// 9. dispatch_once runs its block exactly one time.
static int once_calls;

static void run_once(void)
{
	static dispatch_once_t token;
	dispatch_once(&token, ^{
		once_calls++;
	});
}

static void check_once(void)
{
	run_once();
	run_once();
	run_once();
	report(once_calls == 1, "once", "3 calls, the block ran 1 time");
}

// 10. A user-data source with DATA_ADD adds up merged values.
//     All 3 merges happen before the next pump point. So the handler
//     runs one time and sees the total.
static void check_data_add_source(void)
{
	dispatch_queue_t queue = dispatch_queue_create("demo.data-add", NULL);
	dispatch_semaphore_t handled = dispatch_semaphore_create(0);
	dispatch_source_t source = dispatch_source_create(
			DISPATCH_SOURCE_TYPE_DATA_ADD, 0, 0, queue);
	__block unsigned long total = 0;
	__block int calls = 0;

	dispatch_source_set_event_handler(source, ^{
		total += dispatch_source_get_data(source);
		calls++;
		dispatch_semaphore_signal(handled);
	});
	dispatch_resume(source);

	dispatch_source_merge_data(source, 1);
	dispatch_source_merge_data(source, 2);
	dispatch_source_merge_data(source, 3);
	long timed_out = dispatch_semaphore_wait(handled, in_ms(2000));

	char detail[128];
	snprintf(detail, sizeof(detail),
			"merged 1+2+3, handler saw %lu in %d call(s)", total, calls);
	report(timed_out == 0 && total == 6 && calls == 1, "data-add-source",
			detail);
	dispatch_source_cancel(source);
	dispatch_release(source);
	dispatch_release(handled);
	dispatch_release(queue);
}

// 11. dispatch_data: join two buffers, then map the result into one
//     contiguous buffer.
static void check_data(void)
{
	static const char hello[] = "Hello, ";
	static const char wasi[] = "WASI!";
	dispatch_data_t first = dispatch_data_create(hello, strlen(hello), NULL,
			DISPATCH_DATA_DESTRUCTOR_DEFAULT);
	dispatch_data_t second = dispatch_data_create(wasi, strlen(wasi), NULL,
			DISPATCH_DATA_DESTRUCTOR_DEFAULT);
	dispatch_data_t joined = dispatch_data_create_concat(first, second);

	const void *bytes = NULL;
	size_t size = 0;
	dispatch_data_t mapped = dispatch_data_create_map(joined, &bytes, &size);

	char text[32] = { 0 };
	bool ok = (size == 12 && size < sizeof(text));
	if (ok) {
		memcpy(text, bytes, size);
		ok = (strcmp(text, "Hello, WASI!") == 0);
	}

	char detail[128];
	snprintf(detail, sizeof(detail),
			"concat + map gave \"%s\" (%zu bytes)", text, size);
	report(ok, "data", detail);
	dispatch_release(mapped);
	dispatch_release(joined);
	dispatch_release(second);
	dispatch_release(first);
}

// 12. dispatch_main() runs the main queue. It also sleeps until the next
//     timer is due. It never returns. So the last main-queue block prints the
//     summary and calls exit(). If nothing is left to run, dispatch_main()
//     stops the program with "no runnable work on single-threaded WASI".
static int64_t main_start_ms;

static void finish(void *context)
{
	(void)context;
	int64_t waited = now_ms() - main_start_ms;
	char detail[128];
	snprintf(detail, sizeof(detail),
			"main-queue block ran %lld ms later, inside dispatch_main()",
			(long long)waited);
	report(waited >= 50, "dispatch-main", detail);

	int passed = checks_run - checks_failed;
	if (checks_failed == 0) {
		printf("ALL %d CHECKS PASSED\n", checks_run);
	} else {
		printf("%d of %d checks passed, %d FAILED\n", passed, checks_run,
				checks_failed);
	}
	exit(checks_failed == 0 ? 0 : 1);
}

int main(void)
{
	// Line buffering keeps the output if the program traps part way.
	setvbuf(stdout, NULL, _IOLBF, 0);
	printf("libdispatch on WASI: basic checks\n");

	check_async();
	check_serial_fifo();
	check_sync();
	check_group();
	check_semaphore();
	check_after();
	check_timer();
	check_apply();
	check_once();
	check_data_add_source();
	check_data();

	main_start_ms = now_ms();
	dispatch_after_f(in_ms(50), dispatch_get_main_queue(), NULL, finish);
	dispatch_main();
}
