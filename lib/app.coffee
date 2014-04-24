###
app.coffee - Skeleton Stampede Application
###

###
We support the following application related activities:
	- tasks 	- command line jobs and commands that run in their own isolated 
	- api		- REST / Websocket API
	- web		- HTTP based websites
	- service	- services that run in the background, responding to events
	- dbService	- specialised service that responds to database events
	- jobs		- periodically run jobs
###


stampede = require './stampede'
express = require 'express'
commander = require 'commander'
os = require 'os'
fs = require 'fs'

log = stampede.log

# The application class in all its glory.
# New user applications should inherit from this class and extend it as required.

class module.exports extends stampede.events.eventEmitter
	version:			'0.0.1'
	name:				'<unknown>'
	baseDirectory:		'./'
	shouldRun:			false
	config:				undefined
	environmentFile:	undefined
	environment:		undefined

	constructor: (baseDir = './') ->
		@config = {}
		@environment = { name: '<none>' }
		@environmentFile = {}

		if baseDir is './'
			@setBaseDirectory stampede.path.dirname process.mainModule.filename
		else 
			@setBaseDirectory = baseDir


	## Start up the app
	start: (callback) ->
		@processCommandArguments () =>
			log.info "Initialising system #{commander.environment}"

			@loadConfiguration (confErr, environment, config) =>
				# Did we receive an error
				if confErr?
					log.critical "Error loading configuration: #{confErr}"
					if callback?
						process.nextTick => callback(confErr)
					else
						process.exit()

				# Now we've loaded our configuration let's set it as being active
				@useConfiguration environment, config

				# Okay we're all set up, let's look at the command line options to see what it is we're doing
				if commander.args.length is 0
					# We should boot up all default services for this environment
				else if commander.task?
					# Time to run a specific task
				else
					log.critical "No action specified (no tasks, argument#{if commander.args.length is 1 then ' is' else 's are'} '#{commander.args.join(' ')}')"




	## Base directory - set the base directory from which relative files will be retrieved
	getBaseDirectory: (extList...) ->
		@baseDirectory + extList.join('/')

	setBaseDirectory: (set) ->
		if set.match(/\/$/)
			@baseDirectory = set
		else
			@baseDirectory = set + '/'
		@

	filePath: (extList...) ->
		@baseDirectory + extList.join '/'


	## Process command line arguments
	processCommandArguments: (callback) ->
		commander
			.version(@version)
			.usage('[options]')
			.option('-p, --path <path>', 'Path to the application configuration and support files')
			.option('-d, --debug', 'Output additional debug information')
			.option('-e, --environment <env>', 'Override the hostname derived environment that is to be used')
			.option('-t, --task <task>', 'Run a specific task instead of booting the service')

		commander.parse process.argv
		
		if commander.path? then @setBaseDirectory(commander.path)

		if commander.debug? and commander.debug is true
			log.toConsole('debug')
			log.debug 'Debug mode enabled'
		else
			log.toConsole('info')

		process.nextTick => callback()


	## Load the service configuration
	loadConfiguration: (callback) ->
		log.debug 'Loading environment configuration'
		
		@environmentFile = @forceRequireObject @getBaseDirectory 'config/environment'
		
		@environmentFile.environments ?= {} 	# Make sure environments is defined, even if it's empty
		@environmentFile.default ?= {}  		# Make sure default is defined, even if it's empty

		@initialiseEnvironment callback

	initialiseEnvironment: (callback) ->
		defaultConfig = {}

		if @environmentFile.default.defaultsFile?
			defaultConfig = @forceRequireObject @getBaseDirectory @environmentFile.default.defaultsFile

		if commander.environment?
			log.debug "Using command line set environment of #{commander.environment}."

			config = @environmentFile.environments[commander.environment]
			
			unless config?
				return process.nextTick => callback("Environment #{commander.environment} not defined.")

			return @loadEnvironment commander.environment, config, defaultConfig, callback

		else
			thisHost = os.hostname()
			log.debug "Using hostname of '#{thisHost}'"
			for envName, env of @environmentFile.environments
				for host in env.hosts ? []
					if host is thisHost
						return @loadEnvironment envName, env, defaultConfig, callback

			if @environmentFile.default.environment?
				config = @environmentFile.environments[@environmentFile.default.environment]

				if config?
					return @loadEnvironment @environmentFile.default.environment, config, defaultConfig, callback
				else
					return process.nextTick => callback("Default environment of '#{@environmentFile.default.environment}' not found.")

			process.nextTick => callback "Environment for host '#{thisHost}' not found."

	loadEnvironment: (envName, envConfig, defaultConfig, callback) ->
		if envConfig.name? then log.warn "Environment #{envName} already has a 'name' property." else envConfig.name = envName

		if envConfig.configFile?
			config = @forceRequireObject @getBaseDirectory envConfig.configFile
		else
			config = {}

		# Merge our configuration with the defaults
		config = mergeConfig config, defaultConfig

		# Done loading and merging, so call the callback with our resulting configurations
		process.nextTick => callback undefined, envConfig, config


	# Force the loading of a file via require
	forceRequireObject: (fn) ->
		if require.cache[fn]?
			log.debug "Removing old cached copy of file: #{fn}"
			delete require.cache[fn]

		for ext in ['', '.json', '.js', '.coffee', '.node']
			if fs.existsSync(fn + ext)
				obj = require fn
				
				unless obj?
					log.error "Could not forceRequireObject file '#{fn}'"
					return {}

				if stampede._.isPlainObject obj
					return obj
				
				log.error "File '#{fn}' did not return a plain object in forceRequireObject"
				return {}

		log.error "File '#{fn}' does not exist in forceRequireObject"
		return {}

	# Set the configuration details to be used
	useConfiguration: (env, config) ->
		@environment = env
		@config = config
		@


mergeConfig = (source, merge) ->
	for k,v of merge
		if stampede._.isPlainObject(v) and source[k]? and stampede._.isPlainObject(source[k])
			source[k] = mergeConfig source[k], v
		else
			source[k] ?= v

	source