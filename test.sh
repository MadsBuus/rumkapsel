#!/bin/zsh
# The gate: every suite, then the scenarios, on the fast build, in a throwaway support folder.
#   ./test.sh            all of it
#   ./test.sh staging    only the scenarios whose name contains "staging" (the suites still run)
set -e
cd "$(dirname "$0")"
./build.sh fast >/dev/null
BIN=.build/debug/Rumkapsel
export RUMKAPSEL_SUPPORT=${RUMKAPSEL_SUPPORT:-$(mktemp -d)}
START=$SECONDS
FAILED=0
for suite in rule sim idle walk ledger work deploy pipeline layout spacelog look; do
  OUT=$($BIN --$suite-tests 2>&1) || FAILED=1
  echo "$OUT" | grep -E "not so|FAIL" || true
  echo "$OUT" | tail -1
done
$BIN --scenarios ${1:-} 2>&1 | grep -E "FAIL|not so|passed in" || FAILED=1
echo "gate: $((SECONDS - START))s"
exit $FAILED
