###

API application service to fit into the stampede app framework.

###

stampede = require '../stampede'

log = stampede.log


class module.exports
	sessionId:					undefined			# The unique ID for the session
	userId:						undefined			# The logged in user
	roles:						undefined			# The roles assigned to the user account
	metaData:					undefined			# Data stored against the session
	loggedIn:					false				# True / false is the user logged in

	constructor: ->

	setId: (id) ->
		@sessionId = id
		@userId = undefined
		@roles = {}
		@metaData = {}
		@

	setFromPhp: (sessionData) ->
		if sessionData.id?
			@userId = sessionData.id
			@loggedIn = true
		else
			@userId = undefined
			@loggedIn = false

		@roles = {}
		# check in case weird things with session roles being an object, instead of an array
		if typeof sessionData.roles == 'object'
			for i, r of sessionData.roles
				@roles[r] = true
		else
			for r in sessionData.roles ? []
				@roles[r] = true

		@

	hasRole: (roleName) -> @roles.ROLE_SUPER_ADMIN ? @roles[roleName] ? false

	getUserId: ->
		@userId

	finish: ->
		@

