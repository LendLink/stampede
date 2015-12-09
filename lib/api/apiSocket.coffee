###

Helper module to keep track of connections and state for a specific open socket

###

stampede = require 'stampede'
socketSession = require './socketSession'
apiRequest = require './apiRequest'

log = stampede.log

class module.exports
	controller:				undefined				# Reference to the 
	socket:					undefined				# The socket to which we're attached
	session:				undefined				# Our session object for this connection
	messagesHandler:		undefined				# Function to call whenever we receive a message
	activeRequests:			undefined				# Object containing all active request objects
	lastRequestId:			0						# Incrementing nonce for requests
	redisConnection:		undefined				# Our read only / streaming listener connection to Redis
	redisSubscribers:		undefined				# Hash of subscribers to particular message channels
	errorChannel:			'error'					# Default channel to use for error messages
	redisSessionPrefix:		'session:'				# Prefixed to session IDs to convert to a redis key
	
	# Class helper to retrieve an instance of ourselves from an existing socket
	@getFromSocket: (socket) ->
		socket?.stampedeApi

	constructor: (@controller, @socket) ->
		# Initialise our properties
		@activeRequests = {}
		@redisSubscribers = {}

		# Attach ourselves to the socket itself
		@attachToSocket()

		# Create a new session
		@session = new socketSession()

		# Connect to redis
		@redisConnection = @controller.parentApp.connectRedis 'redis'
		@redisConnection.on 'pmessage', (pattern, channel, message) ->
			for handler in @redisSubscribers[pattern] ? []
				handler(channel, message, pattern)

	attachToSocket: ->
		# Modify the socket onevent method to include a call to our catchall event handler
		onevent = @socket.onevent
		thisInstance = @
		@socket.onevent = (packet) ->
			# Call the original handler
			onevent.call this, packet

			# Call our handler passing the packet data
			thisInstance.messageReceived.apply thisInstance, packet.data ? []

		# Disconnect any existing instances
		if @socket.stampedeApi?
			@socket.stampedeApi.disconnected()

		# Save ourselves against the socket.io object
		@socket.stampedeApi = @
		
		# Attach ourselves to the disconnect event
		@socket.on 'disconnect', =>
			@disconnected()

		@

	# Called when the socket disconnects, used to tidy up any resources that are in use
	disconnected: ->
		# Disconnect any active requests
		for reqId, request of @activeRequests
			request.disconnect()

		# Kill any redis message handlers so any subsequently received messages are not processed
		@redisSubscribers = {}

		# Disconnect from redis
		@redisConnection.quit()

		# Delete the reference to ourselves from the socket to ensure no circular references
		log.debug "Socket from #{@remoteIp()} has disconnected"
		delete @socket.stampedeApi
		delete @socket
		@

	# Subscribe a callback function to a redis channel or pattern
	redisSubscribe: (pattern, callback) ->
		unless @redisSubscribers[pattern]?
			@redisSubscribers[pattern] = []
			@redisConnection.psubscribe pattern

		@redisSubscribers[pattern].push callback
		@

	# Unsubscribe from a redis pub/sub stream.  If a callback is supplied just unsubscribe that one callback.
	redisUnsubscribe: (pattern, callback) ->
		return unless @redisSubscribers[pattern]?

		if callback?
			@redisSubscribers[pattern] = (cb for cb in @redisSubscribers[pattern] when cb isnt callback)
			if @redisSubscribers[pattern].length is 0
				delete @redisSubscribers[pattern]
				@redisConnection.punsubscribe pattern
		else
				delete @redisSubscribers[pattern]
				@redisConnection.punsubscribe pattern
		@

	# Create a new redis connection - the opener is responsible for closing it
	redisConnect: (name = 'redis') ->
		@controller.parentApp.connectRedis name

	# We've received a message!
	messageReceived: (channel, args...) ->
		log.debug "Message received on channel #{channel}: ", args
		
		if channel is 'request'
			@requestHandler channel, args
		else if channel is 'phpSession'
			@phpSessionHandler channel, args
		else if @messageHandler? and typeof @messageHandler is 'function'
			@messageHandler @, channel, args
		@

	# Set our message handling function
	onMessage: (@messageHandler) -> @

	# Wrapper around emit on the base socket
	emit: (channel, obj) ->
		@socket.emit channel, obj

	# Send a message to our attached socket in our standard wrapped form
	send: (channel, type, data, error) ->
		obj = { type: type, data: data }
		if error? then obj.error = error

		@socket.emit channel, obj
		@
	
	# Send an error message
	sendError: (channel, error, details) ->
		log.error "Sending error message: #{error}"
		@send channel, 'error', details, error

	# Helper function to look up the remote IP address of the client
	remoteIp: ->
		@socket.request?.connection?.remoteAddress

	# Helper function to look up the remote port of the client
	remotePort: ->
		@socket.request?.connection?.remotePort

	# Helper function to generate a new requestion object
	newRequest: (path, replyTo, router) ->
		# Create our object
		id = @lastRequestId++
		req = new apiRequest(id, path, replyTo, @session, router)
		req.attachToSocket @

		# Store it in our list of requests
		@activeRequests[id] = req

		# Return our object
		req

	# Handle an inbound request
	requestHandler: (channel, args) ->
		# Check we have a request object
		requestPacket = args.shift()
		unless requestPacket?
			@socket.sendError @errorChannel, 'Badly formed request', { originalChannel: channel, arguments: args }
			return

		# Check we have a request path
		unless requestPacket.path?
			@socket.sendError requestPacket.replyTo ? @errorChannel, 'No request path specified', { originalChannel: channel, arguments: args }
			return

		# Does the path match a known route in our router?
		match = @controller.router.find requestPacket.path

		unless match?
			@socket.sendError requestPacket.replyTo ? @errorChannel, "Unmatched path #{requestPacket.path}", { originalChannel: channel, arguments: args }
			return

		# Instance a new request object and pass over handling of the request to that object
		req = @newRequest requestPacket.path, requestPacket.replyTo, @controller.router
		req.attachToSocket @

		# Create a new route object
		route = new (Object.getPrototypeOf(match.route).constructor)
		route.setRouteParameters match.vars
		route.setRequestParameters requestPacket
		route.processRequest req, (err) =>
			if err?
				@sendError requestPacket.replyTo ? @errorChannel, "Route handler error for #{requestPacket.path}: #{err}", { requestObject: req }

			req.finish()


	# Handle an inbound session authorisation request
	phpSessionHandler: (channel, args) ->
		# Check for an onSession found callback
		if args[1]? then onSession = args[1]
		# We're only interested in the first argument
		args = args[0]

		# Convenience for if we're sent a string instead of an object for the session request
		if stampede._.isString args
			args = { sessionId: args }

		# Check we have a sessionId in our request object
		unless args.sessionId? and stampede._.isString(args.sessionId)
			return @sendError @errorChannel, "setSession error: invalid session ID", { sentId: args.sessionId }

		# Connect to redis and retrieve the session information
		rc = @redisConnect()
		rc.get (@redisSessionPrefix + args.sessionId), (err, rawData) =>
			# Kill our redis connection as it's not needed any more
			rc.quit()

			if err?
				return @sendError @errorChannel, "setSession error retrieving session: #{err}", { sentId: args.sessionId }

			unless rawData?
				return @sendError @errorChannel, "setSession error: session not found", { sentId: args.sessionId }

			sessionData = JSON.parse rawData

			@session.setId args.sessionId
			@session.setFromPhp sessionData

			if onSession?
				@emit channel, onSession({'sessionFound': true})
				@onSession()
