# Simple time library for manipulating times - not dates, or time stamps, just plain simple times

class module.exports
	# Class method to validate a date and return the parsed value
	@validate: (hr, mn, s) ->
		if arguments.length is 0
			t = new Date()
			v = {
				valid:		true
				hours:		t.getHours()
				mins:		t.getMinutes()
				secs:		t.getSeconds()
			}
		else if arguments.length is 1 or (!mn? and !s?)
			if hr instanceof module.exports
				v = {
					valid:		true
					hours:		hr.hours
					mins:		hr.mins
					secs:		hr.secs
				}
			else
				m = hr.match /^(\d{1,2})(:(\d{1,2}))?(:(\d{1,2}))?$/
				if m isnt null
					v = {
						valid:		true
						hours:		if m[1]? then parseInt(m[1]) else 0
						mins:		if m[3]? then parseInt(m[3]) else 0
						secs:		if m[5]? then parseInt(m[5]) else 0
					}
				else
					return {
						valid:		false
						error: 		"Invalid time: #{@hr}"
					}
		else
			v = {
				valid:		true
				hours:		hr
				mins:		mn
				secs:		s
			}

		if v.hours > 23 or v.hours < 0
			v.valid = false
			v.error = "Invalid time: #{v.hours} hours"

		if v.mins > 59 or v.mins < 0
			v.valid = false
			v.error = "Invalid time: #{v.mins} minutes"

		if v.secs > 59 or v.secs < 0
			v.valid = false
			v.error = "Invalid time: #{v.secs} seconds"

		return v


	# Instance properties
	hours:			0
	mins:			0
	secs:			0

	# Class constructor
	constructor: (hr, mn, s) ->
		v = module.exports.validate(hr, mn, s)

		if v.valid
			@hours = v.hours ? 0
			@mins = v.mins ? 0
			@secs = v.secs ? 0
		else
			throw v.error

	format: (fmt = '') ->
		out = ''

		# Iterate through the format string using a regular expression to detect each field we need to output
		while fmt.length > 0
			m = fmt.match /^(.*?)(HH|hh|mm|ss|h|H|AM|PM|am|pm)/			

			if m isnt null
				# Reduce the remaining format string to exclude the field we just parsed
				fmt = fmt.slice m[0].length

				# If we skipped some text to hit a field then add that to the output
				if m[1].length > 0 then out += m[1]

				# Work out the field we need to append to the output
				out += switch m[2]
					when 'HH'
						if @hours < 10 then "0#{@hours}" else "#{@hours}"

					when 'H' then "#{@hours}"

					when 'h' then "#{@hours % 12}"

					when 'hh'
						h = @hours % 12
						if h < 10 then "0#{h}" else "#{h}"

					when 'mm'
						if @mins < 10 then "0#{@mins}" else "#{@mins}"

					when 'ss'
						if @secs < 10 then "0#{@secs}" else "#{@secs}"

					when 'am', 'pm'
						if @hours < 12 then 'am' else 'pm'

					when 'AM', 'PM'
						if @hours < 12 then 'AM' else 'PM'

					else "<unknown field #{m[2]}>"
			else
				# No further matches so add the format string to the output
				out += fmt
				fmt = ''

		# We're all done, so return the formatted output
		out

	toString: (fmt = 'HH:mm:ss') ->
		@format(fmt)

	add: (hr, mn, s) ->
		# See if we've been passed another stampede.time object
		if hr instanceof module.exports
			@hours += hr.hours
			@mins += hr.mins
			@secs += hr.secs
		else
			@hours += parseInt(hr ? 0)
			@mins += parseInt(mn ? 0)
			@secs += parseInt(s ? 0)

		# Adjust the time so it is valid, adding any additional seconds to the minutes, and minutes to the hours
		@mins += Math.floor(@secs / 60)
		@secs = @secs % 60

		@hours += Math.floor(@mins / 60)
		@mins = @mins % 60

		# All done, output @ to allow chaining
		@
