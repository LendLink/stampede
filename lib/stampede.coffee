###
# Stampede web development framework
###

lumberjack = require './lumberjack'
exports.lumberjack = new lumberjack()
exports.log = exports.lumberjack

exports.utils = require './utils'
exports.inform = require './inform'
exports.dba = require './dba'
exports.queryBuilder = require './queryBuilder'
exports.qb = exports.queryBuilder
exports.validator = require './validator'
exports.events = require './events'
exports.time = require './time'
exports.config = require './config'
exports.app = require './app'
exports.dbService = require './dbService'
exports.router = require './router'
exports.route = exports.router.route
exports.paramDefinition = require './paramDefinition'

exports._ = exports.lodash = require 'lodash'
exports.mocha = require 'mocha'
exports.should = require 'should'
exports.path = require 'path'
exports.async = require 'async'
exports.moment = require 'moment'
