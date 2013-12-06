inform
=======

inform is a form library that works with stampede/dba to assist in the creation/updating of dba objects.


The Form
--------

```coffeescript
# UserForm.coffee
stampede require 'stampede'
inform = stampede.inform

User = require '../path/to/User.coffee'

class UserForm
	
	getForm: (modelObject, req, next) ->

		formOptions = 
			csrf: req.session._csrf 			# optional, include hidden CSRF input
			method: 'post'						# optional, defaults to POST
			action: '/register'					# optional, form action
			dateForm: 'MM/YYYY'					# optional, date format for all date inputs, defaults to UK date format
			attributes:							# optional attributes for the form tag
				autocomplete: 'off'	
			useFields:	[						# specify which array of fields from the model you want to use
				'username'
				'first_name'
				'last_name'
				'email'
				'password'
			]
			fields:								# you can override the default field properties
				username:
					validate: ['required']
					label: 'Username'
					help: 'Please enter your username'
					attributes:
						class:	'form-control'
				salutation: 					# default is a single select dropdown
					type:	'choice'
					choices: [
						{ value: 'mr', label: 'Mr' }
						{ value: 'miss', label: 'Miss' }
						{ value: 'mrs', label: 'Mrs' }
					]
					expanded: false 			# checkboxes / radio
					multiple: false 			# allow multiple selection (multiple select / checkboxes)
		
		form = new inform.form('form_name')		# name passed in here is used for the form name and ID
						.bindModel(modelObject, formOptions)	# we are binding to the passed model object with defined options

		return next undefined, form
```

The Controller
-------------

```coffeescript
stampede = require 'stampede'
inform = stampede.inform

User = require '../path/to/User.coffee'
UserForm = new (require '../path/to/UserForm.coffee')

class UserController

	register: (req, res) ->
		UserForm.getForm User, req, (err, form) ->
			res.render('path/to/template', { form: form })
```

The View
---------

This is dependant on your choice of template engine, but for Jade it would be:

```coffeescript
!{form.render}
```

If you want to render individual form components for a more complex layout, you can use the following:
NB. When rendering form elements individually like this you need to define the form tag in your template, it won't be rendered by the form object.

```coffeescript
form(method="post", action="/register")
	!{form.renderGlobalErrors()}
	.form-control
		!{form.renderError('salutation')}
		!{form.renderLabel('salutation')}
		!{form.renderInput('salutation')}
		!{form.renderHelp('salutation')}

	!{form.renderRest}
```


Persisting Data
==============

Persisting Simple Forms
------------------------

The easiest way to save data back to the database with a model driven form, that is a form which is created by binding a DBA model object, is with the "persist" method in your controller. Here's an example of a controller that can render a view, and persist submitted form data back to the database.

```coffeescript
stampede = require 'stampede'
dba = stampede.dba
inform = stampede.inform

User = require '../model/User'
UserForm = new (require '../path/to/UserForm.coffee')

class UserController

	###
	Editing of a user's profile
	###
	editProfile: (req, res) ->
		UserForm.getForm User, req, (err, form) ->
			if req.method is "POST"
				formObjects = form.bindRequest req
					if formObjects.isValid()
						dba.connect global.config.db.connstring, (err, handle) ->
							throw err if err?
							form.persist handle, req, (err, user) ->
		                        handle.disconnect()
								unless err?
									req.flash 'success', 'Your profile has been updated.'
									res.redirect '/edit-profile/'
					else
						res.render('path/to/template', { form: form })
			else
				res.render('path/to/template', { form: form })
```

The persist method will insert or update the record for the model bound to the form.


Persisting Embedded Forms
--------------------------

You can use the above "persist" method for embedded forms too, but be aware that foreign keys will not be automatically inserted. So good for an "Edit Profile" form where the existing foreign keys don't change, not so good for a "Registration Form" where you might want to insert a user and address with a foreign key relation between address and user.

For embedded forms where you would like to insert to a number of tables with the correct foreign key relation, you need to use the "bindRequest" with chained "persist" callbacks. See the example below.

'''NB. It is noted that this is not "tha awesome" and it will be revised in the future to be a single persist call or similar.'''

```coffeescript
stampede = require 'stampede'
dba = stampede.dba
inform = stampede.inform

User = require '../model/User'
ProfileForm = new (require '../form/ProfileForm')

class RegistrationController extends BaseController

	###
	Register a new user
	###
	register: (req, res) ->
		ProfileForm.getForm User, req, (err, form) ->
			if req.method is "POST"
				formObjects = form.bindRequest req
				if formObjects.isValid()
					dba.connect global.config.db.connstring, (err, handle) ->
						formObjects.get('user').persist handle, (err, dbUser) ->
							if err? then throw err
							formObjects.get('address').set('user_id', dbUser.get('id'))
							formObjects.get('address').persist handle, (err, dbAdd) ->
								if err? then throw err
								handle.disconnect()
								req.flash 'success', 'Thank you for registering.'
								res.redirect '/welcome/'
				else
					res.render('user/view/register', { form: form })
			else
				res.render('user/view/register', { form: form })

```

Default values
--------------

