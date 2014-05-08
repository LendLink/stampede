stampede = require '../stampede'


# Socket.IO logger - allows us to capture log events and redirect them to stampede / lumberjack.
class module.exports
	enabled:		true
	logger:			undefined

	constructor: (opts = {}) ->
		@level = 3

		@setEnabled(opts.enabled ? true)
		@setLogger(opts.logger ? stampede.log)

	log: (type, rest...) ->
		if type > @level or @enabled is false
			return @

		msg = rest.join('')
		switch type
			when 0 then @logger.error msg
			when 1 then @logger.warn msg
			when 2 then @logger.info msg
			when 3 then @logger.debug msg

		@

	setEnabled: (en) ->
		@enabled = en ? true
		@

	setLogger: (l) ->
		@logger = l ? stampede.log
		@

	error: (rest...) ->
		rest.unshift 0
		@log.apply @, rest

	warn: (rest...) ->
		rest.unshift 1
		@log.apply @, rest

	info: (rest...) ->
		rest.unshift 2
		@log.apply @, rest

	debug: (rest...) ->
		rest.unshift 3
		@log.apply @, rest

