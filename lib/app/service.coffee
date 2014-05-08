stampede = require '../stampede'
cluster = require 'cluster'
events = require '../events'

log = stampede.log

class module.exports extends events
	parentApp:				undefined
	cluster:				false
	config:					undefined
	name:					'Unnamed service'

	constructor: (app, config) ->
		@parentApp = app
		@config = config

	preStart: (done) ->
		process.nextTick => done()
		@

	start: (done) ->
		@preStart (err) =>
			if err? then log.critical "Failed to pre-start service #{@name}: #{err}"
			if done? then process.nextTick => done()
			@

	## Utility functions

	# Merge our configuration with a local configuration source
	mergeConfig: (fn) ->
		@

	filepath: (path) ->
		@parentApp.getBaseDirectory path
