###
# inform.coffee
#
# Form abstraction layer and builder
###

dba = require './dba'
utils = require './utils'
stValidator = require './validator'
async = require 'async'
moment = require 'moment'
util = require 'util'




class exports.element extends utils.extendEvents
	htmlType:		undefined			# HTML element type
	properties:		undefined			# Properties that are used internally, not rendered
	attributes:		undefined			# Renderable HTML attributes for this tag
	flags:			undefined			# Obsolete HTML flag attributes for this tag
	idIndex:		undefined			# Index object that tracks ids of all form fields
	formNameIndex:	undefined			# Make sure form names are unique
	childFields:	undefined			# Child elements
	rendered:		false				# If the element has been manually rendered or not
	parentForm:		undefined			# If we're an embedded form then this is our parent
	validator:		undefined			# The validator for this form element

	constructor: (id, name = 'form', parentForm, useValidator) ->
		super

		if parentForm?
			@formNameIndex = parentForm.getFormNameIndex()
			@parentForm = parentForm
		else
			@formNameIndex = new utils.idIndex()
	
		name = @formNameIndex.makeUniqueId('name')

		@attributes = {}
		@flags = {}
		@childFields = []
		@properties = {}
		@validator = useValidator ? (new stValidator.Validator())

		if id? then @setId(id)
		if name? then @setAttribute('name', name)

	dump: (indent = '') ->
		console.log "#{indent} #{@htmlType} : id = #{@getAttribute('id')} : rendered = #{@rendered}"

		for attr, val of @attributes
			console.log "#{indent} - Attribute '#{attr}' = '#{val}'"
		for prop, val of @properties
			console.log "#{indent} - Property '#{prop}' = '#{val}'"

		if @validator then @validator.dump(indent)

		if @childFields and @childFields.length > 0
			console.log "#{indent}  - Child Fields:"
			indent += '    '
			for child in @childFields
				child.dump(indent)

	setValidator: (v) ->
		@validator = v
		@

	getValidator: ->
		@validator

	addError: (errStr) ->
		@validator.addNotice 'error', errStr

	addRule: (rule, args, errStr) ->
		@validator.addRule(rule, args, errStr)
		@

	embedForm: (form) ->
		childName = form.getAttribute('name')
		form.removeCSRF()
		form.setFormNameIndex(@formNameIndex)
		form.setAttribute('name', @formNameIndex.makeUniqueId(childName))
		form.setParentForm(@)
		form.reindexIds(@idIndex)
		@setIdIndex(@idIndex)
		@addChildField(form)

	reindexIds: (newIdIndex) ->
		oldIdIndex = @idIndex
		@idIndex = newIdIndex

		for id, obj of oldIdIndex.allItems()
			obj.setIdIndex(@idIndex)

		@


	setValue: (val) ->
		if moment.isMoment(val)
			@setAttribute('value', val.format(@getProperty('format') ? 'DD/MM/YYYY'))
		else
			@setAttribute('value', val)
		@

	setParentForm: (form) ->
		@parentForm = form
		@

	getParentForm: ->
		@parentForm

	setFormNameIndex: (idx) ->
		@formNameIndex = idx
		@

	getFormNameIndex: ->
		@formNameIndex

	setElementType: (newType) ->
		@htmlType = newType
		@

	getElementType: ->
		@htmlType

	setProperty: (prop, value) ->
		@properties[prop] = value
		@

	getProperty: (prop) ->
		@properties[prop]

	unsetProperty: (prop) ->
		delete @properties[prop]
		@

	unsetAttribute: (attr) ->
		if attr is 'id' then return @setId undefined
		delete @attributes[attr]
		@

	setAttribute: (attr, value) ->
		if attr is 'id' then return @setId value
		@attributes[attr] = value
		@

	getAttributes: ->
		@attributes

	getAttribute: (attr) ->
		@attributes[attr]

	setFlag: (flag) ->
		@flags[flag] = true
		@

	unsetFlag: (flag) ->
		delete @flags[flag]
		@

	getId: ->
		@attributes.id

	setId: (newId) ->
		# If we already have the same Id then shortcut the function.  Throw an error if the ID is already in use.
		if @attributes.id?
			if @attributes.id is newId then return @
		
		if @idIndex?.idExists(newId) then throw "Form element with id #{newId} already exists."

		# Save ourselves in the index
		@idIndex?.saveObj newId, @, @attributes.id

		# Save the new ID against the attribute list
		@attributes.id = newId

		# Set the name of the field if it hasn't already been set
		unless @attributes.name? then @attributes.name = newId

		# Return @ to allow method chaining
		@

	idExists: (id) ->
		@idIndex?.exists id

	setIdIndex: (indexObj) ->
		myId = @getId()
		@setId undefined

		@idIndex = indexObj
		@setId @idIndex.makeUniqueId(myId)

		@

	getIdIndex: ->
		@idIndex

	addChildField: (childElement) ->
		# console.log "addChildField called with type #{childElement.htmlType} and id #{childElement.getAttribute('id')}"
		@childFields.push childElement
		@

	removeChildField: (id) ->
		pointer = 0
		if id instanceof exports.element
			for field in @childFields
				if field is id
					@childFields.splice(pointer, 1)
					if @idIndex? then @idIndex.removeObj @attributes.id
					return @
				else
					field.removeChildField id

				pointer++
		else
			for field in @childFields
				if field.attributes.id is id
					@childFields.splice(pointer, 1)
					if @idIndex? then @idIndex.removeObj @attributes.id
					return @
				else
					field.removeChildField id

				pointer++

		return @

	render: ->
		eleList = @renderElement()
		return eleList.join('')

	shouldRenderTag: ->
		return false unless @htmlType?
		return false if @htmlType is 'form' and @parentForm?
		true

	renderElement: (options) ->
		options ?= {}
		@rendered = true
		@emitCall 'prerender'

		renderedAttributes = @renderAttributes()
		children = @renderChildren()

		ele = @renderPrefixElements()
		ele = ele.concat @renderLabelElement() unless options.skipLabel? and options.skipLabel is true
		ele = ele.concat @renderErrorElement() if options.includeErrors? and options.includeErrors is true

		if children.length > 0 or @htmlType is 'select'
			ele.push "<#{@htmlType} #{renderedAttributes.join(' ')}>" if @shouldRenderTag() 
			ele = ele.concat children
			ele.push "</#{@htmlType}>" if @shouldRenderTag() 
		else
			ele.push("<#{@htmlType} #{renderedAttributes.join(' ')} />") if @shouldRenderTag()

		ele = ele.concat @renderPostfixElements()

		# if @htmlType is 'form'
		# 	console.log "Full render stack for element of type #{@htmlType}:"
		# 	console.log ele
		ele

	renderErrorElement: (options = {}, overrideErrors) ->
		errList = []
		
		for err in overrideErrors ? @validator.getErrors()
			errList.push "<span class=\"#{options.errorClass ? 'help-block'}\">"
			errList.push err
			errList.push '</span>'
		
		errList

	renderChildren: ->
		ele = []
		for f in @childFields
			ele = ele.concat(f.renderElement())
		ele

	renderPrefixElements: ->
		[]

	renderLabelElement: ->
		[]

	renderPostfixElements: ->
		[]

	getGlobalErrors: ->
		ele = [].concat @globalErrors
		for f in @childFields
			if f instanceof exports.hidden
				ele = ele.concat f.getValidator().getErrors()
			else if f instanceof exports.form
				ele = ele.concat f.getGlobalErrors()
		ele

	renderGlobalErrors: (options)->
		errs = @getGlobalErrors()
		@renderErrorElement(options, errs).join('')

	renderLabel: (id) ->
		field = @getIdIndex().getById(id)
		unless field? then throw "Could not find form field with id #{id}."

		ele = field.renderLabelElement()
		ele.join('')

	renderHelp: (id) ->
		field = @getIdIndex().getById(id)
		unless field? then throw "Could not find form field with id #{id}."

		field.getProperty('helpText') ? ''

	renderInput: (id) ->
		field = @getIdIndex().getById(id)
		unless field? then throw "Could not find form field with id #{id}."

		ele = field.renderElement({skipLabel: true})
		ele.join('')

	renderError: (id, renderOpts) ->
		field = @getIdIndex().getById(id)
		unless field? then throw "Could not find form field with id #{id}."

		ele = field.renderErrorElement(renderOpts)
		ele.join('')

	hasError: (id) ->
		field = @getIdIndex().getById(id)
		unless field? then throw "Could not find form field with id #{id}."

		field.getValidator().hasErrors()


	renderAttributes: (useAttributes = @attributes, useFlags = @flags) ->
		renderedAttributes = []
		for attr of useAttributes when useAttributes[attr]?
			val = utils.escapeHTML(useAttributes[attr])
			if attr == 'value'
				for ruleType, rule of @validator.ruleList
					if ruleType == 'date' and moment.isMoment(@attributes.value)
						fmt = @properties.format ? @properties.format ? 'DD/MM/YYYY'
						val = @attributes.value.format(fmt)				

			renderedAttributes.push "#{attr}=\"#{val}\""

		renderedAttributes = renderedAttributes.concat (f for f, v of useFlags when v is true)
		renderedAttributes

	renderRest: (doJoin = true) ->
		@rendered = true
		ele = []
		for f in @childFields when f.rendered is false
			if f instanceof exports.form
				ele = ele.concat(f.renderRest(false))
			else
				ele = ele.concat(f.renderElement())
		
		if doJoin is true then ele.join('') else ele

	bindChildRequest: (req, recordSet, recordKey) ->
		for f in @childFields
			# are we a form object?
			if f instanceof exports.form
				subRecordKey = f.getProperty('formName')
				recordSet.set subRecordKey, f.bindRecord ? f.model.createRecord()
				f.bindChildRequest(req, recordSet, subRecordKey)
			else
				origData = data = utils.extractFormField(req, f.getAttribute('name'))

				if f.getProperty('skipIfNull') is true
					continue unless data? and data isnt ''

				# Check if we're valid
				f.getValidator().reset()
				if f.getValidator().validate(data, req, @, f) is false then valid = false else valid = true

				# We're a normal element, are we mapped to a DB column?
				if f.getProperty('dbColumn')? and valid is true

					# Special case for date and timestamp fields
					if f.getProperty('specialBind') is 'moment'
						if data? and data isnt '' then data = moment(data, f.getProperty('format') ? 'DD/MM/YYYY')
						else data = undefined

					# Special case for boolean checkboxes
					if f instanceof exports.multichoice and f.displayAs is 'checkbox'
						if data?
							data = true
							f.setValue f.getProperty('fieldName')
						else
							data = false
							f.deselect f.getProperty('fieldName')
					else
						# For everything else we just bind to the raw value
						f.setValue(data)

					# console.log "Map property #{f.getProperty('dbColumn')} to data #{data}."
					recordSet.get(recordKey).set(f.getProperty('dbColumn'), data) if origData?
					recordSet.get(recordKey).setValidator f.getProperty('dbColumn'), f.getValidator()
				else
					# We're a virtual column, need to be created in the record
					newCol = new dba.virtual()
					newCol.setValidator f.getValidator()
					recordSet.get(recordKey).addColumn f.getProperty('fieldName'), newCol, data
					recordSet.get(recordKey).setValidator f.getProperty('fieldName'), newCol.getValidator()
					f.setValue(data)

				f.bindChildRequest(req, recordSet, recordKey)





