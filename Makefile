GIT = git

all: data-railways

updatenightly: clean deps all
	$(GIT) add data/* intermediate/*

data: data-railways
review: review-railways

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
	rm -fr local/suffix-patterns.json local/regions.json

wp-deps:
	$(PERL) bin/prepare-wikipedia-cache.pl

wp-data: wp-deps
	cd intermediate && $(MAKE) wp-data
	$(GIT) add intermediate

## ------ Railways ------

data-railways: \
    data/railways/lines.json  data/railways/companies.json \
    data/railways/stations.json \
    data/railways/region-lines.json

review-railways: local/railway-line-ids.json.diff

local/src-railway-lines.json: src/railway-lines.txt bin/src-railway-lines.pl
	$(PERL) bin/src-railway-lines.pl > $@
local/railway-line-names.txt: local/src-railway-lines.json \
    intermediate/wp-railway-line-list.json \
    intermediate/wp-railway-stations.json \
    bin/railway-line-names.pl
	$(PERL) bin/railway-line-names.pl > $@
intermediate/line-ids.json: local/railway-line-names.txt \
    bin/railway-line-name-to-id.pl
	$(PERL) bin/railway-line-name-to-id.pl
data/railways/lines.json: bin/railway-lines.pl local/src-railway-lines.json \
    intermediate/wp-railway-line-list.json local/railway-lines.json \
    intermediate/line-ids.json intermediate/company-ids.json \
    intermediate/station-ids.json
	$(PERL) bin/railway-lines.pl > $@
local/railway-line-ids.json.diff: bin/check-railway-line-ids.pl \
    data/railways/lines.json local/railway-line-ids.json \
    intermediate/line-ids.json
	$(PERL) bin/check-railway-line-ids.pl

local/src-railway-companies.json: src/railway-companies.txt \
    bin/src-railway-companies.pl
	$(PERL) bin/src-railway-companies.pl > $@
intermediate/company-ids.json: intermediate/wp-railway-stations.json \
    bin/append-company-ids.pl
	$(PERL) bin/append-company-ids.pl
data/railways/companies.json: bin/railway-companies.pl \
    intermediate/company-ids.json src/railway-companies-names.txt \
    local/src-railway-companies.json
	$(PERL) bin/railway-companies.pl > $@

local/src-railway-stations.json: src/railway-stations.txt \
    bin/src-railway-stations.pl
	$(PERL) bin/src-railway-stations.pl > $@
intermediate/station-ids.json: intermediate/wp-railway-stations.json \
    bin/append-station-ids.pl intermediate/company-ids.json
	$(PERL) bin/append-station-ids.pl
data/railways/stations.json: bin/railway-stations-2.pl \
    intermediate/company-ids.json intermediate/station-ids.json \
    intermediate/line-ids.json local/src-railway-stations.json
	$(PERL) bin/railway-stations-2.pl > $@

local/bin/jq:
	$(WGET) -O $@ http://stedolan.github.io/jq/download/linux64/jq
	chmod u+x local/bin/jq

local/station-list.json: local/bin/jq intermediate/wp-railway-lines.json
	cat intermediate/wp-railway-lines.json  | local/bin/jq "[.[].stations[] | .wref // .name] | unique" > $@

local/suffix-patterns.json:
	$(WGET) -O $@ https://raw.github.com/geocol/data-jp-areas/master/data/jp-regions-suffix-mixed-names.json

local/regions.json:
	$(WGET) -O $@ https://raw.github.com/geocol/data-jp-areas/master/data/jp-regions.json

data/railways/region-lines.json: bin/railways-region-lines.pl \
    data/railways/stations.json
	$(PERL) bin/railways-region-lines.pl > $@

local/N02-12.xml: local/N02-12_GML.zip
	cd local && unzip -o N02-12_GML.zip
	touch $@

local/ksj-railroads.json: local/N02-12.xml bin/ksj-railroads.pl
	$(PERL) bin/ksj-railroads.pl > $@

local/railway-lines.json: \
    intermediate/wp-railway-line-list.json \
    intermediate/wp-railway-lines.json \
    intermediate/wp-railway-stations.json bin/railway-lines-2.pl
	$(PERL) bin/railway-lines-2.pl > $@

## ------ Tests ------

PROVE = ./prove

test: test-deps test-main

test-deps: deps local/bin/jq

test-main:
	$(PROVE) t/*.t