You can set the default values for a model driven form by passing it a model object with the desired values set. For example, in your controller you might do the following to set a default value for the first_name and last_name fields on a user form. 

```coffeescript
newUser = User.createRecord()
newUser.set('first_name', 'Kevin')
newUser.set('last_name', 'Smith')

UserForm.getForm newUser, req, (err, form) ->
	res.render('path/to/template', { form: form })
```


Non-Model, "Static" Fields
--------------------------

You can add arbitrary static fields to a form which are not part of the bound model object. Just define them in the "fields" object in the "formOptions". This is useful for confirm password fields, Ts&Cs checkboxes etc.


Embedded Forms
---------------

You can embed a form into another. For example, you may want to embed a postal address form into a user form. This way, when you create and render your user form the address inputs will also be shown. Additionally, when you save the user form, both the user and their address will be persisted to the database. This makes it quick to create forms to create or update records in a number of related tables at the same time. 

```coffeescript
# UserForm.coffee

getForm: (modelObject, req, next) ->
	formOptions = {}
	form = inform.form('form_name')
				.bindModel(modelObject, formOptions)
	AddressForm.getForm Address, req, (err, addressForm) ->
		form.embedForm(addressForm)
		return next undefined, form
```


Removing fields on the fly
----------------------------

```coffeescript
form.removeChildField('salutation')
```


Validation
=============

In your controller you will have:

```coffeescript
if req.method is "POST"
	formObjects = form.bindRequest req
	if formObjects.isValid()
		# form is valid
	else
		# form is not valid
```

If you are rendering the form in it's entirety with

```coffeescript
!{form.render}
```

Then error messages will be rendered automatically. However, if you are using the other render methods for a more complex layout you will need to use "renderGlobalErrors" and  "renderError" to place the errors where you would like them to appear. Here's a simple example:

```coffeescript
form(method='post', action='')
	fieldset
		!{form.renderGlobalErrors()}
		.row-fluid
			legend Your Details
		.row-fluid
			.span6
				div(class='control-group')
					!{form.renderError('first_name')}
					!{form.renderLabel('first_name')}
					!{form.renderInput('first_name')}
```

Validators
===========

Example:

```coffeescript
fields:
	name:
		validate:	[
			'required'
			{ rule: 'length', args: { min: 0, max: 50 }, errorMessage: 'Name must be between 0 and 50 characters' }
		]
```

### required

This validator ensures that a string with a length greater than zero has been entered for the value of the field.

#### Arguments
* __errorMessage__ - The message the user will see when this validation rule fails

### notNull
This validator ensures that a value been entered for the value of the field. This validator will pass when a blank value is entered, if this is not the desired behaviour use the "required" validator.

#### Arguments
* errorMessage - The message the user will see when this validation rule fails

### length
This validator ensures that a string is of a certain length.

#### Arguments
* min - The minimum length the string can be
* max - The maximum length the string can be
* minMessage - The message the user will see when the min validation rule fails
* maxMessage - The message the user will see when the max validation rule fails


integer
--------
This validator ensures that a valid integer has been entered for the value of the field.

__Arguments__
* min
* max
* step - if integer must be an interval, e.g. every 5
* errorMessage - The message the user will see when this validation rule fails

** numeric **
This validator ensures that a valid number has been entered for the value of the field.

''Arguments''
* min
* max
* errorMessage - The message the user will see when this validation rule fails

** email **
This validator ensures that a valid email address has been entered for the value of the field.

''Arguments''
* errorMessage - The message the user will see when this validation rule fails

** date **
This validator ensures that the date entered matches the format defined with dateFormat.

''Arguments''
* errorMessage - The message the user will see when this validation rule fails

** time **
This validator ensures that the value entered is a time of the format: HH or HH:MM or HH:MM:SS

''Arguments''
* errorMessage - The message the user will see when this validation rule fails

** matchField **
This validator ensures that the value of two fields match. Useful for password confirmation inputs etc.

''Arguments''
* errorMessage - The message the user will see when this validation rule fails
* field - The name of the field that this field's value should match.

** notMatchField **
This validator ensures that the value of two fields do NOT match. Useful for password confirmation inputs etc.

''Arguments''
* errorMessage - The message the user will see when this validation rule fails
* field - The name of the field that this field's value should not match.

** regex **
This validator ensures that the value entered returns true when the specified regular expression is applied.

''Arguments''
* errorMessage - The message the user will see when this validation rule fails
* match - The regular expression as either a string or regular expression object.
* flags - If match is a string, then this is the regular expression flags to apply when compiling it.


Help Messages
===============

You can add help messages to form fields and render them in your template. So in your form class you might have:

```coffeescript
date_of_birth:
	validate: ['required', 'date']
	help: 'In the format dd/mm/yyyy'
```

And you can render it with:
```coffeescript
!{form.renderHelp('date_of_birth)}
```


Debugging
==========

You can call dump() on a form and on formObjects to have their anatomy logged to the console.

```coffeescript
ProfileForm.getForm user, req, (err, form) ->
	form.dump()
	if req.method is "POST"
		formObjects = form.bindRequest req
		formObjects.dump()
```

