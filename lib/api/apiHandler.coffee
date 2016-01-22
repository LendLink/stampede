###

API application service to fit into the stampede app framework.

###

stampede = require '../stampede'

log = stampede.log


class module.exports extends stampede.route
	handlerFunctionList:	[								# List of functions that get called in sequence to process the equest
		'loadSession', 'parseParameters', 'authorise', 'dbPreConnect', 'fetchSQL', 'handle', 'filter'
	]
	
	# Instance properties
	requestObject: 			undefined						# Cached link to our request object
	nextProcessStep:		undefined						# Callback function to iterate to the next 
	routeParameters:		undefined						# Parameters that are passed to us via the route / URL used to reach us
	requestParameters:		undefined						# Parameters that have been passed to the request
	validatedParameters:	undefined						# Parameters that have been through our validator and are safe to use

	# Override the constructor to initialise our object
	constructor: ->
		super

		@routeParameters = {}
		@requestParameters = {}
		@validatedParameters = {}

		@parameters ?= {}

	# Set the route parameters
	setRouteParameters: (@routeParameters) -> @

	# Set the request parameters
	setRequestParameters: (@requestParameters) ->
		unless stampede._.isObject @requestParameters
			@requestParameters = { unnamed: @requestParameters }
		@

	# Get a validated parameter
	get: (k) -> @validatedParameters[k]

	# Set a validated parameter
	set: (k, v) ->
		@validatedParameters[k] = v
		@

	getSession: -> @requestObject.session

	###
	# The following functions are used for flow control as each handler finishes
	###

	send: (args...) ->
		if args.length > 0
			@requestObject.send.apply @requestObject, args

	sendNow: (args...) ->
		if args.length > 0
			@requestObject.sendNow.apply @requestObject, args

	done: (args...) ->
		if args.length > 0
			@requestObject.send.apply @requestObject, args

		@nextProcessStep()

	finished: (args...) ->
		if args.length > 0
			@requestObject.send.apply @requestObject, args

		@nextProcessStep 'finished'

	error: (args...) ->
		if args.length > 0
			@requestObject.error.apply @requestObject, args

		@nextProcessStep 'handledError'

	globalError: (args...) ->
		if args.length > 0
			@requestObject.globalError.apply @requestObject, args

		@nextProcessStep 'handledError'

	###
	# Default handler functions and the processRequest function which is responsible for iterating through them
	###

	processRequest: (@requestObject, done) ->
		stampede.async.eachSeries @handlerFunctionList, (functionName, nextFunction) =>
			# Save our iterator
			@nextProcessStep = nextFunction

			# Look up the function we should be calling			
			fn = @[functionName]
			if fn?
				fn.apply @, [@requestObject, nextFunction]
			else
				nextFunction()
		, (err) =>
			if err is 'handledError' or err is 'finished'
				done()
			else
				done err
		@


	# Parse parameters - preprocess named parameters to validate the inputs
	parseParameters: (request) ->
		# Iterate through each of our parameters
		stampede.async.eachSeries Object.keys(@parameters), (k, next) =>
			# Retrieve the parameter definition
			p = @parameters[k]

			# Get the value we wish to parse
			val = @routeParameters[k] ? @requestParameters[k]

			# Call the validator function to check the value
			p.doCheck k, val, @, (checkError, validatedValue) =>
				if checkError?
					next checkError
				else
					@set k, validatedValue
					next()
		, (err) =>
			if err?
				@error err
			else
				@done()

	# Load the session, if any, from the socket to refresh the latest session data
	loadSession: (request) ->
		@done()		

	# Pre-connect to the database as a convenience
	dbPreConnect: (request) ->
		dbList = []

		# Get our list of databases to connect to
		if @db?.connect?
			if stampede._.isArray(@db.connect)
				dbList = @db.connect
			else
				dbList.push @db.connect

		# Iterate through that list, connecting to each database and saving the connection against the request object
		stampede.async.eachSeries dbList, (dbName, next) =>
			@requestObject.preconnectDatabase dbName, next
		, (err) =>
			if err?
				@error err
			else
				@done()

	# Get a database connection from the preconnected pool
	getDatabaseConnection: (name) ->
		@requestObject.getDatabaseConnection(name)