class exports.form extends exports.element
	htmlType:		'form'
	model:			undefined
	bindRecord:		undefined
	csrfField:		undefined
	globalErrors:	undefined

	constructor: (id = 'f', name) ->
		super id, name ? id

		@setIdIndex(new utils.idIndex())

		# Create the csrf field, it auto adds itself to the form
		@csrfField = new exports.csrf()
		@addField(@csrfField)

		@globalErrors = []

	addGlobalError: (errorStr) ->
		@globalErrors.push errorStr

	resetErrors: ->
		@globalErrors = []

	removeCSRF: ->
		@removeField(@csrfField)
		@csrfField = undefined

	setAction: (url) ->
		@setAttribute 'action', url
		return @

	setMethod: (newMethod) ->
		if newMethod.toLowerCase() is 'get' then @setAttribute 'method', 'GET'
		else if newMethod.toLowerCase() is 'post' then @setAttribute 'method', 'POST'
		else throw "Unknown form method '#{newMethod}'"
		return @

	setAutocomplete: ->
		@setFlag 'autocomplete'
		return @

	unsetAutocomplete: ->
		@unsetFlag 'autocomplete'
		return @

	setMultipart: () ->
		@setAttribute 'enctype', 'multipart/form-data'
		return @

	setPlain: () ->
		@setAttribute 'enctype', 'text/plain'
		return @

	setUrlEncoded: () ->
		@setAttribute 'enctype', 'application/x-www-form-urlencoded'
		return @

	setName: (newName) ->
		@setAttribute 'name', newName
		return @

	setTarget: (newTarget) ->
		@setAttribute 'target', newTarget
		return @

	addField: (newField) ->
		@addChildField newField
		newField.setIdIndex @getIdIndex()
		return @

	removeField: (id) ->
		@removeChildField(id)

	getFieldById: (id) ->
		@getIdIndex().getById id

	bind: (json) ->
		for f in @fields
			name = f.getAttribute('id')
			if name? and json[name]?
				f.bind json[name]
			else
				f.bind undefined
		return @

	addCSRF: (token) ->
		@getFieldById('_csrf')?.setAttribute('value', token)
		return @

	#Bind a DBA model into this form
	###
	{ add : ['field_name']
    exclude : ['other_field'] }
	###
	bindModel: (model, options = {}) ->
		# console.log ">>>>> bindModel called <<<<<<"

		# Save a reference to our model
		if model instanceof dba.record
			@model = model.getTable()
			@bindRecord = model
		else
			@model = model
			@bindRecord = undefined
		
		options.fields ?= {}

		if options.csrf then @addCSRF(options.csrf)

		@setMethod(options.method ? 'POST')
		@setAction(options.action ? '')

		formName = options.formName ? @model.tableName()
		@setProperty('formName', formName)

		for own att, val of options.attributes ? {}
			@setAttribute(att, val)

		processedFields = {}
		for own name, column of @model.getColumns()
			opts = options.fields[name] ? {}
			processedFields[name] = true

			unless options.fields[name]?
				if options.useFields? and options.useFields.indexOf(name) is -1 then continue

			@processBindField(formName, name, column, opts, options)

	
		for name, opts of options.fields
			continue if processedFields[name]?
			processedFields[name] = true

			@processBindField(formName, name, undefined, opts, options)

		return @

	processBindField: (formName, name, column, opts, options) ->
		if @bindRecord? and @bindRecord.columnExists(name)
			boundData = @bindRecord.get(name)
			validator = @bindRecord.getColumn(name).getValidator()

		specialBind = undefined
		fmt = undefined
		addValidatorRules = []

		if column? and column.getType() is 'date'
			fmt = opts.format ? opts.format ? 'DD/MM/YYYY'
			specialBind = 'moment'
			if moment.isMoment(boundData) then boundData = boundData.format fmt
		else if column? and column.getType() is 'time'
			fmt = opts.format ? opts.format ? 'HH:mm'
			specialBind = 'time'
			if moment.isMoment(boundData) then boundData = boundData.format fmt
		else if column? and column.getType() is 'timestamp with time zone'
			fmt = opts.format ? opts.format ? 'DD/MM/YYYY HH:mm'
			specialBind = 'moment'
			if moment.isMoment(boundData) then boundData = boundData.format fmt

		newField = undefined
		showLabel = false
		# console.log "    column type is #{column.type} with form field type #{column.getFormFieldType()}"
		if column? and column.isPrimaryKey() is true
			newField = new exports.hidden(name)
		else
			switch opts.type ? column?.getFormFieldType()
				when 'text'
					newField = new exports.text(name)
					showLabel = true
					if boundData? then newField.setAttribute('value', boundData)

				when 'hidden'
					newField = new exports.hidden(name)
					showLabel = false
					if boundData? then newField.setAttribute('value', boundData)

				when 'textarea'
					newField = new exports.textArea(name)
					showLabel = true
					if boundData? then newField.setText(boundData)

				when 'password'
					newField = new exports.password(name)
					showLabel = true

				when 'checkbox'
					newField = new exports.multichoice(name).setCheckbox()
					newField.setOptions([{id: name, label: opts.label ? column?.getLabel(), value: name}])
					if boundData? and boundData is true then newField.setSelected(name)

				when 'choice'
					newField = new exports.multichoice(name).setAttribute('name', name)
					newField.setOptions(opts.choices) if opts.choices?
					newField.setSelected(opts.selected) if opts.selected?
					newField.setSelected(boundData) if boundData?

					addValidatorRules.push 'selectBox'

					if opts.expanded? and opts.expanded is true
						if opts.multiple? and opts.multiple is true then newField.setCheckbox()
						else newField.setRadio()
					else
						newField.setSelect()
						showLabel = true

				else
					if column?
						console.log "Unknown form column type #{column.getFormFieldType()}"

		# Ignoring types which we don't understand..
		if newField?
			if fmt? then newField.setProperty('format', fmt)
			if specialBind? then newField.setProperty('specialBind', specialBind)

			if validator?
				newField.setValidator(new stValidator.Validator(validator))

			if opts.validate?
				for r in opts.validate
					newField.addRule(r)

			if opts.skipIfNull? and opts.skipIfNull is true
				newField.setProperty('skipIfNull', true)

			for r in addValidatorRules
				newField.addRule(r)

			if opts.help? then newField.setProperty('helpText', opts.help)

			newField.setProperty('fieldName', name)
			newField.setAttribute('name', "#{formName}[#{name}]")
			newField.setProperty('dbColumn', name) if column?

			if showLabel is true
				newField.setLabel(opts.label ? column.getLabel())

			if @model.data?
				newField.setAttribute('value', @model.data[name])

			if opts.attributes?
				for key, val of opts.attributes
					newField.setAttribute(key, val)

			@addField(newField)
	
	bindRequest: (req) ->
		recordSet = new dba.recordSet()

		recordKey = @getProperty('formName')
		recordSet.setRecord recordKey, @bindRecord ? @model.createRecord()
		@bindChildRequest(req, recordSet, recordKey)

		recordSet

	persistResult: (dbh, recordSet, primaryCallback) ->
		recordNames = recordSet.recordNames()

		async.each recordNames, (item, callback) =>
			recordSet.get(item).persist dbh, (err, rec) =>
				if err? then return callback err
				recordSet.set item, rec
				callback undefined
		, (err) =>
			if err?
				primaryCallback err, undefined
			else
				primaryCallback undefined, recordSet


	persist: (dbh, req, primaryCallback) ->
		recordSet = @bindRequest req
		@persistResult dbh, recordSet, primaryCallback




