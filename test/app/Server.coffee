require('es6-shim')

http = require('http')
https = require('https')
fs = require('fs')
path = require('path')

# Proxywrap is used to work with AWS ELB's ProxyProtocol, which is needed to make websockets work
# ProxyWrap is broken in latest node
proxiedHttp = if process.env.LOCAL or true
	http
else
	require('proxywrap').proxy(http, strict: false)

MAX_CONNECTIONS = 1000
connections = new Set()

start = ({
	cors
	httpPort
	httpsPort
	webServer

	enableWebSockets
	onConnect
	onMessage
	onClose

}) ->

	httpPort ?= 9000

	app = require('express')()

	if cors
		app.use (req, res, next) ->
			res.header("Access-Control-Allow-Origin", "*")
			res.header("Access-Control-Allow-Headers", "Origin, X-Requested-With, Content-Type, Accept")
			next()

	webServer?(app)

	httpServer = proxiedHttp.createServer(app).listen(httpPort)

	options =
		key: fs.readFileSync(path.resolve(__dirname, 'server.key'))
		cert: fs.readFileSync(path.resolve(__dirname, 'server.crt'))

	if httpsPort
		httpsServer = https.createServer(options, app).listen(httpsPort)

	if enableWebSockets
		WebSocketServer = require('ws').Server
		wsServer = new WebSocketServer
			server: httpServer

		wsServer.on 'connect', (connection) ->
			addConnection(connection, {onConnect, onMessage, onClose})

addConnection = (connection, {onConnect, onMessage, onClose}) ->
	if connections.size > MAX_CONNECTIONS
		console.error('Max connections')
		return

	connections.add(connection)
	console.log "New connection, #{connections.size} connections in total"

	removeConnection = (connection) ->
		if connections.has(connection)
			connections.delete(connection)
			onClose?(connection)

	connection.on 'close', ->
		removeConnection(connection)

	connection.on 'error', (error) ->
		console.error error
		removeConnection(connection)

	connection.on 'disconnect', ->
		removeConnection(connection)

	connection.on 'message', (data) ->
		message = JSON.parse(data.utf8Data)
		onMessage?(message, connection)?.then?((result) ->
			connection.send(JSON.stringify(result)))
		.then(null, (error) ->
			connection.send(JSON.stringify({error: error.toString()})))

broadcast = (message) ->
	connections.forEach (connection) ->
		connection.send(JSON.stringify(message))

module.exports = {start, broadcast}