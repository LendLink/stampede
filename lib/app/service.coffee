stampede = require '../stampede'
cluster = require 'cluster'
events = require '../events'

log = stampede.log

class module.exports extends events
	parentApp:				undefined
	cluster:				false
	config:					undefined
	bootConfig:				undefined
	repeatEvery:			undefined
	repeatEveryIdCount:		0

	name:					'Unnamed service'

	constructor: (app, config, bootConfig) ->
		@parentApp = app
		@config = config
		@bootConfig = bootConfig ? {}
		@pgDbList = []
		@repeatEvery = {}

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
			if done? then process.nextTick => done(err)
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


	# Repeaters
	cancelEvery: (rep) ->
		clearInterval rep.timer
		@

	every: (seconds, fn) ->
		repeaterId = @repeatEveryIdCount++
		proc = { id: repeaterId, locked: false, instantReRun: false, fn: fn }

		@repeatEvery[repeaterId] = proc

		timerFunction = =>
			if proc.locked
				proc.instantReRun = true
			else
				proc.instantReRun = false
				proc.locked = true

				proc.fn proc, () =>
					proc.locked = false
					if proc.instantReRun
						process.nextTick timerFunction()

		proc.timer = setInterval timerFunction, seconds * 1000

		@
