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

		for dbName in @getSettings('dbList')
			if @dbHandles[dbName]?
				log.critical "Database connection to DB '#{dbName}' already created."
			else
				@connectDb dbName

	connectDb: (dbName) ->
		if @dbHandles[dbName]? 
			@dbHandles[dbName].dbh.disconnect
			delete @dbHandles[dbName]

		@getApp().connectPostgres dbName, (err, dbh) =>
			if err?
				log.critical "Cannot connect to DB '#{dbName}': #{err}"
			else
				@dbHandles[dbName] = { dbh: dbh, listeners: {} }

				@initialiseDbh dbh, dbName

	initialiseDbh: (dbh, dbName) ->
		log.debug "Initialising database #{dbName}"
		for chan of @listeneres when @listeners[chan].length > 0
			do (chan) ->
				dbh.query "LISTEN #{chan}", (err) =>
					if err?
						stampede.log.critical "Error listening for notifications on channel '#{chan}' on database '#{db}': #{err}"

		log.debug "Database #{dbName} initialised"

	listen: (ev, func) ->
		@listeners[ev] ?= []
		@listeners[ev].push func
		@

