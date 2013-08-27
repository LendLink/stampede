###
# queryBuilder.coffee
#
# Build PostgreSQL queries!
###

###

Example usage:

q = new stampede.queryBuilder.query()
q.baseTable(UserModel)
	.join(Address).where(qb.or(qb.gt('id', 17), {active: true, organisation: null}))
	.join(AddressType).where()
q.pager({perPage: 10, page: 1})

q = new stampede.queryBuilder.query()
t = q.baseTable('usr')
t.addField('id', 'usr_id').addField('first_name').addField('last_name')
t.where('last_name', '=', q.bind('smith'))

###

utils = require './utils'


class exports.query
	tables:			undefined

	constructor: (baseTable) ->
		@tables = []

		if baseTable?
			@baseTable baseTable

	baseTable: (setTable, alias) ->
		unless setTable instanceof exports.table
			setTable = new exports.table(@, setTable, alias)

		@tables = [setTable]
		setTable

	join: (type, table, onClause, options) ->
		unless table instanceof exports.table
			table = new exports.table(@,  dtable)

	innerJoin: (table, onClause, options) ->
		@join 'INNER JOIN', table, onClause

	renderQuery: (options) ->
		selectFields = []
		tableList = []
		for t in @tables
			selectFields = selectFields.concat t.renderSelectFields()
			tableList = tableList.concat t.renderFrom()

		sql = "SELECT "
		if selectFields.length > 0
			sql += selectFields.join(', ')
		else
			sql += "*"

		sql += " FROM " + tableList.join(' ')
		sql



class exports.table
	fields:			undefined
	tableName:		undefined
	tableAlias:		undefined
	joinType:		'base'
	joinDetails:	undefined
	parentQuery:	undefined
	whereClause:	undefined

	constructor: (parentQuery, tableName, tableAlias) ->
		@fields = {}
		@parentQuery = parentQuery
		@tableName = tableName
		@tableAlias = tableAlias

	getColumnAlias: (col) ->
		if @fields[col] is true
			(@tableAlias ? @tableName) + '_' + col
		else
			@fields[col]

	renderSelectFields: ->
		("#{f} AS #{@getColumnAlias(f)}" for f of @fields)

	renderJoinOn: ->


	renderFrom: ->
		if @joinType is 'base'
			j = @tableName
		else
			j = @joinType + ' ON ' + @renderJoinOn()

		if @tableAlias? then j += ' AS ' + @tableAlias
		[j]
	
	addField: (field, alias) ->
		@fields[field] = alias ? true
		@

	where: (field, op, val) ->


class exports.whereClause