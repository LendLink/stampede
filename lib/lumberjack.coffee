###
# Lumberjack
#
# A logger!  Take log messages and do something useful with them!
###

# debug, info, warning, error, critical

moment = require 'moment'
sprintfjs = require 'sprintf-js'
fs = require 'fs'

module.exports = class Lumberjack
	actions: []

	levelMap:
		debug: 		0
		info: 		1
		warning: 	2
		error:		3
		critical:	4

	defaultFormat: '%d %t [%L] - %m'
	defaultMinLevel: 2

	constructor: () ->
		@toConsole 'info'

	levelToValue: (level, defaultLevel) ->
		@levelMap[level] ? @levelMap[defaultLevel]

	toConsole: (minLevel, overrideFormat) ->
		@actions = []
		@chainConsole minLevel, overrideFormat

	chainConsole: (minLevel, overrideFormat) ->
		@actions.push {console: true, minLevel: @levelToValue(minLevel, 'info'), format: overrideFormat}

	toFile: (minLevel, overrideFormat) ->
		@actions = []
		@chainFile minLevel, overrideFormat

	chainFile: (fileName, minLevel, overrideFormat) ->
		@actions.push {file: fileName, minLevel: @levelToValue(minLevel, 'info'), format: overrideFormat}

	formatMessage: (format, level, msg, data) ->
		format.replace /%[dtlLm]/g, (code) ->
			switch code
				when '%d' then moment().format('YYYY-MM-DD')
				when '%t' then moment().format('HH:mm:ss')
				when '%l' then level
				when '%L' then level.toUpperCase()
				when '%m' then msg

	log: (level, msg, data...) ->
		levelValue = @levelToValue(level, 'info')

		if data?
			msg = sprintfjs.vsprintf msg, data

		for action in @actions
			if action.minLevel <= levelValue
				fMsg = @formatMessage action.format ? @defaultFormat, level, msg, data

				if action.console?
					console.log fMsg
				else if action.file?
					fs.appendFile action.file, fMsg + "\n", (err) ->
						if err?
							console.log "Couldn't open log file '#{action.file}'."
							console.log "Couldn't write log line: #{fMsg}"


	debug: (msg, data) ->
		@log('debug', msg, data)
	info: (msg, data) ->
		@log('info', msg, data)
	warn: (msg, data) ->
		@log('warning', msg, data)
	warning: (msg, data) ->
		@log('warning', msg, data)
	error: (msg, data) ->
		@log('error', msg, data)
	critical: (msg, data) ->
		@log('critical', msg, data)
