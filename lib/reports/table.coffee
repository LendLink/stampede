stampede = require '../stampede'

log = stampede.log


class columnClass
	name:					undefined
	type:					undefined
	options:				undefined
	mapTo:					undefined

	constructor: (@name, @type, @options, @mapTo) ->
		unless stampede._.isFunction(@mapTo) or stampede._.isString(@mapTo)
			throw "Column mapping must be a function or a string"

	renderExcelHeader: (ws, styles, columnNumber) ->
		style = @options.headerStyle ? 'header'
		ws.Cell(1, columnNumber).String(@name).Style(styles.getExcel(style))

	renderExcelData: (ws, styles, rowData, x, y) ->
		# Calculate the data to write to the cell
		data = undefined
		if stampede._.isFunction @mapTo
			# Direct call, no asynchronous callback
			if @mapTo.length is 1
				data = @mapTo(rowData)
			else
				throw "Mapping function must have precisely one argument"

		else if stampede._.isString @mapTo
			data = rowData[@mapTo]

		# Work out the cell style to apply
		defaultStyle = []
		if @type is 'integer' then defaultStyle = 'integer'
		else if @type is 'currency' then defaultStyle = 'currency'

		style = @options.style ? defaultStyle

		# Map our style to our excel styles
		style = styles.getExcel(style)

		# Apply the data and styling to the cell
		unless data?
			ws.Cell(y, x).Style(style)
		else if @type is 'integer' or @type is 'currency'
			ws.Cell(y, x).Number(data).Style(style)
		else if @type is 'date' or @type is 'month'
			# Make sure we have a date object
			unless stampede._.isDate data
				data = new Date(data)

			ws.Cell(y, x).Date(data).Style(style)
		else
			ws.Cell(y, x).String(data).Style(style)

		@




class module.exports
	columns:				undefined
	rowData:				undefined
	name:					undefined

	constructor: (@name) ->
		@columns = []
		@rowData = []

	addColumn: (args...) ->
		name = undefined
		type = 'string'
		options = {}
		mapTo = undefined

		# Map our arguments
		if args.length < 1
			throw "addColumn called without specifying a column name"

		name = args[0]

		if args.length is 2
			mapTo = args[1]
		else if args.length is 3
			type = args[1]
			mapTo = args[2]
		else if args.length >= 4
			type = args[1]
			options = args[2]
			mapTo = args[3]

		column = new columnClass(name, type, options, mapTo)
		@columns.push column
		@

	data: (data) ->
		@rowData = @rowData.concat data
		@

	renderExcel: (xlsx, styles, done) ->
		ws = xlsx.WorkSheet @name, {}

		stampede.async.series [
			(next) => @renderExcelHeaders ws, styles, next
			(next) => @renderExcelData ws, styles, next
		], done

	renderExcelHeaders: (ws, styles, done) ->
		x = 0
		for column in @columns
			column.renderExcelHeader ws, styles, ++x
		done()

	renderExcelData: (ws, styles, done) ->
		y = 1
		for row in @rowData
			@renderExcelRow ws, styles, row, ++y
		done()

	renderExcelRow: (ws, styles, rowData, y) ->
		x = 0
		for column in @columns
			column.renderExcelData ws, styles, rowData, ++x, y
