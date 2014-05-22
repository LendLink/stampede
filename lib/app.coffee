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
async = require 'async'
cluster = require 'cluster'

log = stampede.log

# The application class in all its glory.
# New user applications should inherit from this class and extend it as required.

forkEnvVar = '__STAMPEDE_APP_SERVICE__'


class module.exports #extends stampede.events
	version:			'0.0.1'
	name:				'<unknown>'
	baseDirectory:		'./'
	shouldRun:			false
	config:				undefined
	environmentFile:	undefined
	environment:		undefined
	runningServices:	undefined
	workerService:		undefined

	# Class methods
	@service:			require './app/service'
	@api:				require './app/api'
	@task:				require './app/task'

	# Constructor for instances
	constructor: (baseDir) ->
		@config = {}
		@environment = { name: '<none>' }
		@environmentFile = {}
		@runningServices = {}

		if baseDir?
			@setBaseDirectory = baseDir
		else
			@setBaseDirectory stampede.path.dirname process.mainModule.filename


	## Start up the app
	start: (callback) ->
		# Process our command line arguments
		@processCommandArguments () =>
			log.info "Initialising system #{if commander.environment? then commander.environment else 'using hostname ' + os.hostname()}"

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
				if cluster.isMaster
					if commander.task?
						# We should execute a task
						log.info "Load and Execute task #{commander.task}"
						@execTask commander.task
					else if commander.args.length is 0
						# We should boot up all default services for this environment
						@startAllServices()
					else
						log.critical "No action specified (no tasks, argument#{if commander.args.length is 1 then ' is' else 's are'} '#{commander.args.join(' ')}')"
				else if cluster.isWorker
					serviceName = process.env[forkEnvVar]
					process.nextTick =>
						@workerStart (err) =>
							if err?
								log.critical "Error starting worker: #{err}"
								cluster.worker.disconnect()
							else
								@startService serviceName
						, serviceName

	workerStart: (callback) ->
		process.nextTick => callback()


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

		@environmentFile = @forceRequireObject @getBaseDirectory 'config/app'

		@environmentFile.environments ?= {} 	# Make sure environments is defined, even if it's empty
		@environmentFile.default ?= {}  		# Make sure default is defined, even if it's empty
		@environmentFile.services ?= {}  		# Make sure services is defined, even if it's empty
		@environmentFile.tasks ?= {}	  		# Make sure tasks is defined, even if it's empty

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
		config = stampede.utils.objectMergeDefault config, defaultConfig

		# Done loading and merging, so call the callback with our resulting configurations
		process.nextTick => callback undefined, envConfig, config

	getEnvironment: -> @environment

	getPostgres: (dbName) -> @environment.postgres?[dbName]

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

	# Start up everything!
	startAllServices: ->
		log.info "Starting all services for this environment."
		@environment.services ?= []
		async.each @environment.services, (service, cb) =>
			if @runningServices[service]?
				return cb("Service #{service} cannot be started twice.")

			unless @environmentFile.services[service]?
				return cb "Service #{service} not defined."

			sd = @environmentFile.services[service]
			log.info "Starting service '#{service}'"
			@runningServices[service] = sv = new runningService(service)
			threads = 1
			if sd.cluster is false then threads = 1
			else if sd.cluster is true then threads = os.cpus.length
			else if sd.cluster? then threads = sd.cluster
			sv.startThreads(threads)
			cb()
		, (err) =>
			if err?
				log.critical "Error starting services: #{err}"
				process.exit()
			log.info "All services started."

	# Start up an individual service
	startService: (name) ->
		service = @environmentFile.services[name]
		unless service?
			log.critical "Service '#{name}' not defined."
			cluster.worker.kill()
			return

		unless service.path?
			log.critical "Service '#{name}' does not specify a library path."
			cluster.worker.kill()
			return

		log.debug "Loading service #{name} on worker #{cluster.worker.id}"

		if require.cache[service.path]?
			log.debug "Removing cached service #{name} from require."
			delete require.cache[service.path]

		serviceLib = require @getBaseDirectory service.path
		log.debug "Loaded service #{name}"
		@workerService = new serviceLib(@, @config)
		log.info "Service #{@workerService.name} initialised, starting."
		@workerService.start()

	# Execute a task
	execTask: (name) ->
		unless @environmentFile.tasks[name]?
			log.critical "Task '#{name}' is not defined."
			return

		classFile = require @getBaseDirectory @environmentFile.tasks[name]
		log.debug "Loaded task #{name}"

		task = new classFile(@)
		task.run commander.args, (err) =>
			if err?
				log.error "Error executing task #{name}: #{err}"
			else
				log.info "Task #{name} successfully completed running"



class runningService
	workers:			undefined
	shutdown:			false
	name:				'<unknown>'

	constructor: (srv) ->
		@name = srv
		@workers = {}

	startThreads: (n) ->
		if cluster.isMaster
			log.debug "Starting worker thread(s): #{n}"
			env = {}
			env[forkEnvVar] = @name
			for i in [1..n]
				log.debug "Starting worker thread #{i} of #{n}"
				@setupWorker cluster.fork(env)

		else if cluster.isWorker
			log.info "Worker starting: #{cluster.worker.id}"
			process.on 'message', (msg) ->
				console.log "Message received: #{msg}"

	setupWorker: (worker) ->
		@workers[worker.id] = worker

		worker.on 'online', =>
			log.debug "Worker #{worker.id} started"

		worker.on 'exit', (code, signal) =>
			delete @workers[worker.id]

			if worker.suicide
				log.debug "Worker #{worker.id} exited voluntarily."
			else
				log.info "Worker #{worker.id} unexpectedly exited (#{code}, #{signal}), restarting."
				@startThreads 1
