_ = require 'lodash'
Handlebars = require 'handlebars'
path = require 'path'
url = require 'url'
fs = require 'fs'
querystring = require 'querystring'
isTextOrBinary = require 'istextorbinary'


CONSTANTS = {
  NAME: 'cruft'
  DISPLAY_NAME: 'Cruft Tracker'
  ICON_FILE_PATH: path.join(__dirname, '../', '123.png')
  AUTH_ENDPOINT: null
}

class CruftService
  constructor: ({@config, @packages, @db, @sourceProviders}) ->
    {mongoose, 'mongoose-findorcreate': findOrCreate} = @packages
    console.log @config
    CruftTrackSchema = new mongoose.Schema {
      repoId: {type: String, required: true},
      userId: {type: String, required: true},
      sourceProviderName: {type: String, required: true},
      cruft: mongoose.Schema.Types.Mixed
    }
    CruftTrackSchema.plugin findOrCreate
    @CruftTrackModel = mongoose.model 'cruft:CruftTrackModel', CruftTrackSchema
    templateString = fs.readFileSync(path.join(__dirname, '../template.handlebars'), 'utf8')
    @template = Handlebars.compile(templateString)
    _.extend @, CONSTANTS

  isAuthenticated: (req) -> true

  initializeAuthEndpoints: (router) ->

  initializeOtherEndpoints: (router) ->

  initializePublicEndpoints: (router) ->
    router.get '/:sourceProviderName/:repoId', (req, res, next) =>
      {sourceProviderName, repoId} = req.params
      @CruftTrackModel.findOne {sourceProviderName, repoId}, (err, model) =>
        return next(err) if err
        return next(new Error('No cruft service has been initialized at that url.')) if not model?
        res.set 'Content-Type', 'text/html'
        res.send @template(model)

    router.get '/:sourceProviderName/:repoId/data.json', (req, res, next) =>
      {sourceProviderName, repoId} = req.params
      @CruftTrackModel.findOne {sourceProviderName, repoId}, (err, model) =>
        return next(err) if err
        return next(new Error('No cruft service has been initialized at that url.')) if not model?
        res.set 'Content-Type', 'text/json'
        res.send model.cruft

  activateServiceForRepo: (repoModel, callback) ->
    {repoId, userId, sourceProviderName} = repoModel
    @CruftTrackModel.findOrCreate {repoId, userId, sourceProviderName}, (err, model, created) =>
      return callback(err) if err
      successMessage = "Cruft tracker activated! View at <a href=\"/plugins/services/#{@NAME}/#{sourceProviderName}/#{encodeURIComponent(repoId)}/\">this link</a>"
      if not created
        model.cruft = {}
        model.markModified 'cruft'
        model.save (err) ->
          callback(err, successMessage)
      else
        callback(null, successMessage)

  handleInitialRepoData: (repoModel, {files, tempPath}, callback) ->
    {repoId, userId, sourceProviderName} = repoModel
    cruft = {}
    for cruftType in @config.cruft
      cruft[cruftType.name] = []
    @CruftTrackModel.findOne {repoId, userId, sourceProviderName}, (err, model) =>
      callback(err) if err
      for file in files
        if isTextOrBinary.isTextSync(file, fs.readFileSync(file))
          lines = fs.readFileSync(file, 'utf8').split('\n')
          for line, lineNumber in lines
            for cruftType in @config.cruft
              if cruftType.regex.test(line)
                cruft[cruftType.name].push {'lineNumber': lineNumber + 1, contents: line, file: path.relative(tempPath, file)}
      model.cruft = cruft
      model.markModified 'cruft'
      model.save(callback)

  handleHookRepoData: (repoModel, {files, tempPath}, callback) ->
    {repoId, userId, sourceProviderName} = repoModel
    cruft = {}
    for cruftType in @config.cruft
      cruft[cruftType.name] = []
    @CruftTrackModel.findOne {repoId, userId, sourceProviderName}, (err, model) =>
      callback(err) if err
      for file in files
        if isTextOrBinary.isTextSync(file, fs.readFileSync(file))
          lines = fs.readFileSync(file, 'utf8').split('\n')
          for line, lineNumber in lines
            for cruftType in @config.cruft
              if cruftType.regex.test(line)
                cruft[cruftType.name].push {'lineNumber': lineNumber + 1, contents: line, file: path.relative(tempPath, file)}
      model.cruft = cruft
      model.markModified 'cruft'
      model.save(callback)

  deactivateServiceForRepo: (repoModel, callback) ->
    {repoId, userId, sourceProviderName} = repoModel
    @CruftTrackModel.findOneAndRemove {repoId, userId, sourceProviderName}, (err) =>
      return callback(err) if err
      callback(null, "#{@DISPLAY_NAME} removed successfully.")

module.exports = CruftService

