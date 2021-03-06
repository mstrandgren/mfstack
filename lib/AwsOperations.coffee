require('es6-shim')
fs = require('fs')
path = require('path')
_ = require('lodash')
AWS = require('aws-sdk')
colors = require('colors/safe')
{wrapPromise, wrapApi} = require('mflib/ApiWrapper')
glob = wrapPromise(require('glob'))
eventTarget = require('mflib/EventTarget')()

{as, cf, ec2, ecs, elb, s3} = {}

initAws = (settings) ->
	AWS.config = settings
	ec2 = wrapApi(new AWS.EC2())
	s3 = wrapApi(new AWS.S3())
	cf = wrapApi(new AWS.CloudFormation())
	ecs = wrapApi(new AWS.ECS())
	as = wrapApi(new AWS.AutoScaling())
	elb = wrapApi(new AWS.ELB())

createStack = (name, template) ->
	cf.createStack
		Capabilities: ['CAPABILITY_IAM']
		StackName: name
		TemplateBody: JSON.stringify(template)
	.then (data) ->
		waitForStack(name, _.keys(template.Resources), "Creating stack", /create/i)

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

emptyBucket = (bucket) ->
	s3.listObjects(Bucket: bucket)
	.then (results) ->
		keys = (item.Key for item in results.Contents)
		console.log "deleting #{keys.join(',')} from #{bucket}"
		s3.deleteObjects
			Bucket: bucket
			Delete:
				Objects: ({Key: k} for k in keys)
	.then (result) ->
		console.log "Deleted files: #{JSON.stringify(result)}"
	.then null, (e) ->
		console.log "Error deleting files: #{e}"

deleteStack = (name) ->
	cf.describeStackResources(StackName: name)
	.then (data) ->
		resources = (r.LogicalResourceId for r in data.StackResources)
		(if 'Bucket' in resources
			bucket = _.find data.StackResources, (r) -> r.LogicalResourceId == 'Bucket'
			emptyBucket(bucket.PhysicalResourceId)
		else
			Promise.resolve())
		.then ->
			cf.deleteStack
				StackName: name
			.then (data) ->
				waitForStack(name, resources, "Deleting stack", /delete/i)
			.then null, (e) ->
				if e.statusCode == 400
					return "Successfully deleted #{name}"
				else
					throw e

scaleTo = (stackName, size) ->
	console.log "Scaling '#{stackName}' to #{size}"
	Promise.all [
		getPhysicalId(stackName, 'ClusterAutoScalingGroup')
		getPhysicalId(stackName, 'Cluster')
		getPhysicalId(stackName, 'Service')
	]
	.then ([asgName, clusterName, serviceName]) ->
		Promise.all [
			as.updateAutoScalingGroup
				AutoScalingGroupName: asgName
				DesiredCapacity: size
				MaxSize: size
				MinSize: size
		,
			ecs.updateService
				cluster: clusterName,
				service: serviceName,
				desiredCount: size
		]
	.then (result) ->
		waitForInstances(stackName, size)
	.then ->
		waitForTasks(stackName, size)
	.then ->
		console.log("'#{stackName}' is now at #{size}")

scaleVertically = (stackName, size) ->
	getPhysicalId(stackName, 'ClusterLaunchConfiguration')
	.then (lcName) ->
		as.describeLaunchConfigurations()
		.then (result) ->
			newLcName = "#{lcName}-#{size}"
			baseLcConfig = null
			for lc in result.LaunchConfigurations
				if lc.LaunchConfigurationName == newLcName
					console.log "There is a LaunchConfiguration available for #{size}"
					return newLcName
				if lc.LaunchConfigurationName == lcName
					baseLcConfig = lc

			console.log "Creating a LaunchConfiguration for #{size}"

			newLcProps = _.pick(baseLcConfig, [
				'ImageId'
				'KeyName'
				'SecurityGroups'
				'UserData'
				'InstanceMonitoring'
				'IamInstanceProfile'
				'EbsOptimized'
				'AssociatePublicIpAddress'
			])
			newLcProps.LaunchConfigurationName = newLcName
			newLcProps.InstanceType = size
			as.createLaunchConfiguration(newLcProps)
			.then ->
				return newLcName
	.then (lcName) ->
		getPhysicalId(stackName, 'ClusterAutoScalingGroup')
		.then (asgName) ->
			as.updateAutoScalingGroup
				AutoScalingGroupName: asgName
				LaunchConfigurationName: lcName
	.then ->
		redeploy(stackName)

