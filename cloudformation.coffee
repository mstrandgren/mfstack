_ = require('lodash')
Promise = require('promise')
{ec2, cf} = require('./awsUtils.coffee')



AWS_UID = '066341227319'
AVAILABILITY_ZONES = ['eu-west-1a', 'eu-west-1b', 'eu-west-1c']

vpcId = 'vpc-a3a929c6'
subnetIds = [
	'subnet-9b7bc4c2'
	'subnet-e0433e85'
	'subnet-e57b1e92'
]

run = ->
	console.log 'Creating stack...'
	template = createTemplate()
	# console.log JSON.stringify(template, null, 2)
	# return

	stackPolicy =
		Statement: [
			Effect : 'Allow',
			Action : 'Update:*',
			Principal: '*',
			Resource : '*'
		]

	cf.createStack
		Capabilities: ['CAPABILITY_IAM']

		StackName: 'test-stack-4'
		# StackPolicyDuringUpdateBody: JSON.stringify(stackPolicy)
		TemplateBody: JSON.stringify(template)

	.then (data) ->
		checkReady = ->
			cf.describeStacks(StackName: data.StackId)
			.then (data) ->
				status = data.Stacks[0].StackStatus
				if status == 'UPDATE_IN_PROGRESS'
					console.log "Update in progress"
					return new Promise (resolve, reject) ->
						setTimeout ->
							resolve(checkReady())
						, 1000

				return data.Stacks[0]

		checkReady()

	.then (data) ->
		console.log data


	.then null, (err) ->
		console.error err


createTemplate = ->

	_subnets = subnets()

	Resources = _.extend {},
	# 	vpc()
	# ,
	# 	_subnets
	# ,
		ExternalSecurityGroup: securityGroup.external()
		InternalSecurityGroup: securityGroup.internal('ExternalSecurityGroup')

		InstanceRole: iam.instanceRole()
		InstanceProfile: iam.profile('InstanceRole')
		ServiceRole: iam.serviceRole()

		Elb: elb
			subnets: _.keys(_subnets)
			securityGroups: ['ExternalSecurityGroup', 'InternalSecurityGroup']

		EcsCluster: cluster()

		ClusterLaunchConfiguration: launchConfiguration
			profile: 'InstanceProfile'
			securityGroups: ['InternalSecurityGroup']
			cluster: 'EcsCluster'

		ClusterAutoScalingGroup: autoScalingGroup
			launchConfiguration: 'ClusterLaunchConfiguration'
			loadBalancers: ['Elb']
			subnets: _.keys(_subnets)


		MarcoPoloTask: taskDefinition('marco-polo', 'mstrandgren/marcopolo')
		MarcoPoloService: service
			autoScalingGroup: 'ClusterAutoScalingGroup'
			cluster: 'EcsCluster'
			count: 1
			loadBalancer: 'Elb'
			containerName: 'marco-polo'
			role: 'ServiceRole'
			taskDefinition: 'MarcoPoloTask'


	return {Resources}


autoScalingGroup = ({launchConfiguration, loadBalancers, subnets}) ->
	Type: 'AWS::AutoScaling::AutoScalingGroup'
	Properties:
		MaxSize: 1
		MinSize: 1
		DesiredCapacity: 1

		LaunchConfigurationName: {Ref: launchConfiguration}
		LoadBalancerNames: ({Ref: lb} for lb in loadBalancers)
		VPCZoneIdentifier: subnetIds # ({Ref: subnet} for subnet in subnets)

		HealthCheckGracePeriod: 300
		HealthCheckType: 'EC2'
		Cooldown: 300
	# DependsOn: subnets.concat(loadBalancers).concat([launchConfiguration])

launchConfiguration = ({profile, securityGroups, cluster}) ->
	Type: 'AWS::AutoScaling::LaunchConfiguration'
	Properties:
		ImageId: 'ami-3db4ca4a'
		InstanceType: 't2.micro'
		IamInstanceProfile: {Ref: profile}
		InstanceMonitoring: true
		SecurityGroups: ({Ref: sg} for sg in securityGroups)

		UserData:
			'Fn::Base64':
				'Fn::Join': ["", [
					"#!/bin/bash\n"
					"echo ECS_CLUSTER="
					{Ref: cluster}
					" >> /etc/ecs/ecs.config"
				]]
	# DependsOn: securityGroups.concat([profile]).concat([cluster])


