_ = require('lodash')
Promise = require('promise')
colors = require('colors/safe')
argv = require('minimist')(process.argv[2..])
path = require('path')
scriptName = path.basename(process.argv[1])
stack = require('./Stack.coffee')
settings = require('./Settings.coffee')

run = ->
	[command, args...] = argv._

	if command == 'init'
		[stackName, image] = args
		return stack.init(stackName, image)
	if command == 'delete'
		return stack.remove()

	settings.load()
	.then (opts) ->
		if not opts.image or not opts.stackName
			throw new Error("No stack found, run  \n\n#{colors.cyan("$ #{scriptName} init")}\n\nto initialize it.")

		if command == 'create' then return stack.create(opts.stackName, opts.image)
		if command == 'destroy' then return stack.destroy(opts.stackName)
		if command == 'deploy' then return stack.redeploy(opts.stackName)

		if command == 'scale'
			size = args[0]
			if not size? or size < 1 or size > 20
				throw new Error("A size between 1 and 20 is required")
			return stack.scale(opts.stackName, size)

		console.log "Unrecognized command #{command}"
		printHelp()

printHelp = ->
	console.log """
Usage: mfstack <command> <stackname> [size] [options]

Available commands:
	init		Initialize a new stack in this directory (local only)
	delete		Delete the stack config from this directory (local only)
	create		Create the stack in AWS
	destroy		Delete the stack from AWS (WARNING: very destructive, nothing remains)
	scale		Set the number of containers/instances the stack should have
	deploy		Redeploy the latest version of the image on the stack

	"""

module.exports = ->
	run()
	.then null, (e) ->
		console.log e.message
		console.log e.stack


