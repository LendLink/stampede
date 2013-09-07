###
# dba.coffee
#
# Database abstraction layer for PostgreSQL.
###

inform = require './inform'
utils = require './utils'
validator = require './validator'
moment = require 'moment'
sha1 = require 'sha1'
async = require 'async'
pg = require 'pg'
crypto = require 'crypto'



###
# Error object
###

class exports.dbError
	pgErr: undefined
	rawSql: undefined
	bindVars: []
	errorMessage: ''

	constructor: (err, sql, bind, msg) ->
		@pgErr = err
		@rawSql = sql
		@bindVars = bind
		@errorMessage = msg

	isError: true

	show: (shouldExit = true) ->
		console.log ' '
		console.log @errorMessage
		console.log "    SQL: #{@rawSql}" if @rawSql
		console.log "    Bind: #{@bindVars.join(', ')}" if @bindVars
		console.log "    Error: #{@pgErr}" if @pgErr
		console.log ' '
		if shouldExit is true then process.exit()

	error: () ->
		"#{@errorMessage}: #{@pgErr}"

	dbError: () ->
		@pgErr

	sql: () ->
		@rawSql

	bindData: () ->
		@bindVars

	throwError: () ->
		throw @error()

###
# Cache object for storing table data
###

class exports.cache
	table:		undefined

	constructor: ->
		@table = {}

	clear: ->
		@table = {}


###
# Database connection details
###

exports.connect = (conString, callback, cache) ->
	exports.connection.connect(conString, callback, cache)

class exports.connection
	pgDbh:		undefined
	pgDone:		undefined
	cacheObj:	undefined
	queryLog:	undefined

	@connect: (conString, callback, cache) ->
		pg.connect conString, (err, client, done) ->
			if err? then return callback err

			dbh = new exports.connection(client, done, cache)
			callback undefined, dbh

	constructor: (dbh, done, cache) ->
		if cache?
			@cacheObj = cache
		else
			@cacheObj = new exports.cache()
		@clearLog()
		@connect(dbh, done)

	handle: -> @pgDbh

	queries: -> @queryLog

	query: (args...) ->
		query_start = new moment()
		handle = @pgDbh.query.apply(@pgDbh, args)
		handle.on 'end', =>
			query_end = new moment()
			@queryLog.push {
				sql:			args[0]
				bind:			if utils.objType(args[1]) is 'array' then args[1] else []
				time:			query_end.diff(query_start)
			}
		return handle

	clearLog: -> @queryLog = []

	disconnect: ->
		if @pgDone?
			@pgDone()

		@pgDone = undefined
		@pgDbh = undefined

		@

	connect: (dbh, done) ->
		@pgDbh = dbh
		@pgDone = done




###
# Field definitions
###


class exports.column extends utils.extendEvents
	name:				undefined
	type:				'bytea'
	dbType:				undefined
	dbFieldName:		undefined
	allowNull:			true
	defaultValue:		undefined
	includeRules:		undefined
	validator:			undefined
	validationRules:	undefined
	extendRecord:		undefined
	preselectEvent: 	undefined
	formFieldType:		undefined
	formLabel:			undefined
	showFormLabel:		true
	primaryKey:			false

	constructor: ->
		super
		@validator = new validator.Validator()
		@validationRules = []
		@events = {}
		@includeRules = {
			select:			true
			insert:			true
			update:			true
			toJson:			true
			fromJson:		true
		}
		@extendRecord = {}

		@addValidationRule (val) ->
			if val? then return true
			if @allowNull is true then return true
			if @defaultValue? then return true
			return "Null values are not allowed."

	addRule: (rule, args, errStr) ->
		@validator.addRule(rule, args, errStr)
		@


	installExtensions: (rec) ->
		for fun of @extendRecord
			unless rec[fun]?
				rec[fun] = @extendRecord[fun]


	setName: (name) ->
		@name = name
		@

	getValidator: ->
		@validator

	setValidator: (v) ->
		@validator = v
		@

	getFormFieldType: ->
		@formFieldType ? 'text'

	setFormFieldType: (type) ->
		@formFieldType = type
		@

	setLabel: (label) ->
		@formLabel = label
		@

	getLabel: ->
		if @formLabel?
			@formLabel
		else
			label = @name
			label = label.replace(/_/g, ' ')
			label = label.replace /([a-z])([A-Z])/g, (str, pre, post) -> pre + ' ' + post
			label = label.replace /([^\W_]+[^\s-]*) */g, (txt) -> txt.charAt(0).toUpperCase() + txt.substr(1).toLowerCase()
			label

	showLabel: ->
		@showFormLabel

	setPrimaryKey: (val = true) ->
		@primaryKey = val
		@

	isPrimaryKey: ->
		@primaryKey

	getName: -> @name

	getType: -> @type
	getDbType: -> @dbType ? @type

	setDbType: (newType) ->
		@dbType = newType
		return @

	serialise: (data, record) -> @emitCall 'serialise', data, record
	deserialise: (data, record) -> @emitCall 'deserialise', data, record

	get: (data, record) ->
		data = @emitCall 'pre_get_value', data, record
		unless data? then data = @evalDefault()
		@emitCall 'get_value', data, record

	set: (data, record) -> 
		data = @emitCall 'pre_set_value', data, record
		errors = @validate(data)
		if errors.length > 0
			throw "Validation error#{if errors.length isnt 1 then 's' else ''} when setting field #{@name} to #{data}: #{errors.join('; ')}"
		@emitCall 'set_value', data, record

	toString: (data, record) ->
		data = @emitCall 'pre_get_value', data, record
		unless data? then data = @evalDefault()
		data = @emitCall 'tostring_value', data, record
		if data? then return '' + data
		else return undefined

	default: (setVal) ->
		@defaultValue = setVal
		@

	noDefault: ->
		@defaultValue = undefined
		@

	evalDefault: ->
		@emitCall 'eval_default', @defaultValue

	setAllowNull: ->
		@allowNull = true
		@

	notNull: ->
		@allowNull = false
		@

	getDbFieldName: -> @dbFieldName ? @name

	setDbFieldName: (newFieldName) ->
		@dbFieldName = newFieldName
		@

	addValidationRule: (rule) ->
		@validationRules.push rule

	validate: (value) ->
		errors = []
		for rule in @validationRules
			valid = rule.apply(@, [value])
			if valid? and valid isnt true
				errors.push valid
		if errors.length > 0
			return @emitCall('validation_fail', errors, value)
		else
			return @emitCall('validation_pass', true, value)
		return errors

	include: (type) ->
		if @includeRules[type] then true else false


	# formField: (form) ->
	# 	new inform.text(form.getAttribute('name')+'_'+utils.idSafe(@fieldName), form)




