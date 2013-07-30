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

###




class exports.query
	overrideSql:		undefined
	tableList:			undefined
	joinList:			undefined


	constructor: () ->
		@tableList = {}
		@joinList = []

	baseTable: (tableDef) ->
		console.log tableDef
		@