redeploy = (stackName) ->
	console.log "Redeploying '#{stackName}'"
	originalSize = undefined
	getTasks(stackName)
	.then (tasks) ->
		if tasks.length >= 2 then return tasks

		originalSize = 1
		console.log "Stack is too small, scaling up to 2 tasks"
		scaleTo(stackName, 2)
		.then ->
			return tasks
	.then (tasks) ->
		console.log "Restarting #{tasks.length} tasks"
		desiredCapacity = Math.max(tasks.length, 2)
		executeSerially (_.partial(restartTask, stackName, task, desiredCapacity) for task in tasks)
	.then ->
		console.log "Restarted all tasks"
		if originalSize?
			console.log "Scaling down again"
			scaleTo(stackName, originalSize)
	.then ->
		console.log "All done"

restartTask = (stackName, taskId, desiredCapacity) ->
	console.log "Restarting task #{taskId}"
	getPhysicalId(stackName, 'Cluster')
	.then (cluster) ->
		ecs.stopTask
			cluster: cluster
			task: taskId
	.then ->
		waitForTasks(stackName, desiredCapacity)

getIpForInstances = (stackName) ->
	getPhysicalId(stackName, 'Vpc')
	.then (vpcName) ->
		ec2.describeInstances
			Filters: [
				Name: 'vpc-id'
				Values: [vpcName]
			]
	.then (result) ->
		for res in result.Reservations
			for ins in res.Instances
				ins.PublicIpAddress

putConfigFiles = (stackName, files, opts) ->
	put = (file) ->
		if opts?.log
			console.log "Uploading #{file}..."
		s3.putObject
			ACL: 'private'
			Bucket: "#{stackName}-config"
			Key: path.basename(file)
			Body: fs.createReadStream(file)


	if _.isArray(files)
		return Promise.all(put(file) for file in files)

	glob(files)
	.then (resolvedFiles) ->
		putConfigFiles(stackName, resolvedFiles)




getElbPublicDns = (stackName) ->
	getPhysicalId(stackName, 'Elb')
	.then (elbName) ->
		elb.describeLoadBalancers
			LoadBalancerNames: [elbName]
	.then (result) ->
		result.LoadBalancerDescriptions[0].DNSName

module.exports = _.extend eventTarget, {
	initAws
	createStack
	updateStack
	deleteStack
	scaleTo
	scaleVertically
	redeploy
	getIpForInstances
	putConfigFiles
	getElbPublicDns
}

# --------------------------------------------------------

waitForInstances = (stackName, desiredCapacity, interval = 3000) ->
	console.log "Waiting for instances..."
	instanceNames = []
	printer = statusPrinter('Terminated')

	new Promise (resolve, reject) ->
		check = ->
			getInstances(stackName)
			.then (instances) ->
				statusMap = {}
				allDone = true
				for i in instances
					if i.status != "InService" or i.health != "Healthy" then allDone = false
					statusMap[i.name] = {status: i.status, health: i.health}

				if instances.length >= instanceNames.length
					instanceNames = (i.name for i in instances)

				printer.print(instanceNames, statusMap)

				if allDone and instances.length == desiredCapacity
					console.log "Instance count is now at #{desiredCapacity}"
					return resolve()

				setTimeout(check, interval)
			.then(null, reject)
		check()

getInstances = (stackName) ->
	getPhysicalId(stackName, 'ClusterAutoScalingGroup')
	.then (asgName) ->
		as.describeAutoScalingGroups
			AutoScalingGroupNames: [asgName]
	.then (result) ->
		asg = result.AutoScalingGroups[0]
		instances = for i in asg.Instances
			name: i.InstanceId
			status: i.LifecycleState
			health: i.HealthStatus

# ------------------------------------------------

