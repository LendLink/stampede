stampede = require '../stampede'
styleManager = require './styles'
tableClass = require './table'

excel = require 'excel4node'


log = stampede.log


###

Our core report class which is the core export of this library

###

class module.exports
	styles: 				undefined
	tables:					undefined

	constructor: ->
		@styles = new styleManager()
		@tables = {}

	# Return (or create if it doesn't exit) a new named table of data
	table: (name) ->
		unless @tables[name]?
			@tables[name] = new tableClass(name)

		@tables[name]

	# Save our report to an excel file
	saveExcel: (filename, done) ->
		# If no filename has been specified then we cannot save the file, so just return
		unless filename?
			return @

		xlsx = new excel.WorkBook()
		@styles.setExcelWorkBook xlsx
		stampede.async.eachSeries Object.keys(@tables), (tableName, nextTable) =>
			table = @tables[tableName]
			table.renderExcel xlsx, @styles, nextTable
		, (err) =>
			if err?
				log.error "Error generating excel file: #{err}"				
				done err
			else
				xlsx.write filename, (err) =>
					if err?
						log.error "Error writing excel file to '#{filename}': #{err}"

					done err
