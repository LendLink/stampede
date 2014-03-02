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


sioLogger = require './sioLogger'


# Our main class that API applications will inherit from
class module.exports extends events.EventEmitter
	# Internal configuration and storage properties
	devMode:			true							# if true then we are in dev mode and additional instrumentation is provided at cost to performance
	httpServer:			undefined						# Our Node.JS HTTP Server
	expressApp:			undefined						# The express application upon which our API app will be built
	socketIo:			undefined						# The instance of the websocket library
	socketIoLogger:		undefined						# The instance of the logger for the websocket library

	# 
	serverPort:			undefined						# The port we want to run on.  The default value is set in the constructor.
	name:				'API Application'				# Name of the service, used for logging purposes

	# Initialise a new instance of this module.  If overridden then in general this routine should be called prior to any extensions to the functionality.
	constructor: (opts = {}) ->
		@socketIoLogger = new sioLogger(log)

		@setPort opts.port ? 8080						# Specify the port we are running on 
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
	# Define the Application
	#

	# Add a new path that contains libraries for us to include within the application
	addController: (path) ->
		console.log "Adding controller #{path}"
		@

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
		@httpServer.listen @getPort()

		@socketIo.sockets.on 'connection', (socket) =>
			socket.set 'controllerObject', @

		# We're all done
		log.info "#{@name} started on port #{@getPort()}."
		@emit 'started'
		@