class exports.record
	columns:			undefined
	overrideColumn:		undefined
	data:				undefined
	modified:			undefined
	table:				undefined
	columnValidator:	undefined
	linkedRecords:		undefined

	constructor: (setTable) ->
		@columns = {}
		@data = {}
		@modified = {}
		@columnValidator = {}
		@linkedRecords = {}

		if setTable?
			@setTable(setTable)

	setValidator: (col, v) ->
		@columnValidator[col] = v
		@

	isValid: (recordSet, iAm) ->
		valid = true
		for col, v of @columnValidator
			if v.isValid() is false then valid = false
		valid

	hasErrors: (col) ->
		if @columnValidator[col]? then @columnValidator[col].hasErrors() else false

	hasWarnings: (col) ->
		if @columnValidator[col]? then @columnValidator[col].hasWarnings() else false

	getErrors: (col) ->
		if @columnValidator[col]? then @columnValidator[col].getErrors() else false

	getWarnings: (col) ->
		if @columnValidator[col]? then @columnValidator[col].getWarnings() else false

	setTable: (setTable) ->
		@table = setTable

		colDef = @table.getColumns()
		for cname of colDef
			@columns[cname] = colDef[cname]
			@data[cname] = undefined
			@columns[cname].installExtensions(@)

		@

	setLinkedRecord: (col, rec) ->
		unless @getColumn(col) instanceof exports.link then throw "Column #{col} is not a linked column."
		@linkedRecords[col] = rec
		@

	getLinkedRecord: (col, dbh, options, callback) ->
		column = @getColumn(col)
		unless column instanceof exports.link then throw "Column #{col} is not a linked column."

		if arguments.length is 3 
			callback = options
			options = {}

		# If we're called synchronously then we just return whatever's been cached
		unless callback?
			return @linkedRecords[col]

		# Asynchronous call
		# If we have a record cached then shortcut outta here
		if @linkedRecords[col]? and not options.link? and options.ignoreCache isnt true
			callback undefined, @linkedRecords[col]
			return @linkedRecords[col]

		# Nothing cached so let's go fetch it from the database
		selectOpts = { filter: {} }
		selectOpts.filter[column.getLinkColumn()] = @get(col)

		column.getLinkTable().newSelect dbh, selectOpts, (err, res) =>
			if err? then return callback err, undefined

			if column.getLinkType() is 'one to one'
				unless options.skipSave is true
					@linkedRecords[col] = res[0]

				callback undefined, res[0]
			else
				callback undefined, res

	getTable: ->
		@table

	getParent: -> @parentTable

	dump: (indent = '') ->
		console.log "#{indent}Table #{@table.tableName()} (all primary keys set is #{@allPrimaryKeysSet()})"
		for f of @columns
			mod = if @modified[f] then ' (modified)' else ''
			if @columns[f].getType() is 'map'
				console.log "#{indent}  #{f} of type map:"
				subField = @get(f)
				if subField? then subField.dump(indent+'    ')
				else console.log indent+'    <null>'
			if @columns[f].getType() is 'link'
				console.log "#{indent}  #{f} of type link with key: #{@get(f)}"
				if @linkedRecords[f]?
					console.log "#{indent}    Linked record is cached:"
					@linkedRecords[f].dump(indent+'       ')
				else
					console.log "#{indent}    Linked record is not cached or is null."
			else
				console.log "#{indent}  #{f} of type #{@columns[f].getType()} = #{@data[f]}#{mod}"

			if @columnValidator[f] then @columnValidator[f].dump(indent + '  ')
	
	set: (col, value) ->
		if @table?
			@data[col] = @columns[col].set(value, @)
			@modified[col] = true
			@
		else
			@data[col] = value
			@modified[col] = true
			@

	addColumn: (colName, colDef, data) ->
		@columns[colName] = colDef
		@data[colName] = data
		@

	getColumn: (col) ->
		@columns[col]

	columnExists: (col) ->
		if @columns[col]? then true else false

	columnNames: () ->
		col for col of @columns

	forceSet: (col, value, setModified = true) ->
		@data[col] = value
		@modified[col] = true if setModified
		@

	edit: (col) ->
		@modified[col] = true
		@data[col]

	rawData: (col) ->
		@data[col]

	get: (col) ->
		if @table?
			unless @columns[col]? then throw "Unknown table column '#{col}' in result set."
			@columns[col].get(@data[col], @)
		else
			@data[col]

	toString: (col) ->
		if @table?
			@columns[col].toString(@data[col], @)
		else
			if @data[col]? then return '' + @data[col]
			else return undefined

	getType: (col) ->
		@columns[col].getType()

	serialise: (col) ->
		if @table?
			@columns[col].serialise(@data[col], @)
		else
			@data[col]

	deserialise: (col, value) ->
		if @table?
			@data[col] = @columns[col].deserialise(value, @)
		else
			@data[col] = value
		@

	isModified: (col) -> if @modified[col]? and @modified[col] is true then true else false

	applyDefaults: ->
		for col of @columns
			unless @data[col]? 
				@data[col] = @columns[col].evalDefault()
				@modified[col] = true

	resetModified: (col) ->
		if col?
			@modified[col] = false
		else
			@modified = {}
		@

	setModified: (cols...) ->
		for c in cols
			if utils.objType(c) is 'array'
				for c2 in cols
					@modified[c2] = true
			else
				@modified[c] = true
		@

	setAllModified: ->
		for col of @columns
			@modified[col] = true
		@

	insert: (dbh, callback) ->
		@table.insert(dbh, @, callback)

	update: (dbh, callback) ->
		@table.update(dbh, @, callback)

	persist: (dbh, callback) ->
		if @allPrimaryKeysSet() is true
			@update dbh, callback
		else
			@insert dbh, callback

	allPrimaryKeysSet: ->
		for col in @table.getPrimaryKeys()
			return false unless @data[col]?
		true

	toJson: ->
		obj = {}
		for col in @columns
			obj[col] = @serialise(col)
		obj

