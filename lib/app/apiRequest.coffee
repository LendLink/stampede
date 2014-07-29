###

API application service to fit into the stampede app framework.

###

stampede = require '../stampede'
log = stampede.log

class sessionHandler
	data:					undefined

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

	constructor: (p, session) ->
		@parentApi = p
		@routeVars = {}
		@pgDbList = []
		@pgNamed = {}
		@params = {}
		@session = session ? new sessionHandler()

	setExpress: (@expressReq, @expressRes, @expressNext) ->
		@isExpress = true
		@

	setSocket: (@socket, @socketReq, @socketCallback) ->
		if @socket.stampede?.session?
			@session = @socket.stampede.session
		@isSocket = true
		@
	
	newSession: ->
		@session = new sessionHandler()
		@session

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

	arg: (v) ->
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
			@socketReq.query[v]
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
		for dbh in @pgDbList when dbh?
			dbh.disconnect()

	send: (response = {}, doNotFinish = false) ->
		# Tidy up and close our connections
		@finish() unless doNotFinish is true

		if @isExpress is true
			@expressRes.json response
		else if @isSocket is true
			if @socketCallback?
				@socketCallback response
		else
			log.error "apiRequest - Eh?  Dunno how to send"

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
