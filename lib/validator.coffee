###
# Validation library to be shared between server and browser
###

utils = require './utils'
nodeUtil = require 'util'
moment = require 'moment'


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

	dump: (indent) ->
		if @ruleList and Object.keys(@ruleList).length > 0
			console.log indent + ' - Validation rules'
			for r, rule of @ruleList
				rule.dump(indent + '  ')
		else
			console.log indent + ' - No validation rules'

		for type, errs of @notices
			if errs.length > 0
				console.log "#{indent} #{type}:"
				for e in errs
					console.log "#{indent}   #{e}"

	setRequired: (val) ->
		@fieldRequired = val

	isRequired: ->
		@fieldRequired

	reset: ->
		@status = 'not run'
		@notices = { error: [], warning: [], info: []}
		@

	addNotice: (type, msg) ->
		@notices[type] ?= []
		@notices[type].push msg
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


	validate: (value, req, formData, field) ->
		@reset()

		for t, rule of @ruleList
			err = rule.validate(value, req, formData, field)
			
			@notices.info.push {'rule': t, result: err}

			if err?
				if utils.objType(err) is 'object'
					for k, v of err when k is 'error' or k is 'warning' or k is 'info'
						@notices[k].push v
				else
					@notices.error.push err
		
		if @hasErrors() then false else true

	isValid: ->
		if @notices.error.length > 0 then false else true

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

	dump: (indent) ->
		if @['dump_'+@type]? then @['dump_'+@type](indent)
		else
			console.log "#{indent} Rule #{@type}: #{if @args then nodeUtil.inspect(@args) else ''}"
			console.log "#{indent}    - Error string override: #{@errorString}" if @errorString
			console.log "#{indent}    - Warning string override: #{@warningString}" if @warningString



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

	validate: (val, req, formData, field) ->
		if @['rule_'+@type]? then @['rule_'+@type](val, req, formData, field) else undefined

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

	# Integers
	rule_integer: (val) ->
		unless val? then return undefined

		if @args.min? and val < @args.min
			return @error(@args.minMessage ? "Minimum value of #{@args.min}")
		
		if @args.max? and val > @args.max
			return @error(@args.maxMessage ? "Maximum value of #{@args.max}")
		
		if @args.step? and val % @args.step isnt 0
			return @error(@args.stepMessage ? "Value must be divisible by #{@args.step}")

		undefined

	# Email Address
	rule_email: (val) ->
		unless val? and val.length > 0 then return undefined

		if /^[^@]+@[^@]+$/.test(val)
			if /^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.(?:[A-Z]{2}|com|org|net|edu|gov|mil|biz|info|mobi|name|aero|asia|jobs|museum)$/i.test(val)
				return undefined
			else
				return {warning: @warning('Badly formatted email address')}
		@error 'Invalid email address'

	# Cross reference another form field
	rule_matchField: (val, req, form) ->
		unless @args.field?
			return 'Field to check against not specified'

		compField = form.getFieldById(@args.field)
		unless compField? then return "Field #{@args.field} not found within the form."

		compVal = utils.extractFormField(req, compField.getAttribute('name'))

		unless compVal?
			return "No form data for field #{@args.field}."

		if compVal is val then return undefined
		@error "Does not match #{@args.field} field"

	# Cross reference another form field
	rule_notMatchField: (val, req, form) ->
		unless @args.field?
			return 'Field to check against not specified'

		compField = form.getFieldById(@args.field)
		unless compField? then return "Field #{@args.field} not found within the form."

		compVal = utils.extractFormField(req, compField.getAttribute('name'))

		unless compVal?
			return "No form data for field #{@args.field}."

		unless compVal is val then return undefined
		@error "Has the same value as the #{@args.field} field"

	# Generic regex rule
	rule_regex: (val) ->
		unless val? and val.length > 0 then return undefined
		unless @args.match? then return 'No regex specified'

		if @args.match instanceof RegExp
			re = @args.match
		else
			re = new RegExp(@args.match, @args.flags ? '')

		if re.test(val) then return undefined
		@error "Incorrect data entered"

	# Date
	rule_date: (val, req, form, field) ->
		unless val? and val.length > 0 then return undefined

		fmt = args ? field.getProperty('format') ? 'DD/MM/YYYY'
		m = if moment.isMoment(val) then val else moment(val, fmt)
		if m.isValid() then return undefined
		@error 'Invalid date'

	# Select box, value must be one of the present options
	rule_selectBox: (val, req, form, field) ->
		unless val? and val.length > 0 then return undefined

		if field.getOptionId(val)? then return undefined
		@error 'Unknown option has been selected'