###
# A collection of records
###

class exports.recordSet
	records:		undefined

	constructor: ->
		@records = {}

	setRecord: (key, rec) ->
		@records[key] = rec
		@

	recordNames: ->
		(n for n of @records)

	get: (key) ->
		@records[key]

	set: (key, rec) ->
		@setRecord(key, rec)

	isValid: ->
		valid = true
		
		for k, r of @records
			if r.isValid(@, k) is false then valid = false

		valid

	dump: ->
		for k, r of @records
			r.dump()





class exports.table
	@dbTable:				undefined
	@columns:				{}
	@primaryKeys:			[]
	@initialised:			false
	@recordClass:			exports.record
	@validator:				undefined

	@initialise: ->
		return if @initialised is true
		for c of @columns
			@columns[c].setName c
		for pk in @primaryKeys
			@columns[pk].setPrimaryKey()

		@initialised = true
		@

	@dump: ->
		@initialise()
		console.log "Table definition for DB Table #{@dbTable}"
		for f of @columns
			console.log "#{f} = #{@columns[f]}"

	constructor: ->
		throw "DBA Tables should never be instantiated!"

	@fromJson: (json, options) ->
		@initialise()

		if Array.isArray(json)
			result = []
			for j in json
				result.push @_fromJson(j, options)
			return result
		else
			return @_fromJson(json, options)

	@_fromJson: (json, options = {}) ->
		options.skipChecks ?= {}
		if options.allowFieldList?
			allow = {}
			for f in options.allowFieldList
				allow[f] = true

		r = new @recordClass(@)
		for cname of @columns when not allow? or allow[cname] is true
			jname = if options.map? and options.map[cname] then options.map[cname] else cname
			if json[jname]?
				if (options.checkValues? and options.checkValues is false) or (options.skipChecks[cname]? and options.skipChecks[cname] is true)
					r.deserialise(cname, json[jname])
					r.setModified [cname]
				else
					r.set(cname, json[jname])
		r

	@getPrimaryKeys: ->
		@initialise()
		utils.clone @primaryKeys

	@numPrimaryKeys: -> 
		@initialise()
		@primaryKeys.length

	@getColumns: ->
		@initialise()
		@columns

	@columnNames: ->
		@initialise()
		col for col of @columns

	@getColumn: (col) ->
		@initialise()
		@columns[col]

	@dbField: (column) -> 
		@initialise()
		@columns[column].getDbFieldName()

	@tableName: ->
		@initialise()
		@dbTable

	@setRecord: (newRecord) ->
		@initialise()
		@recordClass = newRecord ? exports.record
		@

	@createRecord: ->
		new @recordClass(@)

	@buildCache: (dbh, callback) ->
		@preselectEvent dbh, callback

	@preselectEvent: (dbh, callback) ->
		@initialise()
		ev = []
		for c of @columns
			if @columns[c].preselectEvent?
				if utils.objType(@columns[c].preselectEvent) is 'array'
					for e in @columns[c].preselectEvent
						ev.push @makePreselectCallback(dbh, c, @columns[c].preselectEvent)
				else
					ev.push @makePreselectCallback(dbh, c)

		if ev.length > 0
			async.parallel(ev, callback)
		else
			callback()

	@makePreselectCallback: (dbh, col, fun) ->
		return (asyncCallback) => 
			if fun?
				fun(dbh, @, asyncCallback)
			else
				@columns[col].preselectEvent(dbh, @, asyncCallback)

	@getSelectFields : (prefix) ->
		selectColumns = []
		for c of @columns when @columns[c].include('select')
			if prefix?
				selectColumns.push prefix+"."+@columns[c].getDbFieldName()
			else
				selectColumns.push @columns[c].getDbFieldName()
		return selectColumns

	@getSelectColumns: ->
		(c for c of @columns when @columns[c].include('select'))

	@select: (dbh, options, callback) ->
		@initialise()

		selectColumns = @getSelectFields()

		@preselectEvent dbh, =>
			unless callback? then return
			options.bind ?= []

			if options.filter?
				f = []
				for k of options.filter
					throw "Unknown filter column #{k}" unless @columns[k]?
					if options.filter[k] is null
						f.push "#{@columns[k].getDbFieldName()} IS NULL"
					else
						options.bind.push options.filter[k]
						f.push "#{@columns[k].getDbFieldName()} = $#{options.bind.length}"

				if options.where? then options.where += " AND (#{f.join(' AND ')})"
				else options.where = f.join(' AND ')

			if options.sort?
				o = []
				for f of options.sort
					throw "Unknown sort column #{f}" unless @columns[f]?
					throw "Invalid sort details #{options.sort[f]}" unless options.sort[f].match /^\s*(asc|desc)(\s+nulls\s+(first|last))?\s*$/i
					o.push "#{@columns[f].getDbFieldName()} #{options.sort[f]}"
				options.order = o.join(', ')

			if options.pager? and utils.objType(options.pager) is "object"
				sql = "SELECT COUNT(*) FROM #{@tableName()}"
				if options.where? then sql += " WHERE #{options.where}"
				# if options.order? then sql += " ORDER BY #{options.order}"

				options.pager.perPage ?= 10
				options.pager.page ?= 1

				dbh.query sql, options.bind, (err, pRes) =>
					pagerInfo = {
						totalRows:		pRes.rows[0].count
						totalPages:		if pRes.rows[0].count==0 then 1 else Math.ceil(pRes.rows[0].count / options.pager.perPage)
						page:			options.pager.page
						perPage:		options.pager.perPage
						rows:			[]
					}
					if options.pager.page < 0 then pagerInfo.page = pagerInfo.totalPages - options.pager.page
					if pagerInfo.page < 1 or pagerInfo.page > pRes.totalPages
						errObj = new exports.dbError("Invalid page '#{pagerInfo.page}' selected", sql, (options.bind ? []), "Database error when selecting record from table #{@dbTable}")
						return callback(errObj, pagerInfo)

					pagerInfo.nextPage = if pagerInfo.page < pagerInfo.totalPages then parseInt(pagerInfo.page,10)+1 else undefined
					pagerInfo.prevPage = if pagerInfo.page > 1 then parseInt(pagerInfo.page,10)-1 else undefined
					pagerInfo.pageRows = {
						from:		(pagerInfo.page - 1) * pagerInfo.perPage + 1
						to:			(pagerInfo.page) * pagerInfo.perPage
					}
					if pagerInfo.pageRows.to > pagerInfo.totalRows then pagerInfo.pageRows.to = pagerInfo.totalRows

					pagerInfo.offset = pagerInfo.perPage * (pagerInfo.page - 1)
					pagerInfo.limit = pagerInfo.perPage

					sql = "SELECT #{selectColumns.join(', ')} FROM #{@tableName()}"
					if options.where? then sql += " WHERE #{options.where}"
					if options.order? then sql += " ORDER BY #{options.order}"
					sql += " LIMIT #{pagerInfo.limit} OFFSET #{pagerInfo.offset}"

					dbh.query sql, options.bind, @handleSelectDbResponse(sql, options, callback, pagerInfo)
			else
				sql = "SELECT #{selectColumns.join(', ')} FROM #{@tableName()}"
				if options.where? then sql += " WHERE #{options.where}"
				if options.order? then sql += " ORDER BY #{options.order}"
				if options.limit? then sql += " LIMIT #{options.limit}"
				dbh.query sql, options.bind, @handleSelectDbResponse(sql, options, callback)
		@

	@handleSelectDbResponse: (sql, options, callback, resultObject) ->
		return (err, res) =>
				if err?
					errObj = new exports.dbError(err, sql, (options.bind ? []), "Database error when selecting record from table #{@dbTable}")
					if callback? then return callback errObj, undefined
					return

				records = []
				for row in res.rows
					record = new @recordClass(@)
					for c of @columns when @columns[c].include('select')
						record.deserialise(c, row[@columns[c].getDbFieldName()])
					records.push record

				if resultObject? then resultObject.rows = records
				else resultObject = records

				if callback?
					callback undefined, resultObject

	@getLinkedValues: (dbh, column, callback) ->
		@initialise()
		if @columns[column]?.getType() is 'map'
			@preselectEvent dbh, =>
				callback undefined, dbh.cacheObj.table[@columns[column].getLinkTable().tableName()]
		else
			callback "Column #{column} is not a mapped field."


	@get: (dbh, pks, callback) ->
		@initialise()
		pks = buildPrimaryKeys(pks, @primaryKeys)

		unless Object.keys(pks).length is @primaryKeys.length
			callback(new exports.dbError("Require fields #{@primaryKeys.join(', ')}, supplied #{Object.keys(pks).join(', ')}", undefined, undefined, "Require all primary key fields to be supplied."), undefined)
			return @

		whereClause = []
		bind = []
		for key in @primaryKeys
			bind.push pks[key]
			whereClause.push "#{key} = $#{bind.length}"

		selectColumns = []
		for c of @columns when @columns[c].include('select')
			selectColumns.push @columns[c].getDbFieldName()

		@preselectEvent dbh, =>
			sql = "SELECT #{selectColumns.join(', ')} FROM #{@tableName()} WHERE #{whereClause.join(' AND ')} LIMIT 1"
			dbh.query sql, bind, (err, res) =>
				if err?
					errObj = new exports.dbError(err, sql, bind, "Database error when selecting record from table #{@dbTable}")
					if callback? then return callback errObj, undefined
					return

				unless res.rowCount is 1
					if callback? then return callback undefined, undefined
					return

				record = new @recordClass(@)
				for c of @columns when @columns[c].include('select')
					record.deserialise(c, res.rows[0][@columns[c].getDbFieldName()])

				if callback?
					callback undefined, record
		@


	@insert: (dbh, rec, callback) ->
		@initialise()

		bind = []
		insertColumns = []
		returningColumns = []
		for c of @columns
			if @columns[c].include('insert') and rec.isModified(c)
				insertColumns.push @columns[c].getDbFieldName()
				bind.push rec.serialise(c)
			if @columns[c].include('select')
				returningColumns.push @columns[c].getDbFieldName()

		unless insertColumns.length > 0
			if callback? then callback undefined, undefined
			return @

		valuesList = ("$#{i}" for i in [1..bind.length])

		sql = "INSERT INTO #{@tableName()}(#{insertColumns.join(', ')}) VALUES(#{valuesList.join(', ')})
				RETURNING #{returningColumns.join(', ')}"
		dbh.query sql, bind, (err, res) =>
			if err?
				errObj = new exports.dbError(err, sql, bind, "Database error when inserting record into table #{@dbTable}")
				if callback? then return callback errObj, undefined
				return

			unless res.rowCount is 1
				if callback? then return callback undefined, undefined
				return

			record = new @recordClass(@)
			for c of @columns when @columns[c].include('select')
				record.deserialise(c, res.rows[0][@columns[c].getDbFieldName()])

			if callback?
				callback undefined, record
		@

	@update: (dbh, rec, callback) ->
		@initialise()

		bind = []
		updateColumns = []
		returningColumns = []

		for c of @columns
			if @columns[c].include('update') and rec.isModified(c)
				bind.push rec.serialise(c)
				updateColumns.push @columns[c].getDbFieldName()+"=$#{bind.length}"
			if @columns[c].include('select')
				returningColumns.push @columns[c].getDbFieldName()

		unless updateColumns.length > 0
			if callback? then callback undefined, undefined
			return @

		pks = buildPrimaryKeys(rec, @primaryKeys)
		unless Object.keys(pks).length is @primaryKeys.length
			callback(new exports.dbError("Require fields #{@primaryKeys.join(', ')}, supplied: #{Object.keys(pks).join(', ')}.", undefined, undefined, "Require all primary key fields to be supplied."), undefined)
			return @

		whereClause = []
		for key in @primaryKeys
			bind.push pks[key]
			whereClause.push "#{key} = $#{bind.length}"

		sql = "UPDATE #{@tableName()} SET #{updateColumns.join(', ')} WHERE #{whereClause.join(' AND ')}
				RETURNING #{returningColumns.join(', ')}"
		dbh.query sql, bind, (err, res) =>
			if err?
				errObj = new exports.dbError(err, sql, bind, "Database error when inserting record into table #{@dbTable}")
				if callback? then return callback errObj, undefined
				return

			unless res.rowCount is 1
				if callback? then return callback undefined, undefined
				return

			record = new @recordClass(@)
			for c of @columns when @columns[c].include('select')
				record.deserialise(c, res.rows[0][@columns[c].getDbFieldName()])

			if callback?
				callback undefined, record
		@

	@newSelect: (dbh, options = {}, callback) ->
		@initialise()

		@preselectEvent dbh, =>
			unless callback? then return

			sb = new selectBuilder
			tableAlias = sb.baseTable(@, options.selectColumns ? @getSelectColumns())
			
			for k of options.filter ? {}
				if options.filter[k] is null
					sb.addFilter(tableAlias, @columns[k].getDbFieldName(), 'IS NULL', undefined)
				else
					sb.addFilter(tableAlias, @columns[k].getDbFieldName(), '=', options.filter[k])

			if options.link?
				bMap = linkTables sb, @, tableAlias, options.link
				sb.setBindMap bMap

			if options.where?
				sb.addWhereSql options.where

			for f of options.sort ? {}
				mapped = sb.mapColumn(f)
				unless mapped? then throw "Unknown sort column #{f}"
				throw "Invalid sort details #{options.sort[f]}" unless options.sort[f].match /^\s*(asc|desc)(\s+nulls\s+(first|last))?\s*$/i
				sb.addOrderSQL mapped + ' ' + options.sort[f]

			if options.limit? then sb.setLimit(options.limit)
			if options.offset? then sb.setOffset(options.offset)

			if options.pager? and utils.objType(options.pager) is 'object'
				console.log "Pager isn't supported yet, bitches."
				console.log sb.sql({countAll: true})
			else
				dbh.query sb.sql(), sb.bindValues(), (err, res) =>
					if err? then return callback(err)

					r = (sb.bindResult(row) for row in res.rows)
					callback undefined, r

