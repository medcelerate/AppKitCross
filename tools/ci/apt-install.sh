#!/bin/sh
# Installs the Linux CI packages inside the swift:6.2-noble container.
#
# The container resolves archive.ubuntu.com / security.ubuntu.com through the
# runner's DNS, which has been observed to fail for hours at a time
# ("Could not resolve 'archive.ubuntu.com'"). GitHub's own Ubuntu runners use
# the Azure-hosted mirror, which is reachable from the runner network, so point
# apt there and retry a few times before giving up.
set -eu

for f in /etc/apt/sources.list /etc/apt/sources.list.d/ubuntu.sources; do
  [ -f "$f" ] || continue
  sed -i -e 's#http://archive\.ubuntu\.com/ubuntu#http://azure.archive.ubuntu.com/ubuntu#g' \
         -e 's#http://security\.ubuntu\.com/ubuntu#http://azure.archive.ubuntu.com/ubuntu#g' "$f"
done

attempt=1
until apt-get update -o Acquire::Retries=3; do
  if [ "$attempt" -ge 5 ]; then
    echo "apt-get update failed after $attempt attempts" >&2
    exit 1
  fi
  echo "apt-get update failed (attempt $attempt); retrying in 15s" >&2
  attempt=$((attempt + 1))
  sleep 15
done

apt-get install -y --no-install-recommends -o Acquire::Retries=3 "$@"
