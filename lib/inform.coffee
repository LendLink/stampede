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



class exports.element extends utils.extendEvents
	htmlType:		'unknown'
	attributes:		undefined
	flags:			undefined
	idIndex:		undefined
	name:			undefined
	childFields:	undefined

	constructor: (id, name) ->
		super

		@attributes = {}
		@flags = {}
		@childFields = []

		if id? then @setId(id)
		if name? then @setAttribute('name', name)

	setElementType: (newType) ->
		@htmlType = newType
		@

	getElementType: ->
		@htmlType

	unsetAttribute: (attr) ->
		if attr is 'id' then return @setId undefined
		delete @attributes[attr]
		@

	setAttribute: (attr, value) ->
		if attr is 'id' then return @setId value
		@attributes[attr] = value
		@

	getAttribute: (attr) ->
		@attributes[attr]

	setFlag: (flag) ->
		@flags[flag] = true
		@

	unsetFlag: (flag) ->
		delete @flags[flag]
		@

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
		@idIndex = indexObj
		if @attributes.id?
			@idIndex.saveObj @attributes.id, @
		@

	getIdIndex: ->
		@idIndex

	addChildField: (childElement) ->
		console.log "addChildField called with type #{childElement.htmlType} and id #{childElement.getAttribute('id')}"
		@childFields.push childElement
		@

	removeChildField: (id) ->
		pointer = 0
		for field in @childFields
			if field.attributes.id == id
				@childFields.splice(pointer, 1)
				if @idIndex? then @idIndex.removeObj @attributes.id
				return @

			pointer++
		return @

	render: ->
		eleList = @renderElement()
		return eleList.join('')

	renderElement: ->
		@emitCall 'prerender'

		renderedAttributes = @renderAttributes()
		children = @renderChildren()

		ele = @renderPrefixElements()
		if children.length > 0
			ele.push "<#{@htmlType} #{renderedAttributes.join(' ')}>"
			ele = ele.concat children
			ele.push "</#{@htmlType}>"
		else
			ele.push("<#{@htmlType} #{renderedAttributes.join(' ')} />")
		ele = ele.concat @renderPostfixElements()

		if @htmlType is 'form'
			console.log "Full render stack for element of type #{@htmlType}:"
			console.log ele
		ele

	renderChildren: ->
		ele = []
		for f in @childFields
			console.log "Rendering field #{f.htmlType} with id #{f.getAttribute('id')}"
			ele = ele.concat(f.renderElement())
		ele

	renderPrefixElements: ->
		[]

	renderPostfixElements: ->
		[]


	renderAttributes: (useAttributes = @attributes, useFlags = @flags) ->
		renderedAttributes = []
		for attr of useAttributes
			val = utils.escapeHTML(useAttributes[attr])
			renderedAttributes.push "#{attr}=\"#{val}\""
		renderedAttributes = renderedAttributes.concat (f for f, v of useFlags when v is true)
		renderedAttributes

	setLabel: (newName) ->
		@name = newName
		@






class exports.form extends exports.element
	htmlType:		'form'
	model:			undefined

	constructor: (id = 'f', name) ->
		super id, name ? id

		@setIdIndex(new idIndex())

		# Create the csrf field, it auto adds itself to the form
		new exports.csrf(@)

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
		map = options['map'] ? {}
		overrideLabels = options.label ? {}
		@model = model #keep reference to this
		
		for own name, column of model.getColumns()
			console.log "Building form from model column #{name}"
			addField = true

			if (map.add? and map.add.indexOf(name) is -1)
				addField = false # there is a list, and not on the list
			if (map.exclude? and map.exclude.indexOf(name) >- 1)
				addField = false # there is a list, and on the exclude list
			
			console.log "    addField is #{addField}"
			if addField
				newField = undefined
				showLabel = false
				console.log "    column type is #{column.type}"
				if column.isPrimaryKey() is true
					newField = new exports.hidden(name)
				else
					switch column.getFormFieldType()
						when 'text'
							newField = new exports.text(name)
							showLabel = true

						when 'password'
							newField = new exports.password(name)
							showLabel = true

						# when 'checkbox'
						# 	newField = new exports.multichoice(name).setCheckbox()

						# when 'select'
						# 	newField = new exports.multichoice(name).setSelect()

						else
							console.log "Unknown form column type #{column.getFormFieldType()}"

				# Ignoring types which we don't understand..
				if newField?
					if showLabel is true
						if overrideLabels[name]?
							newField.setLabel(overrideLabels[name])
						else if column.showLabel() is true
							newField.setLabel(column.getLabel())

					if model.data?
						newField.setAttribute('value', model.data[name])
					@addField(newField)
		return @

	bindToModel: (model) ->
		console.log model
		for f in @fields
			if model.data?
				model.data[f.getAttribute('name')] = f.getAttribute('value')
				model.modified[f.getAttribute('name')] = true
		return @









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

	setLabel: (newName) ->
		if @label?
			@label.setLabel(newName)
		else
			@label ?= new exports.label(newName)
			@label.forField(@)
		@

	renderPrefixElements: ->
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


class exports.submit extends exports.field
	constructor: (id, form) ->
		super id, form
		@setAttribute 'type', 'submit'
		@label = undefined #don't show label for submit buttons


# class exports.multichoice extends exports.field
# 	options: undefined
# 	displayAs: 'select'
# 	selected: undefined

# 	constructor: (id, form) ->
# 		super id, form
# 		@options = []
# 		@selected = []

# 	setOptions: (list) ->
# 		@options = list
# 		return @

# 	getOptions: ->
# 		return @options

# 	appendOptions: (list) ->
# 		@options = @options.concat list
# 		return @

# 	setSelect: ->
# 		@displayAs = 'select'
# 		return @
		
# 	setCheckbox: ->
# 		@displayAs = 'checkbox'
# 		return @
		
# 	setRadio: ->
# 		@displayAs = 'radio'
# 		return @

# 	render: (useAttributes, useFlags) ->
# 		if !@name? and @attributes.id then @name = @attributes.id
# 		if @displayAs == 'select' then return @renderSelect(useAttributes, useFlags)
# 		if @displayAs == 'checkbox' then return @renderCheckbox(useAttributes, useFlags)
# 		if @displayAs == 'radio' then return ''

# 	renderSelect: (useAttributes, useFlags) ->
# 		renderedOption = []
# 		for option of options
# 			renderedOption.push("<option value=\"#{option.value}\">#{option.name}</option>")
# 		renderSelect = []
# 		renderSelect.push(@label.render())
# 		renderSelect.push("<select #{@renderAttributes(useAttributes, useFlags).join(' ')}>#{renderedOption.join('')}</select>")
# 		return renderSelect.join('')

# 	renderCheckbox: (useAttributes, useFlags) ->
# 		renderedBoxes = []
# 		renderedBoxes.push("<label for=\"#{@attributes.id}\">#{@name}<input type=\"checkbox\" #{@renderAttributes(useAttributes, useFlags).join(' ')}></label>")
# 		return renderedBoxes.join('')


class exports.hidden extends exports.field
	constructor: (id, form) ->
		super id, form
		@setAttribute 'type', 'hidden'
		@label = undefined #hide the label for hidden elements


class exports.csrf extends exports.hidden
	constructor: (form) ->
		console.log "Creating new csrf field"
		super '_csrf', form			#always uses '_csrf'


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