linkTables = (sb, table, tableAlias, link, path = '', bMap = {}) ->
	switch utils.objType(link)
		when 'string'
			newLink = {}
			newLink[link] = {}
			link = newLink
		when 'array'
			oldLink = link
			link = {}
			for l in oldLink
				link[l] = {}

	if path.length > 0 then path += '.'

	for linkField, options of link
		options = {} if options is true
		col = table.getColumn linkField
		unless col? and col instanceof exports.link then throw "Column #{linkField} is not a linked field."
		unless col.getLinkType() is 'one to one' then throw "Only one to one links are supported; column #{linkField}"

		joinedAlias = sb.addTable 'LEFT JOIN', col.getLinkTable(), tableAlias, col.getDbFieldName(), col.getLinkColumn(), path + linkField, link.columns

		bMap[linkField] ?= {}
		bMap[linkField].map = joinedAlias

		for k of options.filter ? {}
			if options.filter[k] is null
				sb.addFilter(joinedAlias, col.getLinkTable().getColumn(k).getDbFieldName(), 'IS NULL', undefined)
			else
				sb.addFilter(joinedAlias, col.getLinkTable().getColumn(k).getDbFieldName(), '=', options.filter[k])

		if options.link?
			bMap[linkField] ?= {}
			bMap[linkField].link = linkTables sb, col.getLinkTable(), joinedAlias, options.link, (if path.length > 0 then path + linkField else linkField)

	bMap


