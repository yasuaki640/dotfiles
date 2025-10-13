#!/bin/bash
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
if [ -n "$branch" ]; then
  diff_stats=$(git diff --numstat 2>/dev/null | awk '{added+=$1; deleted+=$2} END {if(added+deleted>0) printf " (+%d/-%d)", added, deleted}')
  echo "on: $branch$diff_stats"
fi
