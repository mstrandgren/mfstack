_ = require('lodash')
Promise = require('promise')

{cf, ec2, ecs} = require('./AwsWrapped.coffee')





createStack = (name, template) ->
	cf.createStack
		Capabilities: ['CAPABILITY_IAM']
		StackName: name
		TemplateBody: JSON.stringify(template)
	.then (data) ->
		waitFor(checkStackReady(name), 10000, "Creating stack")

updateStack = (name, template) ->
	stackPolicy =
		Statement: [
			Effect : 'Allow',
			Action : 'Update:*',
			Principal: '*',
			Resource : '*'
		]

	cf.updateStack
		Capabilities: ['CAPABILITY_IAM']
		StackName: name
		TemplateBody: JSON.stringify(template)
		StackPolicyDuringUpdateBody: JSON.stringify(stackPolicy)

deleteStack = (name) ->
	cf.deleteStack
		StackName: name
	.then (data) ->
		waitForStack(name, "Deleting stack")
	.then null, (e) ->
		if e.statusCode == 400
			return "Successfully deleted #{name}"
		else
			throw e

checkStackReady = (name) ->
	cf.describeStacks(StackName: name)
	.then (data) ->
		status = data.Stacks[0].StackStatus
		if /COMPLETE/.test(status) then return data.Stacks[0]
		return

getStackEvents = (name) ->
	cf.describeStackEvents
		StackName: name
	.then (result) ->
		events = for e in result.StackEvents
			id: e.EventId
			name: e.LogicalResourceId
			status: e.ResourceStatus
			type: e.ResourceType
			timestamp: new Date(e.Timestamp)

		events = _.sortBy(events, 'timestamp')
		return events



describe = (name) ->

	# cf.describeStackResource
	# 	StackName: name
	# 	LogicalResourceId: 'EcsCluster'
	# .then (result) ->
	# 	console.log JSON.stringify(result, null, 2)

	# ecs.listTasks
	# 	cluster: 'test-EcsCl-1CGS1BJKZNATQ'
	# 	serviceName: 'test-Marco-V1QCBBG7YQ0S'
	# 	desiredStatus: 'RUNNING'
	# .then (result) ->
	# 	console.log JSON.stringify(result, null, 2)

	# 'arn:aws:ecs:eu-west-1:066341227319:service/test-Marco-V1QCBBG7YQ0S'


module.exports = {
	createStack
	updateStack
	deleteStack
	describe
}

# --------------------------------------------------------

waitFor = (condition, interval, label) ->
	startTime = Date.now()
	new Promise (resolve, reject) ->
		check = ->
			condition()
			.then (data) ->
				if data?
					process.stdout.write('\n')
					return resolve(data)

				timeElapsed = (Date.now() - startTime)/1000
				process.stdout.clearLine()
				process.stdout.cursorTo(0)
				process.stdout.write("#{label} #{Math.floor(timeElapsed/60)}m #{Math.round(timeElapsed)%60}s")
				setTimeout(check, 10000)
		check()


columnify = require('columnify')

waitForStack = (name, label, interval = 3000) ->
	startTime = new Date()
	new Promise (resolve, reject) ->
		displayedEvents = {}
		check = ->
			checkStackReady(name)
			.then (result) ->
				if result?
					return resolve(result)
				getStackEvents(name)
				.then (events) ->
					output = for e in events when not displayedEvents[e.id]? and e.timestamp > startTime
						time: e.timestamp.toLocaleTimeString()
						resource: e.name
						status: e.status
					if output.length > 0
						console.log columnify(output, {showHeaders: false})
					setTimeout(check, interval)
			.then null, (e) ->
				reject(e)

		check()