class selectBuilder
	tableIndex:			undefined
	tableList:			undefined
	columnIndex:		undefined
	columnLookup:		undefined
	tableMap:			undefined
	bindVars:			undefined
	filterCondition:	undefined
	orderBy:			undefined
	limit:				undefined
	offset:				undefined
	whereSql:			undefined
	resultMap:			undefined
	bindMap:			undefined

	constructor: ->
		@tableList = []
		@tableIndex = new utils.idIndex
		@columnIndex = new utils.idIndex
		@columnLookup = {}
		@filterCondition = []
		@tableMap = {}
		@bindVars = []
		@orderBy = []
		@resultMap = {}
		@bindMap = {}

	setBindMap: (m) ->
		@bindMap = m
		@

	baseTable: (table, cols) ->
		@tableList = []
		@addTable 'FROM', table, '', '', '', '', cols

	mapColumn: (col) ->
		@columnLookup[col]?.db

	addTable: (joinType, joinTable, baseTableAlias, baseField, linkedField, linkPath = '', cols) ->
		# Save the table, working out what to alias it to
		tableAlias = @tableIndex.saveUniqueId joinTable.tableName(), joinTable
		@tableList.push {
			type:				joinType
			table:				joinTable
			alias:				tableAlias
			fromField:			baseTableAlias + '.' + baseField
			toField:			tableAlias + '.' + joinTable?.getColumn(linkedField)?.getDbFieldName()
		}

		@resultMap[tableAlias] = {table: joinTable, columns: {}}

		# Map the columns to unique ids
		for col in cols ? joinTable.getSelectColumns()
			colName = joinTable.getColumn(col).getDbFieldName()
			colAlias = @columnIndex.saveUniqueId tableAlias+'_'+colName, {table: tableAlias, field: colName, as: col}
			@columnLookup[(if linkPath?.length > 0 then linkPath+'.'+col else col)] = {
				alias: 	colAlias
				table: 	tableAlias
				field:	colName
				db:		tableAlias + '.' + colName
			}

			@resultMap[tableAlias].columns[colAlias] = col

		tableAlias

	bindValue: (val) ->
		@bindVars.push(val)
		"$#{@bindVars.length}"

	addWhereSql: (sql) ->
		@whereSql = sql
		@

	addFilterSql: (sql) ->
		@filterCondition.push sql
		@

	addFilter: (tableAlias, fieldName, operator, value) ->
		f = tableAlias + '.' + fieldName
		op = operator
		v = if value? then @bindValue(value) else ''
		@filterCondition.push "#{f} #{op} #{v}"
		@
	
	addOrderSQL: (clause) ->
		@orderBy.push clause
		@

	addSort: (field, order = 'DESC') ->
		@orderBy.push @mapColumn(field) + ' ' + order

	setLimit: (val) ->
		@limit = val
		@

	setOffset: (val) ->
		@offset = val
		@

	bindValues: ->
		@bindVars

	sql: (options = {}) ->
		if options.countAll is true
			columns = ['count(*)']
		else
			columns = (def.table+'.'+def.field+' AS '+col for col, def of @columnIndex.allItems())

		# Iterate through tables to build up the sql
		from = ''
		for t in @tableList
			tableName = t.table.tableName()
			from += ' ' + t.type + ' ' + tableName
			if tableName isnt t.alias then from += ' AS ' + t.alias
			if t.type isnt 'FROM'
				from += ' ON ' + t.fromField + ' = ' + t.toField

		clause = @filterCondition.join(' AND ')
		if @whereSql?
			if clause? then clause = @whereSql + ' AND (' + clause + ')'
			else clause = @whereSql
		if clause? then clause = ' WHERE ' + clause

		order = if @orderBy.length > 0 then ' ORDER BY ' + @orderBy.join(', ') else ''
		limit = if @limit? and options.countAll isnt true then ' LIMIT ' + @limit else ''
		offset = if @offset? and options.countAll isnt true then ' OFFSET ' + @offset else ''

		return 'SELECT ' + columns.join(', ') + from + clause + order + limit + offset

	bindResult: (row) ->
		return undefined unless @tableList.length > 0

		firstTable = @tableList[0]
		res = @_doBindResult row, firstTable.alias, @bindMap
		res

	_doBindResult: (row, tableAlias, bindMap) ->
		rec = @resultMap[tableAlias].table.createRecord()

		for resCol, recCol of @resultMap[tableAlias].columns
			rec.deserialise recCol, row[resCol]

		for field, op of bindMap when op['map']?
			subRec = @_doBindResult row, op['map'], op.link ? {}
			rec.setLinkedRecord field, subRec

		rec


