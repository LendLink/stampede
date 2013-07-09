###
# inform.coffee
#
# Form abstraction layer and builder
###

utils = require './utils'

class idIndex
	index: undefined

	constructor: ->
		@index = {}

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



class exports.form
	attributes:		undefined
	flags:			undefined
	fields:			undefined
	ids:			undefined

	constructor: ->
		@attributes = {}
		@flags = {}
		@fields = []
		@ids = new idIndex()

	render: () ->
		renderedAttributes = []
		for attr of @attributes
			val = utils.escapeHTML(@attributes[attr])
			renderedAttributes.push "#{attr}=\"#{val}\""
		renderedAttributes = renderedAttributes.concat (f for f of @flags)
		"<form #{renderedAttributes.join(' ')}>" + @renderFields() + "</form>"

	renderFields: ->
		(f.render() for f in @fields).join ''

	setAttribute: (attr, value) ->
		@attributes[attr] = value
		return @

	getAttribute: (attr) ->
		return @attributes[attr]

	setFlag: (flag) ->
		@flags[flag] = true
		return @

	unsetFlag: (flag) ->
		delete @flags[flag]
		return @

	setAction: (url) ->
		@setAttribute 'action', url

	setMethod: (newMethod) ->
		if newMethod.toLowerCase() is 'get' then @setAttribute 'method', 'GET'
		else if newMethod.toLowerCase() is 'post' then @setAttribute 'method', 'POST'
		else throw "Unknown form method '#{newMethod}'"
		return @

	setId: (newId) ->
		@setAttribute 'id', newId

	setClass: (newClass) ->
		@setAttribute 'class', newClass

	setAutocomplete: ->
		@setFlag 'autocomplete'

	unsetAutocomplete: ->
		@unsetFlag 'autocomplete'

	setMultipart: () ->
		@setAttribute 'enctype', 'multipart/form-data'

	setPlain: () ->
		@setAttribute 'enctype', 'text/plain'

	setUrlEncoded: () ->
		@setAttribute 'enctype', 'application/x-www-form-urlencoded'

	setName: (newName) ->
		@setAttribute 'name', newName

	setTarget: (newTarget) ->
		@setAttribute 'target', newTarget

	addField: (newField) ->
		@fields.push newField
		newField.setIdIndex @ids
		return @

	getFieldById: (id) ->
		@ids.getById id

	bind: (json) ->
		for f in @fields
			name = f.getAttribute('name')
			if name? and json[name]?
				f.bind json[name]
			else
				f.bind undefined
		return @



class exports.field
	attributes:		undefined
	flags:			undefined
	idIndex:		undefined
	boundCallback:	undefined

	constructor: (id, form) ->
		@attributes = {}
		@flags = {}
		if id? then @setId id
		if form? then form.addField @

	render: (useAttributes = @attributes, useFlags = @flags) ->
		renderedAttributes = []
		for attr of useAttributes
			val = utils.escapeHTML(useAttributes[attr])
			renderedAttributes.push "#{attr}=\"#{val}\""
		renderedAttributes = renderedAttributes.concat (f for f of useFlags)
		"<input #{renderedAttributes.join(' ')} />"

	idExists: (id) ->
		@idIndex.exists id

	setIdIndex: (indexObj) ->
		@idIndex = indexObj
		if @attributes.id?
			@idIndex.saveObj @attributes.id, @
		return @

	setAttribute: (attr, value) ->
		if attr is 'id' then return @setId value
		@attributes[attr] = value
		return @

	getAttribute: (attr) ->
		return @attributes[attr]

	setFlag: (flag) ->
		@flags[flag] = true
		return @

	unsetFlag: (flag) ->
		delete @flags[flag]
		return @

	setId: (newId) ->
		# If we already have the same Id then shortcut the function.  Throw an error if the ID is already in use.
		if @attributes.id? and @attributes.id is newId then return @
		if @idIndex?.idExists(newId) then throw "Form element with id #{newId} already exists."

		# Save ourselves in the index
		@idIndex?.saveObj newId, @, @attributes.id

		# Save the new ID against the attribute list
		@attributes.id = newId

		# Set the name of the field if it hasn't already been set
		unless @attributes.name? then @attributes.name = newId

		# Return @ to allow method chaining
		return @

	onBind: (callback) ->
		@boundCallback = callback
		return @

	bind: (value) ->
		if @boundCallback
			@boundCallback(value, @)
		return @


# Specific field types
class exports.text extends exports.field
	constructor: (id, form) ->
		super id, form
		@setAttribute 'type', 'text'

class exports.textArea extends exports.field
	contructor: (id, form) ->
		super id, form
		@setAttribute 'type', 'textarea'

class exports.password extends exports.field
	contructor: (id, form) ->
		super id, form
		@setAttribute 'type', 'password'

class exports.submit extends exports.field
	contructor: (id, form) ->
		super id, form
		@setAttribute 'type', 'submit'

class exports.multichoice extends exports.field
	options: undefined
	displayAs: 'select'
	selected: undefined

	contructor: (id, form) ->
		super id, form
		@setAttribute 'type', 'textarea'
		@options = []
		@selected = []

	setOptions: (list) ->
		@options = list
		return @

	getOptions: ->
		return @options

	appendOptions: (list) ->
		@options.concat list
		return @

	setSelect: ->
		@displayAs = 'select'
		return @
		
	setCheckbox: ->
		@displayAs = 'checkbox'
		return @
		
	setRadio: ->
		@displayAs = 'radio'
		return @
		
