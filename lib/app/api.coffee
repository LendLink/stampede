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

class apiRequest
	parentApi:				undefined
	isExpress:				false
	isInternal:				false
	params:					undefined
	args:					undefined
	expressReq:				undefined
	expressRes:				undefined
	expressNext:			undefined
	responseSent:			false
	pgDbList:				undefined

	constructor: (p) ->
		@parentApi = p
		@params = {}
		@args = {}
		@pgDbList = []

	setExpress: (@isExpress = false, @expressReq, @expressRes, @expressNext) -> @
	
	setParams: (@params) -> @

	param: (v) -> @params[v] ? @arg v

	route: (v) -> @params[v]

	arg: (v) ->
		if @isExpress is true
			@expressReq.param v
		else
			undefined

	queryArg: (v) ->
		if @isExpress is true
			@expressReq.query v
		else
			undefined

	bodyArg: (v) ->
		if @isExpress is true
			@expressReq.body[v]
		else
			undefined

	getService: -> @parentApi

	getConfig: -> @parentApi.getConfig()

	getApp: -> @parentApi.getApp()

	connectPostgres: (dbName, callback) ->
		db = @parentApi.getApp().getPostgres(dbName)

		# Did we find out database definition?
		return process.nextTick(=> callback("Database connection '#{dbName}' is not defined.")) unless db?

		stampede.dba.connect db, (err, dbh) =>
			@pgDbList.push dbh unless err?
			process.nextTick => callback err, dbh

	finish: ->
		for dbh in @pgDbList when dbh?
			dbh.disconnect()

	send: (response = {}, doNotFinish = false) ->
		# Tidy up and close our connections
		@finish() unless doNotFinish is true

		if @isExpress is true
			@expressRes.json response
		else
			console.log "Eh?  Dunno how to send (api.coffee)"

	notFound: ->
		if @isExpress is true
			@responseSent = true
			@expressNext()
		else
			console.log "Unhandled Not Found within apiRequest."


class module.exports extends service
	@apiRequest:			apiRequest
	# @apiResponse:			apiResponse

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
		@expressApp.use @expressRequest
		@expressApp.use (req, res, next) =>
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

	expressRequest: (req, res, next) =>
		# Does the request match anything in our router?
		match = @router.find req.path

		# If we don't have a match tell express to move on to the next handler
		return next() unless match?

		# We have a match, let's build up the internal request object
		apiReq = new apiRequest(@)
		apiReq.setExpress true, req, res, next
			.setParams match.vars

		method = req.method.toLowerCase()
		if match.route[method]?
			match.route[method] apiReq, (response) =>
				apiReq.send response
		else
			next()

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
