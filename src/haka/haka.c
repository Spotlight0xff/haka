
#include <sys/types.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <assert.h>
#include <getopt.h>

#include <haka/error.h>
#include <haka/version.h>
#include <haka/lua/state.h>

#include "app.h"
#include "thread.h"
#include "lua/state.h"


extern void packet_set_mode(enum packet_mode mode);

static void usage(FILE *output, const char *program)
{
	fprintf(stdout, "Usage: %s [options] script_file [...]\n", program);
}

static void help(const char *program)
{
	usage(stdout, program);

	fprintf(stdout, "Options:\n");
	fprintf(stdout, "\t-h,--help:       Display this information\n");
	fprintf(stdout, "\t--version:       Display version information\n");
	fprintf(stdout, "\t-d,--debug:      Display debug output\n");
	fprintf(stdout, "\t--daemon:        Run in the background\n");
	fprintf(stdout, "\t-jN:             Use N threads for packet capture (if supported)\n");
	fprintf(stdout, "\t--pass-through:  Run in pass-through mode\n");
}

static bool daemonize = false;
static bool pass_throught = false;

static int parse_cmdline(int *argc, char ***argv)
{
	int c;
	int index = 0;

	static struct option long_options[] = {
		{ "version",      no_argument,       0, 'v' },
		{ "help",         no_argument,       0, 'h' },
		{ "debug",        no_argument,       0, 'd' },
		{ "daemon",       no_argument,       0, 'D' },
		{ "pass-through", no_argument,       0, 'P' },
		{ 0,              0,                 0, 0 }
	};

	while ((c = getopt_long(*argc, *argv, "dhj:", long_options, &index)) != -1) {
		switch (c) {
		case 'd':
			setlevel(HAKA_LOG_DEBUG, NULL);
			break;

		case 'h':
			help((*argv)[0]);
			return 0;

		case 'v':
			printf("version %s, arch %s, %s\n", HAKA_VERSION, HAKA_ARCH, HAKA_LUA);
			printf("API version %d\n", HAKA_API_VERSION);
			return 0;

		case 'D':
			daemonize = true;
			break;

		case 'P':
			pass_throught = true;
			break;

		case 'j':
			{
				const int thread_count = atoi(optarg);
				if (thread_count > 0) {
					thread_set_packet_capture_cpu_count(thread_count);
				}
				else {
					usage(stderr, (*argv)[0]);
					fprintf(stderr, "invalid thread count\n");
					return 2;
				}
			}
			break;

		default:
			usage(stderr, (*argv)[0]);
			return 2;
		}
	}

	if (optind >= *argc) {
		usage(stderr, (*argv)[0]);
		return 2;
	}

	*argc -= optind;
	*argv += optind;
	return -1;
}

int main(int argc, char *argv[])
{
	int ret;

	initialize();

	/* Check arguments */
	ret = parse_cmdline(&argc, &argv);
	if (ret >= 0) {
		clean_exit();
		return ret;
	}

	/* Init lua vm */
	{
		struct lua_state *global_lua_state = haka_init_state();

		/* Execute configuration file */
		if (run_file(global_lua_state->L, argv[0], argc-1, argv+1)) {
			message(HAKA_LOG_FATAL, L"core", L"configuration error");
			lua_state_close(global_lua_state);
			clean_exit();
			return 1;
		}

		lua_state_close(global_lua_state);
	}

	check();

	if (pass_throught) {
		messagef(HAKA_LOG_INFO, L"core", L"setting packet mode to pass-through\n");
		packet_set_mode(MODE_PASSTHROUGH);
	}

	/* Main loop */
	prepare(-1);
	start();

	clean_exit();
	return 0;
}
