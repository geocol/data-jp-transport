#!/bin/sh
echo "1..3"
basedir=`dirname $0`/..
jq=$basedir/local/bin/jq

test() {
  (cat $basedir/data/railways/stations.json | $jq "$2" | sh && echo "ok $1") || echo "not ok $1"
}

test 1 '.stations["10048"].label == "高岡駅"'
test 2 '.stations["10102"].companies["8"] | not | not'
test 3 '.stations["10161"].closed_date | not | not'
