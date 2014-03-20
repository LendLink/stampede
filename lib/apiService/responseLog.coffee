# Response Logger - Express middleware

module.exports = (opt) ->
	(req, res, next) ->
		console.log req
		next()
		console.log res
