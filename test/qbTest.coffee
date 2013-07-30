###
# Test script used whilst developing the dba.coffee library
###

stampede = require '../lib/stampede'
dba = stampede.dba
qb = stampede.qb

class AddressType extends dba.table
	@dbTable:					'address_type'
	@columns:
		id:						new dba.serial()
		label:					new dba.text()
		active:					new dba.boolean()

class Address extends dba.table
	@dbTable:					'address'
	@columns:
		id:						new dba.serial()
		label:					new dba.text()
		organisationId:			new dba.integer()
		address1:				new dba.text()
		address2:				new dba.text()
		town:					new dba.text()
		county:					new dba.text()
		postcode:				new dba.text()
		country:				new dba.text()
	@primaryKeys:				['id']

class User extends dba.table
	@dbTable:					'usr'
	@columns:
		id:						new dba.serial()
		username:				new dba.varchar(40).notNull()
		password:				new dba.password('salt').notNull()
		salt:					new dba.varchar(100).notNull()
		created:				new dba.timestamp().defaultNow()
		sex:					new dba.enum('male', 'female', 'other').notNull().setDbType('sex_type')
	@primaryKeys:				['id']


q = new stampede.queryBuilder.query()
q.baseTable(User)
	.join(Address)
	.where({active: true, organisation: null})
	.orWhere(qb.gt('id', 17))
	.join(AddressType).where()
q.pager({perPage: 10, page: 1})
q.toSql()

