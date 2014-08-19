stampede = require '../stampede'
cluster = require 'cluster'
service = require './service'

log = stampede.log


class module.exports extends service
	name:					'Unnamed DB service'
	dbHandles:				undefined
	listeners:				undefined

	constructor: (app, config, bootConfig) ->
		super app, config, bootConfig

		@dbHandles = {}
		@listeners = {}

	start: (done) ->
		super (err) =>
			if err?
				if done? then return done err
				else return

			dbList = @getSettings('dbList') ? []

			unless dbList.length
				log.warn "No databases to connect to for db service #{@name}" 

			for dbName in dbList
				log.debug "#{@name} connecting to database #{dbName}"
				if @dbHandles[dbName]?
					log.critical "Database connection to DB '#{dbName}' already created."
				else
					@connectDb dbName

			if done? then done()

	connectDb: (dbName) ->
		log.debug "Connecting to database '#{dbName}'"
		if @dbHandles[dbName]? 
			@dbHandles[dbName].dbh.disconnect
			delete @dbHandles[dbName]

		@getApp().connectPostgres dbName, (err, dbh) =>
			if err?
				log.critical "Cannot connect to DB '#{dbName}': #{err}"
			else
				@dbHandles[dbName] = { dbh: dbh, listeners: {} }

				@initialiseDbh dbh, dbName
		@

	initialiseDbh: (dbh, dbName) ->
		log.debug "Initialising database #{dbName}"
		for chan of @listeners when @listeners[chan].length > 0
			log.debug "Adding database listener on '#{chan}' to '#{dbName}'"
			do (chan) ->
				dbh.query "LISTEN #{chan}", (err) =>
					if err?
						log.critical "Error listening for notifications on channel '#{chan}' on database '#{db}': #{err}"

		dbh.handle().on 'notification', (msg) =>
			@notification dbh, dbName, msg.channel, msg.payload

		log.debug "Database #{dbName} initialised"
		@

	listen: (ev, func) ->
		@listeners[ev] ?= []
		@listeners[ev].push func
		@

	notification: (dbh, dbName, channel, payload) ->
		log.debug "Event triggered on db #{dbName}: #{channel}"
		if @listeners[channel]?
			log.debug "Calling any synchronous handlers (#{dbName}: #{channel})"
			stampede.async.eachSeries (fn for fn in @listeners[channel] when fn.length is 4), (func, cb) =>
				func dbh, channel, payload, cb
			, (err) =>
				if err?
					log.error "Error on db #{db} handling event #{channel}: #{err}"
				else
					log.debug "Synchronous callbacks called, calling any parallel handlers (#{dbName}: #{channel})"
					stampede.async.each (fn for fn in @listeners[channel] when fn.length isnt 4), (func, cb) =>
						process.nextTick => func dbh, channel, payload
						cb()
					log.debug "Done handling event #{dbName}: #{channel}"
		@
