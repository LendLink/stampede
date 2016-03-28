stampede = require '../stampede'

log = stampede.log

class module.exports
	typeMap:				undefined
	styles: 				undefined
	colourLibrary:			undefined
	excelStyleCache:		undefined
	excelWorkBook:			undefined

	constructor: ->
		@excelStyleCache = {}
		@setupBaseStyles()
		@setupColours()

	setExcelWorkBook: (@excelWorkBook) -> @

	getExcel: (nameList) ->
		unless stampede._.isArray nameList
			nameList = [nameList]

		# Merge our list of styles together, adding in the default styles as our starting point
		nameList.unshift 'default'

		name = JSON.stringify(nameList)
		unless @excelStyleCache[name]?
			objList = (@styles[k] ? {} for k in nameList)
			merged = stampede._.defaultsDeep.apply(@, objList.reverse())

			console.log nameList
			console.log merged

			# Generate our excel style
			style = @excelWorkBook.Style()
			if merged.Font?
				if merged.Font.Bold then style.Font.Bold()
				if merged.Font.Italics then style.Font.Italics()
				if merged.Font.Underline then style.Font.Underline()
				if merged.Font.Family? then style.Font.Family(merged.Font.Family)
				if merged.Font.Colour? then style.Font.Color(@colourLibrary[merged.Font.Colour] ? merged.Font.Colour)
				if merged.Font.Size? then style.Font.Size(merged.Font.Size)
				if merged.Font.WrapText then style.Font.WrapText()

				if merged.Font.Alignment?
					if merged.Font.Alignment.Vertical? then style.Font.Alignment.Vertical(merged.Font.Alignment.Vertical)
					if merged.Font.Alignment.Horizontal? then style.Font.Alignment.Vertical(merged.Font.Alignment.Horizontal)
					if merged.Font.Alignment.Rotation? then style.Font.Alignment.Vertical(merged.Font.Alignment.Rotation)

			if merged.Number?
				if merged.Number.Format? then style.Number.Format(merged.Number.Format)

			if merged.Fill?
				if merged.Fill.Colour? then style.Fill.Color(@colourLibrary[merged.Fill.Colour] ? merged.Fill.Colour)
				if merged.Fill.Pattern? then style.Fill.Pattern(merged.Fill.Pattern)

			if merged.Border?
				border = merged.Border
				if merged.Border.setBorder?
					border =
						top: merged.Border.setBorder
						bottom: merged.Border.setBorder
						left: merged.Border.setBorder
						right: merged.Border.setBorder
				merged.Border border

			# Save our style
			@excelStyleCache[name] = style

		@excelStyleCache[name]

	setupColours: ->
		@colourLibrary =
			'default':							'000000'
			headerBackground:					'333333'
			headerForeground:					'FFFFFF'

	setColour: (name, colour) ->
		@colourLibrary[name] = colour
		@

	setupBaseStyles: ->
		@typeMap =
			'integer':							{ type: 'Number', style: 'integer' }
			'string':							{ type: 'String', style: 'default' }
			'currency':							{ type: 'Number', style: 'currency' }

		@styles =
			'default':
				Font:
					Alignment:
						Horizontal:				'general'
						Vertical:				'center'
					Family:						'Calibri'
					Size:						11
					Colour:						'default'
					WrapText:					true

			header:
				Font:
					Colour:						'headerForeground'


			left:
				Font:
					Alignment:
						Horizontal:				'left'

			right:
				Font:
					Alignment:
						Horizontal:				'right'

			left:
				Font:
					Alignment:
						Horizontal:				'left'

			border:
				setBorder:
					style:						'thin'
				top:						null
				bottom:						null
				left:						null
				right:						null

			integer:
				Number:
					Format:						'#,##0 ;[Red]-#,##0'

			currency:
				Number:
					Format:						'_-£* #,##0.00_-;[Red]-£* #,##0.00_-;_-£* "-"??_-;_-@_-'
				Font:
					Alignment:
						Horizontal:				'general'

			date:
				Number:
					Format:						'yyyy-mm-dd'

			month:
				Number:
					Format:						'mmmm yyyy'

			timestamp:
				Number:
					Format:						'yyyy-mm-dd HH:MM:SS'
		@