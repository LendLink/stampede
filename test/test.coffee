assert = require 'assert'
async = require 'async'
user = require './User.coffee'
stampede = require '../lib/stampede'
dba = stampede.dba

###
Update this with a real connection string - tests will create and drop test data automagically
###
connstring = "pg://alex:XXXX@127.0.0.1/demo"

beforeEach (done) ->
	clearDb(done)

describe "selecting", ->
	it "single object with correct id", (done) ->
		dba.connect connstring, (err, handle) ->
			user.get handle, 1, (err, result) ->
				handle.disconnect()
				if err? 
					console.log err
					throw err
				assert.equal result.get("id"), 1
				done()
	it "select with no criteria brings back everything", (done) ->
		dba.connect connstring, (err, handle) ->
			user.select handle, {}, (err, result) ->
				if err?
					throw err
				handle.disconnect()
				assert.equal result.length, 6
				done()
	it "select with filter brings back filtered results", (done) ->
		dba.connect connstring, (err, handle) ->
			user.select handle, {
				filter:
					firstname: "super"
			}, (err, result) ->
				if err? 
					throw err
				handle.disconnect()
				for row in result
					assert.equal row.get("firstname"), "super"
				done()
	it "select with order by ascending", (done) ->
		dba.connect connstring, (err, handle) ->
			user.select handle, {
				sort:
					firstname: "ASC"
			}, (err, result) ->
				if err?
					throw err
				handle.disconnect()
				previousname = ""
				for row in result
					assert.ok(row.get("firstname")>=previousname, "#{row.get("firstname")} >= #{previousname}")
					previousname = row.get("firstname")
				done()

describe "updating", ->
	it "updating field saves to database", (done) ->
		dba.connect connstring, (err, handle) ->
			user.select handle, {
				filter:
					firstname : "super"
					lastname : "ted"
				}, (err, result) ->
					if err?
						throw err
					assert.equal result.length, 1
					result[0].set("firstname", "spotty")
					result[0].set("lastname", "man")
					assert.equal(result[0].get("firstname"), "spotty")
					assert.equal(result[0].get("lastname"), "man")
					user.update handle, result[0], (err, result) ->
						if err?
							throw err
						user.select handle, {
							filter :
								firstname : "spotty"
								lastname : "man"
						}, (err, result) ->
							handle.disconnect()
							if err?
								throw err
							assert.equal result.length, 1
							assert.equal(result[0].get("firstname"), "spotty")
							assert.equal(result[0].get("lastname"), "man")
							done()

describe "inserting", ->
	it "creating new record saves to database"


#put up and tear down for the database test script
clearDb = (next) ->
	toDo = []
	toDo.push "drop table if exists users"
	toDo.push "create table users (id serial, firstname character varying(100) not null, lastname character varying(100) not null, description text)"
	toDo.push "alter table users add primary key (id)"
	toDo.push "insert into users(firstname, lastname, description)
				select 'super', 'man','not sure about the pants'
				union all
				select 'super','ted','lives in a treehouse'
				union all
				select 'texas','pete','bad guy'
				union all
				select 'Lion','O','Give me sight beyond sight'
				union all
				select 'Marshall','Bravestar','Strength of the bear!'
				union all
				select 'Danger','Mouse','Works in a postbox'"
	
	doQuery = (query, next) ->
		dba.connect connstring, (err, handle) ->
			if err?
				throw err
			handle.query query, [], (err, result) ->
				handle.disconnect()
				if err?
					throw err
				return next undefined

	async.mapLimit toDo, 1, doQuery, (err, result) ->
		if err?
			throw err
		return next undefined



