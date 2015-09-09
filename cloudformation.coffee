_ = require('lodash')
Promise = require('promise')
aws = require('./AwsOperations.coffee')
{createTemplate} = require('./Template.coffee')
colors = require('colors/safe')
argv = require('minimist')(process.argv[2..])


run = ->
	if argv._.length < 2
		console.log "Not enough arguments"
		return printHelp()

	[command, stackName] = argv._

	if command == 'create'
		return createStack(stackName)
	if command == 'destroy'
		return deleteStack(stackName)
	if command == 'scale'
		size = argv._[2]
		if not size? or size < 1 or size > 20
			return console.log "A size between 1 and 20 is required"
		return scaleStack(stackName, size)
	if command == 'deploy'
		return redeploy(stackName)

	console.log "Unrecognized command #{command}"
	printHelp()

printHelp = ->
	console.log """
Usage: mfstack <command> <stackname> [size] [options]

Available commands:
	create		Create a new stack
	destroy		Delete the stack (WARNING: very destructive, nothing remains)
	scale		Set the number of containers/instances the stack should have
	deploy		Redeploy the latest version of the image on the stack

	"""


createStack = (name) ->
	template = createTemplate()

	aws.createStack(name, template)
	.then (result) ->
		console.log "Stack '#{name}' Done"
		console.log "Visit #{result.Outputs[0].OutputValue}"
	.then null, (e) ->
		console.log "Something went wrong: ", e
		console.error e.stack

deleteStack = (name) ->
	aws.deleteStack(name)
	.then (result) ->
		console.log "Stack '#{name}' deleted"
	.then null, (e) ->
		console.error e
		console.error e.stack

scaleStack = (name, size) ->
	aws.scaleTo(name, size)
	.then (result) ->
		console.log "Stack '#{name}' updated"
	.then null, (e) ->
		console.error e
		console.error e.stack

redeploy = (name) ->
	aws.redeploy(name)
	.then (result) ->
		console.log "Stack '#{name}' updated"
	.then null, (e) ->
		console.error e
		console.error e.stack

run()

