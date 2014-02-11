###
dbService.coffee - Skeleton Stampede database scheduled tasks and listener
###


stampede = require './stampede'
events = require 'events'
pg = require 'pg'


class dbConnection extends events.EventEmitter
	conStr:					undefined
	pgDbh:					undefined
	pgDisconnect:			undefined
	timer:					undefined
	connectFunction: 		undefined
	notificationFunction:	undefined
	pingFrequency:			3

	constructor: (con) ->
		@conStr = con

		@on 'connect', =>
			stampede.lumberjack.info "Connecting to database '#{@conStr}'."
			pg.connect @conStr, (err, client, done) =>
				if err?
					stampede.lumberjack.critical "Connection error on '#{@conStr}': #{err}"
					if @timer then clearTimeout @timer
					@timer = setTimeout((=> @emit 'connect'), 30000)
					@dbh = undefined
				else
					@pgDbh = client
					@pgDisconnect = done
					stampede.lumberjack.info "Connected to database '#{@conStr}'."
					@emit 'connected'

		@on 'disconnect', =>
			stampede.lumberjack.info "Disconnecting from database '#{@conStr}'."

			if @pgDisconnect? then @pgDisconnect()
			@pgDbh = undefined
			if @timer? then clearTimeout @timer

		@on 'reconnect', =>
			stampede.lumberjack.warn "Reconnecting to database '#{@conStr}'."
			@emit 'disconnect'
			@emit 'connect'

		@on 'connected', =>
			if @timer then clearTimeout @timer
			@timer = setTimeout((=> @emit 'ping'), @pingFrequency * 1000)
			if @connectFunction? then @connectFunction @pgDbh

			@pgDbh.on 'notification', (msg) =>
				if @notificationFunction? then @notificationFunction(msg.channel, msg.payload)


		@on 'ping', =>
			if @timer then clearTimeout @timer
			@timer = setTimeout((=> @emit 'ping'), @pingFrequency * 1000)
			@pgDbh.query 'SELECT 1', (err, res) =>
				if err?
					stampede.lumberjack.critical "Error pinging the database '#{@conStr}': #{err}"
					@reconnect()
				# Otherwise we're all good



	onConnect: (func) ->
		@connectFunction = func
		@

	onNotification: (func) ->
		@notificationFunction = func
		@

	connect: ->
		@emit 'connect'
		@

	disconnect: ->
		@emit 'disconnect'
		@

	reconnect: ->
		@emit 'reconnect'
		@

	h: ->
		@pgDbh


class module.exports
	dbList: 		undefined
	listeners:		undefined
	repeat:			undefined

	onStart: ->
		stampede.lumberjack.critical "No events or handlers defined."

	constructor: ->
		@dbList = []
		@listeners = {}
		@repeat = []

		@onStart()

	connect: (l) ->
		for db in l
			@connectDb db
		@

	listen: (ev, func) ->
		@listeners[ev] ?= []
		@listeners[ev].push func
		@

	every: (minutes, func) ->
		@repeat
		@

	connectDb: (dbStr) ->
		db = new dbConnection(dbStr)
		db.onConnect () =>
			# Connect to each of our listener channels
			for chan of @listeners when @listeners[chan].length > 0
				db.h().query "LISTEN #{chan}", (err) =>
					if err?
						lumberjack.critical "Error listening for notifications."
					console.log "Listening to #{chan}"
					db.h().query "NOTIFY announce_notification"

		db.onNotification (chan, msg) =>
			console.log chan
			console.log msg

		db.connect()
		@dbList.push db




# class Dbh extends events.EventEmitter
# 	pgDbh: undefined
# 	pgDisconnect: undefined
# 	timeout: undefined

# 	constructor: (dbhost, dbname, dbuser, dbpass) ->
# 		@on 'Connect', ->
# 			conStr = "pg://#{dbuser}:#{dbpass}@#{dbhost}/#{dbname}"
# 			pg.connect conStr, (err, client, done) =>
# 				if err?
# 					lumberjack.critical "Database connection to '#{conStr}' received error: '#{err}'"
# 					setTimeout (=> @emit 'Connect'), 30000
# 					if @timeout?
# 						clearTimeout @timeout
# 				else
# 					@pgDbh = client
# 					@pgDisconnect = done
# 					@emit 'Connected'

# 		@on 'Disconnect', ->
# 			lumberjack.info "Disconnecting from database #{dbname} on #{dbhost}"
# 			if pgDisconnect? then pgDisconnect()
# 			pgDbh = undefined
# 			pgDisconnect = undefined
# 			if @timeout?
# 				clearTimeout @timeout

# 		@on 'Reconnect', ->
# 			lumberjack.warn "Reconnecting to database #{dbname} on #{dbhost}"
# 			@emit 'Disconnect'
# 			@emit 'Connect'

# 		@on 'Connected', ->
# 			lumberjack.critical "Connected to database #{dbname} on #{dbhost}"

# 			@pgDbh.on 'notification', (msg) =>
# 				lumberjack.debug 'Recevied notification: %s', msg
# 				# Trigger a tick
# 				@setTimer 0

# 			@pgDbh.query 'LISTEN announce_async', (err, res) =>
# 				if err?
# 					lumberjack.critical "Error listening to announce_async in db #{dbname} on #{dbhost}: '#{err}'"
# 					@emit 'Reconnect'
# 			@setTimer 0

# 		@on 'Tick', ->
# 			lumberjack.debug "Processing queue on database #{dbname} on #{dbhost}"
# 			@pgDbh.query 'SELECT * FROM announce_email_queue WHERE sent IS NULL AND error IS NULL ORDER BY id ASC LIMIT 100', (err, res) =>
# 				if err?
# 					lumberjack.critical "Error retrieving email queue on database #{dbname} on #{dbhost}: '#{err}'"
# 					@emit 'Reconnect'
# 					return

# 				if res.rows.length > 0
# 					async.eachLimit res.rows, 10, @processEmail(), (asErr) =>
# 						if err?
# 							lumberjack.critical "Error processing email list on database #{dbname} on #{dbhost}: '#{asErr}'"
# 							@emit 'Reconnect'
# 							return

# 						@setTimer 0
# 				else
# 					lumberjack.debug "No emails in the queue on database #{dbname} on #{dbhose}"
# 					@setTimer 60000

# 	processEmail: ->
# 		(email, callback) =>
# 			lumberjack.log 'Processing an email with id #{email.id}'
# 			callback()

# 	start: () ->
# 		@emit 'Connect'

# 	setTimer: (timeoutDelay) ->
# 		if @timeout?
# 			clearTimeout @timeout
# 		lumberjack.debug "Resetting timer to #{timeoutDelay}"
# 		@timeout = setTimeout (=> @emit 'Tick'), timeoutDelay

