_ = require('lodash')
Promise = require('promise')
{ec2} = require('./awsUtils.coffee')

###

Create vpc
Create subnets (for each availabilityzone)
Create IAM roles
 - for instances
 - for services
Create security group for ELB
Create security group for cluster
Create cluster
Create task definition
Create service

Create s3 bucket for frontend
Create s3 bucket for logging


Create ELB
 - needs subnet
 - needs ELB security group
Create launch config for cluster AG
 - needs an IAM role
 - needs security group
Create autoscaling group for cluster
 - needs VPCZoneIdentifier
 - needs launch config

###



AWS_UID = '066341227319'
AVAILABILITY_ZONES = ['eu-west-1a', 'eu-west-1b', 'eu-west-1c']


run = ->
	console.log "Creating security group"
	securityGroup(null, 'elb-sg', 'Automatically created sg')
	.then (elbSgId) ->
		console.log "Created first sg"
		addOpenPermissions(elbSgId)
		.then ->
			console.log "Added open permissions"
			securityGroup(null, 'cluster-sg', 'SG for the cluster')
		.then (clusterSgId) ->
			console.log "Created cluster sg"
			addClosedPermissions(clusterSgId, elbSgId)
	.then ->
		console.log 'All done'
	.then null, (err) ->
		console.error(err)

securityGroup = (vpcId, name, description)->
	ec2.createSecurityGroup
		Description: description
		GroupName: name
		VpcId: vpcId
	.then (data) -> data.GroupId

addClosedPermissions = (securityGroupId, fromGroupId) ->
	ec2.authorizeSecurityGroupIngress
		GroupId: securityGroupId
		IpPermissions: [
			FromPort: 80
			IpProtocol: 'tcp'
			ToPort: 80
			UserIdGroupPairs: [
				GroupId: fromGroupId
				UserId: AWS_UID
			]
		]

addOpenPermissions = (securityGroupId) ->
	ec2.authorizeSecurityGroupIngress
		GroupId: securityGroupId
		IpProtocol: "-1"



iamEC2Role = ->
	{
	 "Type": "AWS::IAM::Role",
	 "Properties": {
			"AssumeRolePolicyDocument": {
				"Version": "2008-10-17",
				"Statement": [
					{
						"Action": "sts:AssumeRole",
						"Principal": {
							"Service": "ec2.amazonaws.com"
						},
						"Effect": "Allow",
						"Sid": ""
					}
				]
			},
			"Path": "/"
		}
	}

subnet = (vpcId, availabilityZone, cidrBlock) ->
	{
		"Type": "AWS::EC2::Subnet",
		"Properties": {
			"CidrBlock": cidrBlock,
			"AvailabilityZone": availabilityZone,
			"VpcId": {
				"Ref": vpcId
			}
		}
	}


subnets = (prefix, vpcId) ->
	subnets = {}
	for availabilityZone, idx in AVAILABILITY_ZONES
		cidrBlock = "10.0.#{idx*16}.0/20"
		subnets["#{prefix}-#{availabilityZone}"] = subnet(vpcId, availabilityZone, cidrBlock)
	return subnets

vpc = ->
	{
		"Type": "AWS::EC2::VPC",
		"Properties": {
			"CidrBlock": "10.0.0.0/16",
			"InstanceTenancy": "default",
			"EnableDnsSupport": "true",
			"EnableDnsHostnames": "true"
		}
	}

run()
