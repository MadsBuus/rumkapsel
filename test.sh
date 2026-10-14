#!/bin/zsh
# The gate: every suite, then the three smoke scenarios, on the fast build, each in a throwaway support folder.
# The three slowest run beside the rest, so at most four processes at once.
#   ./test.sh            all of it
#   ./test.sh offices    only the smoke scenarios whose name contains "offices" (the suites still run)
cd "$(dirname "$0")"
./build.sh fast >/dev/null || { echo "build failed"; exit 1 }
BIN=$PWD/.build/debug/Rumkapsel
OUT=$(mktemp -d)
trap 'kill $(jobs -p) 2>/dev/null; wait' EXIT INT TERM
START=$SECONDS
run() { RUMKAPSEL_SUPPORT=$(mktemp -d) $BIN "$@" >$OUT/$1 2>&1; echo $? >$OUT/$1.code }
run --scenarios ${1:-} &
run --playback-tests &
run --intake-tests &
for suite in rule sim idle walk work deploy github pipeline layout spacelog look log; do run --$suite-tests; done
wait
FAILED=0
for suite in rule intake playback sim idle walk work deploy github pipeline layout spacelog look log; do
  grep -E "not so|FAIL" $OUT/--$suite-tests
  tail -1 $OUT/--$suite-tests
  [ "$(cat $OUT/--$suite-tests.code 2>/dev/null)" = 0 ] || { FAILED=1; echo "$suite: exit $(cat $OUT/--$suite-tests.code 2>/dev/null || echo none)" }
done
grep -E "FAIL|not so|passed in" $OUT/--scenarios
[ "$(cat $OUT/--scenarios.code 2>/dev/null)" = 0 ] || { FAILED=1; echo "scenarios: exit $(cat $OUT/--scenarios.code 2>/dev/null || echo none)" }
echo "gate: $((SECONDS - START))s"
exit $FAILED
