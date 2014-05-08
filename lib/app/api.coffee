###

API application service to fit into the stampede app framework.

###

stampede = require '../stampede'
events = require 'events'
express = require 'express'
http = require 'http'
io = require 'socket.io'
fs = require 'fs'

log = stampede.log

sioLogger = require './sioLogger'
service = require './service'


class module.exports extends service
	devMode:				true						# If true then we are in dev mode and additional instrumentation and logging is provided
	httpServer:				undefined					# Our Node.JS HTTP or HTTPS server
	expressApp:				undefined					# The express application upon which our API app will be built
	socketIo:				undefined					# The instance of socket.io that will provide our real time communication
	socketIoLogger:			undefined					# The instance of our logger that will bridge socket.io's logging with that of stampede
	router:					undefined
	handlers:				undefined

	name:					'Unnamed API Service'		# For reporting and logging we can name our service

	constructor: (app, config) ->
		super app, config
		@router = new stampede.router()
		@handlers = {}


	start: (done) ->
		# Create our express app, http service and socket.io instance and connect them all together
		@socketIoLogger = new sioLogger(log)
		@expressApp = express()
		@httpServer = http.createServer @expressApp
		@socketIo = io.listen @httpServer, { logger: @socketIoLogger }

		# Set up our express middleware
		@expressApp.use express.compress()
		@expressApp.use (req, res, next) ->
			res.send 404, 'Sorry could not find that!'
		@expressApp.use (err, req, res, next) =>
			res.send 500, "We made a boo boo: #{err}"

		# Fire up the server on the appropriate port
		port = @config[@name]?.port ? 8080
		@httpServer.listen port

		@socketIo.sockets.on 'connection', (socket) =>
			socket.set 'controllerObject', @

		# We're all done
		log.info "#{@name} started on port #{port}."

		# Call back to our parent
		super done


	addHandlerDirectory: (path, done) ->
		path = @filepath path
		log.debug "Adding handler directory #{path}"

		# Open the directory asynchronously so we can scan through its files
		fs.readdir path, (err, files) =>
			if err?
				log.error "Error scanning directory '#{path}': #{err}"
				return done(err)

			# For each file in our directory we're going to require it and then scan it for routes
			for file in files when not @handlers[path + '/' + file]?
				log.debug "Loading handler #{path + '/' + file}"
				h = require path + '/' + file
				@handlers[path + '/' + file] = h

				# Scan through the handler for routes that can be added to the router
				for name, route of h when stampede._.isFunction(route)
					log.debug "Checking potential route #{name}"
					
					# Temporarily instance the route
					i = new route()
					if i instanceof stampede.route
						log.debug "Route #{name} is valid, installing in our router."
						@router.addRoute i
					else
						log.debug "Route #{name} is not a stampede route."

			process.nextTick => done()
		@