elb = ({subnets, securityGroups}) ->
	Type: 'AWS::ElasticLoadBalancing::LoadBalancer'
	Properties:
		Policies:[
			PolicyName: 'WebSocketProxyProtocolPolicy'
			PolicyType: 'ProxyProtocolPolicyType'
			Attributes: [
				Name: 'ProxyProtocol'
				Value: true
			]
			InstancePorts: [80]
		]
		Subnets: subnetIds #({Ref: subnet} for subnet in subnets)
		SecurityGroups: ({Ref: sg} for sg in securityGroups)
		Listeners: [
			InstancePort: 80
			LoadBalancerPort: 80
			Protocol: 'tcp'
			InstanceProtocol: 'tcp'
		]
		# ConnectionSettings:
		# 	IdleTimeout: 3600
		# ConnectionDrainingPolicy:
		# 	Enabled: true
		# 	Timeout: 300
		# CrossZone: true
	# DependsOn: subnets.concat(securityGroups)

		# HealthCheck:
		# 	HealthyThreshold: 10
		# 	Interval: 30
		# 	Target: "HTTP:80/index.html"
		# 	Timeout: 5
		# 	UnhealthyThreshold: 2




service = ({autoScalingGroup, cluster, count, containerName, loadBalancer, role, taskDefinition}) ->
	Type: 'AWS::ECS::Service'
	DependsOn: [autoScalingGroup]
	Properties:
		Cluster: { Ref: cluster }
		DesiredCount: count
		LoadBalancers: [
			ContainerName: containerName
			ContainerPort: 8000
			LoadBalancerName: {Ref: loadBalancer}
		]
		Role: {Ref: role}
		TaskDefinition: {Ref: taskDefinition}


taskDefinition = (name, image) ->
	Type: 'AWS::ECS::TaskDefinition'
	Properties:
		ContainerDefinitions: [
			Name: name
			Cpu: 1024,
			Image: image
			Memory: 512
			PortMappings: [
				HostPort: 80
				ContainerPort: 8000
			]
		]
		Volumes: []

cluster = ->
	Type: 'AWS::ECS::Cluster'

securityGroup =
	external: ->
		Type: 'AWS::EC2::SecurityGroup'
		Properties:
			GroupDescription: 'External Security Group'
			SecurityGroupIngress: [
				CidrIp: '0.0.0.0/0'
				IpProtocol: '-1'
			]
			VpcId: vpcId # { Ref: 'Vpc'}


	internal: (externalSecurityGroup, fromPort = 80, toPort = 80) ->
		Type: 'AWS::EC2::SecurityGroup',
		Properties:
			GroupDescription: 'Internal Security Group'
			SecurityGroupIngress: [
				SourceSecurityGroupId: { Ref: externalSecurityGroup }
				IpProtocol: 'tcp'
				FromPort: fromPort
				ToPort: toPort
			]
			VpcId: vpcId # { Ref: 'Vpc'}

iam =
	instanceRole: ->
		Type: 'AWS::IAM::Role',
		Properties:
			AssumeRolePolicyDocument:
				Version: '2012-10-17'
				Statement: [
					Action: ['sts:AssumeRole']
					Principal:
						Service: ['ec2.amazonaws.com']
					Effect: 'Allow'
				]
			Path: '/'
			ManagedPolicyArns: [
				'arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role'
			]

	profile: (role) ->
		Type: 'AWS::IAM::InstanceProfile'
		Properties:
			Path: '/'
			Roles: [{Ref: role}]

	serviceRole: ->
		Type: 'AWS::IAM::Role',
		Properties:
			AssumeRolePolicyDocument:
				Version: '2012-10-17'
				Statement: [
					Action: ['sts:AssumeRole']
					Principal:
						Service: ['ecs.amazonaws.com']
					Effect: 'Allow'
				]
			Path: '/'
			ManagedPolicyArns: [
				'arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceRole'
				# 'arn:aws:iam::aws:policy/AmazonEC2ContainerServiceFullAccess'
			]



subnet = (vpcId, availabilityZone, cidrBlock) ->
	Type: 'AWS::EC2::Subnet'
	Properties:
		CidrBlock: cidrBlock
		AvailabilityZone: availabilityZone
		VpcId: { Ref: 'Vpc'}
	DependsOn: ['Vpc', 'Igw', 'IgwAttachment']

subnets = ->
	subnets = {}
	for availabilityZone, idx in AVAILABILITY_ZONES
		cidrBlock = "10.0.#{idx*16}.0/20"
		subnets["Subnet#{availabilityZone.split('-').pop()}"] = subnet('Vpc', availabilityZone, cidrBlock)
	return subnets

internetGateway = ->
	Type: 'AWS::EC2::InternetGateway'

vpc = ->
	Igw:
		Type: 'AWS::EC2::InternetGateway'
		Properties: {}
	IgwAttachment:
		Type: 'AWS::EC2::VPCGatewayAttachment'
		Properties:
			InternetGatewayId: {Ref: 'Igw'}
			VpcId: {Ref: 'Vpc'}
	Vpc:
		Type: 'AWS::EC2::VPC'
		Properties:
			CidrBlock: '10.0.0.0/16'
			InstanceTenancy: 'default'
			EnableDnsSupport: 'true'
			EnableDnsHostnames: 'true'

run()
