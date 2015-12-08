###

API application service to fit into the stampede app framework.

###

stampede = require '../stampede'

log = stampede.log


class module.exports
	sessionId:					undefined			# The unique ID for the session
	metaData:					undefined			# Data stored against the session

	constructor: ->
		@metaData = {}

	finish: ->
		@