buildPrimaryKeys = (pks, pkDef) ->
	if pkDef.length is 0 then return {}

	if pks instanceof exports.record
		res = {}
		for k in pkDef
			val = pks.serialise(k)
			if val? then res[k] = val
		return res

	switch utils.objType(pks)
		when 'number', 'string'
			res = {}
			res[pkDef[0]] = pks
			return res
		when 'array'
			res = {}
			for i in [1..(if pks.length < pkDef.length then pks.length else pkDef.length)]
				res[pkDef[i]] = pks[i]
			return res
		when 'object'
			res = {}
			for k in pkDef
				res[k] = pks[k]
			return res
	return {}







###
# Additional column types
###

class exports.virtual extends exports.column
	type:				'virtual'

	constructor: ->
		super
		@includeRules.insert = false
		@includeRules.select = false
		@includeRules.insert = false
		@includeRules.update = false


class exports.integer extends exports.column
	type: 				'integer'

	# Type specific validation
	minValue:			undefined
	maxValue:			undefined

	constructor: (limitMax, limitMin) ->
		super
		if limitMax? and limitMin? and limitMax < limitMin then [limitMax, limitMin] = [limitMin, limitMax]
		@maxValue = limitMax
		@minValue = limitMin

		@addValidationRule (val) ->
			if @maxValue? and val > @maxValue then return "#{val} exceeds maximum value of #{@maxValue}"
			true

		@addValidationRule (val) ->
			if @minValue? and val < @minValue then return "#{val} is less than minimum value of #{@minValue}"
			true

		@onCall 'pre_get_value', (ev, val) ->
			if val? then return Number(val)
			val



