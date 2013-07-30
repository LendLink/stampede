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
	fieldset:		undefined
	model:			undefined

	constructor: (name) ->
		@attributes = {}
		@flags = {}
		@fields = []
		@fieldset = []
		@ids = new idIndex()

		#need to add fields to fieldset rather than to the form..
		@fieldset.push(new exports.fieldset(name))
		@addField(new exports.csrf()) #this will be added with the id _csrf

	render: () ->
		renderedAttributes = []
		for attr of @attributes
			val = utils.escapeHTML(@attributes[attr])
			renderedAttributes.push "#{attr}=\"#{val}\""
		renderedAttributes = renderedAttributes.concat (f for f of @flags)
		form = []
		form.push("<form #{renderedAttributes.join(' ')}>")
		form.push(@fieldset[0].render().replace("%s",@renderFields()))
		form.push("</form>")
		return form.join('')

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
		return @

	setMethod: (newMethod) ->
		if newMethod.toLowerCase() is 'get' then @setAttribute 'method', 'GET'
		else if newMethod.toLowerCase() is 'post' then @setAttribute 'method', 'POST'
		else throw "Unknown form method '#{newMethod}'"
		return @

	setId: (newId) ->
		@setAttribute 'id', newId
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
		@fields.push newField
		newField.setIdIndex @ids
		return @

	removeField: (id) ->
		pointer = 0
		for field in @fields
			if field.attributes.id == id
				@fields.splice(pointer, 1)
				return @
			pointer++
		return @

	getFieldById: (id) ->
		@ids.getById id

	bind: (json) ->
		for f in @fields
			name = f.getAttribute('id')
			if name? and json[name]?
				f.bind json[name]
			else
				f.bind undefined
		return @

	addCSRF: (token) ->
		@getFieldById('_csrf').setAttribute('value', token)
		return @

	#Bind a DBA model into this form
	###
	{ add : ['field_name']
    exclude : ['other_field'] }
	###
	bindModel: (model, map = {}) ->
		@model = model #keep reference to this
		for own name, column of model.columns
			addField = true
			if (map.add? and map.add.indexOf(name)==-1)
				addField = false #there is a list, and not on the list
			if (map.exclude? and map.exclude.indexOf(name)>-1)
				addField = false #there is a list, and on the exclude list
			if addField
				newfield = undefined
				if column.type=='serial'
					newfield = new exports.hidden(name)
				if column.type=='varchar'
					newfield = new exports.text(name)
				if column.type=='text'
					newfield = new exports.textArea(name)
				if column.type=='boolean'
					newfield = new exports.multichoice(name).setCheckbox()
				#ignoring types which we don't understand..
				if newfield?
					if model.data?
						newfield.setAttribute('value', model.data[name])
					@addField(newfield)
		return @

	bindToModel: (model) ->
		console.log model
		for f in @fields
			if model.data?
				model.data[f.getAttribute('name')] = f.getAttribute('value')
				model.modified[f.getAttribute('name')] = true
		return @

class exports.element
	attributes:		undefined #key => [values]
	idIndex:		undefined
	name:			undefined

	constructor: ->
		@attributes = {}

	setAttribute: (attr, value) ->
		if attr is 'id' then return @setId value
		@attributes[attr] = value
		return @

	getAttribute: (attr) ->
		return @attributes[attr]

	setId: (newId) ->
		# If we already have the same Id then shortcut the function.  Throw an error if the ID is already in use.
		if @attributes.id? and @attributes.id is newId then return @
		if @idIndex?.idExists(newId) then throw "Form element with id #{newId} already exists."

		# Save ourselves in the index
		@idIndex?.saveObj newId, @, @attributes.id

		# Save the new ID against the attribute list
		@attributes.id = newId

		# Set the name of the field if it hasn't already been set
		unless @attributes.name? then @attributes.name = newId

		# Return @ to allow method chaining
		return @

	idExists: (id) ->
		@idIndex.exists id

	setIdIndex: (indexObj) ->
		@idIndex = indexObj
		if @attributes.id?
			@idIndex.saveObj @attributes.id, @
		return @

	renderAttributes: (useAttributes = @attributes, useFlags = @flags) ->
		renderedAttributes = []
		for attr of useAttributes
			val = utils.escapeHTML(useAttributes[attr])
			renderedAttributes.push "#{attr}=\"#{val}\""
		renderedAttributes = renderedAttributes.concat (f for f of useFlags)
		return renderedAttributes

	setLabel: (newName) ->
		@name = newName
		return @

