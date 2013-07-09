dba
===

dba is a database abstraction for PostgreSQL databases allowing the creation and modification of simple models.  It is not designed to become an all encompassing ORM that replaces the need to understand SQL, it merely tries to make simple and common queries and patterns trivial to implement in a consistent way.

Multi-table joins are not supported, for example, and we have no intention of providing for more complicated queries.  If you need to do something more complicated then you can write raw SQL and feed the resulting JSON back into the model to hydrate objects as you need.

This allows you to balance performance and flexibility with just getting the job done.

# Using the library

dba is automatically imported by stampede.  In order to reduce typing you can always assign dba to a local variable.

```javascript
stampede = require '../lib/stampede'

dba = stampede.dba
```

# Connecting to the database

Behind the scenes dba uses the pg library to connect to Postgres and talk to the database.  dba provides a wrapper around this library, encapsulating the connection and storing various items of metadata against the connection itself.

To create a new connection you can either ask dba to connect or connect using pg and pass the client to dba:

```javascript
# Preferred method for connecting
dba.connect "pg://dbatest:dbatest88@localhost/dbatest", (err, dbh) ->
	if err? then throw "Argh, a horrible error: #{err}"

# To reuse an existing connection just create a new dba.connection object
pg = require 'pg'
pg.connect "pg://dbatest:dbatest88@localhost/dbatest", (err, client, done) ->
	if err? then throw "Argh, a horrible error: #{err}"
    dbh = new dba.connection (client, done)
```

The returned 'dbh' database handle is then your method for interacting with the database.

# Disconnecting

The pg library requires an explicit disconnect call in order to release the connection to the database.  Failure to do so will result in the program hoarding connections until the database runs out at which point new connection attempts will be rejected.

To disconnect from the database simply call the disconnect method on the database handle object.

```javascript
dbh.disconnect()
```

# Manual querying

You can still bypass dba and run queries directly.  Simply call the query method of the db handle in the same way you would call query on a pg connection.

```javascript
dbh.query 'SELECT now() + $1::interval as t', ['1 month'], (err, res) ->
    if err? then throw "The database is unimpressed: #{err}"

    console.log "Can you believe that in 1 month the time will be #{res.rows[0].t}."
```

# Query log

Every database query that passes through a given database handle is logged, with the raw SQL, round trip execution time, and any bound variables being stored.  This includes all queries produced automatically by the model as well as any queries run via the query method.

If you need to bypass this mechanism then you can still query the database using the underlying pg client by calling `dbh.handle().query(...)`

To retrieve a list of all the queries that have been logged:

```javascript
callLog = dbh.queries()
console.log callLog
```

In general it should be avoided but you can also clear the call log if required, for example if a connection is being reused between jobs or in long lived processes:

```javascript
dbh.clearLog()
```
