###

API application service to fit into the stampede app framework.

###

stampede = require '../stampede'

log = stampede.log


class module.exports
	id:					undefined					# Unique ID nonce
	path:				undefined					# The resource request path
	replyTo:			undefined					# The named channel we should send replies to
	session:			undefined					# Our session object
	router:				undefined					# Router object to use for sub-requests
	socket:				undefined					# Attached socket via which responses will be sent
	outputQueue:		undefined					# Queued output messages
	databaseHandlers:	undefined					# List of all connected databases
	namedDatabases:		undefined					# Hash storing all named database connections
	active:				true						# True if a response is still wanted, false if the client has terminated or disconnected

	constructor: (@id, @path, @replyTo, @session, @router) ->
		@clearOutput()

		@databaseHandlers = []
		@namedDatabases = {}

	disconnect: () ->
		@active = false
		@

	attachToSocket: (@socket) ->
		@socket.activeRequests[@id] = @
		@

	finish: ->
		console.log "apiRequest.finish() called"

		# Flush our output messages
		@flushQueue()

		# Disconnect from any databases
		for dbh in @databaseHandlers
			dbh.disconnect()
			
		@databaseHandlers = []
		@namedDatabases = {}

		# Make sure we don't have any circular references in our parent socket
		delete @socket.activeRequests[@id]
		@socket = undefined
		@

	clearOutput: ->
		@outputQueue = []
		@

	flushQueue: ->
		# Send our queued output
		for obj in @outputQueue
			@sendNextObject obj
		@

	# Physically send a message to the client instead of queuing it up
	sendNextObject: (obj) ->
		return @ unless @active
		@socket.emit (obj.channel ? @replyTo), obj.toSend
		@

	# Our actual send function that does the hard work of adding a message to the queue
	sendToQueue: (channel, type, data, options = {}) ->
		obj = { toSend: { type: type, data: data } }
		
		if channel? then obj.channel = channel

		# Set any additional top level fields
		for k,v of options.set ? {}
			obj.toSend[k] = v

		# Do we want to send immediately or add to the queue?
		if options.sendImmediately
			@sendNextObject obj
		else
			# Adding to the queue
			@outputQueue.push obj

			if options.flushQueue
				@flushQueue()
		@

	# Wrapper around @sendToQueue to present a nicer interface with the following argument options:
	# 	request.send(messageObject)
	#	request.send(messageType, messageObject)
	#	request.send(channel, messageType, messageObject)
	send: (args...) ->
		if args.length is 1
			@sendToQueue undefined, 'response', args[0]
		else if args.length is 2
			@sendToQueue undefined, args[0], args[1]
		else
			@sendToQueue args[0], args[1], args[2]
		@

	# Wrapper around @sendToQueue in the same way as send, and with the same calling patterns, however messages are sent immediately instead of queued
	sendNow: (args...) ->
		if args.length is 1
			@sendToQueue undefined, 'response', args[0], { sendImmediately: true }
		else if args.length is 2
			@sendToQueue undefined, args[0], args[1], { sendImmediately: true }
		else
			@sendToQueue args[0], args[1], args[2], { sendImmediately: true }
		@


	# Wrapper around @sendToQueue for sending error responses, always sent immediately instead of queued
	#	request.error(errorMessage)
	#	request.error(errorMessage, detailsObject)
	#	request.error(channel, errorMessage, detailsObject)
	error: (args...) ->
		if args.length is 1
			@sendToQueue undefined, 'error', {}, { sendImmediately: true, set: { error: args[0]} }
		else if args.length is 2
			@sendToQueue undefined, 'error', args[1], { sendImmediately: true, set: { error: args[0]} }
		else
			@sendToQueue args[0], 'error', args[2], { sendImmediately: true, set: { error: args[1]} }
		@

	# Convenience wrapper around @error to always send to the error channel instead of @replyTo
	globalError: (args...) ->
		if args.length is 1
			@error 'error', args[0], undefined
		else
			@error 'error', args[0], args[1]
		@


	###
	# Database helper functions
	###

	# Create a new connection to the database
	databaseConnect: (dbName, callback) ->
		@socket.controller.parentApp.connectPostgres dbName, (err, dbh) =>
			if dbh? then @databaseHandlers.push dbh
			callback err, dbh
		@

	# Create a new named connection to the database
	preconnectDatabase: (dbName, callback) ->
		@databaseConnect dbName, (err, dbh) =>
			unless err? then @namedDatabases[dbName] = dbh
			callback err, dbh
		@

	# Get an already connected database
	getDatabaseConnection: (name) ->
		@namedDatabases[name]


	# Connect to redis
	redisConnect: (name) ->
		@socket.controller.parentApp.connectRedis name
