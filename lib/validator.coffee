###
# Validation library to be shared between server and browser
###

utils = require './utils'


root = exports ? this

class root.Validator 
	ruleList:				undefined
	fieldRequired:			false
	status:					undefined
	notices:				undefined

	constructor: (clone) ->
		@ruleList = {}
		@reset()

		if clone?
			for k,r in clone.ruleList
				@ruleList[k] = new root.rule(r)

	setRequired: (val) ->
		@fieldRequired = val

	isRequired: ->
		@fieldRequired

	reset: ->
		@status = 'not run'
		@notices = { error: [], warning: [], info: []}
		@

	addRule: (rule, args, errStr) ->
		if rule instanceof root.rule
			# rule is good
		else if utils.objType(rule) is 'object'
			rule = new root.rule(rule.rule, rule.args ? args, rule.errorMessage ? errStr)
		else
			# Just a text name...
			rule = new root.rule(rule, args, errStr)

		@ruleList[rule.getType()] = rule
		rule.bindToValidator(@)
		@


	validate: (value, record, recordSet, mySet) ->
		@reset()

		for t, rule of @ruleList
			err = rule.validate(value, record, recordSet, mySet)
			
			@notices.info.push {'rule': t, result: err}

			if err?
				if utils.objType(err) is 'object'
					for k, v of err when k is 'error' or k is 'warning' or k is 'info'
						@notices[k].push v
				else
					@notices.error.push err
		
		if @hasErrors() then false else true

	hasErrors: ->
		if @notices.error.length > 0 then true else false

	hasWarnings: ->
		if @notices.warning.length > 0 then true else false

	hasInfo: ->
		if @notices.info.length > 0 then true else false

	getErrors: ->
		@notices.error

	getWarnings: ->
		@notices.warning

	getInfo: ->
		@notices.info





class root.rule
	type:					undefined
	args:					undefined
	severity:				'error'
	errorString:			undefined
	warningString:			undefined

	constructor: (type, args, errStr) ->
		if type instanceof root.rule
			@type = type.type
			@args = utils.clone type.args
			@severity = type.severity
			@errorString = type.errorString
			@warningString = type.warningString
		else 
			unless @['rule_'+type]? then throw "Rule '#{type}' not found."

			@type = type
			@args = args ? {}
			if errStr then @setErrorMessage(errStr)

			if @['init_'+type]?
				@['init_'+type]()


	getType: ->
		@type


	bindToValidator: (validator) ->
		if @['bind_'+@type]?
			@['bind_'+@type](validator)

	setColumnName: (name) ->
		@columnName = name
		@

	getColumnName: ->
		@columnName

	setErrorMessage: (str) ->
		@errorString = str
		@

	setWarningMessage: (str) ->
		@warningString = str
		@

	error: (str) ->
		if @errorString then @errorString else str

	warning: (str) ->
		if @errorString then @errorString else str

	validate: (val, record, recordSet, mySet) ->
		if @['rule_'+@type]? then @['rule_'+@type](val, record, recordSet, mySet) else undefined

	### Validation Rules ###

	rule_flibble: (val) ->
		if val? and val is 'flibble' then return undefined
		@error 'Value is not set to flibble'

	# Check that a value is present
	rule_notNull: (val) ->
		if val? then return undefined


	# Value is required in forms
	rule_required: (val) ->
		if val? and val.length > 0 then return undefined
		@error 'Required field'

	bind_required: (validator) ->
		validator.setRequired(true)


	# Default
	rule_default: (val) ->
		undefined

	mod_default: (val) ->
		unless val?
			if utils.objType(@args) is 'object' then return @args.value ? undefined
			return @args
		val

	bind_default: (validator) ->
		validator.setRequired(false)

	# Strings
	rule_length: (val) ->
		unless val? then return undefined

		if @args.min? and val.length < @args.min
			return @error(@args.minMessage ? "Minimum length of #{@args.min} character#{if @args.min is 1 then '' else 's'}")

		if @args.max? and val.length > @args.max
			return @error(@args.maxMessage ? "Maximum length of #{@args.max} character#{if @args.min is 1 then '' else 's'}")

		undefined

	# Email Address
	rule_email: (val) ->
		if /^[^@]+@[^@]+$/.test(val)
			if /^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.(?:[A-Z]{2}|com|org|net|edu|gov|mil|biz|info|mobi|name|aero|asia|jobs|museum)$/i.test(val)
				return undefined
			else
				return {warning: @warning('Badly formatted email address')}
		@error 'Invalid email address'


	# Cross reference another field and make sure they match
	rule_matchRecord: (val, record, recordSet, mySet) ->
		unless @args.column?
			return 'Column to check against not specified'

		unless record.columnExists(@args.column)
			return "Column #{@args.column} does not exist to check against"

		if record.get(@args.column) is val then return undefined
		@error "Does not match #{record.getColumn(@args.column).getLabel()} field"

	# Cross reference another password field
	rule_matchPassword: (val, record, recordSet, mySet) ->
		unless @args.column?
			return 'Column to check against not specified'

		unless record.columnExists(@args.column)
			return "Column #{@args.column} does not exist to check against"

		if record.checkPassword(@args.column, val) then return undefined
		@error "Does not match #{record.getColumn(@args.column).getLabel()} field"

	# Generic regex rule
	rule_regex: (val) ->
		unless @args.match? then return 'No regex specified'

		if @args.match instanceof RegExp
			re = @args.match
		else
			re = new RegExp(@args.match, @args.flags ? '')

		if re.test(val) then return undefined
		@error "Incorrect data entered"