class exports.field extends exports.element
	flags:			undefined
	boundCallback:	undefined
	label:			undefined
	startShim:		undefined
	endShim:		undefined

	constructor: (id, form) ->
		super
		@flags = {}
		if id?
			@setId id
			@label = new exports.label(id)
		if form? then form.addField @

	render: (useAttributes = @attributes, useFlags = @flags) ->
		element = []
		if @startShim? then element.push(@startShim)
		if @label? then	element.push(@label.render())
		element.push("<input #{@renderAttributes(useAttributes, useFlags).join(' ')}>")
		if @endShim? then element.push(@endShim)
		return element.join(' ')

	setFlag: (flag) ->
		@flags[flag] = true
		return @

	unsetFlag: (flag) ->
		delete @flags[flag]
		return @

	onBind: (callback) ->
		@boundCallback = callback
		return @

	bind: (value) ->
		@setAttribute('value', value)
		if @boundCallback
			@boundCallback(value, @)
		return @

	setStartShim: (value) ->
		@startShim = value
		return @

	setEndShim: (value) ->
		@endShim = value
		return @

	setLabel: (newName) ->
		if @label? then @label.setLabel(newName)
		@name = newName

# Specific field types
class exports.text extends exports.field
	constructor: (id, form) ->
		super id, form
		@setAttribute 'type', 'text'

class exports.textArea extends exports.field
	constructor: (id, form) ->
		super id, form

	render: (useAttributes = @attributes, useFlags = @flags) ->
		textarea = []
		textarea.push(@label.render())
		textarea.push("<textarea #{@renderAttributes(useAttributes, useFlags).join(' ')} >")
		if @attributes.value? then textarea.push(@attributes.value)
		textarea.push("</textarea>")
		return textarea.join('')

class exports.password extends exports.field
	constructor: (id, form) ->
		super id, form
		@setAttribute 'type', 'password'

class exports.submit extends exports.field
	constructor: (id, form) ->
		super id, form
		@setAttribute 'type', 'submit'
		@label = undefined #don't show label for submit buttons

class exports.multichoice extends exports.field
	options: undefined
	displayAs: 'select'
	selected: undefined

	constructor: (id, form) ->
		super id, form
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

	render: (useAttributes, useFlags) ->
		if !@name? and @attributes.id then @name = @attributes.id
		if @displayAs == 'select' then return @renderSelect(useAttributes, useFlags)
		if @displayAs == 'checkbox' then return @renderCheckbox(useAttributes, useFlags)
		if @displayAs == 'radio' then return ''

	renderSelect: (useAttributes, useFlags) ->
		renderedOption = []
		for option of options
			renderedOption.push("<option value=\"#{option.value}\">#{option.name}</option>")
		renderSelect = []
		renderSelect.push(@label.render())
		renderSelect.push("<select #{@renderAttributes(useAttributes, useFlags).join(' ')}>#{renderedOption.join('')}</select>")
		return renderSelect.join('')

	renderCheckbox: (useAttributes, useFlags) ->
		renderedBoxes = []
		renderedBoxes.push("<label for=\"#{@attributes.id}\">#{@name}<input type=\"checkbox\" #{@renderAttributes(useAttributes, useFlags).join(' ')}></label>")
		return renderedBoxes.join('')

class exports.hidden extends exports.field
	constructor: (id, form) ->
		super id, form
		@setAttribute 'type', 'hidden'
		@label = undefined #hide the label for hidden elements

class exports.csrf extends exports.hidden
	constructor: (id, form) ->
		super '_csrf', form #always uses '_csrf'

class exports.label extends exports.element
	constructor: (id) ->
		super
		@setAttribute('id', id)

	render: ->
		if @attributes.id?
			@attributes['for'] = @attributes.id
		"<label for=\"#{@attributes.for}\" >#{@name}</label>"

class exports.fieldset extends exports.element
	constructor: (newName) ->
		super
		@name = newName

	render: ->
		fieldset = []
		fieldset.push("<fieldset>")
		if @name? then fieldset.push("<legend>#{@name}</legend>")
		fieldset.push("%s")
		fieldset.push("</fieldset>")
		return fieldset.join('')