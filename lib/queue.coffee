###
# queue.coffee
#
# Quick and easy worker queues within PostgreSQL.
###

###

Creation SQL:

CREATE TABLE stampede_queue (
	id				bigserial NOT NULL PRIMARY KEY,
	created			timestamp with time zone NOT NULL DEFAULT now(),
	event			text NOT NULL,
	started			timestamp with time zone,
	finished		timestamp with time zone,
	error			text
);

CREATE INDEX ON stampede_queue(id) WHERE started IS NULL;

###

