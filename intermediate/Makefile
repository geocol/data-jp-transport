all:

wp-data: wp-railway-line-list.json \
    wp-railway-lines.json \
    wp-railway-stations.json

PERL = ../perl

wp-railway-line-list.json: ../bin/wp-railway-line-list.pl
	$(PERL) ../bin/wp-railway-line-list.pl > $@
wp-railway-lines.json: ../bin/wp-railway-lines.pl \
    wp-railway-line-list.json
	$(PERL) ../bin/wp-railway-lines.pl
wp-railway-stations.json: ../local/station-list.json \
    ../bin/wp-railway-stations-update.pl \
    ../bin/wp-railway-station-update-by-name.pl
	echo "{}" > $@
	$(PERL) ../bin/wp-railway-stations-update.pl

../local/station-list.json:
	cd .. && $(MAKE) local/station-list.json
