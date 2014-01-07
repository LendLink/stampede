###
app.coffee - Skeleton Stampede Application
###

###
We support the following application related activities:
	- tasks 	- command line jobs and commands that run in their own isolated 
	- api		- REST / Websocket API
	- web		- HTTP based websites
###


stampede = require './stampede'
express = require 'express'

# The application class in all its glory.
# New user applications should inherit from this class and extend it as required.

class module.exports extends stampede.events.eventEmitter
	baseDirectory: './'

	constructor: (baseDir = './') ->
		if baseDir is './'
			@setBaseDirectory process.cwd()
		else 
			@setBaseDirectory = baseDir

		console.log @getBaseDirectory()

	getBaseDirectory: (extList...) ->
		if extList?
			@baseDirectory + extList.join('/')
		else
			@baseDirectory

	setBaseDirectory: (set) ->
		if set.match(/\/$/)
			@baseDirectory = set
		else
			@baseDirectory = set + '/'
		@

	exec: ->
		console.log "app.exec() called."
		for arg in process.argv
			console.log "Argument: #{arg}"
