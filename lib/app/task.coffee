# Baseline task definition
stampede = require '../stampede'

class module.exports
	parentApp:			undefined

	constructor: (@parentApp) ->

	execute: (args, done) ->
		if args? and args.length > 0
			stampede.log.debug "Arguments: #{args.join(', ')}"
		done('Task action not defined.')

	getApp: -> @parentApp

	run: (args, done) ->
		done ?= () ->

		if @initialise?
			@initialise args, (err) =>
				if err? then return done err
				process.nextTick => @execute args, done
		else
			process.nextTick => @execute args, done
