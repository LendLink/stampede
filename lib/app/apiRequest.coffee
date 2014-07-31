###

API application service to fit into the stampede app framework.

###

stampede = require '../stampede'
log = stampede.log

class sessionHandler
	data:					undefined
	loggedIn:				undefined

	constructor: ->
		@data = {}

	get: (k) -> @data[k]
	set: (k, v) ->
		@data[k] = v
		@
	remove: (k) ->
		delete @data[k]
		@

	setFromPhp: (ses) ->
		@set 'userId', ses.id
		@set 'roles', ses.roles ? []
		
		if ses.id?
			@setLoggedIn()

	setLoggedIn: (@loggedIn = 'logged in') -> @
	getLoggedIn: -> @loggedIn
	isLoggedIn: -> if @loggedIn? then true else false
	logout: ->
		@loggedIn = undefined
		@

	dump: ->
		console.log ' '
		console.log 'Session details:'
		console.log "- logged in: #{@loggedIn}"
		console.log '- data:'
		for k, v of @data
			console.log "    #{k} = '#{v}'"
		console.log ' '

class module.exports
	@sessionHandler:		sessionHandler

	parentApi:				undefined
	isExpress:				false
	isSocket:				false
	isInternal:				false
	params:					undefined
	routeVars:				undefined
	args:					undefined
	expressReq:				undefined
	expressRes:				undefined
	expressNext:			undefined
	socket:					undefined
	socketReq:				undefined
	socketCallback:			undefined
	responseSent:			false
	pgDbList:				undefined
	pgNamed:				undefined
	url:					''
	method:					undefined
	session:				undefined

	autoTidyBucket:			undefined
	streamingTidyBucket:	undefined

	isStreaming:			false

	dump: ->
		console.log " "
		console.log "apiRequest Object"
		console.log "---------- ------"
		console.log " "
		console.log "URL:			#{@url}"
		console.log "Params:"
		for k,v of @params
			console.log "	'#{k}' = '#{v}'"
		console.log " "

	constructor: (p, session) ->
		@parentApi = p
		@routeVars = {}
		@pgDbList = []
		@pgNamed = {}
		@params = {}
		@session = session ? new sessionHandler()
		@autoTidyBucket = new stampede.autoTidy.bucket
		@streamingTidyBucket = new stampede.autoTidy.bucket

	setExpress: (@expressReq, @expressRes, @expressNext) ->
		@isExpress = true
		@

	setSocket: (@socket, @socketReq, @socketCallback) ->
		if @socket.stampede?.session?
			@session = @socket.stampede.session
		@isSocket = true
		@

	setStreaming: (set) ->
		if set is true
			if @isSocket
				@isStreaming = true
			else
				log.error "Trying to set streaming to true on a non-socket request.  Ignoring."
		else
			if @isStreaming
				log.error "Trying to set a streaming connection to not stream.  Ignoring."

	canSend: ->
		if @isExpress
			true
		else if @isSocket and @socketCallback
			true
		else
			false
	
	newSession: ->
		@session = new sessionHandler()
		@session

	getSession: -> @session
	setSession: (@session) -> @

	setParams: (@params) -> @

	param: (v) -> @params[v]

	setParam: (k, v) ->
		@params[k] = v
		@

	route: (v) -> @routeVars[v]

	setRouteVars: (@routeVars) -> @

	setUrl: (@url) -> @
	getUrl: -> @url

	setMethod: (@method) -> @
	getMethod: -> @method

	arg: (k) ->
		@param(k) ? @queryArg(k) ? @bodyArg(k)

	baseParams: (v) ->
		if @isExpress is true
			@expressReq.params[v]
		else if @isSocket is true
			@socketReq.params[v]
		else
			undefined

	queryArg: (v) ->
		if @isExpress is true
			@expressReq.query[v]
		else if @isSocket is true
			@socketReq.args?[v]
		else
			undefined

	bodyArg: (v) ->
		if @isExpress is true
			@expressReq.body[v]
		else if @isSocket is true
			@socketReq.body?[v]
		else
			undefined

	getService: -> @parentApi

	getConfig: -> @parentApi.getConfig()

	getApp: -> @parentApi.getApp()

	connectPostgres: (dbName, callback) ->
		db = @parentApi.getApp().connectPostgres dbName, (err, dbh) => 
			unless err?
				@pgDbList.push dbh
				@firstSetPgConnection dbName, dbh

			process.nextTick => callback err, dbh

	firstSetPgConnection: (dbName, dbh) ->
		unless @pgNamed[dbName]? then @pgNamed[dbName] = dbh
		@

	setPgConnection: (dbName, dbh) ->
		@pgNamed[dbName] = dbh
		@

	getPgConnection: (dbName) -> @pgNamed[dbName]
	getPostgresDbh: (dbName) -> @pgNamed[dbName]

	finish: ->
		log.debug "Auto-closing DB connections"
		for dbh in @pgDbList when dbh?
			dbh.disconnect()

	send: (response = {}, doNotFinish = false) ->
		# Tidy up and close our connections
		@finish() unless doNotFinish is true
		@canSend = false

		if @isExpress is true
			@expressRes.json response
		else if @isSocket is true
			if @socketCallback?
				# console.log "sending..."
				# console.log response
				@socketCallback response
				@socketCallback = undefined
		else
			log.error "apiRequest - Eh?  Dunno how to send"

		@

	stream: (channel, msg, callback, autoFinish = false) ->
		unless @isStreaming
			@setStreaming(true)

		unless @isStreaming
			log.error "Trying to stream to a non-streaming connection."
			return @

		if @isSocket
			log.debug "Sending stream message to #{channel}"
			# console.log msg
			@socket.emit channel, msg, callback
		else
			log.error "Do not how to stream to this connection."

		if autoFinish
			@finish()

		@

	sendError: (error, detail = undefined, doNotFinish = false) ->
		errObj = { error: error, url: @url }
		if detail? then errObj.detail = detail

		@send errObj, doNotFinish

	notFound: ->
		if @isExpress is true
			@responseSent = true
			@expressNext()
		else if @isSocket is true
			@send { error: "Path not found: '#{@socketReq.path}'", request: @socketReq }
		else
			log.error "Unhandled Not Found within apiRequest."
