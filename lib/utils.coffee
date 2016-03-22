###
# Utility library
###

stampede = require './stampede'
events = require 'events'

# Returns:  number, array, object, string, etc.
exports.objType = (obj) ->
	if obj == undefined or obj == null
		return String obj
	classToType = new Object
	for name in ['Boolean', 'Number', 'String', 'Function', 'Array', 'Date', 'RegExp']
		classToType["[object #{name}]"] = name.toLowerCase()
	myClass = Object.prototype.toString.call obj
	if myClass of classToType
		return classToType[myClass]
	return 'object'


exports.isObject = (value) ->
	exports.objType(value) is 'object'

exports.isArray = (value) ->
    value and
        typeof value is 'object' and
        value instanceof Array and
        typeof value.length is 'number' and
        typeof value.splice is 'function' and
        not ( value.propertyIsEnumerable 'length' )

exports.isMember = (item, array) ->
	for i in array
		if i is item then return true
	return false


exports.clone = (obj, excludeProperties = []) ->
	if not obj? or typeof obj isnt 'object'
		return obj

	if obj instanceof Date
		return new Date(obj.getTime())

	if obj instanceof RegExp
		flags = ''
		flags += 'g' if obj.global?
		flags += 'i' if obj.ignoreCase?
		flags += 'm' if obj.multiline?
		flags += 'y' if obj.sticky?
		return new RegExp(obj.source, flags)

	newInstance = new obj.constructor()

	for key of obj
		if excludeProperties[key]
			newInstance[key] = obj[key]
		else
			newInstance[key] = exports.clone obj[key]

	return newInstance


exports.greatest = (args...) ->
	if args.length is 1 and stampede._.isArray args[0]
		args = args[0]

	v = args.shift()
	for i in args
		if i > v then v = i

	v

exports.least = (args...) ->
	if args.length is 1 and stampede._.isArray args[0]
		args = args[0]

	v = args.shift()
	for i in args
		if i < v then v = i

	v

exports.toBool = (val) ->
	unless val? then return false
	if val then return true
	return false

exports.toInt = (val) ->
	parseInt(val)

exports.escapeHTML = (str) ->
	String(str).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')

exports.idSafe = (str) ->
	String(str).replace(/[^A-Za-z0-9_:\.\-]+/g, '_')

exports.arrayify = (arg) ->
	if exports.objType(arg) isnt 'array' then return [arg]
	arg

exports.filterHash = (hash, allowed) ->
	newHash = {}
	for f in allowed
		if hash[f]?
			newHash[f] = hash[f]
	return newHash

class exports.extendEvents extends events.EventEmitter
	events:				undefined

	constructor: ->
		@events = {}

	onCall: (eventName, callback) ->
		@events[eventName] ?= []
		@events[eventName].push callback

	emitCall: (eventName, argument, additionalArgs...) ->
		return argument unless @events[eventName]?
		for ev in @events[eventName]
			args = [eventName, argument].concat(additionalArgs)
			argument = ev.apply(@, args)
		return argument

	step: (args...) ->
		setTimeout =>
				@emit.apply @, args
			, 0

exports.extractFormFieldPath = (obj, path) ->
	if path is '' then return obj

	p = path.match /^\[([^\]]+)\](.*?)$/
	if p?
		if obj[p[1]]? then return exports.extractFormFieldPath(obj[p[1]], p[2])
		else return undefined

	p = path.match /^([^\[]+)(.*?)$/
	if p?
		if obj[p[1]]? then return exports.extractFormFieldPath(obj[p[1]], p[2])
		else return undefined

	undefined

exports.extractFormField = (req, path) ->
	exports.extractFormFieldPath(req.body, path)


exports.objectMergeDefault = (source, merge) ->
	for k,v of merge
		if stampede._.isPlainObject(v) and source[k]? and stampede._.isPlainObject(source[k])
			source[k] = exports.objectMergeDefault source[k], v
		else
			source[k] ?= v

	source

class exports.idIndex
	index: undefined
	uniqueCounter: undefined

	constructor: ->
		@index = {}
		@uniqueCounter = {}

	saveObj: (id, obj, oldId) ->
		if oldId? then @removeObj oldId
		if id?
			if obj? then @index[id] = obj
			else delete @index[id]
		return @

	removeObj: (id) ->
		if @index[id]?
			delete @index[id]
		return @

	getById: (id) ->
		@index[id]

	idExists: (id) ->
		if @index[id]? then return true
		return false

	genUniqueId: (prefix = '', startId = 0) ->
		@uniqueCounter[prefix] ?= startId
		id = prefix + '_' + (++@uniqueCounter[prefix])
		if @idExists(id) then @genUniqueId(prefix) else id

	makeUniqueId: (prefix = '') ->
		if @idExists(prefix) then @genUniqueId(prefix, 1) else prefix

	saveUniqueId: (id, obj, oldId) ->
		uid = @makeUniqueId(id)
		@saveObj uid, obj, oldId
		uid

	allItems: ->
		@index


# Convert HSL to RGB.  HSL between 0 and 1; RGB values between 0 and range (defaults to 255)
exports.hsl = (h, s, l, range = 255) ->
	if s is 0
		r = g = b = l			# Achromatic, so just use the lightness
	else
		hue2rgb = (p, q, t) ->
			if t < 0 then t += 1
			if t > 1 then t -= 1
			if t < 1/6 then return p + (q - p) * 6 * t
			if t < 1/2 then return q
			if t < 2/3 then return p + (q - p) * (2/3 - t) * 6
			return p

		q = if l < 0.5 then l * (1 + s) else l + s - l * s
		p = 2 * l - q
		r = hue2rgb p, q, h + 1/3
		g = hue2rgb p, q, h
		b = hue2rgb p, q, h - 1/3

	return [Math.round(r * range), Math.round(g * range), Math.round(b * range)]

# Same as above but output to hex code
exports.hslToHex = (h, s, l) ->
	[r, g, b] = exports.hsl h, s, l

	convertToHex = (v) ->
		hex = v.toString 16
		if hex.length is 1 then '0'+hex else hex

	"##{convertToHex(r)}#{convertToHex(g)}#{convertToHex(b)}"


