stampede = require './stampede'

log = stampede.log

class routeClass
	url:				''

	routeBuildParams: (apiReq, callback) ->
		unless @routeParams
			return process.nextTick => callback()

		stampede.async.each Object.keys(@routeParams), (name, cb) =>
			p = @routeParams[name]
			val = apiReq.route name
			p.doCheck "route[#{name}]", val, apiReq, (checkErr, newVal) =>
				if checkErr?
					cb checkErr
				else
					log.debug "Param #{p.getParamName(name)} set to '#{newVal}' (originally #{val})"
					apiReq.setParam p.getParamName(name), newVal
					cb()
		, (err) =>
			if err? then return callback err
			callback()

	getBuildParams: (apiReq, callback) ->
		unless @getParams
			return @routeBuildParams apiReq, callback

		stampede.async.each Object.keys(@getParams), (name, cb) =>
			p = @getParams[name]
			val = apiReq.queryArg name
			p.doCheck "get[#{name}]", val, apiReq, (checkErr, newVal) =>
				if checkErr?
					cb checkErr
				else
					log.debug "Param #{p.getParamName(name)} set to '#{newVal}' (originally #{val})"
					apiReq.setParam p.getParamName(name), newVal
					cb()
		, (err) =>
			if err? then return callback err
			@routeBuildParams apiReq, callback

	socketBuildParams: (apiReq, callback) ->
		@getBuildParams apiReq, callback

	getUrl: ->
		if stampede._.isArray @url
			@url.join ','
		else
			@url

	getRoutes: ->
		u = @url
		u = [u] unless stampede._.isArray u
		
		(url.split /\// for url in u)

	getSessionConfig: ->
		@session



class routeMatcher
	namedPaths:		undefined
	variableName:	undefined
	variableRoute:	undefined
	endPointRoute:	undefined

	constructor: ->
		@namedPaths = {}

	addRouteSpec: (spec, routerInstance) ->
		# Is the spec zero length?  If so we're defining the end point
		if spec.length is 0
			if @endPointRoute?
				log.warning "End point already defined as #{@endPointRoute.getUrl()} for route #{routerInstance.getUrl()}."
				return "End point already defined"
			else
				@endPointRoute = routerInstance
				return undefined

		# Get the first part of the spec that relates to what we're doing here and now
		part = spec.shift()

		# Is this a variable?
		if part.substring(0,1) is ':'
			varPart = part.substring 1		# Extract the name of the variable

			# Do we already have a variable defined
			if @variableName?
				# Do they match
				if @variableName is varPart
					# Yup, so attach our route to the variable route
					return @variableRoute.addRouteSpec spec, routerInstance
				else
					# Eh oh, no match no add route
					log.warning "Cannot add variable #{varPart} from route #{routerInstance.getUrl()} due to clash with variable #{@variableName}."
					return "Variable with different name already defined"
			else
				# Variable is not already defined, so install ourselves
				@variableName = varPart
				@variableRoute = new routeMatcher
				return @variableRoute.addRouteSpec spec, routerInstance

		# Otherwise we're expecting a hard and fast match
		@namedPaths[part] = new routeMatcher() unless @namedPaths[part]
		@namedPaths[part].addRouteSpec spec, routerInstance

	find: (spec, vars) ->
		# Is the spec zero length?  If we're an end point then groovy, else return no match
		if spec.length is 0
			if @endPointRoute?
				return { route: @endPointRoute, vars: vars }
			else
				return undefined

		# Otherwise we have some matching to do - do we match any predefined routes?
		part = spec.shift()

		if @namedPaths[part]?
			return @namedPaths[part].find spec, vars

		# Final check, is a variable defined?  If so save the value and move on to the next step of the route
		if @variableName?
			vars[@variableName] = part
			return @variableRoute.find spec, vars

		# No match I'm afraid, return undefined
		return undefined



	dump: (indent = '') ->
		if stampede._.size(@namedPaths) > 0
			console.log indent + 'Named Routes:'
			for n, sub of @namedPaths
				console.log indent + '  ' + n
				sub.dump(indent + '    ')

		if @variableName
			console.log indent + 'Variable:'
			console.log indent + '  :' + @variableName
			@variableRoute.dump(indent + '    ')

		if @endPointRoute
			console.log indent + 'End Point for: ' + @endPointRoute.url


###

Our core router class which is the core export of this library

###

class module.exports
	@route:				routeClass

	routes:				undefined

	dump: ->
		@routes.dump()

	constructor: ->
		@routes = new routeMatcher()

	find: (url = '/') ->
		urlSpec = url.split /\//
		urlSpec.pop() while urlSpec.length > 0 and urlSpec[urlSpec.length - 1] is ''
		urlSpec.shift() while urlSpec.length > 0 and urlSpec[0] is ''

		@routes.find urlSpec, {}

	addRoute: (r, callback) ->
		# Check the url being added is an instance of our route class
		unless r instanceof routeClass
			return process.nextTick => callback('Can only add stampede.route objects as routes.')

		# Iterate through our one or more routes
		for routeSpec in r.getRoutes()
			# Remove any spurious /'s from the beginning and end of the route
			routeSpec.pop() while routeSpec.length > 0 and routeSpec[routeSpec.length - 1] is ''
			routeSpec.shift() while routeSpec.length > 0 and routeSpec[0] is ''

			# If we still have any route info left after our trimming, add it to our table
			if routeSpec.length > 0
				log.debug "Adding route to router: '#{routeSpec.join ' / '}'"
				@routes.addRouteSpec routeSpec, r

		@


