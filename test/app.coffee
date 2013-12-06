###
###

stampede = require '../lib/stampede'

class testApp extends stampede.app
	constructor: ->
		super

		@onCall 'config.load', (callback) =>
			console.log os.hostname()
			callback {}
	

app = new testApp()
app.start()
