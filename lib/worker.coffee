###

Flexible worker that accepts remote jobs to execute from the master process

###

cluster = require 'cluster'
stampede = require './stampede'

console.log "worker.coffee"

if cluster.isMaster
	# Do nada, we're in the master so we just want to export our interface and exit
	console.log "in master"
else if cluster.isWorker
	console.log "Yo yo mo fo, I'm in a worker: #{cluster.worker.id}"
	process.on 'message', (msg) ->
		console.log "Message received: #{msg}"

	setTimeout ->
		console.log 'boo'
	, 5000