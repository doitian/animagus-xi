#!/bin/bash

set -e
set -u
[ -n "${DEBUG:-}" ] && set -x || true

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR"

for AST_FILE in *.bin; do
  DOT_FILE="${AST_FILE%.bin}.dot"
  PDF_FILE="${AST_FILE%.bin}.pdf"

  go run . "${AST_FILE}" "${DOT_FILE}"
  dot -Tpdf "${DOT_FILE}" -o "${PDF_FILE}"

  if command -v open &> /dev/null; then
    open "${PDF_FILE}"
  else
    xopen "${PDF_FILE}"
  fi
done
