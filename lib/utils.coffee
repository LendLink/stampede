###
# Utility library
###

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


exports.toBool = (val) ->
	unless val? then return false
	if val then return true
	return false

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

