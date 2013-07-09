stampede = require '../lib/stampede'
dba = stampede.dba
#address = require './Address.coffee' #require in mapped entities

class User extends dba.table
	@dbTable: 			'users'
	@columns:
		id:				new dba.serial()
		firstname:		new dba.varchar(100).notNull()
		lastname:		new dba.varchar(100).notNull()
		description:	new dba.text()
		#address_id:		new dba.map(address).setToStringField('postcode')
	@primaryKeys:		['id']
module.exports = User