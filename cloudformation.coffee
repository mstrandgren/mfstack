_ = require('lodash')
Promise = require('promise')
aws = require('./AwsOperations.coffee')
{createTemplate} = require('./Template.coffee')



run = ->
	template = createTemplate()

	# aws.createStack('test-stack-9', template)
	# .then (result) ->
	# 	console.log "Stack Done"
	# 	console.log "Visit #{result.Outputs[0].OutputValue}"
	# .then null, (e) ->
	# 	console.log "Something went wrong: ", e


	# aws.deleteStack('test-stack-9')
	# .then (result) ->
	# 	console.log "Deleted stack: \n#{JSON.stringify(result, null, 2)}"
	# .then null, (e) ->
	# 	console.error e
	# 	console.error e.stack

	aws.describe('test-stack-9')

	return





run()

