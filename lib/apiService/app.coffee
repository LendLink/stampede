###

App - This is the basic application class that allows you to quickly and easily create API servers
	that serve a REST API using OAUTH authentication with additional support for streaming data
	over websockets.

###

stampede = require '../stampede'
events = require 'events'
express = require 'express'
http = require 'http'
io = require 'socket.io'

log = stampede.log



# Socket.IO logger - allows us to capture log events and redirect them to stampede / lumberjack.
class sioLogger
	enabled:		true

	constructor: (opts = {}) ->
		@level = 3

		@setEnabled(opts.enabled ? true) 

	log: (type, rest...) ->
		if type > @level or @enabled is false
			return @

		msg = rest.join('')
		switch type
			when 0 then log.error msg
			when 1 then log.warn msg
			when 2 then log.info msg
			when 3 then log.debug msg

		@

	setEnabled: (en) ->
		@enabled = en ? true
		@

	error: (rest...) ->
		rest.unshift 0
		@log.apply @, rest

	warn: (rest...) ->
		rest.unshift 1
		@log.apply @, rest

	info: (rest...) ->
		rest.unshift 2
		@log.apply @, rest

	debug: (rest...) ->
		rest.unshift 3
		@log.apply @, rest


# Our main class that API applications will inherit from
class module.exports extends events.EventEmitter
	devMode:			true							# if true then we are in dev mode and additional instrumentation is provided at cost to performance
	httpServer:			undefined						# Our Node.JS HTTP Server
	expressApp:			undefined						# The express application upon which our API app will be built
	socketIo:			undefined						# The instance of the websocket library
	socketIoLogger:		undefined						# The instance of the logger for the websocket library

	serverPort:			undefined						# The port we want to run on.  The default value is set in the constructor.
	name:				'API Application'				# Name of the service, used for logging purposes

	# Initialise a new instance of this module.  If overridden then in general this routine should be called prior to any extensions to the functionality.
	constructor: (opts = {}) ->
		@socketIoLogger = new sioLogger()

		@serverPort = opts.port ? 8080					# Specify the port we are running on 
		@setDevMode opts.devMode ? true					# Initialise if we should be running in dev mode or not


	# Getter and setter for specifying if we're in dev mode or not
	setDevMode: (s = true) ->
		@devMode = s
		@socketIoLogger.setEnabled(s)
		@

	getDevMode: -> @devMode


	# Getter and setter for the name
	@setName: (n) ->
		@name = n
		@

	@getName: -> @name

	# Getter and setter for the port we wish to run on - only settable until the start method is called
	setPort: (p) ->
		@serverPort = p
		@

	getPort: -> @serverPort


	#
	# Let's get the show on the road!!
	#

	start: ->
		# Create our express app, http service, and socket.io instance and connect them all together
		@expressApp = express()
		@httpServer = http.createServer @expressApp
		@socketIo = io.listen @httpServer, {
			logger:			@socketIoLogger
		}

		# Fire up the server on the appropriate port
		@httpServer.listen @serverPort

		@socketIo.sockets.on 'connection', (socket) =>
			socket.set 'controllerObject', @

		# We're all done
		log.info "#{@name} started."
		@emit 'started'

