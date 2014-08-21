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

apiRequest = require './apiRequest'

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

	redisDbName:			'redis'
	redisSessionPrefix:		'session:'

	name:					'Unnamed API Service'		# For reporting and logging we can name our service

	constructor: (app, config, bootConfig) ->
		super app, config, bootConfig
		@router = new stampede.router()
		@handlers = {}


	start: (done) ->
		# Create our express app, http service and socket.io instance and connect them all together
		@socketIoLogger = new sioLogger(log)
		@expressApp = express()
		@httpServer = http.createServer @expressApp

		@socketIo = io.listen @httpServer, { logger: @socketIoLogger, origins: @getSettings('origins') }

		# Set up our express middleware
		@expressApp.use express.compress()
		@expressApp.use @expressRequest
		@expressApp.use (req, res, next) =>
			res.send 404, 'Sorry could not find that!'
		@expressApp.use (err, req, res, next) =>
			res.send 500, "We made a boo boo: #{err}"

		# Fire up the server on the appropriate port
		port = @config[@name]?.port ? 8080
		stampede.log.info "Starting API service #{@name} on port #{port}"
		@httpServer.listen port

		@socketIo.sockets.on 'connection', (socket) =>
			log.debug "New socket connection established"
			socket.stampede = {}
			socket.stampede.controllerObject = @
			socket.stampede.messageHandlers = {}
			socket.stampede.cancelableRequests = {}
			socket.stampede.autoTidy = new stampede.autoTidy.bucket()
			socket.stampede.redisClient = {}


			# Register any socket event listeners that have been defined
			if @socketCallbacks?
				for fnName, fn in @socketCallbacks
					socket.on fnName, fn

			socket.on 'disconnect', () =>
				log.debug 'Socket disconnected'
				
				for n, rc of socket.stampede.redisClient ? {}
					log.debug "Auto-disconnecting from redis db: #{n}"
					rc.quit()

				delete socket.stampede

			socket.on 'setSession', (sessionId, callback) =>
				socket.stampede.setSessionId = sessionId
				@socketSetSession socket, sessionId, callback

			socket.on 'call', (req) =>
				unless req.path?
					log.error "Path not specified in request, ignoring"
					return

				@socketRequest socket, req

			socket.on 'request', (req, callback) =>
				unless callback?
					return socket.emit 'error', { error: 'Callback function not specified', request: req }

				unless req.path?
					return callback { error: 'path not specified' }

				@socketRequest socket, req, callback

			socket.on 'message', (req) =>
				log.error "Unhandled message on socket: #{req}"

			if @onSocketConnect?
				@onSocketConnect(con)

		# We're all done
		log.info "#{@name} started on port #{port}."

		# Call back to our parent
		super done

	expressRequest: (req, res, next) =>
		# Does the request match anything in our router?
		match = @router.find req.path

		# If we don't have a match tell express to move on to the next handler
		unless match?
			log.debug "Route for url '#{req.path}' not found."
			return next()

		log.debug "Route for url '#{req.path}' was found."

		# We have a match, let's build up the internal request object
		apiReq = new apiRequest(@)
		apiReq.setExpress req, res, next
			.setRouteVars match.vars
			.setUrl req.path

		method = req.method.toLowerCase()
		apiReq.setMethod method

		# Do we have a matching definition for our method type?
		if match.route[method]?
			log.debug "Handler for method #{method} was found"
			@handleRequest match, apiReq
		else
			log.debug "Handler for method #{method} was not found"
			next()

	socketRequest: (socket, req, callback) ->
		# Does the request match anything in our router?
		match = @router.find req.path

		# If we don't have a match then throw that error
		unless match?
			log.debug "Route for url (socket) '#{req.path}' not found."
			return callback { error: "Path not found: '#{req.path}'", request: req }

		log.debug "Route for url '#{req.path}' was found."

		# Build the internal request object
		apiReq = new apiRequest(@)
		apiReq.setSocket socket, req, callback
			.setRouteVars match.vars
			.setUrl req.path

		# Work out which HTTP method to use in our request
		method = req.method
		unless method?
			if match.route.socket? then method = 'socket'
			else method = 'get'

		apiReq.setMethod method

		# Work through the config
		apiReq.setStreaming(match.route.socketOptions?.stream ? match.route.options?.stream ? false)

		if match.route.socketOptions?
			# Is this a request that should only have a single instance per connection?
			if match.route.socketOptions.singleInstance?
				sid = match.route.socketOptions.singleInstance

				# Cancel existing request
				if socket.stampede.cancelableRequests[sid]?
					log.debug "Cancelling existing request for #{sid}"
					socket.stampede.cancelableRequests[sid].cancel()

				log.debug "Starting unique instance of #{sid}"
				socket.stampede.cancelableRequests[sid] = apiReq
				apiReq.setInstanceId sid

		# Do we have a matching definition for our method type?
		if match.route[method]?
			log.debug "Handler for method #{method} was found"

			@handleRequest match, apiReq
		else
			callback { error: "Handler for method #{method} was not found", request: req }

	finishRequestInstance: (socket, sid) ->
		delete socket.stampede.cancelableRequests[sid]
		@

	handleRequest: (match, apiReq) ->
		method = apiReq.getMethod()
		
		# Build up our params objects
		match.route[method+'BuildParams'] apiReq, (err) =>
			# If there's an error building our parameters then send the error response
			if err?
				log.error "Error building params: #{err}"
				apiReq.sendError { error: err }
			else
				log.debug "Params processed"
				if match.route.getSessionConfig()
					@checkSession match, apiReq
				else
					@preconnectDb match, apiReq

	checkSession: (match, apiReq) ->
		log.debug "Checking the session credentials"

		session = apiReq.getSession()

		sessionConfig = match.route.session
		if sessionConfig.loggedIn?
			if session.isLoggedIn() is false
				log.debug "Session is not logged in"
				return apiReq.send { error : 'Insufficient permissions', detail: 'Session is not logged in' }
			else
				log.debug 'Session is correctly logged in'

		if sessionConfig.userIdMatch?
			if '' + session.get('userId') isnt '' + apiReq.arg(sessionConfig.userIdMatch)
				log.debug "Session match failed: '#{session.get('userId')}' vs '#{apiReq.arg(sessionConfig.userIdMatch)}'"
				return apiReq.send { error: 'Insufficient permissions' }
			else
				log.debug "Session userIdMatch passed"


		# No authentication mechanisms yet
		@preconnectDb match, apiReq

	preconnectDb: (match, apiReq) ->
		dbList = if apiReq.isSocket
			match.route.socketOptions?.connectDb ? match.route.options?.connectDb ? []
		else if apiReq.isExpress
			match.route.options?.connectDb ? []

		unless stampede._.isArray dbList
			dbList = [ dbList ]

		stampede.async.each dbList, (dbName, callback) =>
			log.debug "Preconnecting to DB #{dbName}"
			apiReq.connectPostgres dbName, (err, dbh) =>
				log.debug "Connected to DB '#{dbName}' with response: #{if err? then err else 'connected'}"
				callback err
		, (err) =>
			if err?
				log.error "Error preconnecting to DB: #{err}"
				apiReq.sendError err
			else
				log.debug "Finished preconnecting to databases"
				@executeRequest match, apiReq

	executeRequest: (match, apiReq) ->
		method = apiReq.getMethod()

		# We have everything we need to generate our reponse, first let's see if we have a simple function to call
		if stampede._.isFunction match.route[method]
			log.debug "Calling handler function"
			match.route[method] apiReq, (response) =>
				apiReq.send response
		else
			# Nope, okay let's go through our checks for the clever bits of automated functionality
			log.debug "Auto DB request found"
			@autoRequestDb match.route[method], apiReq


	autoRequestDb: (route, apiReq) ->
		if route.db?
			apiReq.connectPostgres route.db, (err, dbh) =>
				if err? 
					apiReq.sendError err
				else
					@autoRequestRunQuery route, apiReq, dbh
		else if route.fn?
			route.fn apiReq
		else
			apiReq.sendError "No DB connection specified"

	autoRequestRunQuery: (route, apiReq, dbh) ->
		if route.fetchAll? and route.fetchOne?
			apiReq.error "Only one of fetchAll and fetchOne can be defined"
		else if route.fetchAll? or route.fetchOne?
			# Map any bind variables to our validated parameters
			bind = (apiReq.param(k) for k in (route.bind ? []))

			# Log what we're executing
			log.debug "Running query: #{route.fetchAll ? route.fetchOne}"
			bindCount = 0
			for b in bind
				log.debug "Binding value $#{++bindCount}: #{b}"

			# Execute the query
			dbh.query (route.fetchAll ? route.fetchOne), bind, (err, res) =>
				if err?
					apiReq.sendError "Error running query: #{err}"
				else
					if route.fetchOne? and res.rows.length > 1
						apiReq.sendError "fetchOne returned more than one result"
					else if route.fetchOne? and res.rows.length is 0
						log.debug "AutoSQL fetchOne returned zero results, sending notFound error."
						apiReq.send { error: "not found" }
					else
						# Pass our results on to the filter
						@autoRequestFilter route, apiReq, dbh, res.rows, route.fetchOne?
		else if route.send?
			route.send apiReq
		else
			apiReq.error "Either fetchAll or fetchOne or send must be defined"

	autoRequestFilter: (route, apiReq, dbh, res, fetchOne) ->
		if route.filter?
			# Use async to process each result row, filtering the result back into our result object
			stampede.async.map res, (item, callback) =>
				if route.filter.length is 2 then route.filter item, callback
				else route.filter apiReq, item, callback
			, (err, results) =>
				if err?
					apiReq.error err
				else if fetchOne
					if route.send? then route.send apiReq, results[0]
					else apiReq.send results[0]
				else
					results = stampede._.compact results
					if route.send? then route.send apiReq, results
					else apiReq.send results
		else
			if fetchOne
				if route.send? then route.send apiReq, res[0]
				else apiReq.send res[0]
			else
				if route.send? then route.send apiReq, res
				else apiReq.send res


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


	socketSetSession: (socket, sId, callback) ->
		unless stampede._.isString sId
			callback { status: 'error', error: 'Specified session Id is not a string', sessionFound: false }
			log.error "Session ID is not a string: #{sId}"
			return socket.emit 'server error', { error: 'Specified session Id is not a string', detail: sId }

		rc = @getApp().connectRedis @redisDbName
		rc.get @redisSessionPrefix + sId, (err, ses) =>
			rc.quit()

			if err?
				callback { status: 'error', error: err, sessionFound: false }
				log.error "Session lookup error: #{err}"
				return socket.emit 'server error', { error: 'Error retrieving session details', detail: err }

			unless ses?
				log.error "Session not found: #{sId}"
				callback { status: 'notFound', sessionFound: false }
				return socket.emit 'server error', { error: 'Session not found', detail: sId }

			sesData = JSON.parse ses

			session = new (apiRequest.sessionHandler)
			session.setFromPhp sesData

			socket.stampede.session = session

			callback { status: 'ok', sessionFound: true }

			if @onSession?
				@onSession socket

