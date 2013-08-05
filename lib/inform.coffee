###
# inform.coffee
#
# Form abstraction layer and builder
###

dba = require './dba'
utils = require './utils'
stValidator = require './validator'
async = require 'async'

class idIndex
	index: undefined
	uniqueCounter: undefined

	constructor: ->
		@index = {}
		@uniqueCounter = {}

	saveObj: (id, obj, oldId) ->
		if oldId? then @removeObj oldId
		if id?
			if obj? then @index[id] = obj
			else delete @index[id]
		return @

	removeObj: (id) ->
		if @index[id]?
			delete @index[id]
		return @

	getById: (id) ->
		@index[id]

	idExists: (id) ->
		if @index[id]? then return true
		return false

	genUniqueId: (prefix = '', startId = 0) ->
		@uniqueCounter[prefix] ?= startId
		id = prefix + '_' + (++@uniqueCounter[prefix])
		if @idExists(id) then @genUniqueId(prefix) else id

	makeUniqueId: (prefix = '') ->
		if @idExists(prefix) then @genUniqueId(prefix, 1) else prefix

	allItems: ->
		@index


class exports.recordSet
	records:		undefined

	constructor: ->
		@records = {}

	setRecord: (key, rec) ->
		@records[key] = rec
		@

	recordNames: ->
		(n for n of records)

	get: (key) ->
		@records[key]

	set: (key, rec) ->
		@setRecord(key, rec)

	isValid: ->
		valid = true
		
		for k, r of @records
			if r.isValid() is false then valid = false

		valid

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
			@formNameIndex = new idIndex()
	
		name = @formNameIndex.makeUniqueId('name')

		@attributes = {}
		@flags = {}
		@childFields = []
		@properties = {}
		@validator = useValidator ? (new stValidator.Validator())

		if id? then @setId(id)
		if name? then @setAttribute('name', name)

	setValidator: (v) ->
		@validator = v
		@

	getValidator: ->
		@validator

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
		@addChildField(form)

	reindexIds: (newIdIndex) ->
		oldIdIndex = @idIndex
		@idIndex = newIdIndex

		for id, obj of oldIdIndex.allItems()
			obj.setIdIndex(@idIndex)

		@


	setValue: (val) ->
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

				pointer++
		else
			for field in @childFields
				if field.attributes.id is id
					@childFields.splice(pointer, 1)
					if @idIndex? then @idIndex.removeObj @attributes.id
					return @

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

	hasErrors: (id) ->
		field = @getIdIndex().getById(id)
		unless field? then throw "Could not find form field with id #{id}."

		field.getValidator().hasErrors()


	renderAttributes: (useAttributes = @attributes, useFlags = @flags) ->
		renderedAttributes = []
		for attr of useAttributes when useAttributes[attr]?
			val = utils.escapeHTML(useAttributes[attr])
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
				recordKey = f.getProperty('formName')
				recordSet.set recordKey, f.bindRecord ? f.model.createRecord()
				f.bindChildRequest(req, recordSet, recordKey)
			else
				# We're a normal element, are we mapped to a DB column?
				if f.getProperty('dbColumn')?
					data = utils.extractFormField(req, f.getAttribute('name'))
					# console.log "Map property #{f.getProperty('dbColumn')} to data #{data}."
					recordSet.get(recordKey).set(f.getProperty('dbColumn'), data) if data?
					recordSet.get(recordKey).setValidator f.getProperty('dbColumn'), f.getValidator()
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

		@setIdIndex(new idIndex())

		# Create the csrf field, it auto adds itself to the form
		@csrfField = new exports.csrf()
		@addField(@csrfField)

		@globalErrors = []

	addError: (errorStr) ->
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

				when 'textarea'
					newField = new exports.textArea(name)
					showLabel = true
					if boundData? then newField.setText(boundData)

				when 'password'
					newField = new exports.password(name)
					showLabel = true

				when 'checkbox'
					newField = new exports.multichoice(name).setCheckbox()
					newField.setOptions([{id: name, label: opts.label ? column?.getLabel()}])
					if boundData? and boundData is true then newField.setSelected(name)

				when 'choice'
					newField = new exports.multichoice(name).setAttribute('name', name)
					newField.setOptions(opts.choices) if opts.choices?
					newField.setSelected(opts.selected) if opts.selected?

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
			if validator?
				newField.setValidator new stValidator.Validator(validator)

			if opts.validate?
				for r in opts.validate 
					newField.addRule(r)

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
		recordSet = new exports.recordSet()

		recordKey = @getProperty('formName')
		recordSet.setRecord recordKey, @bindRecord ? @model.createRecord()
		@bindChildRequest(req, recordSet, recordKey)

		recordSet

	persistResult: (dbh, recordSet, primaryCallback) ->
		recordNames = recordSet.recordNames()

		console.log "Calling into async"
		async.each recordNames, (item, callback) =>
			recordSet.get(item).persist dbh, (err, rec) =>
				console.log "Processing a record set: #{item}"
				if err? then return callback err
				recordSet.set item, rec
				callback undefined
		, (err) =>
			console.log "Async finsihed, calling the callback"
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
			ele.concat @label.render()
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
					if option.label? then out.push "<label for=\"#{attr['id']}\">"
					out.push "<input type=\"checkbox\" #{@renderAttributes(attr).join(' ')}#{checked} />"
					if option.label? then out.push " #{option.label}</label>"
			when 'radio'
				for option in @options
					# checked = if @selected[option.id] then ' checked="checked"' else ''
					checked = if @selected[option.value] then ' checked="checked"' else ''
					attr = utils.clone @getAttributes()
					if option.value? then attr.value = option.value
					attr.id = option.id ? @getIdIndex().genUniqueId(attr.id)
					if option.label? then out.push "<label for=\"#{attr['id']}\">"
					out.push "<input type=\"radio\" #{@renderAttributes(attr).join(' ')}#{checked} />"
					if option.label? then out.push " #{option.label}</label>"
		out

	getOptionId: (val) ->
		switch @displayAs
			when 'select'
				for o in @options
					if val is (o.value ? o.name) then return val
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
		if @text?
			[@text]
		else
			[]

	forField: (f) ->
		@linkedField = f
		@

