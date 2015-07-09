_ = require('lodash')
Promise = require('promise')
AWS = require('aws-sdk')
awsConfig = require('./aws.json')

AWS.config =
	accessKeyId: awsConfig.key
	secretAccessKey: awsConfig.secret
	region: awsConfig.region
	sslEnabled: true

wrapPromise = (cb) ->
	(params) ->
		new Promise (resolve, reject) ->
			cb params, (err, data) ->
				if err then return reject(err)
				resolve(data)

wrapAPI = (original) ->
	wrapped = {}
	for key, fn of original when _.isFunction(fn)
		wrapped[key] = wrapPromise(fn.bind(original))
	return wrapped

ec2 = wrapAPI(new AWS.EC2())
s3 = wrapAPI(new AWS.S3())
cf = wrapAPI(new AWS.CloudFormation())

module.exports = {
	ec2
	s3
	cf
}



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
