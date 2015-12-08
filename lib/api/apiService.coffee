###

API application service to fit into the stampede app framework.

###

stampede = require '../stampede'
Inotify = require('inotify').Inotify
express = require 'express'
http = require 'http'
io = require 'socket.io'
fs = require 'fs'
cookieParser = require 'cookie-parser'

log = stampede.log

sioLogger = require '../app/sioLogger'
service = require '../app/service'

socketSession = require './socketSession'

# apiRequest = require './apiRequest'
apiSocket = require './apiSocket'


class module.exports extends service
	devMode:				false						# If true then we are in dev mode and additional instrumentation and logging is provided
	httpServer:				undefined					# Our Node.JS HTTP or HTTPS server
	expressApp:				undefined					# The express application upon which our API app will be built
	socketIo:				undefined					# The instance of socket.io that will provide our real time communication
	socketIoLogger:			undefined					# The instance of our logger that will bridge socket.io's logging with that of stampede
	router:					undefined					# Our main router for working out what should handle a given request
	hanlders:				undefined					# Object storing the paths of imported handler files and their resultant compiled code
	inotify:				undefined					# Central inotify object used to track changes of handler files when in debug mode

	onSocketConnect:		undefined					# If defined then this function is called whenever a new socket is opened

	redisDbName:			'redis'
	redisSessionPrefix:		'session:'

	name:					'Unnamed API Service'		# For reporting and logging we can name our service

	constructor: (app, config, bootConfig) ->
		super app, config, bootConfig
		@router = new stampede.router()
		@handlers = {}

		if app.isDebug() or @getSetting('developerMode', false) is true
			@devMode = true
			@inotify = new Inotify()

	# Called when the service first starts
	start: (done) ->
		stampede.async.series [
			(next) =>
				@preStart next

			(next) =>
				# Create our express app, http service and socket.io instance and connect them all together
				@socketIoLogger = new sioLogger(log)
				@expressApp = express()
				@httpServer = http.createServer @expressApp

				@socketIo = io.listen @httpServer, { logger: @socketIoLogger, origins: @getSetting('origins') }

				# Set up our express middleware
				@expressApp.use cookieParser()
				@expressApp.use (req, res, next) =>
					res.send 404, 'Sorry could not find that!'
				@expressApp.use (err, req, res, next) =>
					res.send 500, "We made a boo boo: #{err}"

				# Fire up the server on the appropriate port
				port = @getSetting 'port', 8080
				stampede.log.info "Starting API service #{@name} on port #{port}"
				@httpServer.listen port

				@socketIo.sockets.on 'connection', (socket) =>
					log.debug "New websocket connection created"
					@initialiseSocket socket

			(next) =>
				@postStart next

		], (err) =>
			if err?
				log.critical "Error during startup, stopping process: #{err}"

			done err

	# Called prior to any other setup work being done, including the creation of the websocket listener
	# Override this function to do something interesting during this phase
	preStart: (done) ->
		done()

	# Same as above but called after everything else in the startup phase
	postStart: (done) ->
		done()

	# Called on a new socket when it first connects.  Sets up our abstractions.
	initialiseSocket: (socket) ->
		api = new apiSocket(@, socket)
		log.info "New socket connection established from #{api.remoteIp()}"

		if @onSocketConnect?
			@onSocketConnect(api)

	# Scan a directory for apiHandler classes, adding them to our request router
	addHandlerDirectory: (path, done) ->
		path = @filepath path
		log.info "Adding handler directory #{path}"

		# Open the directory asynchronously so we can scan through its files
		fs.readdir path, (err, files) =>
			if err?
				log.error "Error scanning directory '#{path}': #{err}"
				return done(err)

			# For each file in our directory we're going to require it and then scan it for routes
			for file in files when not @handlers[path + '/' + file]?
				# Calculate the full local path and then localise it to this loop iteration
				localPath = path + '/' + file
				do (localPath) =>
					log.debug "Loading handler #{localPath}"
					h = require localPath
					@handlers[localPath] = h

					# If we're in debug mode reload the process (call exit) if one of our source files changes
					if @inotify?
						@inotify.addWatch {
							path:			localPath
							watch_for:		Inotify.IN_CLOSE_WRITE
							callback:		->
								log.debug "File '#{localPath}' has changed, restarting process."
								process.exit()
						}

					# Scan through the handler for routes that can be added to the router
					for name, route of h when stampede._.isFunction(route)
						log.debug "Checking potential route #{name} in file #{localPath}"
						
						# Temporarily instance the route
						i = new route()
						if i instanceof stampede.api.handler
							log.debug "Route #{name} is valid, installing in our router."
							@router.addRoute i
						else
							log.debug "Route #{name} is not a stampede API handler."

			setImmediate => done()
		@