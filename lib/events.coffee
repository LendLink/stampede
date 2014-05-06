###
events.coffee - An advanced eventEmitter equivalent with multiple event types and mechanisms.

Event types:
	on / once / emit 		- the same as standard event emitters, called asynchronously in parallel
	onFilter / emitFilter	- run in series, each returning a value to the next through to a final callback
	onRequest / emitRequest	- run in parallel, each returning a value to a final callback
	onCall / emitCall		- run as a plugin to behaviour replacing a default function, returns content
	emitRequests			- emit multiple requests in parallel to each other, collating into a final callback
###

async = require 'async'

class module.exports
	onListeners: 		undefined
	onceListeners:		undefined
	filterListeners:	undefined
	requestListeners:	undefined
	
	constructor: ->
		@onListeners = {}
		@onceListeners = {}
		@callListeners = {}
		@filterListeners = {}
		@requestListeners = {}


	#########################
	# Classical events

	on: (event, listener) ->
		@onListeners[event] ?= []
		@onListeners[event] = (l for l in @onListeners[event] when l isnt listener)
		@onListeners[event].push listener
		@

	once: (event, listener) ->
		@onceListeners[event] ?= []
		@onceListeners[event] = (l for l in @onceListeners[event] when l isnt listener)
		@onceListeners[event].push listener
		@

	removeListener: (event, listener) ->
		@onListeners[event] ?= []
		@onListeners[event] = (l for l in @onListeners[event] when l isnt listener)

		@onceListeners[event] ?= []
		@onceListeners[event] = (l for l in @onceListeners[event] when l isnt listener)

		@

	removeAllListeners: (event) ->
		@onListeners[event] = []
		@

	getListeners: (event) ->
		ret = @onListeners[event] ? []
		ret.concat @onceListeners[event] ? []


	#########################
	# Filters

	onFilter: (event, filter) ->
		@filterListeners[event] ?= []
		@filterListeners[event].push filter
		@

	removeFilter: (event, filter) ->
		@filterListeners[event] ?= []
		@filterListeners[event] = (f for f in @filterListeners[event] when f isnt filter)
		@

	removeAllFilters: (event) ->
		@filterListeners[event] = []
		@

	getFilters: (event) ->
		@filterListeners[event] ? []

	


	#########################
	# Calls

	onCall: (event, call) ->
		@callListeners[event] = call
		@

	removeCall: (event) ->
		delete @filterListeners[event]
		@

	getCall: (event) ->
		@callListeners[event]



	#########################
	# Requests

	onRequest: (event, filter) ->
		@removeRequest event, filter
		@requestListeners[event].push filter
		@

	removeRequest: (event, filter) ->
		@requestListeners[event] ?= []
		@requestListeners[event] = (f for f in @requestListeners[event] when f isnt filter)
		@

	removeAllRequests: (event) ->
		@requestListeners[event] = []
		@

	getRequests: (event) ->
		@requestListeners[event] ? []