class exports.field extends exports.element
	flags:			undefined
	boundCallback:	undefined
	label:			undefined
	htmlType:		'input'

	constructor: (id) ->
		super id
		@flags = {}
		if id?
			@setId id
		if form? then form.addField @

	onBind: (callback) ->
		@boundCallback = callback
		@

	bind: (value) ->
		@setAttribute('value', value)
		if @boundCallback
			@boundCallback(value, @)
		@

	getLabel: ->
		@label


	setLabel: (newName) ->
		if @label?
			@label.setLabel(newName)
		else
			@label ?= new exports.label(newName)
			@label.forField(@)
		@

	renderLabelElement: ->
		ele = super
		if @label?
			ele.concat @label.render(@)
		else
			ele






# Specific field types
class exports.text extends exports.field
	constructor: (id, form) ->
		super id, form
		@setAttribute 'type', 'text'

class exports.textArea extends exports.field
	htmlType:		'textarea'
	text:			''

	constructor: (id, form) ->
		super id, form

	setText: (t) ->
		@text = t
		@

	renderChildren: ->
		[@text]

	setValue: (t) ->
		@setText t


class exports.password extends exports.field
	constructor: (id, form) ->
		super id, form
		@setAttribute 'type', 'password'

	setValue: (val) ->
		@


