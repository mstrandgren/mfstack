_ = require('lodash')

AVAILABILITY_ZONES = ['eu-west-1a', 'eu-west-1b', 'eu-west-1c']

exports.createTemplate = (stackName, {image, environment, keyName}) ->

	taskName = image.split('/').pop()

	_subnets = subnets()
	bucketName = "#{stackName}-config"
	subnetIds = _.keys(_subnets)

	Resources = _.extend {},
		vpc()
	,
		_subnets
	,
		routeTableAssocs(subnetIds)
	,
		ExternalSecurityGroup: securityGroup.external()
		InternalSecurityGroup: securityGroup.internal('ExternalSecurityGroup')

		InstanceRole: iam.instanceRole(bucketName)
		InstanceProfile: iam.profile('InstanceRole')
		ServiceRole: iam.serviceRole()

		Bucket: bucket
			name: bucketName

		Elb: elb
			subnets: subnetIds
			securityGroups: ['ExternalSecurityGroup']

		Cluster: cluster()

		ClusterLaunchConfiguration: launchConfiguration
			profile: 'InstanceProfile'
			securityGroups: ['InternalSecurityGroup']
			cluster: 'Cluster'
			keyName: keyName
			bucketName: bucketName

		ClusterAutoScalingGroup: autoScalingGroup
			launchConfiguration: 'ClusterLaunchConfiguration'
			loadBalancers: ['Elb']
			subnets: subnetIds

		Task: taskDefinition(taskName, image, environment)
		Service: service
			autoScalingGroup: 'ClusterAutoScalingGroup'
			cluster: 'Cluster'
			count: 1
			loadBalancer: 'Elb'
			containerName: taskName
			role: 'ServiceRole'
			taskDefinition: 'Task'


	Outputs =
		URL:
			Value:
				'Fn::Join': ['',[
					'http://'
					'Fn::GetAtt': ['Elb' ,'DNSName']
				]]

	return {
		Resources
		Outputs
	}

autoScalingGroup = ({launchConfiguration, loadBalancers, subnets}) ->
	Type: 'AWS::AutoScaling::AutoScalingGroup'
	Properties:
		MaxSize: 1
		MinSize: 1
		DesiredCapacity: 1

		LaunchConfigurationName: {Ref: launchConfiguration}
		LoadBalancerNames: ({Ref: lb} for lb in loadBalancers)
		VPCZoneIdentifier: ({Ref: subnet} for subnet in subnets)

		HealthCheckGracePeriod: 300
		HealthCheckType: 'EC2'
		Cooldown: 300

launchConfiguration = ({stackName, profile, securityGroups, cluster, keyName, bucketName}) ->
	Type: 'AWS::AutoScaling::LaunchConfiguration'
	Properties:
		ImageId: 'ami-3db4ca4a'
		InstanceType: 't2.micro'
		IamInstanceProfile: {Ref: profile}
		InstanceMonitoring: true
		SecurityGroups: ({Ref: sg} for sg in securityGroups)
		AssociatePublicIpAddress: true
		KeyName: keyName

		UserData:
			'Fn::Base64':
				'Fn::Join': ["", [
					"#!/bin/bash\n"
					"echo ECS_CLUSTER="
					{Ref: cluster}
					" >> /etc/ecs/ecs.config\n"
					"yum install -y aws-cli\n"
					"aws s3 cp s3://#{bucketName}/ecs.config /etc/ecs/ecs.credentials\n"
					"cat /etc/ecs/ecs.credentials >> /etc/ecs/ecs.config"
					""
				]]

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
		Subnets: ({Ref: subnet} for subnet in subnets)
		SecurityGroups: ({Ref: sg} for sg in securityGroups)
		Listeners: [
			InstancePort: 80
			# InstanceProtocol: 'tcp' Need to fix proxywrapper first
			InstanceProtocol: 'http'
			LoadBalancerPort: 80
			# Protocol: 'tcp'
			Protocol: 'http'
		# ,
		# 	InstancePort: 80
		# 	InstanceProtocol: 'tcp'
		# 	LoadBalancerPort: 443
		# 	Protocol: 'ssl'
		# 	SSLCertificateId: 'SelfSignedCert'
		]

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

taskDefinition = (name, image, environment = {}) ->
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
			Environment: (Name: k, Value: v for k, v of environment)
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
			VpcId: { Ref: 'Vpc'}

	internal: (externalSecurityGroup, fromPort = 80, toPort = 80) ->
		Type: 'AWS::EC2::SecurityGroup',
		Properties:
			GroupDescription: 'Internal Security Group'
			SecurityGroupIngress: [
				SourceSecurityGroupId: { Ref: externalSecurityGroup }
				IpProtocol: 'tcp'
				FromPort: fromPort
				ToPort: toPort
			,
				CidrIp: '0.0.0.0/0'
				IpProtocol: 'tcp'
				FromPort: 22
				ToPort: 22
			]
			VpcId: { Ref: 'Vpc'}

bucket = ({name}) ->
	Type: 'AWS::S3::Bucket'
	Properties:
		BucketName: name

iam =
	instanceRole: (bucketName) ->
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
			Policies: [
				PolicyName: 's3AccessPolicy'
				PolicyDocument:
					Version: '2012-10-17'
					Statement: [
						Action: ['s3:GetObject']
						Resource: [
							"arn:aws:s3:::#{bucketName}/*"
						]
						Effect: 'Allow'
					]
			]
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
			]

subnet = (vpcId, availabilityZone, cidrBlock) ->
	Type: 'AWS::EC2::Subnet'
	Properties:
		CidrBlock: cidrBlock
		AvailabilityZone: availabilityZone
		VpcId: { Ref: 'Vpc'}
	DependsOn: ['Vpc', 'Igw', 'IgwAttachment']

routeTableAssoc = (subnet, routeTable) ->
	Type: 'AWS::EC2::SubnetRouteTableAssociation'
	Properties:
		SubnetId: {Ref: subnet}
		RouteTableId: {Ref: routeTable}

routeTableAssocs = (subnetIds) ->
	result = {}
	for subnetId, idx in subnetIds
		result["RouteTableAssoc#{idx}"] = routeTableAssoc(subnetId, 'RouteTable')
	return result

subnets = ->
	subnets = {}
	for availabilityZone, idx in AVAILABILITY_ZONES
		cidrBlock = "10.0.#{idx*16}.0/20"
		subnetId = "Subnet#{availabilityZone.split('-').pop()}"
		subnets[subnetId] = subnet('Vpc', availabilityZone, cidrBlock)
	return subnets

internetGateway = ->
	Type: 'AWS::EC2::InternetGateway'

vpc = ->
	Igw:
		Type: 'AWS::EC2::InternetGateway'

	IgwAttachment:
		Type: 'AWS::EC2::VPCGatewayAttachment'
		Properties:
			InternetGatewayId: {Ref: 'Igw'}
			VpcId: {Ref: 'Vpc'}

	Route:
		Type: 'AWS::EC2::Route'
		DependsOn: 'IgwAttachment'
		Properties:
			RouteTableId: {Ref: 'RouteTable'}
			DestinationCidrBlock: '0.0.0.0/0'
			GatewayId: {Ref: 'Igw'}

	RouteTable:
		Type: 'AWS::EC2::RouteTable'
		Properties:
			VpcId: {Ref: 'Vpc'}

	Vpc:
		Type: 'AWS::EC2::VPC'
		Properties:
			CidrBlock: '10.0.0.0/16'
			InstanceTenancy: 'default'
			EnableDnsSupport: 'true'
			EnableDnsHostnames: 'true'