class exports.serial extends exports.integer
	type: 'serial'

	constructor: ->
		super
		@includeRules.insert = false


class exports.varchar extends exports.column
	type:				'text'

	# Type specific validation
	maxLen:				undefined

	constructor: (limitLength) ->
		super

		if limitLength? and limitLength > 0
			@maxLen = limitLength
			@type = "varchar(#{limitLength})"
		else
			throw "Varchar columns require a maximum length to be set."

		@addValidationRule (val) ->
			if @maxLen? and val?.length > @maxLen then return "String exceeds maximum length of #{@maxLen}"
			true


class exports.text extends exports.column
	type:				'text'
	formFieldType:		'textarea'


class exports.json extends exports.column
	type:				'json'



class exports.boolean extends exports.column
	type: 'boolean'
	formFieldType: 'checkbox'

	constructor: ->
		super

		@addValidationRule (val) ->
			if val is 'true' or val is 'on' or val is 1 or val is '1'
				val = true
			else if val is 'false' or val is 'off' or val is 0 or val is '0'
				val = false
				
			unless val is true or val is false or val is undefined or val is null
				return "Boolean values can only be set to true, false, or null / undefined not #{val}."
			true



class exports.date extends exports.column
	type: 				'date'
	doDefaultNow: 		false

	constructor: ->
		super

		@onCall 'pre_get_value', (ev, val) ->
			if val? then return new moment(val)
			if @doDefaultNow then return new moment()
			return undefined

		@onCall 'set_value', (ev, val) ->
			if val?
				if /^\d{1,2}\/\d{1,2}\/\d{2,4}$/.test(val) then return new moment(val, "DD/MM/YYYY")
				return new moment(val)
			undefined

		@onCall 'serialise', (ev, val) ->
			if val? and moment.isMoment(val)
				return val.format 'YYYY-MM-DD'
			undefined

		@onCall 'deserialise', (ev, val) ->
			if val? then return new moment(val)
			undefined

	defaultNow: ->
		@doDefaultNow = true
		@defaultValue = 'now'
		@


class exports.timestamp extends exports.column
	type: 				'timestamp with time zone'
	doDefaultNow: 		false

	constructor: ->
		super

		@onCall 'pre_get_value', (ev, val) ->
			if val? then return new moment(val)
			if @doDefaultNow then return new moment()
			return val

		@onCall 'set_value', (ev, val) ->
			if val? then return new moment(val)
			undefined

		@onCall 'serialise', (ev, val) ->
			if val? and moment.isMoment(val)
				return val.format 'YYYY-MM-DD HH:mm:ss.SSSZ'
			undefined

		@onCall 'deserialise', (ev, val) ->
			if val? then return new moment(val)
			undefined

	defaultNow: ->
		@doDefaultNow = true
		@defaultValue = 'now'
		@