waitForTasks = (stackName, desiredCapacity, interval = 3000) ->
	console.log "Waiting for tasks..."
	printer = statusPrinter('Terminated')
	_tasks = []
	_getTasks = ->
		if _tasks.length >= desiredCapacity
			# Final list of tasks already fetched
			return Promise.resolve(_tasks)
		getTasks(stackName)
		.then (tasks) ->
			_tasks = tasks

	new Promise (resolve, reject) ->
		check = ->
			_getTasks()
			.then (tasks) ->
				if tasks.length != desiredCapacity
					# Tasks to be created are not even there yet
					return setTimeout(check, interval)

				getPhysicalId(stackName, 'Cluster')
				.then (clusterName) ->
					ecs.describeTasks
						cluster: clusterName
						tasks: tasks
				.then (result) ->
					resources = tasks
					statusMap = {}
					done = true
					for task in result.tasks
						if task.lastStatus != 'RUNNING' then done = false
						statusMap[task.taskArn] =
							status: task.lastStatus
							desiredStatus: task.desiredStatus
					printer.print(tasks, statusMap)
					if done then return resolve()
					setTimeout(check, interval)
			.then(null, reject)

		check()

getTasks = (stackName) ->
	Promise.all([
		getPhysicalId(stackName, 'Cluster')
		getPhysicalId(stackName, 'Service')
	])
	.then ([clusterId, serviceId]) ->
		ecs.listTasks
			cluster: clusterId
			serviceName: serviceId
	.then (result) ->
		return result.taskArns

# ------------------------------------------------

waitForStack = (name, resources, label, statusRegex, interval = 3000) ->
	startTime = new Date()
	resourceStatus = {}
	printer = statusPrinter()

	updateStatus = (events) ->
		for e in events when statusRegex.test(e.status)
			resourceStatus[e.name] =
				status: e.status
				time: e.timestamp.toLocaleTimeString()
			eventTarget.dispatchEvent('stackchanged', {resource: e.name, status: e.status})

	printer.print(resources, {})

	new Promise (resolve, reject) ->
		displayedEvents = {}
		check = ->
			checkStackReady(name)
			.then (result) ->
				if result?
					process.stdout.write('\n')
					return resolve(result)
				getStackEvents(name)
				.then (events) ->
					updateStatus(events)
					printer.print(resources, resourceStatus)
					setTimeout(check, interval)
			.then null, (e) ->
				reject(e)

		check()

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

# ------------------------------------------------

physicalIdCache = {}
getPhysicalId = (stackName, resourceName) ->
	cachedName = physicalIdCache["#{stackName}/#{resourceName}"]
	if cachedName then return Promise.resolve(cachedName)
	cf.describeStackResource
		StackName: stackName
		LogicalResourceId: resourceName
	.then (result) ->
		physicalIdCache["#{stackName}/#{resourceName}"] = result.StackResourceDetail.PhysicalResourceId

# ------------------------------------------------
# ------------------------------------------------
# ------------------------------------------------

statusPrinter = (defaultStatus = "Waiting...") ->
	printedLines = 0
	resources = []
	statusMap = {}

	print = (_resources, _statusMap) ->
		if _resources? then resources = _resources
		if _statusMap? then statusMap = _statusMap

		process.stdout.moveCursor(0, -printedLines)
		printedLines = resources.length
		for rid in resources
			process.stdout.clearLine()
			process.stdout.write(rid + ' ')

			status = statusMap[rid]
			if status?
				color = colors[getColorForStatus(status.status)]
				process.stdout.write(color(status.status))
				if status.health?
					process.stdout.write(' ' + colors[getColorForStatus(status.health)](status.health))
				if status.time?
					process.stdout.write(" (#{status.time})")
			else
				color = colors[getColorForStatus(defaultStatus)]
				process.stdout.write(' '+ color(defaultStatus))

			process.stdout.write('\n')

	return {
		print
	}

getColorForStatus = (status) ->
	if /complete|running|inservice|detached|healthy/i.test(status) then return 'green'
	if /in_progress|pending|enteringstandby|terminating|initializing/i.test(status) then return 'yellow'
	if /terminated/i.test(status) then return 'gray'
	if /failed|error/i.test(status) then return 'red'
	return 'white'

executeSerially = (callbacks) ->
	promise = callbacks[0]()
	for cb in callbacks[1..]
		promise = promise.then(cb)
	return promise


