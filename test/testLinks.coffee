###
# Test script used whilst developing the dba.coffee library
###

stampede = require '../lib/stampede'
dba = stampede.dba
inform = stampede.inform

# form = new inform.form()
# form
# 	.setAutocomplete()
# 	.setAction('/submit.html')
# 	.setMethod('POST')
# 	.setName('Geoff')

# new inform.text('username', form).setFlag('autocomplete')

# form.getFieldById('username').setAttribute('pattern', '[A-Za-z0-9]')
# 	.onBind (value, f) ->
# 		console.log "Oooo a bound value: #{value} for field #{f.getAttribute('name')}"

# form.bind({username: 'bob'})


# console.log form.render()
# console.log ' '

class Salutation extends dba.table
	@dbTable:					'salutation'
	@columns:
		id:						new dba.serial()
		label:					new dba.text().addRule('notNull').addRule('default', 'bob').addRule('email')
	@primaryKeys:				['id']


class UserObj extends dba.record
	sayHi: -> console.log "Hello World"

class User extends dba.table
	@dbTable:					'usr'
	@columns:
		id:						new dba.serial()
		username:				new dba.varchar(40).notNull().addRule('email')
		password:				new dba.password('salt').notNull()
		salt:					new dba.varchar(100).notNull()
		created:				new dba.timestamp().defaultNow()
		sex:					new dba.enum('male', 'female', 'other').notNull().setDbType('sex_type')
		salutation:				new dba.map(Salutation).notNull().setToStringField('label')
		primaryAddress:			new dba.link().setDbFieldName('primary_address_id')
	@primaryKeys:				['id']
	@recordClass:				UserObj

class Address extends dba.table
	@dbTable:					'address'
	@columns:
		id:						new dba.serial().setDbFieldName('id')
		userId:					new dba.link(User, 'one to one').setDbFieldName('user_id')
		address:				new dba.text()
	@primaryKeys:				['id']

User.getColumn('primaryAddress').setLinkTable(Address).setLinkType('one to one')

# pg = require 'pg'
# pg.connect "pg://dbatest:dbatest88@localhost/dbatest", (err, client, done) ->
dba.connect "pg://dbatest:dbatest88@localhost/dbatest", (err, dbh) ->
	if err?
		throw "DB connection error: #{err}"

	selectOptions = {
		filter:
			username: 'geoff'
		pager:
			perPage: 20
		link:
			'primaryAddress': { link: 'userId'} # { filter: {id: 1}}
		sort:
			'primaryAddress.id': 'ASC'
	}
	User.select dbh, selectOptions, (err, res) =>
		if err? then throw "Select error: #{err}"
		
		console.log ">>> RESULTS <<<"
		console.log res
		for r in res.rows
			r.dump()

		myUser = res[0]

		# address = myUser.getLinkedRecord 'primaryAddress'
		add = myUser.getLinkedRecord 'primaryAddress', dbh, (err, add) =>
			add.dump()

			dbh.disconnect()
			process.exit()
