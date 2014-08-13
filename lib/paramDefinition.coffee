###

Define our validator helper class

###

stampede = require './stampede'

module.exports = class paramDefinition
	nullable:		true
	paramName:		undefined
	overrideValue:	undefined
	defaultValue:	undefined

	required: ->
		@nullable = false
		@

	null: @required
	allowNull: @required

	notRequired: ->
		@nullable = true
		@

	notNull: @notRequired
	disallowNull: @notRequired

	parse: (val) -> val

	checkNull: (val) ->
		if val? then return true		# If we have a value then we're all okay
		return @nullable				# Otherwise we can simply return the value of @nullable

	setParamName: (@paramName) -> @
	getParamName: (def) -> @paramName ? def

	setValue: (@overrideValue) -> @
	setDefault: (@defaultValue) -> @

	doCheck: (paramName, val, apiReq, cb) ->
		val = @parse(@overrideValue ? val ? @defaultValue)

		# Check for nulls
		unless val?
			if @nullable then return cb undefined, val
			return cb("#{paramName}: is a required paramter")

		# Check against our regex
		if @regex? and @regex.test(val) is false
			return cb "#{paramName}: invalid value supplied"

		# Call our check function
		if @check?
			@check val, (err, newVal) =>
				if err? then return cb "#{paramName}: #{err}"
				else return cb undefined, newVal
			, apiReq
		else
			# No more checks so we can call our callback
			return cb undefined, val



###

Define our preset validation rules

###

class validatorInteger extends paramDefinition
	typeName:		'integer'
	min:			undefined
	max:			undefined

	setMin: (@min) -> @
	getMin: -> @min
	setMax: (@max) -> @
	getMax: -> @max

	regex: /^[0-9]+$/

	check: (val, cb) ->
		parsedVal = undefined
		error = undefined

		try
			parsedVal = parseInt val
			if @min? and parsedVal < @min
				error = "Value less than minimum of #{@min}"
			if @max? and parsedVal > @max
				error = "Value greater than maximum of #{@max}"
		catch e
			parsedVal = undefined
			error = e

		cb error, parsedVal

paramDefinition.integer = -> new validatorInteger()


class validatorFloat extends paramDefinition
	typeName:		'float'
	min:			undefined
	max:			undefined

	setMin: (@min) -> @
	getMin: -> @min
	setMax: (@max) -> @
	getMax: -> @max

	regex: /^[0-9]+(\.[0-9]*)?$/

	check: (val, cb) ->
		parsedVal = undefined
		error = undefined

		try
			parsedVal = parseFloat val
			if @min? and parsedVal < @min
				error = "Value less than minimum of #{@min}"
			else if @max? and parsedVal > @max
				error = "Value greater than maximum of #{@max}"
		catch e
			parsedVal = undefined
			error = e

		cb error, parsedVal

paramDefinition.float = -> new validatorFloat()


class validatorString extends paramDefinition
	minLength:		undefined
	maxLength:		undefined

	setMinLength: (@minLength) -> @
	getMinLength: -> @minLength
	setMaxLength: (@maxLength) -> @
	getMaxLength: -> @maxLength

	check: (val, cb) ->
		if @minLength and val.length < @minLength then return cb "Length must be greater than #{@minLength}"
		if @maxLength and val.length > @maxLength then return cb "Length must be less than #{@maxLength}"
		cb undefined, val

paramDefinition.string = -> new validatorString()


class validatorBoolean extends paramDefinition
	check: (val, cb) ->
		if val is true or val is 't' or val is 'true'
			return cb undefined, true
		if val is false or val is 'f' or val is 'false'
			return cb undefined, false
		cb "Must be boolean true or false"

paramDefinition.boolean = -> new validatorBoolean()


class validatorJson extends paramDefinition
	check: (val, cb) ->
		parsedVal = undefined
		error = undefined

		try
			if stampede._.isString val
				parsedVal = JSON.parse(val)
			else if stampede._.isObject val
				parsedVal = val
			else
				error = "Invalid JSON object: #{val}"
		catch e
			parsedVal = undefined
			error = e

		cb error, parsedVal

paramDefinition.json = -> new validatorJson()


