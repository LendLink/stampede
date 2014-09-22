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

	toString: (val) -> val

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

class validatorAny extends paramDefinition
	typeName:		'any'
	check: (val, cb) ->
		cb undefined, val

paramDefinition.any = -> new validatorAny()



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

	regex: /^\-?[0-9]+(\.[0-9]*)?$/

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


class validatorBigNumber extends paramDefinition
	typeName:		'float'
	min:			undefined
	max:			undefined
	precision:		undefined

	setMin: (min) ->
		@min = stampede.bignumber min
		@
	getMin: -> @min

	setMax: (max) ->
		@max = stampede.bignumber max
		@
	getMax: -> @max

	setPrecision: (val) ->
		@precision = stampede.bignumber precision
		@

	regex: /^\-?[0-9]+(\.[0-9]*)?$/

	check: (val, cb) ->
		parsedVal = undefined
		error = undefined

		try
			parsedVal = stampede.bignumber val
			if @min? and parsedVal.lt(@min)
				error = "Value less than minimum of #{@min.toString()}"
			else if @max? and parsedVal.gt(@max)
				error = "Value greater than maximum of #{@max.toString()}"
			else if @precision? and parsedVal.mod(stampede.bignumber(10).pow(@precision.neg())) isnt 0
				error = "Value has more than #{@precision.toString()} decimal place#{if @precision.equals(1) then '' else 's'}"
		catch e
			parsedVal = undefined
			error = e

		cb error, parsedVal

paramDefinition.numeric = -> new validatorBigNumber()
paramDefinition.bignumber = -> new validatorBigNumber()


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


class validatorArray extends paramDefinition
	check: (val, cb) ->
		parsedVal = undefined
		error = undefined

		try
			if stampede._.isString val
				parsedVal = JSON.parse(val)
				unless stampede._.isArray parsedVal
					error = "Invalid JSON Array: #{val}"
			else if stampede._.isArray val
				parsedVal = val
			else
				error = "Invalid JSON Array object: #{val}"
		catch e
			parsedVal = undefined
			error = e

		cb error, parsedVal

paramDefinition.array = -> new validatorArray()


class validatorDate extends paramDefinition
	regex: /^\d{4}\-\d{2}\-\d{2}/

paramDefinition.date = -> new validatorDate()


class validatorMomentDate extends paramDefinition
	format:			['ddd MMM DD YYYY', 'YYYY-MM-DD', 'DD/MM/YYYY']

	setFormat: (@format) -> @
	getFormat: -> @format

	check: (val, cb) ->
		parsedVal = undefined
		error = undefined

		try
			if @format?
				parsedVal = stampede.moment val, @format
		catch e
			parsedVal = undefined
			error = e

		cb error, parsedVal

	toString: (val) ->
		val?.format('YYYY-MM-DD')

paramDefinition.momentDate = -> new validatorMomentDate()


class validatorMomentTimestamp extends paramDefinition
	format:			['ddd MMM DD YYYY hh:mm:ss', 'YYYY-MM-DD hh:mm:ss']

	setFormat: (@format) -> @
	getFormat: -> @format

	check: (val, cb) ->
		parsedVal = undefined
		error = undefined

		try
			if @format?
				parsedVal = stampede.moment val, @format
		catch e
			parsedVal = undefined
			error = e

		cb error, parsedVal

	toString: (val) ->
		val?.format('YYYY-MM-DD HH:mm:ss')

paramDefinition.momentTimestamp = -> new validatorMomentTimestamp()
