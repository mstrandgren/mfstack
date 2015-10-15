http = require('http')
AWS = require('aws-sdk')

port = 8000

# Proxywrap is used to work with AWS ELB's ProxyProtocol, which is needed to make websockets work
# ProxyWrap is broken in latest node
proxiedHttp = if process.env.LOCAL or true
	http
else
	require('proxywrap').proxy(http, strict: false)

s3 = new AWS.S3()

app = require('express')()

# CORS
app.use (req, res, next) ->
	res.header("Access-Control-Allow-Origin", "*")
	res.header("Access-Control-Allow-Headers", "Origin, X-Requested-With, Content-Type, Accept")
	next()

app.get '/config/:file', (request, response) ->
	s3.getObject {Bucket: 'mfstack-test-config', Key: request.params.file}, (err, data) ->
		response.header('Content-type', 'text-plain')
		if err?
			response.statusCode = 500
			response.end(JSON.stringify({message: err.toString(), stack: err.stack}))
			return

		response.statusCode = 200
		response.end(data.Body.toString('utf8'))

proxiedHttp.createServer(app).listen(port)
console.log "Server listening on port #{port}"