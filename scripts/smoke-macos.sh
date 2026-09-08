#!/bin/bash
set -euo pipefail
export AIDOKU_TEST_PAYLOAD="$PWD/build/SourcePackages/checkouts/AidokuRunner/Tests/AidokuRunnerTests/Resources/Payload"
test -f "$AIDOKU_TEST_PAYLOAD/main.wasm"
python3 - <<'PY'
import subprocess, pathlib
app="build/DerivedData/Build/Products/Release/Aidoku.app/Contents/MacOS/Aidoku"
try:
    result=subprocess.run([app,"--smoke-test"],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=90,text=True)
except subprocess.TimeoutExpired as error:
    print("Native smoke tests timed out")
    raise SystemExit(1)
pathlib.Path("build/smoke.log").write_text(result.stdout)
print(result.stdout)
if result.returncode != 0 or "ALL NATIVE SMOKE TESTS PASSED" not in result.stdout:
    raise SystemExit(1)
PY
