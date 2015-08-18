###
# Lumberjack
#
# A logger!  Take log messages and do something useful with them!
###

# debug, info, warning, error, critical

moment = require 'moment'
sprintfjs = require 'sprintf-js'
fs = require 'fs'
util = require 'util'
clc = require 'cli-color'




noFormatting = (t) -> t

module.exports = class Lumberjack
	actions: []

	levelMap:
		debug: 		0
		info: 		1
		warning: 	2
		error:		3
		critical:	4
		note:		5

	defaultFormat: '%d %t [%C] - %m'
	currentMinLevel: 2

	isDebug: -> @currentMinLevel is 0

	constructor: () ->
		@toConsole 'info'

	levelToValue: (level, defaultLevel) ->
		@levelMap[level] ? @levelMap[defaultLevel]

	toConsole: (minLevel, overrideFormat) ->
		@actions = []
		@chainConsole minLevel, overrideFormat
		@currentMinLevel = minLevel

	chainConsole: (minLevel, overrideFormat) ->
		@actions.push {console: true, minLevel: @levelToValue(minLevel, 'info'), format: overrideFormat}
		@currentMinLevel = minLevel if minLevel < @currentMinLevel

	toFile: (minLevel, overrideFormat) ->
		@actions = []
		@chainFile minLevel, overrideFormat
		@currentMinLevel = minLevel

	chainFile: (fileName, minLevel, overrideFormat) ->
		@actions.push {file: fileName, minLevel: @levelToValue(minLevel, 'info'), format: overrideFormat}
		@currentMinLevel = minLevel if minLevel < @currentMinLevel

	formatMessage: (format, level, msg, codeColour) ->
		format.replace /%[dtlLCm]/g, (code) ->
			switch code
				when '%d' then moment().format('YYYY-MM-DD')
				when '%t' then moment().format('HH:mm:ss')
				when '%l' then level
				when '%L' then level.toUpperCase()
				when '%C' then (codeColour ? noFormatting)(level.toUpperCase())
				when '%m' then msg
				else code

	logFormat: (level, msg, data...) ->
		if data? and data.length > 0 and (data.length isnt 1 or data[0] isnt undefined)
			msg = sprintfjs.vsprintf msg, data

		@log level, msg


	log: (level, msgList, codeColour = noFormatting, textColour = noFormatting) ->
		levelValue = @levelToValue(level, 'info')

		msg = ''
		for m in msgList
			if typeof(m) is 'string'
				msg += m
			else
				msg += util.inspect(m, { showHidden: false, depth: 4 })

		msg = textColour(msg)

		for action in @actions
			if action.minLevel <= levelValue
				fMsg = @formatMessage action.format ? @defaultFormat, level, msg, codeColour

				if action.console?
					console.log fMsg
				else if action.file?
					fs.appendFile action.file, fMsg + "\n", (err) ->
						if err?
							console.log "Couldn't open log file '#{action.file}'."
							console.log "Couldn't write log line: #{fMsg}"


	debug: (msg...) ->
		@log('debug', msg)
	info: (msg...) ->
		@log('info', msg, clc.blueBright, clc.blueBright)
	warn: (msg...) ->
		@log('warning', msg, clc.yellow, clc.yellow)
	warning: (msg...) ->
		@log('warning', msg, clc.yellow, clc.yellow)
	error: (msg...) ->
		@log('error', msg, clc.red.bold, clc.red)
	critical: (msg...) ->
		@log('critical', msg, clc.red.bold.bgYellow, clc.red.bgYellow)
	note: (msg...) ->
		@log('note', msg, clc.green, clc.green)
