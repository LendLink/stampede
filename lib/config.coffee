###
dbService.coffee - Skeleton Stampede database scheduled tasks and listener
###


stampede = require './stampede'
fs = require 'fs'
os = require 'os'

exports.loadFile = (fileList, defaults) ->
	# Scan through each file in the list, see if it exists and if so load it
	for file in fileList
		if fs.existsSync(file)
			contents = fs.readFileSync file
			return JSON.parse contents

	return defaults

exports.loadEnvironment = (envFile) ->
	fc = fs.readFileSync envFile
	throw "Could not loan environment configuration file '#{envFile}'." unless fc?
	
	env = JSON.parse fc
	serverName = os.hostname()
	unless env.environments?
		stampede.lumberjack.critical "Could not find environment definitions in file '#{envFile}'."
		throw "Could not find environment definitions in file '#{envFile}'."

	# Find which environment we should use
	for eName, e of env.environments
		if stampede.utils.isMember(serverName, e.hosts ? [])
			useFile = e.configFile ? "config_#{eName}.json"
			stampede.lumberjack.info "Found environment '#{eName}' loading config file '#{useFile}'."
			return exports.loadFile(['config/' + useFile])

	if env.default?
		useFile = env.environments[env.default]?.configFile ? "config_#{env.default}.json"
		stampede.lumberjack.info "Using default environment, loading config file '#{useFile}'."
		return exports.loadFile(['config/' + useFile])

	return undefined
