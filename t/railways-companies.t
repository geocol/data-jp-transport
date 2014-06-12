#!/bin/sh
echo "1..2"
basedir=`dirname $0`/..
jq=$basedir/local/bin/jq

test() {
  (cat $basedir/data/railways/companies.json | $jq "$2" | sh && echo "ok $1") || echo "not ok $1"
}

test 1 '.companies["16"].names["JR貨物"] | not | not'
test 2 '.companies["60"].label == "多摩都市モノレール"'
