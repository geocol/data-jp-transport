GIT = git

all: data-railways

dataautoupdate: clean deps all
	$(GIT) add data/*

clean:

## ------ Setup ------

WGET = wget
PERL = ./perl

deps: git-submodules pmbp-install

git-submodules:
	$(GIT) submodule update --init

local/bin/pmbp.pl:
	mkdir -p local/bin
	$(WGET) -O $@ https://raw.github.com/wakaba/perl-setupenv/master/bin/pmbp.pl
pmbp-upgrade: local/bin/pmbp.pl
	perl local/bin/pmbp.pl --update-pmbp-pl
pmbp-update: git-submodules pmbp-upgrade
	perl local/bin/pmbp.pl --update
pmbp-install: pmbp-upgrade
	perl local/bin/pmbp.pl --install \
            --create-perl-command-shortcut perl \
            --create-perl-command-shortcut prove

## ------ Wikipedia dumps ------

wikipedia-dumps: local/cache/xml/jawiki-latest-pages-meta-current.xml

%.xml: %.xml.bz2
	bzcat $< > $@

local/cache/xml/jawiki-latest-pages-meta-current.xml.bz2:
	mkdir -p local/cache/xml
	$(WGET) -O $@ http://download.wikimedia.org/jawiki/latest/jawiki-latest-pages-meta-current.xml.bz2

wp-autoupdate: deps wp-clean wp-data

wp-clean:
	rm -fr local/intermediate-wikipedia local/suffix-patterns.json
	rm -fr local/regions.json

wp-deps:
	$(PERL) bin/prepare-wikipedia-cache.pl

wp-data: wp-deps intermediate/railway-lines.json \
    intermediate/railway-stations.json \
    intermediate/stations.json
	$(GIT) add intermediate

## ------ Railways ------

data-railways: \
    data/railway-lines.json data/stations.json data/region-lines.json \
    data/stations.json.gz \
    data/railways/lines.json  data/railways/companies.json \
    data/railways/stations.json

intermediate/railway-lines.json: bin/railway-lines.pl \
    local/intermediate-wikipedia #wikipedia-dumps
	$(PERL) bin/railway-lines.pl > $@

intermediate/line-ids.json: intermediate/railway-lines.json \
    bin/append-line-ids.pl
	$(PERL) bin/append-line-ids.pl

intermediate/company-ids.json: intermediate/stations.json \
    bin/append-company-ids.pl
	$(PERL) bin/append-company-ids.pl

intermediate/station-ids.json: intermediate/stations.json \
    bin/append-station-ids.pl
	$(PERL) bin/append-station-ids.pl

intermediate/railway-stations.json: bin/railway-stations.pl \
    intermediate/railway-lines.json local/intermediate-wikipedia \
    #wikipedia-dumps
	mkdir -p intermediate
	$(PERL) bin/railway-stations.pl

local/railway-station-lines.json: bin/railway-station-lines.pl \
    intermediate/railway-stations.json
	mkdir -p intermediate
	$(PERL) bin/railway-station-lines.pl > $@

local/bin/jq:
	$(WGET) -O $@ http://stedolan.github.io/jq/download/linux64/jq
	chmod u+x local/bin/jq

local/station-list.json: local/bin/jq intermediate/railway-stations.json
	cat intermediate/railway-stations.json  | local/bin/jq "[.[].stations[] | .wref // .name] | unique" > $@

intermediate/stations.json: local/station-list.json \
    bin/update-station-data.pl local/intermediate-wikipedia #wikipedia-dumps
	echo "{}" > $@
	$(PERL) bin/update-station-data.pl

data/railway-lines.json: intermediate/railway-stations.json \
    intermediate/stations.json bin/railway-lines-2.pl
	$(PERL) bin/railway-lines-2.pl > $@

data/railways/lines.json: bin/railway-lines-3.pl data/railway-lines.json \
    intermediate/line-ids.json
	$(PERL) bin/railway-lines-3.pl > $@

data/railways/companies.json: bin/railway-companies.pl \
    intermediate/company-ids.json
	$(PERL) bin/railway-companies.pl > $@

data/railways/stations.json: bin/railway-stations-2.pl \
    intermediate/company-ids.json intermediate/station-ids.json
	$(PERL) bin/railway-stations-2.pl > $@

data/stations.json: intermediate/stations.json \
    local/suffix-patterns.json local/regions.json bin/stations.pl
	$(PERL) bin/stations.pl > $@

data/stations.json.gz: data/stations.json
	cat $< | gzip > $@

local/intermediate-wikipedia:
	touch $@

local/suffix-patterns.json:
	$(WGET) -O $@ https://raw.github.com/geocol/data-jp-areas/master/data/jp-regions-suffix-mixed-names.json

local/regions.json:
	$(WGET) -O $@ https://raw.github.com/geocol/data-jp-areas/master/data/jp-regions.json

data/region-lines.json: bin/region-lines.pl data/stations.json
	$(PERL) bin/region-lines.pl > $@

local/N02-12.xml: local/N02-12_GML.zip
	cd local && unzip -o N02-12_GML.zip
	touch $@

local/ksj-railroads.json: local/N02-12.xml bin/ksj-railroads.pl
	$(PERL) bin/ksj-railroads.pl > $@

## ------ Tests ------

PROVE = ./prove

test: test-deps test-main

test-deps: deps

test-main:
#	$(PROVE) t/*.t