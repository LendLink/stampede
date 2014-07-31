
class exports.action
	obj:				undefined
	tidyFunction:		undefined

	constructor: (@obj, @tidyFunction) ->

	onTidy: (@tidyFunction) -> @
	setObject: (@obj) -> @

	tidy: ->
		@tidyFunction(@obj)


class exports.bucket
	allObjs:			undefined

	constructor: ->
		@allObjs = {}

	tidy: ->
		for k, v of @allObjs
			v.tidy()
		@

	add: (obj, setKey) ->
		useKey = setKey ? obj
		old = @allObjs[useKey]

		if old?
			old.tidy

		@allObjs[useKey] = obj
		@

	remove: (specific) ->
		delete @allObjs[specific]
		@

	tidyObject: (specific) ->
		@allObjs[specific]?.tidy()
		@