class exports.submit extends exports.field
	constructor: (id, form) ->
		super id, form
		@setAttribute 'type', 'submit'
		@label = undefined #don't show label for submit buttons


class exports.multichoice extends exports.field
	displayAs:			'select'
	options:			undefined
	selected:			undefined

	constructor: (id, form) ->
		super id, form
		@options = []
		@selected = {}

		@onCall 'prerender', ->
			switch @displayAs
				when 'select' then @htmlType = 'select'
				when 'checkbox' then @htmlType = undefined
				when 'radio' then @htmlType = undefined

	dump: (indent) ->
		super indent

		console.log "#{indent} - Display as: #{@displayAs}"
		console.log "#{indent} - Options:"
		for opt in @options
			console.log "#{indent}   - #{util.inspect(opt)}"

		console.log "#{indent} - Selected: #{util.inspect(@selected)}"

	setOptions: (list) ->
		@options = list
		@

	getOptions: ->
		@options

	appendOptions: (list) ->
		@options = @options.concat list
		@

	setSelect: ->
		@displayAs = 'select'
		@

	setCheckbox: ->
		@displayAs = 'checkbox'
		@

	setRadio: ->
		@displayAs = 'radio'
		@

	setSelected: (id) ->
		@selected = {}
		@selected[id] = true
		@

	addSelected: (id) ->
		@selected[id] = true
		@

	deselect: (id) ->
		delete @selected[id]
		@

	deselectAll: ->
		@selected = {}
		@

	renderChildren: ->
		out = []
		switch @displayAs
			when 'select'
				for option in @options
					selected = if @selected[option.value ? option.name]? then ' selected="selected"' else ''
					out.push "<option value=\"#{option.value ? option.name}\"#{selected}>#{option.label}</option>"
			when 'checkbox'
				for option in @options
					# checked = if @selected[option.id] then ' checked="checked"' else ''
					checked = if @selected[option.value] then ' checked="checked"' else ''
					attr = utils.clone @getAttributes()
					if option.value? then attr.value = option.value
					attr.id = option.id ? @getIdIndex().genUniqueId(attr.id)
					if option.label? then out.push "<label for=\"#{attr['id']}\" class=\"checkbox\">"
					out.push "<input type=\"checkbox\" #{@renderAttributes(attr).join(' ')}#{checked} />"
					if option.label? then out.push " #{option.label}</label>"
			when 'radio'
				for option in @options
					# checked = if @selected[option.id] then ' checked="checked"' else ''
					checked = if @selected[option.value] then ' checked="checked"' else ''
					attr = utils.clone @getAttributes()
					if option.value? then attr.value = option.value
					attr.id = option.id ? @getIdIndex().genUniqueId(attr.id)
					if option.label? then out.push "<label for=\"#{attr['id']}\" class=\"radio\">"
					out.push "<input type=\"radio\" #{@renderAttributes(attr).join(' ')}#{checked} />"
					if option.label? then out.push " #{option.label}</label>"
		out

	getOptionId: (val) ->
		switch @displayAs
			when 'select'
				for o in @options
					if ''+val is ''+(o.value ? o.name) then return val
			when 'checkbox', 'radio'
				for o in @options
					if val is o.value then return val

		return undefined

	setValue: (val) ->
		id = @getOptionId(val)
		if id? then @setSelected(id)
		else
			console.log "Multichoice:"
			console.log val
		@




class exports.hidden extends exports.field
	constructor: (id, form) ->
		super id, form
		@setAttribute 'type', 'hidden'


class exports.csrf extends exports.hidden
	constructor: (form) ->
		super '_csrf', form			#always uses '_csrf'
		@setAttribute 'name', '_csrf'


class exports.label extends exports.element
	htmlType:		'label'
	text:			''
	linkedField:	undefined

	constructor: (id, t) ->
		super undefined
		@text = t ? id

		@onCall 'prerender', ->
			if @linkedField?
				@setAttribute 'for', @linkedField.getAttribute('id')
			else
				@unsetAttribute 'for'

	renderChildren: ->
		ele = []
		if @text?
			ele = [@text]

		if @linkedField? and @linkedField.getValidator().isRequired()
			ele.push '<em title="This field is required" class="required">*</em>'

		ele

	forField: (f) ->
		@linkedField = f
		@

