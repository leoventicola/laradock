#!/bin/sh
#
# pecl.php.net is flaky: downloads truncate mid-file ("unable to unpack") and its REST
# metadata sometimes comes back broken ("Package X does not have REST info xml
# available"). This wrapper makes every `pecl install` survive both: it retries after
# clearing the partial-download cache, and as a last resort fetches the package tarball
# with curl (the same URL PEAR uses) and installs that local file instead.
#
# It is installed as `pecl`; the original binary stays next to it as `pecl.real`.
#
i=1
while :; do
	if "$0.real" "$@"; then
		exit 0
	fi

	# Fallback: install from the tarball(s) on pecl.php.net instead of over its REST API.
	# The command keeps its original shape (subcommand and options stay where the caller
	# put them); only the package specs are replaced by the downloaded files.
	case " $* " in
		*" install "*)
			cmd=""
			files=""
			for arg in "$@"; do
				case "$arg" in
					install | -* | */*) cmd="$cmd $arg" ;;
					*)
						if curl -fsSL --http1.1 --retry 5 --retry-delay 2 --retry-all-errors \
							-o "/tmp/pecl-$arg.tgz" "https://pecl.php.net/get/$arg"; then
							files="$files /tmp/pecl-$arg.tgz"
						else
							cmd="$cmd $arg"
						fi
						;;
				esac
			done
			# shellcheck disable=SC2086  # word splitting is intended for the arg lists
			if [ -n "$files" ] && "$0.real" $cmd $files; then
				rm -f /tmp/pecl-*.tgz
				exit 0
			fi
			;;
	esac

	[ "$i" -ge 5 ] && exit 1
	echo "pecl: attempt $i failed, clearing cache and retrying..." >&2
	rm -rf /tmp/pear/download/* /tmp/pear/temp/* 2>/dev/null || true
	i=$((i + 1))
	sleep 3
done
