stampede = require '../stampede'
cluster = require 'cluster'
events = require '../events'

log = stampede.log

class module.exports extends events
	parentApp:				undefined
	cluster:				false
	config:					undefined
	bootConfig:				undefined

	name:					'Unnamed service'

	constructor: (app, config, bootConfig) ->
		@parentApp = app
		@config = config
		@bootConfig = bootConfig ? {}
		@pgDbList = []

		@bootConfig.name ?= 'unknown'
		@bootConfig.settings ?= {}

		if config.service? and config.service[@bootConfig.name]?
			@bootConfig.settings = stampede._.defaults config.service[@bootConfig.name], @bootConfig.settings

	preStart: (done) ->
		process.nextTick => done()
		@

	start: (done) ->
		@preStart (err) =>
			if err? then log.critical "Failed to pre-start service #{@name}: #{err}"
			if done? then process.nextTick => done()
			@

	## Accessors
	getConfig: -> @config
	getApp: -> @parentApp
	getSettings: (k) -> if k? then @bootConfig.settings[k] else @bootConfig.settings

	## Utility functions

	# Merge our configuration with a local configuration source
	mergeConfig: (fn) ->
		console.log "mergeConfig called"
		@

	filepath: (path) ->
		@parentApp.getBaseDirectory path


