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
		label:					new dba.text()
	@primaryKeys:				['id']


class UserObj extends dba.record
	sayHi: -> console.log "Hello World"

class User extends dba.table
	@dbTable:					'usr'
	@columns:
		id:						new dba.serial()
		username:				new dba.varchar(40).notNull()
		password:				new dba.password('salt').notNull()
		salt:					new dba.varchar(100).notNull()
		created:				new dba.timestamp().defaultNow()
		sex:					new dba.enum('male', 'female', 'other').notNull().setDbType('sex_type')
		salutation:				new dba.map(Salutation).notNull().setToStringField('label')
	@primaryKeys:				['id']
	@recordClass:				UserObj


# pg = require 'pg'
# pg.connect "pg://dbatest:dbatest88@localhost/dbatest", (err, client, done) ->
dba.connect "pg://dbatest:dbatest88@localhost/dbatest", (err, dbh) ->
	if err?
		throw "DB connection error: #{err}"

	User.dump()
	User.get dbh, 1, (err, u) =>
		if err? then err.show()
	
		# u = User.fromJson {
		# 	id:				17
		# 	active:			true
		# }

		# u.applyDefaults()

		# console.log u.get('created').toString()

		# u.set('username', undefined)

		u.dump()
		u.sayHi()

		u.set('username', 'geoff')
		u.set('password', 'dave')

		console.log u.checkPassword('password', 'bob')
		console.log u.checkPassword('password', 'dave')

		console.log u.get('salutation').get('label')
		# console.log u

		u.dump()

		User.update dbh, u, (err, nu) =>
			if err? then err.show()

			nu.dump()

			User.select dbh, {where: "#{User.dbField('sex')} = $1", bind: ['male']}, (err, recs) =>
				if err? then err.show()

				for r in recs
					console.log "Found user: #{r.get('username')}"
					console.log r.toString('created')
					console.log r.toString('sex')
					console.log r.toString('salutation')

				setTimeout ->
						console.log ' '
						console.log 'Executed queries:'
						console.log ' '
						console.log dbh.queries()
					, 0

	# Interrogate the User table
	for colName, column of User.getColumns()
		if column.getType() is 'map'
			linkTable = column.getLinkTable()
			console.log ">> Map field #{colName} found, links to #{linkTable.tableName()}."
		else
			console.log "Damn you #{colName}."

	displayColumnInfo = (column) ->
		return (err, values) ->
			if err? then err.show()

			console.log "Column #{column} has values:"
			for v of values
				console.log values[v].get('label')

	for colName, column of User.getColumns()
		if column.getType() is 'map'
			User.getLinkedValues dbh, column.getName(), displayColumnInfo(column.getName())

	# Do a select on all dem users
	User.select dbh, {
			filter:
				username:	'geoff'
				sex:		'male'
			pager:
				page:		1
				perPage:	10
			sort:
				username: 	'ASC NULLS FIRST'
		}, (err, userPage) =>
			if err? then err.show()

			console.log ' '
			console.log ">>> SELECT found: "
			console.log userPage
			console.log ' '

