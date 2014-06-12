#!/bin/sh
echo "1..4"
basedir=`dirname $0`/..
jq=$basedir/local/bin/jq

test() {
  (cat $basedir/data/railways/lines.json | $jq "$2" | sh && echo "ok $1") || echo "not ok $1"
}

test 1 '.lines["1060"].names["高尾登山ケーブル"] | not | not'
test 2 '.lines["1096"].closed | not | not'
test 3 '.lines["1098"].stations | length > 10'
test 4 '.lines["1159"].companies["15"] | not | not'