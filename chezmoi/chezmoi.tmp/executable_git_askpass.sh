#!/bin/sh
## Non-interactively pass credentials to git
## Point environmental variable GIT_ASKPASS to this file

case "$1" in
  Username*) echo 51386141 ;;
  Password*) echo "$GITHUB_PAT" ;;
esac