class exports.enum extends exports.column
	type:				'enum'
	allowedValues:		undefined
	formFieldType: 		'select'

	constructor: (values) ->
		super

		@allowedValues = {}
		for v in values
			@allowedValues[v] = true

		@addValidationRule (val) ->
			unless val? then return true
			unless @allowedValues[val] is true
				return "'#{val}' is an invalid value for this enum."
			true


class exports.password extends exports.column
	type:				'password'
	dbType:				'text'
	saltField:			'salt'
	saltLen:			48
	formFieldType: 		'password'

	constructor: (setSaltField) ->
		super

		if setSaltField? then @saltField = setSaltField

		@onCall 'pre_set_value', (ev, val, record) ->
			unless val? then return undefined
			
			newSalt = crypto.randomBytes(48).toString('base64').substring(0, @saltLen)
			record.set(@saltField, newSalt)

			return sha1(newSalt + ':' + val)

		@extendRecord.checkPassword = (field, pass) ->
			if @get(field) is sha1(@get(@columns[field].saltField) + ':' + pass)
				return true
			return false


class exports.link extends exports.column
	type: 				'link'
	dbType:				'integer'
	linkTable:			undefined
	linkColumn:			undefined
	linkType:			'one to one'
	filter:				undefined

	constructor: (linkedTable, linkType, linkColumn) ->
		super
		
		if linkedTable
			@linkTable = linkedTable
			linkedTable.initialise()

		@setLinkType linkType if linkType
		@setLinkColumn linkColumn if linkColumn

		@onCall 'pre_set_value', (ev, val, record) ->
			@recordCache = undefined
			val

	setLinkTable: (table) ->
		@linkTable = table
		@

	getLinkTable: ->
		@linkTable

	setLinkColumn: (col) ->
		@linkColumn = col
		@

	getLinkColumn: ->
		@linkColumn ? (@linkTable.getPrimaryKeys())[0]

	setLinkType: (type) ->
		if type is 'one' or type is 'one to one' or type is 'single'
			@linkType = 'one to one'
		else if type is 'many' or type is 'one to many' or type is 'multiple'
			@linkType = 'one to many'
		else throw "Unknown link type #{type}."
		@

	getLinkType: ->
		@linkType

	setFilter: (filter) ->
		@filter = filter
		@

	# getLinkedRecord: (dbh, val, rec, callback) ->
	# 	callback "No linked table.", undefined unless @linkTable?

	# 	if @linkType is 'one to one'
	# 		@linkTable.get dbh, val, (err, rec) =>
	# 			@setCachedRecord(rec) unless err?
	# 			callback err, rec
	# 	else
	# 		options = {filter: {}}
	# 		if @filter?
	# 			options.filter = @filter

	# 		# options.filter.

	# 		callback undefined

	# setCachedRecord: (obj) ->
	# 	@recordCache = obj
	# 	@

	# getCachedRecord: ->
	# 	@recordCache


class exports.map extends exports.column
	type:				'map'
	dbType:				'integer'
	linkTable:			undefined
	cacheObj:			undefined
	toStringField:		undefined

	constructor: (linkedTable) ->
		super

		# unless linkedTable? and linkedTable.

		@linkTable = linkedTable
		linkedTable.initialise()

		unless @linkTable.primaryKeys.length == 1
			throw("Map field #{@name} must link to a table with exactly one primary key, #{@linkTable.tableName()} has #{@linkTable.primaryKeys.length}.")

		@addValidationRule (val) ->
			unless val? then return true
			unless @cacheObj.table[@linkTable.tableName()][val]?
				return "Linked record not found."
			true

		@onCall 'pre_set_value', (ev, val, record) ->
			unless val? then return undefined
			if val instanceof exports.record then return val.get(@linkTable.primaryKeys[0])
			return val

		@onCall 'get_value', (ev, val, record) ->
			unless val? then return undefined

			return @cacheObj.table[@linkTable.tableName()][val]

		@onCall 'tostring_value', (ev, val, record) ->
			unless val? then return undefined

			linkedTable = @cacheObj.table[@linkTable.tableName()][val]
			field = @toStringField ? (linkedTable.getPrimaryKeys)[0]
			linkedTable.get(field)

		@preselectEvent = (dbh, table, callback) =>
			@cacheObj = dbh.cacheObj

			if @cacheObj.table[@linkTable.tableName()]?
				return callback()

			selectColumns = []

			for c of @linkTable.columns when @linkTable.columns[c].include('select')
				selectColumns.push @linkTable.columns[c].getDbFieldName()

			sql = "SELECT #{selectColumns.join(', ')} FROM #{@linkTable.tableName()}"
			dbh.query sql, [], (err, res) =>
				if err?
					errObj = new exports.dbError(err, sql, [],
						"Database error when preselecting record from table #{@linkTable.tableName()}")
					if callback? then return callback errObj, undefined
					return

				@cacheObj.table[@linkTable.tableName()] = {}
				pkField = @linkTable.primaryKeys[0]
				for row in res.rows
					record = new @linkTable.recordClass(@linkTable)
					for c of @linkTable.columns when @linkTable.columns[c].include('select')
						record.deserialise(c, row[@linkTable.columns[c].getDbFieldName()])
					@cacheObj.table[ @linkTable.tableName() ][ record.rawData(pkField) ] = record

				callback()

	setToStringField: (fieldName) ->
		@toStringField = fieldName
		@

	getToStringField: ->
		@toStringField

	getLinkTable: ->
		@linkTable

